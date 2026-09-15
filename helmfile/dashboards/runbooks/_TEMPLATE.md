# AlertNameHere

`metric_or_promql_here`

Что показывает метрика: кратко — что считает метрика и что происходит, когда срабатывает этот алерт.

---

Как чинить и куда смотреть если сработал этот алерт:

1. Шаг 1 — открыть связанный Grafana dashboard и подтвердить, что SLI/метрика действительно в красной зоне.
2. Шаг 2 — логи (Loki) по namespace/сервису, найти ошибку и `trace_id`.
3. Шаг 3 — трейсы (Jaeger / Grafana Jaeger) по сервису, сверить с `trace_id`.
4. Шаг 4 — устранить причину (фикc / остановить нагрузку) и проверить, что SLI вернулся в норму.

Ссылки на полезные источники:

- Grafana dashboard: {{publicBaseURL}}/ui/grafana/d/<dashboard-uid>/
- Логи в Grafana Explore / Loki: {{publicBaseURL}}/ui/grafana/d/k8s-app-logs?var-namespace=<ns>
- Трейсы Jaeger: {{publicBaseURL}}/ui/jaeger/search?service=<service>
