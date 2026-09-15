# Helmfile — observability stack

Installs the apps onto an existing DOKS cluster. Cluster create/destroy is [../terraform/README.md](../terraform/README.md).

```bash
export KUBECONFIG=/path/to/kubeconfig
helmfile -f helmfile/helmfile.yaml sync
```

`sync` runs hooks (CRDs) then Helm. Charts are vendored under `helm-charts/` (`skipDeps: true`). Prefer `sync` over `apply` — `apply` needs the `helm-diff` plugin.

## What gets installed

| Release | Namespace | Chart / app | Role |
|---|---|---|---|
| `traefik` | `traefik` | Traefik 41.5.0 / v3.7.13 | Edge LB + `/ui/*` |
| `kubernetes-dashboard` | `kubernetes-dashboard` | Dashboard 7.14.0 | Cluster UI |
| `kube-prometheus-stack` | `monitoring` | 90.1.1 / Operator v0.93.1 | Prometheus, Grafana, Alertmanager |
| `loki` | `loki` | 18.13.0 / 3.7.7 | Logs (monolithic, filesystem PVC) |
| `alloy` | `loki` | 1.12.1 / v1.19.2 | DaemonSet: node/pod logs → Loki |
| `jaeger` | `jaeger` | 4.13.1 / 2.20.0 | Traces, in-memory |
| `opentelemetry-collector` | `opentelemetry-collector` | 0.173.1 / 0.160.0 | OTLP 4317/4318 → `jaeger.jaeger.svc:4317` |

Order is the `bases:` list in `helmfile.yaml`. One Alertmanager only (the stack in `monitoring`).

`traefik.io` CRDs and Prometheus Operator CRDs (`monitoring.coreos.com`) are applied by Traefik's `presync` kubectl hook so a fresh `sync` can render Traefik's ServiceMonitor before kube-prometheus-stack (which `needs` Traefik). kube-prometheus-stack applies the same Prom CRDs again (idempotent). These are not Helm releases.

## UIs

All public UIs sit behind Traefik: `https://<lb-ip>/ui/<service>`. See the [root README](../README.md#user-interfaces).

The **single high-level value** for that host is `lab.publicBaseURL` in [`values/lab.yaml`](./values/lab.yaml) (scheme + host, no trailing slash). Helmfile loads it via `environments.default`. Grafana `root_url`, Prometheus/Alertmanager `externalUrl`, and links inside runbook/SLO dashboards (placeholder `{{publicBaseURL}}`) all come from there.

When the LoadBalancer IP changes (or you later put DNS in front):

```bash
kubectl -n traefik get svc traefik
# edit helmfile/values/lab.yaml  →  lab.publicBaseURL: "https://<EXTERNAL-IP>"
helmfile -f helmfile/helmfile.yaml sync
```

Do not hardcode the IP in dashboard JSON or runbook text.

Send traces to `opentelemetry-collector.opentelemetry-collector.svc.cluster.local:4317` (gRPC) or `:4318` (HTTP).

## Layout

```
helmfile/
  helmfile.yaml
  values/lab.yaml    # lab.publicBaseURL — LB IP or future DNS, one place
  releases/          # one file per Helm release
  values/<app>/      # common.yaml + routes.yaml
  helm-charts/       # vendored official charts
  dashboards/        # Grafana JSON (plus runbooks/*.md sources)
  alerts/            # PrometheusRule YAML, one folder per service
  scripts/           # helmfile hooks
```

## Dashboards

Default kube-prometheus-stack dashboards are off. JSON in `dashboards/<folder>/` (`k8s`, `loki` / K8s App Logs, `traefik`, `jaeger-opensearch`, `alloy`, `otel`, `sla-slo-sli`) is applied as ConfigMaps. The Grafana sidecar creates those folder names (`grafana_folder` annotation; directory `runbooks` is published as folder **Runbooks**).

`scripts/apply-grafana-dashboards.sh` (helmfile pre/postsync) also substitutes `{{publicBaseURL}}` from `values/lab.yaml`.

### Runbooks

Authors never write Grafana JSON for runbooks.

1. Copy `dashboards/runbooks/_TEMPLATE.md` to a new `dashboards/runbooks/<slug>.md` (not `_TEMPLATE*`).
2. Fill the alert name, PromQL, “что показывает”, steps, and links. Use `{{publicBaseURL}}` in URLs (do not paste the LB IP).
3. Commit. Next `helmfile sync` (or `scripts/apply-grafana-dashboards.sh`) runs `scripts/render-runbook-dashboards.py`: each file becomes a dashboard with one large Markdown **Text** panel in folder **Runbooks**. UID = filename stem.

Example: `demo-load-error-rate-slo-breach.md` → alert `DemoLoadErrorRateSLOBreach`.

### SLO (demo-load)

Folder `sla-slo-sli`, dashboard **SLA / SLO / SLI — demo-load** (`uid: slo-demo-load`):

- **SLA** — 99% successful HTTP responses (what we promise the customer)
- **SLO** — error rate **< 1%** over 5m (internal target; alert `DemoLoadErrorRateSLOBreach` in `alerts/demo/slo.yaml`)
- **SLI** — `5xx / total` on `demo_http_requests_total` for namespace `demo`

The 1% SLO is **meant to fire** during the existing k6 mix (~5% `GET /error`). After the Job is deleted, SLI should recover. Story: [`../for-load-test/README.md`](../for-load-test/README.md).

## Alerts

`alerts/<service>/down.yaml` becomes a `PrometheusRule` (`release: kube-prometheus-stack`). A service is down when `max(up{job=...}) == 0` or the job is missing, for 2 minutes. `alerts/demo/slo.yaml` is the demo-load error-rate SLO (`DemoLoadErrorRateSLOBreach`); runbook is auto-built from `dashboards/runbooks/`.

Default rules that cannot scrape on DOKS (controller-manager, kube-proxy, etcd, scheduler) and Watchdog are disabled.

## Persistence

| Component | Disk | Retention |
|---|---|---|
| Prometheus | 5Gi | 3d or 4GB |
| Grafana | 5Gi | dashboards also live in git |
| Loki | 10Gi | 72h (compactor) |
| Alertmanager | 1Gi | 120h (silences / nflog) |
| Jaeger | none | process lifetime |

Replicas stay at 1. HA does not fit this node pool.

## Telegram (optional)

Placeholders: `values/kube-prometheus-stack/telegram.yaml`.  
Real token / chat id: gitignored `telegram.local.yaml` (copy `telegram.local.yaml.example`). Helmfile warns if the local file is missing.

`parse_mode: HTML` with a compact `message` template: firing/resolved and severity emojis, then alertname, severity/service, summary, and runbook + Prometheus source as `click-me` links (not a raw label dump). Helm list-merge replaces `receivers`, so keep that `message` block in `telegram.local.yaml`.

## Destroy apps only

```bash
helmfile -f helmfile/helmfile.yaml destroy
```
