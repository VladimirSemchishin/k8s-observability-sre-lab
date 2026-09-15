# SLA incident: `DemoLoadErrorRateSLOBreach`

Outcome-proof story for the lab: **SLI above SLO → alert → runbook → logs → traces → recovery**.

The app is [`for-load-test/`](../../for-load-test/) (`demo-load` in namespace `demo`). k6’s mix includes **~5% `GET /error`**, which is meant to break the **1% error-rate SLO**. This is not a pod crash: `/error` returns HTTP 500 on purpose.

Grafana dashboard copy and the runbook text are in **Russian**; this walkthrough is in English.

## Expected screenshots

PNG files are not in git yet (add them on this PR or a follow-up). Filenames:

| File | What to capture |
|---|---|
| [`01-slo-dashboard-breach.png`](01-slo-dashboard-breach.png) | Grafana folder `sla-slo-sli` — SLI (error rate) above the 1% SLO line |
| [`02-telegram-alert.png`](02-telegram-alert.png) | Telegram message for `DemoLoadErrorRateSLOBreach` (optional if Telegram is not configured) |
| [`03-alertmanager-firing.png`](03-alertmanager-firing.png) | Alertmanager UI — alert firing, `runbook_url` present |
| [`04-runbook.png`](04-runbook.png) | Grafana folder **Runbooks** → **DemoLoadErrorRateSLOBreach** |
| [`05-grafana-logs.png`](05-grafana-logs.png) | Loki: `namespace=demo`, `path=/error` (or `status=500`), `trace_id` in the JSON line |
| [`06-jaeger-error-trace.png`](06-jaeger-error-trace.png) | Jaeger: service `demo-load`, operation `GET /error` |
| [`07-slo-recovered.png`](07-slo-recovered.png) | Same SLO dashboard after k6 is stopped — SLI back under 1% |

## Preconditions

1. Observability stack is up:

   ```bash
   helmfile -f helmfile/helmfile.yaml sync
   ```

2. `lab.publicBaseURL` in [`helmfile/values/lab.yaml`](../../helmfile/values/lab.yaml) matches the Traefik LoadBalancer (`scheme + host`, no trailing slash). Grafana `root_url`, Prometheus / Alertmanager `externalUrl`, runbook links, and `runbook_url` on the PrometheusRule all come from that value. Do not paste the LB IP into dashboards.

   ```bash
   kubectl -n traefik get svc traefik
   # if the EXTERNAL-IP changed: edit lab.yaml, then helmfile sync
   ```

3. `demo-load` is deployed (ServiceMonitor scraped by kube-prometheus-stack):

   ```bash
   kubectl apply -k for-load-test
   kubectl -n demo rollout status deploy/demo-load --timeout=5m
   ```

4. Login: `admin` / `admin`. Open UIs at `https://<lb-ip>/ui/<service>` (same host as `lab.publicBaseURL`).

Optional: Alertmanager Telegram (`helmfile/values/kube-prometheus-stack/telegram.local.yaml`). Without it, still use Alertmanager / Prometheus Alerts.

## How the signals are wired

| Signal | Path |
|---|---|
| Metrics (SLI) | `demo-load` `/metrics` → Prometheus Operator **ServiceMonitor** `demo/demo-load` → Prometheus → Grafana folder `sla-slo-sli` |
| Logs | JSON stdout (`path`, `status`, `trace_id`) → Grafana **Alloy** → **Loki** → Grafana |
| Traces | app OTLP HTTP **4318** → OpenTelemetry Collector → **Jaeger** (in-memory) |

The collector in this lab is traces-only. Alloy already tails pod logs. Do not deploy a second collector.

**SLI** (5 minutes):

```promql
sum(rate(demo_http_requests_total{namespace="demo",code=~"5.."}[5m]))
/
clamp_min(sum(rate(demo_http_requests_total{namespace="demo"}[5m])), 1e-9)
```

**SLO:** that ratio **< 1%**. Alert `DemoLoadErrorRateSLOBreach` (`helmfile/alerts/demo/slo.yaml`) fires when it stays **> 0.01** for **1m**.

## Trigger

```bash
kubectl -n demo delete job demo-load-k6 --ignore-not-found
kubectl apply -k for-load-test/k6
kubectl -n demo logs -f job/demo-load-k6
```

In-cluster Job (~3 min): ~80% `/work`, ~15% `/slow`, ~5% `/error`. Host-side k6 is documented in [`for-load-test/README.md`](../../for-load-test/README.md).

Wait about a minute after error traffic appears so the `for: 1m` clause can fire.

---

## Step 1 — SLO dashboard: SLI above SLO

Grafana → folder **`sla-slo-sli`** → dashboard **SLA / SLO / SLI — demo-load** (`uid: slo-demo-load`).

While k6 is running you should see:

- SLI (error rate, 5m) **above** the red **1%** line (~5% from `/error`)
- error budget in the red / negative
- dashboard link **Runbook DemoLoadErrorRateSLOBreach** (uses `lab.publicBaseURL`)

![Grafana SLO dashboard — SLI above 1%](01-slo-dashboard-breach.png)

<!-- screenshot: 01-slo-dashboard-breach.png -->

## Step 2 — Alert fires (Telegram / Alertmanager)

Alert name: **`DemoLoadErrorRateSLOBreach`**. Severity `warning`. Annotation `runbook_url` is:

`{{publicBaseURL}}/ui/grafana/d/demo-load-error-rate-slo-breach/`

(substituted from `lab.publicBaseURL` by `apply-prometheus-alerts.sh`, not left as a literal placeholder).

- **Telegram** (if configured): firing message, then a resolved message after recovery (`send_resolved: true`).
- **Alertmanager**: `https://<lb-ip>/ui/alertmanager`
- **Prometheus Alerts**: `https://<lb-ip>/ui/prometheus/alerts`

![Telegram — DemoLoadErrorRateSLOBreach](02-telegram-alert.png)

![Alertmanager — firing](03-alertmanager-firing.png)

<!-- screenshot: 02-telegram-alert.png -->
<!-- screenshot: 03-alertmanager-firing.png -->

## Step 3 — Open the runbook

Grafana → folder **Runbooks** → **DemoLoadErrorRateSLOBreach** (`uid: demo-load-error-rate-slo-breach`).

Source: [`helmfile/dashboards/runbooks/demo-load-error-rate-slo-breach.md`](../../helmfile/dashboards/runbooks/demo-load-error-rate-slo-breach.md). Rendered on `helmfile sync` (Markdown **Text** panel). It tells you to check the SLO dashboard, Loki (`trace_id`), Jaeger `GET /error`, then stop k6.

![Grafana Runbooks — DemoLoadErrorRateSLOBreach](04-runbook.png)

<!-- screenshot: 04-runbook.png -->

## Step 4 — Loki: ns=`demo`, path `/error`, `trace_id`

Grafana → folder **`loki`** → **K8s App Logs** (variable `namespace=demo`), or Explore → Loki:

```logql
{namespace="demo"} | json | status = 500
```

Lines are JSON from the app. Copy **`trace_id`**. Filter on `path="/error"` the same way if you prefer path over status.

![Grafana Loki — demo /error with trace_id](05-grafana-logs.png)

<!-- screenshot: 05-grafana-logs.png -->

## Step 5 — Jaeger: `demo-load` `GET /error`

Jaeger UI: `https://<lb-ip>/ui/jaeger` → service **`demo-load`**, operation **`GET /error`** (neighbours: `GET /work`, `GET /slow`). Open a span and match **`trace_id`** from Loki.

Same search from Grafana Explore → datasource **Jaeger** (`uid: jaeger`).

Traces: **OTLP HTTP 4318** → OpenTelemetry Collector → Jaeger (in-memory, not OpenSearch).

![Jaeger — demo-load GET /error](06-jaeger-error-trace.png)

<!-- screenshot: 06-jaeger-error-trace.png -->

## Step 6 — Stop load / recover

```bash
kubectl -n demo delete job demo-load-k6
```

`demo-load` stays up; only the Job stops. After the 5m rate window drains:

- SLO dashboard: SLI **under 1%**, error budget back in the green
- `DemoLoadErrorRateSLOBreach` → **Inactive**
- Telegram resolved message (if Telegram is enabled)

![Grafana SLO dashboard — recovered](07-slo-recovered.png)

<!-- screenshot: 07-slo-recovered.png -->

Tear down the app when you are done: `kubectl delete -k for-load-test` (see [`for-load-test/README.md`](../../for-load-test/README.md)).

---

## Кратко (RU)

1. Стенд: `helmfile sync`, `lab.publicBaseURL`, `kubectl apply -k for-load-test`.
2. Нагрузка: `kubectl apply -k for-load-test/k6` (~5% `GET /error`).
3. Grafana, папка **`sla-slo-sli`**: SLI > SLO 1%.
4. Алерт **`DemoLoadErrorRateSLOBreach`** (Telegram / Alertmanager) → `runbook_url`.
5. Папка **Runbooks** → **DemoLoadErrorRateSLOBreach**.
6. Loki `{namespace="demo"} | json | status = 500` → `trace_id`.
7. Jaeger, сервис **`demo-load`**, operation **`GET /error`** (OTLP → коллектор → Jaeger).
8. `kubectl -n demo delete job demo-load-k6` → SLI < 1%.
