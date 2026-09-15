# SLA incident: `DemoLoadErrorRateSLOBreach`

Данный стенд — это решение, как отслеживать и поддерживать SLA/SLO проекта.

Стенд полностью описан кодом: Kubernetes в DigitalOcean Cloud с настроенным monitoring stack для наблюдения за сервисами и быстрой реакции на инциденты.

Ниже — кейс, когда web-приложение внутри Kubernetes начинает отвечать ошибками с кодом 500. Для быстрой реакции на такой и подобные инциденты реализована система мониторинга:

1. **Grafana + Prometheus** — собирают и отображают метрики со всего, что развёрнуто в Kubernetes, через дашборды, в том числе SLA/SLO/SLI.
2. **Alertmanager** — уведомления по критическим метрикам и сообщение в Telegram со всей информацией, нужной инженеру для быстрой реакции.
3. **Loki** — собирает и отображает логи всех сервисов. Во время инцидента можно сразу разобрать ошибки приложения.
4. **Jaeger** — собирает и отображает traces. При расследовании видно, какой именно запрос не выполняется.

Ниже — путь, который проходит инженер, реагируя на инцидент: получает уведомление о нарушении SLO, по стеку мониторинга выясняет причину и чинит её, затем получает уведомление, что инцидент закрыт.

![Путь инженера: HTTP 500 в кластере → SLO recovered](incident-path.png)

Приложение: [`for-load-test/`](../../for-load-test/) (`demo-load` в namespace `demo`). В смеси k6 около **5% `GET /error`** — этого достаточно, чтобы пробить **SLO 1% error rate**. Это не падение пода: `/error` специально отвечает HTTP 500.

## Содержание

- [Как поднять стенд](#как-поднять-стенд)
- [Как связаны сигналы](#как-связаны-сигналы)
- [Как воспроизвести инцидент](#как-воспроизвести-инцидент)
- [Шаг 1 — SLO dashboard: SLI выше SLO](#шаг-1--slo-dashboard-sli-выше-slo)
- [Шаг 2 — Алерт (Telegram / Alertmanager)](#шаг-2--алерт-telegram--alertmanager)
- [Шаг 3 — Runbook](#шаг-3--runbook)
- [Шаг 4 — Loki: ns=`demo`, path `/error`, `trace_id`](#шаг-4--loki-nsdemo-path-error-trace_id)
- [Шаг 5 — Jaeger: `demo-load` `GET /error`](#шаг-5--jaeger-demo-load-get-error)
- [Шаг 6 — Снять нагрузку / recover](#шаг-6--снять-нагрузку--recover)
- [Кратко](#кратко)

## Как поднять стенд

1. Стек наблюдаемости:

   ```bash
   helmfile -f helmfile/helmfile.yaml sync
   ```

2. `lab.publicBaseURL` в [`helmfile/values/lab.yaml`](../../helmfile/values/lab.yaml) совпадает с Traefik LoadBalancer (`scheme + host`, без trailing slash). Из этого значения берутся Grafana `root_url`, Prometheus / Alertmanager `externalUrl`, ссылки в runbook и `runbook_url` в PrometheusRule. IP балансировщика в дашборды руками не копировать.

   ```bash
   kubectl -n traefik get svc traefik
   # if the EXTERNAL-IP changed: edit lab.yaml, then helmfile sync
   ```

3. `demo-load` задеплоен (ServiceMonitor снимает kube-prometheus-stack):

   ```bash
   kubectl apply -k for-load-test
   kubectl -n demo rollout status deploy/demo-load --timeout=5m
   ```

4. Логин: `admin` / `admin`. UI: `https://<lb-ip>/ui/<service>` (тот же host, что в `lab.publicBaseURL`).

Опционально: Telegram в Alertmanager (`helmfile/values/kube-prometheus-stack/telegram.local.yaml`). Без него смотрите Alertmanager / Prometheus Alerts.

## Как связаны сигналы

| Сигнал | Путь |
|---|---|
| Метрики (SLI) | `demo-load` `/metrics` → Prometheus Operator **ServiceMonitor** `demo/demo-load` → Prometheus → Grafana, папка `sla-slo-sli` |
| Логи | JSON stdout (`path`, `status`, `trace_id`) → Grafana **Alloy** → **Loki** → Grafana |
| Трейсы | приложение OTLP HTTP **4318** → OpenTelemetry Collector → **Jaeger** (in-memory) |

Коллектор в этой лабе только для traces. Логи подов уже снимает Alloy. Второй коллектор ставить не нужно.

**SLI** (5 минут):

```promql
sum(rate(demo_http_requests_total{namespace="demo",code=~"5.."}[5m]))
/
clamp_min(sum(rate(demo_http_requests_total{namespace="demo"}[5m])), 1e-9)
```

**SLO:** эта доля **< 1%**. Алерт `DemoLoadErrorRateSLOBreach` (`helmfile/alerts/demo/slo.yaml`) срабатывает, если она держится **> 0.01** дольше **1m**.

## Как воспроизвести инцидент

```bash
kubectl -n demo delete job demo-load-k6 --ignore-not-found
kubectl apply -k for-load-test/k6
kubectl -n demo logs -f job/demo-load-k6
```

Job в кластере (~3 мин): ~80% `/work`, ~15% `/slow`, ~5% `/error`. k6 с хоста описан в [`for-load-test/README.md`](../../for-load-test/README.md).

После появления 5xx подождите около минуты, чтобы сработал `for: 1m`.

---

## Шаг 1 — SLO dashboard: SLI выше SLO

Grafana → папка **`sla-slo-sli`** → дашборд **SLA / SLO / SLI — demo-load** (`uid: slo-demo-load`).

Пока крутится k6:

- SLI (error rate, 5m) **выше** красной линии **1%** (~5% из `/error`)
- error budget в красной зоне / отрицательный
- ссылка **Runbook DemoLoadErrorRateSLOBreach** (из `lab.publicBaseURL`)

![Grafana SLO dashboard — SLI above 1%](01-slo-dashboard-breach.png)

## Шаг 2 — Алерт (Telegram / Alertmanager)

Имя алерта: **`DemoLoadErrorRateSLOBreach`**. Severity `warning`. Annotation `runbook_url`:

`{{publicBaseURL}}/ui/grafana/d/demo-load-error-rate-slo-breach/`

(подставляется из `lab.publicBaseURL` скриптом `apply-prometheus-alerts.sh`, в git не оставляем сырой placeholder).

- **Telegram** (если настроен): firing, затем resolved после recovery (`send_resolved: true`).
- **Alertmanager**: `https://<lb-ip>/ui/alertmanager`
- **Prometheus Alerts**: `https://<lb-ip>/ui/prometheus/alerts`

![Telegram — DemoLoadErrorRateSLOBreach](02-telegram-alert.png)

![Alertmanager — firing](03-alertmanager-firing.png)

## Шаг 3 — Runbook

Grafana → папка **Runbooks** → **DemoLoadErrorRateSLOBreach** (`uid: demo-load-error-rate-slo-breach`).

Источник: [`helmfile/dashboards/runbooks/demo-load-error-rate-slo-breach.md`](../../helmfile/dashboards/runbooks/demo-load-error-rate-slo-breach.md). Рендерится на `helmfile sync` (Markdown **Text** panel). Дальше: SLO dashboard, Loki (`trace_id`), Jaeger `GET /error`, снять k6.

![Grafana Runbooks — DemoLoadErrorRateSLOBreach](04-runbook.png)

## Шаг 4 — Loki: ns=`demo`, path `/error`, `trace_id`

Grafana → папка **`loki`** → **K8s App Logs** (переменная `namespace=demo`) или Explore → Loki:

```logql
{namespace="demo"} | json | status = 500
```

Строки — JSON приложения. Скопируйте **`trace_id`**. Фильтр `path="/error"` — если удобнее искать по path, а не по status.

![Grafana Loki — demo /error with trace_id](05-grafana-logs.png)

## Шаг 5 — Jaeger: `demo-load` `GET /error`

Jaeger UI: `https://<lb-ip>/ui/jaeger` → сервис **`demo-load`**, operation **`GET /error`** (рядом: `GET /work`, `GET /slow`). Откройте span и сверьте **`trace_id`** из Loki.

Тот же поиск: Grafana Explore → datasource **Jaeger** (`uid: jaeger`).

Трейсы: **OTLP HTTP 4318** → OpenTelemetry Collector → Jaeger (in-memory, не OpenSearch).

![Jaeger — demo-load GET /error](06-jaeger-error-trace.png)

## Шаг 6 — Снять нагрузку / recover

```bash
kubectl -n demo delete job demo-load-k6
```

`demo-load` остаётся; останавливается только Job. Когда окно 5m rate стечёт:

- SLO dashboard: SLI **ниже 1%**, error budget снова зелёный
- `DemoLoadErrorRateSLOBreach` → **Inactive**
- Telegram resolved (если Telegram включён)

![Grafana SLO dashboard — recovered](07-slo-recovered.png)

Когда закончите: `kubectl delete -k for-load-test` (см. [`for-load-test/README.md`](../../for-load-test/README.md)).

---

## Кратко

1. Стенд: `helmfile sync`, `lab.publicBaseURL`, `kubectl apply -k for-load-test`.
2. Нагрузка: `kubectl apply -k for-load-test/k6` (~5% `GET /error`).
3. Grafana, папка **`sla-slo-sli`**: SLI > SLO 1%.
4. Алерт **`DemoLoadErrorRateSLOBreach`** (Telegram / Alertmanager) → `runbook_url`.
5. Папка **Runbooks** → **DemoLoadErrorRateSLOBreach**.
6. Loki `{namespace="demo"} | json | status = 500` → `trace_id`.
7. Jaeger, сервис **`demo-load`**, operation **`GET /error`** (OTLP → коллектор → Jaeger).
8. `kubectl -n demo delete job demo-load-k6` → SLI < 1%.
