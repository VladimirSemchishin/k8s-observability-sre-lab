# k8s-observability-sre-lab

DigitalOcean Kubernetes (DOKS) observability lab.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
Task: https://github.com/VladimirSemchishin/tasks/issues/1

```
terraform/     # VPC + DOKS (Spaces tfstate)
helmfile/      # Traefik + Dashboard + kube-prometheus-stack + Loki + Alloy + Jaeger + OTel
```

## What Terraform creates

| Resource | Name / value |
|---|---|
| Spaces bucket (tfstate) | `tf-state-k8s-observability-sre-lab` (`nyc3`) |
| VPC | `k8s-observability-sre-lab-net` `10.10.10.0/24` |
| DOKS | `k8s-observability-sre-lab`, version `1.35.7-do.4`, `ha=false` |
| Node pool | **2 × `s-2vcpu-4gb`** (4 GiB / 2 vCPU each) |

HA control plane is **off**. Official provider default is `ha=true` on 1.36+ ($40/mo).

Traefik Load Balancer IP is created in the helmfile step (DOKS `Service` type `LoadBalancer`), not as a Reserved IP.

## Node size (why 2×4 GiB)

From `GET /v2/sizes` (account, 2026-09-12):

- `s-2vcpu-2gb` = 2 GiB — too small for Prom + Loki + Jaeger + Traefik + Dashboard + kube-system
- `s-2vcpu-4gb` = 4 GiB, **$24/mo = $0.03571/hr**
- `s-4vcpu-8gb` = 8 GiB on one node, $48/mo

Two `s-2vcpu-4gb` ≈ 8 GiB / 4 vCPU, **$0.071/hr**. Destroy after the test.

## Deploy Terraform

Need: Terraform >= 1.5, DigitalOcean API token, Spaces access key + secret.

1. Copy `terraform/terraform.tfvars.example` → `terraform/terraform.tfvars` and fill in.

2. Bucket (once; local state in `terraform/bootstrap/`):

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

3. Cluster (state in Spaces). Export Spaces keys as AWS creds for the S3 backend ([DO docs](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/)):

```bash
export AWS_ACCESS_KEY_ID="$spaces_access_id"
export AWS_SECRET_ACCESS_KEY="$spaces_secret_key"
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

4. Kubeconfig:

```bash
terraform -chdir=terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

5. Tear down (Helm first if applied, then):

```bash
terraform -chdir=terraform destroy
terraform -chdir=terraform/bootstrap destroy
```

## Helmfile

Official charts vendored under `helmfile/helm-charts/`:

- Traefik `41.5.0` / `v3.7.13` — `traefik.io` CRDs applied by a `presync` hook
- Kubernetes Dashboard `7.14.0` (last official release; project archived, helm repo 404). Kong stays in-cluster; Traefik is the edge.
- kube-prometheus-stack `90.1.1` / Operator `v0.93.1` as `helm-charts/kube-prometheus-stack-90.1.1.tgz`. Prometheus Operator CRDs (`prometheus-operator-crds` 31.0.1 slim extract) applied by a `presync` hook — not a Helm release (same size reason as Traefik).
- Loki `18.13.0` / `3.7.7` (grafana-community) — monolithic, filesystem PVC, no MinIO
- Grafana Alloy `1.12.1` / `v1.19.2` — DaemonSet, cluster/pod logs → Loki
- Jaeger `4.13.1` / `2.20.0` all-in-one (in-memory, no Operator / Tempo / OpenSearch)
- OpenTelemetry Collector `0.173.1` / `0.160.0` Deployment (OTLP in → `jaeger.jaeger.svc:4317`)

One command after the cluster exists (`skipDeps` is set — charts are local):

```bash
helmfile -f helmfile/helmfile.yaml sync
```

`sync` = hook (CRDs) + Helm upgrade, no plugins. `apply` also needs `helm-diff`.

UIs (Traefik default self-signed cert):

- Traefik: `https://<lb-ip>/ui/traefik`
- Kubernetes Dashboard: `https://<lb-ip>/ui/kubernetes-dashboard`
- Grafana: `https://<lb-ip>/ui/grafana`
- Prometheus: `https://<lb-ip>/ui/prometheus`
- Alertmanager: `https://<lb-ip>/ui/alertmanager` (kube-prometheus-stack; routePrefix, no stripPrefix)
- Jaeger: `https://<lb-ip>/ui/jaeger` (stripPrefix; in-cluster query is `jaeger.jaeger.svc:16686`)

Loki has no UI here. Alloy pushes to `http://loki.loki.svc.cluster.local:3100`.

Edge login for Traefik `/ui/traefik`, Grafana, Prometheus, Alertmanager, Jaeger: **admin / admin** (`ui-auth` basicAuth, `removeHeader: true`). Grafana login form is off (anonymous Admin). Prometheus/Grafana use cookies, not Bearer, so they stay on shared basicAuth.

Dashboard `/ui/kubernetes-dashboard`: **admin / admin** once (cookie gate). Traefik basicAuth is not used here — it 401-loops when the SPA sends `Authorization: Bearer`. After the cookie, helmfile injects the `admin-user` SA token so v7 skips the token form. Token is not in git.

Do not commit `terraform.tfvars` or `*.tfstate`.

## Step 6 — Loki logs + Telegram on stack Alertmanager

Logs: Alloy DaemonSet (clustering on so each node does not tail the whole cluster) ships pod logs to Loki in namespace `loki`. Persistence is a 10Gi filesystem PVC (DOKS default StorageClass). Memcached caches and MinIO are off to fit 2×4 GiB nodes.

Alerts: **one** Alertmanager — kube-prometheus-stack in namespace `monitoring`, UI at `/ui/alertmanager` (`routePrefix`, no stripPrefix). Do not add a second AM.

Telegram: placeholders in `helmfile/values/kube-prometheus-stack/telegram.yaml`. Real bot token / chat id go in gitignored `telegram.local.yaml` (copy `telegram.local.yaml.example`). helmfile warns if the local file is missing. This overlay does not change the Traefik IngressRoute or `alertmanagerSpec.routePrefix`.

## Step 7 — Traces (Jaeger + OpenTelemetry)

Jaeger all-in-one in namespace `jaeger` (memory store, no PVC). UI at `/ui/jaeger` behind Traefik `ui-auth` + `stripPrefix`. Collector Deployment in `opentelemetry-collector` receives OTLP (ClusterIP 4317/4318) and exports to `jaeger.jaeger.svc.cluster.local:4317`. Grafana Jaeger datasource is the same in-cluster query URL (sidecar reload is 403; postsync hook POSTs it).

## Grafana dashboards

Default kube-prometheus-stack dashboards are off (`grafana.defaultDashboardsEnabled: false`). Custom JSON lives in `helmfile/dashboards/<folder>/` — same layout as the GazProm stand (`k8s`, `loki`, `traefik`, `jaeger-opensearch`). Alloy and OTel folders were added for this lab. A helmfile hook loads them into ConfigMaps; the Grafana sidecar puts each directory in its own folder.

## Alerts

Basic service-down rules live in `helmfile/alerts/<service>/` (`prometheus`, `grafana`, `alertmanager`, `loki`, `alloy`, `traefik`, `jaeger`, `otel`, `k8s`). A helmfile `postsync` hook applies them as `PrometheusRule` objects (`release: kube-prometheus-stack`). They fire when `max(up{job=...}) == 0` or the job is absent, for 2m.

## Persistence, retention, HA

| Component | Disk | Retention | Replicas |
|---|---|---|---|
| Prometheus | 5Gi `do-block-storage` | 3d or 4GB | 1 |
| Grafana | 5Gi `do-block-storage` | n/a (dashboards in git/ConfigMaps) | 1 |
| Loki | 10Gi `do-block-storage` | 72h (compactor) | 1 |
| Alertmanager | 1Gi `do-block-storage` (silences / nflog) | 120h | 1 |
| Jaeger | none (in-memory) | process lifetime | 1 |
| Traefik | none | n/a | 1 |

HA is **off** on purpose: DOKS `ha=false`, 2× `s-2vcpu-4gb`. A second Prometheus/Loki replica does not fit. Control-plane HA would be a DigitalOcean toggle, not this helmfile.
