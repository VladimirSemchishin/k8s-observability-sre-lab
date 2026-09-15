# DemoLoadErrorRateSLOBreach

`sum(rate(demo_http_requests_total{namespace="demo",code=~"5.."}[5m])) / clamp_min(sum(rate(demo_http_requests_total{namespace="demo"}[5m])), 1e-9)`

Что показывает метрика: **SLI** сервиса `demo-load` — доля HTTP 5xx среди всех запросов за 5 минут. Алерт `DemoLoadErrorRateSLOBreach` горит, когда эта доля **> 1%** дольше 1 минуты (внутренний **SLO**). Штатный k6 (`for-load-test/k6`, ~5% `GET /error`) специально пробивает этот порог.

---

Как чинить и куда смотреть если сработал этот алерт:

1. Grafana → папка **SLA/SLO/SLI** → дашборд **SLA / SLO / SLI — demo-load**. Проверьте, что SLI (error rate) выше красной линии 1% и error budget отрицательный. Пока k6 крутит `/error`, это ожидаемо.
2. Логи Loki, namespace `demo`: `{namespace="demo"} | json` и ошибки `{namespace="demo"} | json | status = 500`. Скопируйте `trace_id` из JSON-строки.
3. Трейсы: Jaeger UI, сервис **`demo-load`**, operation `GET /error` (и соседние `GET /work`, `GET /slow`). Вставьте `trace_id` из лога. В Grafana тот же datasource **Jaeger** (`uid: jaeger`).
4. Починить / снять нагрузку: `kubectl -n demo delete job demo-load-k6` (или уменьшите долю `/error`). Приложение само отдаёт 500 на `/error` — это не падение пода.
5. Вернитесь на SLO-дашборд: error rate должен упасть ниже 1%, error budget — в плюс, алерт в Prometheus/Alertmanager — в Inactive.

Ссылки на полезные источники:

- Grafana SLO (demo-load): {{publicBaseURL}}/ui/grafana/d/slo-demo-load/
- Grafana логи (K8s App Logs, ns=demo): {{publicBaseURL}}/ui/grafana/d/k8s-app-logs?var-namespace=demo
- Grafana Explore / Loki (ошибки 500): {{publicBaseURL}}/ui/grafana/explore?orgId=1&schemaVersion=1&panes=%7B%22loki%22%3A%7B%22datasource%22%3A%22loki%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22loki%22%2C%22uid%22%3A%22loki%22%7D%2C%22expr%22%3A%22%7Bnamespace%3D%5C%22demo%5C%22%7D%20%7C%20json%20%7C%20status%20%3D%20500%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-1h%22%2C%22to%22%3A%22now%22%7D%7D%7D
- Jaeger UI (service=demo-load): {{publicBaseURL}}/ui/jaeger/search?service=demo-load
- Grafana Explore / Jaeger: {{publicBaseURL}}/ui/grafana/explore?orgId=1&schemaVersion=1&panes=%7B%22jaeger%22%3A%7B%22datasource%22%3A%22jaeger%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22jaeger%22%2C%22uid%22%3A%22jaeger%22%7D%2C%22queryType%22%3A%22search%22%2C%22service%22%3A%22demo-load%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-1h%22%2C%22to%22%3A%22now%22%7D%7D%7D
- Prometheus Alerts: {{publicBaseURL}}/ui/prometheus/alerts
- Kubernetes / Compute Resources / Namespace: {{publicBaseURL}}/ui/grafana/d/85a562078cdf77779eaa1add43ccec1e?var-namespace=demo
