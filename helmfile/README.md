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

`traefik.io` and Prometheus Operator CRDs are applied by `presync` kubectl hooks, not as Helm releases.

## UIs

All public UIs sit behind Traefik: `https://<lb-ip>/ui/<service>`. See the [root README](../README.md#user-interfaces).

Send traces to `opentelemetry-collector.opentelemetry-collector.svc.cluster.local:4317` (gRPC) or `:4318` (HTTP).

## Layout

```
helmfile/
  helmfile.yaml
  releases/          # one file per Helm release
  values/<app>/      # common.yaml + routes.yaml
  helm-charts/       # vendored official charts
  dashboards/        # Grafana JSON, one folder per service
  alerts/            # PrometheusRule YAML, one folder per service
  scripts/           # helmfile hooks
```

## Dashboards

Default kube-prometheus-stack dashboards are off. JSON in `dashboards/<folder>/` (`k8s`, `loki` / K8s App Logs, `traefik`, `jaeger-opensearch`, `alloy`, `otel`) is applied as ConfigMaps. The Grafana sidecar creates those folder names.

## Alerts

`alerts/<service>/down.yaml` becomes a `PrometheusRule` (`release: kube-prometheus-stack`). A service is down when `max(up{job=...}) == 0` or the job is missing, for 2 minutes.

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

## Destroy apps only

```bash
helmfile -f helmfile/helmfile.yaml destroy
```
