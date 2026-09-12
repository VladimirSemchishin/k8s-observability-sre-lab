#!/usr/bin/env bash
# One ConfigMap per dashboard JSON. Folder name = directory name (no numeric prefix).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=monitoring
SRC="$ROOT/dashboards"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# drop leftover numbered CMs from the failed first apply
kubectl -n "$NS" delete cm -l grafana_dashboard=1 -l grokbot-dashboard=1 --ignore-not-found >/dev/null || true
for old in grafana-dashboards-000-k8s grafana-dashboards-001-loki grafana-dashboards-005-traefik \
           grafana-dashboards-007-jaeger-opensearch grafana-dashboards-008-alloy grafana-dashboards-009-otel; do
  kubectl -n "$NS" delete cm "$old" --ignore-not-found >/dev/null || true
done

shopt -s nullglob
for dir in "$SRC"/*/; do
  folder="$(basename "$dir")"
  for f in "$dir"*.json; do
    base="$(basename "$f" .json)"
    name="grafana-dash-${folder}-${base}"
    # sanitize DNS-1123
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-63)"
    kubectl -n "$NS" create configmap "$name" --from-file="${base}.json=${f}" --dry-run=client -o yaml \
      | kubectl -n "$NS" apply --server-side --force-conflicts -f - >/dev/null
    kubectl -n "$NS" label configmap "$name" grafana_dashboard=1 grokbot-dashboard=1 --overwrite >/dev/null
    kubectl -n "$NS" annotate configmap "$name" "grafana_folder=${folder}" --overwrite >/dev/null
    echo "applied $name -> ${folder}/${base}.json"
  done
done

if kubectl -n "$NS" get deploy kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/kube-prometheus-stack-grafana
  kubectl -n "$NS" rollout status deploy/kube-prometheus-stack-grafana --timeout=180s
fi
