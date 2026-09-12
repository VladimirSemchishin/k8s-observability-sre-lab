# Architecture (agreed)

Portfolio stand for Gig A. Cloud switched to **DigitalOcean** on 2026-09-12. Budget top-up `N` is **not** set.

## Goal
Working DigitalOcean Kubernetes (DOKS) observability lab: metrics, logs, traces, alerting, SLO/SLI, FinOps, chaos/load evidence, 2 incident case studies. English README + diagram + short demo later.

## Cluster
- **DigitalOcean Kubernetes (DOKS)**, managed control plane — **no** self-managed master nodes
- **Not** AWS / EKS
- Worker node pool + DigitalOcean VPC
- Reserved IP / Load Balancer in front of Traefik

## Ingress / UI
- Traefik as the edge LB
- Path-prefix: `https://<lb-ip>/ui/<service>`
- Extra strip-prefix / root-url config is expected so Grafana, Dashboard, and Jaeger work behind a path
- Traefik basic auth in front; disable default auth on the apps behind it

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
- Auth: `do_token` (DigitalOcean Personal Access Token) in local `terraform.tfvars` (**gitignored**)
- Repo ships `terraform.tfvars.example` with an empty `do_token` placeholder only
- Do not commit the token
- Account top-up amount `N`: **TBD** — do not assume a number

## Out of scope for this file
Droplet/node sizes, region, node count, and dollar budget — still open.
