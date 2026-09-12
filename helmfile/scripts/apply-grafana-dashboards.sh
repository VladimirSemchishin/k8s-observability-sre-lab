#!/usr/bin/env bash
# Load JSON dashboards from helmfile/dashboards/<folder>/*.json into
# labeled ConfigMaps for the Grafana sidecar (folder = Grafana folder).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=monitoring
SRC="$ROOT/dashboards"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

shopt -s nullglob
for dir in "$SRC"/*/; do
  folder="$(basename "$dir")"
  files=("$dir"*.json)
  if [ ${#files[@]} -eq 0 ]; then
    continue
  fi
  name="grafana-dashboards-${folder}"
  args=()
  for f in "${files[@]}"; do
    args+=(--from-file="$(basename "$f")=$f")
  done
  kubectl -n "$NS" create configmap "$name" "${args[@]}" --dry-run=client -o yaml \
    | kubectl -n "$NS" apply -f -
  kubectl -n "$NS" label configmap "$name" grafana_dashboard=1 --overwrite
  kubectl -n "$NS" annotate configmap "$name" "grafana_folder=${folder}" --overwrite
  echo "applied $name -> folder $folder (${#files[@]} dashboards)"
done

if kubectl -n "$NS" get deploy kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/kube-prometheus-stack-grafana
  kubectl -n "$NS" rollout status deploy/kube-prometheus-stack-grafana --timeout=180s
fi
