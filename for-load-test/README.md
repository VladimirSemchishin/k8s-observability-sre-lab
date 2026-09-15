# Load-proof: demo app + k6

Tiny Go service that hurts on purpose so the **already-deployed** helmfile stack can show it:

| Signal | Path |
|---|---|
| Traces | app → OTLP HTTP **4318** → OpenTelemetry Collector → Jaeger |
| Metrics (RED) | app `/metrics` → Prometheus Operator `ServiceMonitor` → Grafana |
| Logs | JSON stdout (`trace_id`) → Grafana Alloy → Loki → Grafana |

The lab collector is traces-only (`metrics` / `logs` pipelines are `null` in `helmfile/values/opentelemetry-collector/common.yaml`). Do not deploy a second collector. Alloy already tails pod logs.

OTLP default (matches helmfile):

`http://opentelemetry-collector.opentelemetry-collector.svc.cluster.local:4318`

gRPC on `:4317` is the same Service; this app uses HTTP/protobuf.

## Layout

```
for-load-test/
  app/          # Go service + Dockerfile
  k8s/          # Namespace demo, Deployment, Service, ServiceMonitor
  k8s/prebuilt/ # Deployment that runs a pushed image (IMAGE=)
  k6/           # script.js + in-cluster Job
  kustomization.yaml
  README.md
```

Endpoints: `GET /health` (200), `GET /work` (RED), `GET /slow` (1–3s), `GET /error` (500).

## 0. Cluster

Helmfile stack must already be up (`helmfile -f helmfile/helmfile.yaml sync`). `kubectl` talks to that cluster (`KUBECONFIG`).

## 1. Deploy the app (no registry)

Init container compiles from a ConfigMap using public images (`golang:1.23-alpine`, `gcr.io/distroless/static-debian12:nonroot`). First pod start waits on `go mod download` + compile (a minute or two).

```bash
kubectl apply -k for-load-test
kubectl -n demo rollout status deploy/demo-load --timeout=5m
kubectl -n demo get pods,svc
```

Expect namespace `demo`, one Ready pod, ClusterIP Service `demo-load:8080`.

## 2. Optional: build and push your own image

Use this instead of the in-cluster compile. No secrets belong in git; pass the tag yourself.

```bash
export IMAGE=registry.digitalocean.com/<registry>/demo-load:0.1.0   # any registry
docker build -t "$IMAGE" for-load-test/app
docker push "$IMAGE"

kubectl apply -f for-load-test/k8s/namespace.yaml \
  -f for-load-test/k8s/service.yaml \
  -f for-load-test/k8s/servicemonitor.yaml
sed "s|image: IMAGE|image: ${IMAGE}|" for-load-test/k8s/prebuilt/deployment.yaml | kubectl apply -f -
kubectl -n demo rollout status deploy/demo-load --timeout=3m
```

`IMAGE=` is the only override. DigitalOcean Container Registry (DOCR) works if `doctl registry login` (or equivalent) is already done on the machine that builds/pushes. The cluster must be able to pull that tag.

To switch back to in-cluster compile: `kubectl apply -k for-load-test`.

## 3. Run k6 (~3 min, 80% /work, 15% /slow, 5% /error)

**In-cluster Job** (needs no local k6):

```bash
kubectl -n demo delete job demo-load-k6 --ignore-not-found
kubectl apply -k for-load-test/k6
kubectl -n demo logs -f job/demo-load-k6
```

**Host-side** (k6 installed locally):

```bash
kubectl -n demo port-forward svc/demo-load 8080:8080
# other terminal:
k6 run -e BASE_URL=http://127.0.0.1:8080 for-load-test/k6/script.js
```

Override duration / VUs: `k6 run -e BASE_URL=... --vus 5 --duration 5m for-load-test/k6/script.js`.

In-cluster base URL default: `http://demo-load.demo.svc.cluster.local:8080`.

## 4. What to look for

Replace `<lb-ip>` with `kubectl -n traefik get svc traefik` (lab login `admin` / `admin`).

**Grafana → Explore → Prometheus**

- `sum(rate(demo_http_requests_total{namespace="demo"}[1m])) by (path, code)` — `/work` dominates; `/error` is ~5% and `code="500"`.
- `histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket{namespace="demo"}[1m])) by (le, path))` — `/slow` around 1–3s.

Target job is `demo-load` (Prometheus → Status → Targets).

**Grafana → Explore → Loki**

- `{namespace="demo"} | json` — `path`, `status`, `trace_id`.
- Filter errors: `{namespace="demo"} | json | status = 500`.

**Jaeger** (`https://<lb-ip>/ui/jaeger`)

- Service `demo-load`. Operations `GET /work`, `GET /slow`, `GET /error`.
- Error spans are tagged; open one and copy `trace_id` into the Loki query `{namespace="demo"} | json | trace_id = "<id>"`.

**Grafana → folder `k8s`** — namespace `demo` CPU/memory while k6 runs.

## Tear down

```bash
kubectl delete -k for-load-test/k6 --ignore-not-found
kubectl delete -k for-load-test
```

## Notes

- Resources are tiny (fits the 2 × s-2vcpu-4gb pool). Init compile is 512Mi **limit** and goes away when the container finishes.
- No Ingress; load is in-cluster or via port-forward.
- If traces are missing: `kubectl -n demo logs deploy/demo-load` (OTLP errors) and `kubectl -n opentelemetry-collector get svc`.
- If metrics are missing: confirm `ServiceMonitor` `demo/demo-load` has label `release: kube-prometheus-stack` and the kube-prometheus-stack CRDs exist.
