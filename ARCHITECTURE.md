# Architecture

How the lab is wired. How to run it: [README.md](./README.md).

```mermaid
flowchart TB
  subgraph clients [You]
    Browser
    kubectl
  end

  subgraph do [DigitalOcean nyc3]
    subgraph doks [DOKS 2 x s-2vcpu-4gb]
      API[API server]
      T[Traefik]
      G[Grafana]
      P[Prometheus]
      AM[Alertmanager]
      L[Loki]
      Al[Alloy]
      J[Jaeger]
      O[OTel Collector]
      KD[Kubernetes Dashboard]
    end
    VPC[VPC 10.10.10.0/24]
    LB[DOKS LoadBalancer]
  end

  kubectl --> API
  Browser -->|HTTPS /ui/* admin:admin| LB --> T
  T --> G & P & AM & J & KD
  Al -->|pod logs| L
  Workloads -->|OTLP| O --> J
  P & L & J -->|in-cluster DNS| G
  P --> AM
  AM -.-> Telegram
```

## Layers

1. **Terraform** — VPC + DOKS. State in Spaces. [terraform/README.md](./terraform/README.md)
2. **Helmfile** — Traefik, Dashboard, kube-prometheus-stack, Loki, Alloy, Jaeger, OTel. [helmfile/README.md](./helmfile/README.md)
3. **Edge** — one LB, path prefix `/ui/<service>`, shared basic auth except Kubernetes Dashboard (cookie gate)

Grafana datasources (Prometheus, Loki, Jaeger, Alertmanager) use Service DNS, so a new LB IP does not break them.

## Not in this stand

- Control-plane or app HA
- Persistent Jaeger (no OpenSearch / Cassandra)
- Kubecost / FinOps dashboards (use the DigitalOcean billing page)
- SLO burn alerts, chaos reports, incident write-ups
