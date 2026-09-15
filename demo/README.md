# Demo

Two kinds of proof from the same lab:

| Folder | What it shows |
|---|---|
| [`stand-screenshots/`](./stand-screenshots/) | **Stack is up.** Grafana dashboards and service UIs after `helmfile sync` (install proof). |
| [`sla-incident/`](./sla-incident/) | **Reliability flow.** `demo-load` SLO breach → Telegram / Alertmanager → runbook → Loki logs → Jaeger traces → recovery. |

Login is `admin` / `admin`. Public URLs are `https://<lb-ip>/ui/<service>`; the single source for that host is `lab.publicBaseURL` in [`helmfile/values/lab.yaml`](../helmfile/values/lab.yaml).
