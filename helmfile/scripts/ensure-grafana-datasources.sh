#!/usr/bin/env bash
# Ensure Grafana datasources via in-cluster Service DNS.
# Sidecar writes the YAML but reload is 403 (anonymous org Admin
# lacks provisioning:reload), so we POST through Grafana's API
# from a pod. Never use the Traefik LoadBalancer IP.
set -euo pipefail

NS=monitoring
POD=ensure-grafana-datasources
IMAGE=curlimages/curl:8.15.0

kubectl -n "$NS" wait --for=condition=available deploy/kube-prometheus-stack-grafana --timeout=180s
kubectl -n loki wait --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=180s

kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null

kubectl -n "$NS" run "$POD" --restart=Never --image="$IMAGE" --command -- /bin/sh -c '
set -eu
G=http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local/ui/grafana
ok=0
i=0
while [ "$i" -lt 30 ]; do
  if curl -sf --max-time 5 "$G/api/health" | grep -q database; then
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

ensure() {
  uid="$1"
  payload="$2"
  ds=$(curl -sf --max-time 8 "$G/api/datasources")
  if echo "$ds" | grep -Eq "\"uid\": ?\"$uid\""; then
    echo "grafana datasource $uid already present"
    return 0
  fi
  curl -sf --max-time 15 -H "Content-Type: application/json" -X POST "$G/api/datasources" -d "$payload"
  echo
  echo "grafana datasource $uid created"
}

ensure prometheus "{\"name\":\"Prometheus\",\"type\":\"prometheus\",\"uid\":\"prometheus\",\"access\":\"proxy\",\"isDefault\":true,\"url\":\"http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/ui/prometheus\",\"jsonData\":{\"httpMethod\":\"POST\",\"timeInterval\":\"30s\"}}"
ensure alertmanager "{\"name\":\"Alertmanager\",\"type\":\"alertmanager\",\"uid\":\"alertmanager\",\"access\":\"proxy\",\"url\":\"http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093/ui/alertmanager\",\"jsonData\":{\"handleGrafanaManagedAlerts\":false,\"implementation\":\"prometheus\"}}"
ensure loki "{\"name\":\"Loki\",\"type\":\"loki\",\"uid\":\"loki\",\"access\":\"proxy\",\"url\":\"http://loki.loki.svc.cluster.local:3100\",\"jsonData\":{\"timeout\":60,\"maxLines\":1000}}"
'

if ! kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$POD" --timeout=90s; then
  echo "ensure-grafana-datasources pod failed" >&2
  kubectl -n "$NS" logs "$POD" >&2 || true
  kubectl -n "$NS" describe pod "$POD" >&2 || true
  kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null || true
  exit 1
fi
kubectl -n "$NS" logs "$POD"
kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null
