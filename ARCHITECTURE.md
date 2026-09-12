# Architecture (agreed)

Portfolio stand for Gig A. Cloud: **DigitalOcean / DOKS** (`nyc3`). Budget top-up `N` is **not** set.

## Goal
Working DigitalOcean Kubernetes (DOKS) observability lab: metrics, logs, traces, alerting, SLO/SLI, FinOps, chaos/load evidence, 2 incident case studies. English README + diagram + short demo later.

## Repo layout
- `terraform/` — VPC + DOKS. Remote state in Spaces bucket `tf-state-k8s-observability-sre-lab`.
- `helmfile/` — local charts + values + releases (same idea as chatbot-infra-helm). One `helmfile sync`: presync hook applies `traefik.io` CRDs, then Traefik. Later stacks add a release file.

## Cluster
- **DigitalOcean Kubernetes (DOKS)**, managed control plane — **no** self-managed master nodes
- **Not** AWS / EKS
- Region `nyc3`, pool **2 × `s-2vcpu-4gb`**, k8s `1.35.7-do.4`, `ha=false`
- VPC `k8s-observability-sre-lab-net` `10.10.10.0/24`
- Public IP for Traefik comes from the DOKS LoadBalancer Service (not a DigitalOcean Reserved IP — those attach to Droplets only)

## Ingress / UI
- Traefik as the edge LB
- Path-prefix: `https://<lb-ip>/ui/<service>`
- Extra strip-prefix / root-url config is expected so Grafana, Dashboard, and Jaeger work behind a path
- Traefik basic auth in front (`admin` / `admin`); disable default auth on the apps behind it

UI list:
- Grafana — `/ui/grafana`
- Prometheus — `/ui/prometheus`
- Alertmanager — `/ui/alertmanager`
- Jaeger — `/ui/jaeger`
- Traefik dashboard — `/ui/traefik`
- Official **Kubernetes Dashboard** — `/ui/dashboard`
- **Not** kube-web-view

## Observability stack
- Metrics: Prometheus + Grafana (kube-prometheus-stack)
- Logs: Loki + Grafana Alloy
- Alerts: Alertmanager → Telegram
- Traces: OpenTelemetry collectors + **Jaeger** (not Tempo)
- FinOps: Kubecost and/or $/day, $/namespace (later steps)

## DigitalOcean / Terraform
- Auth: `do_token` in local `terraform/terraform.tfvars` (**gitignored**)
- Repo ships `terraform/terraform.tfvars.example` with an empty `do_token` placeholder only
- Do not commit the token
- Account top-up amount `N`: **TBD** — do not assume a number

## Out of scope for this file
Dollar budget top-up `N`.
