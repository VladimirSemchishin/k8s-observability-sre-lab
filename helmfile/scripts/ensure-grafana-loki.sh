#!/usr/bin/env bash
# Ensure Grafana has a Loki datasource via in-cluster DNS.
# Sidecar reload is 403 (anonymous org Admin lacks provisioning:reload).
# Helmfile runs this on the operator machine; curl runs in a pod so we
# never depend on the Traefik LoadBalancer IP.
set -euo pipefail

NS=monitoring
POD=ensure-grafana-loki
IMAGE=curlimages/curl:8.15.0

kubectl -n "$NS" wait --for=condition=available deploy/kube-prometheus-stack-grafana --timeout=180s
kubectl -n loki wait --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=180s

kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null

kubectl -n "$NS" run "$POD" --restart=Never --image="$IMAGE" --command -- /bin/sh -c '
set -eu
GRAFANA=http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local/ui/grafana
ok=0
i=0
while [ "$i" -lt 30 ]; do
  if curl -sf --max-time 5 "$GRAFANA/api/health" | grep -q database; then
    ok=1
    break
  fi
  i=$((i+1))
  sleep 2
done
if [ "$ok" -ne 1 ]; then
  echo "grafana health not ready" >&2
  exit 1
fi
if curl -sf --max-time 8 "$GRAFANA/api/datasources" | grep -Eq '"'"'"type": ?"loki"'"'"'; then
  echo "grafana loki datasource already present"
  exit 0
fi
curl -sf --max-time 15 -H "Content-Type: application/json" -X POST "$GRAFANA/api/datasources" \
  -d "{\"name\":\"Loki\",\"type\":\"loki\",\"uid\":\"loki\",\"access\":\"proxy\",\"url\":\"http://loki.loki.svc.cluster.local:3100\",\"jsonData\":{\"timeout\":60,\"maxLines\":1000}}"
echo
echo "grafana loki datasource created"
'

if ! kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$POD" --timeout=90s; then
  echo "ensure-grafana-loki pod failed" >&2
  kubectl -n "$NS" logs "$POD" >&2 || true
  kubectl -n "$NS" describe pod "$POD" >&2 || true
  kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null || true
  exit 1
fi
kubectl -n "$NS" logs "$POD"
kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null
