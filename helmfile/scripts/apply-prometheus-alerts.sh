#!/usr/bin/env bash
# Apply helmfile/alerts/<service>/*.yaml as PrometheusRules (label release=kube-prometheus-stack).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=monitoring
SRC="$ROOT/alerts"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
shopt -s nullglob
for f in "$SRC"/*/*.yaml; do
  kubectl apply --server-side --force-conflicts -f "$f"
done
echo "prometheus lab alerts applied"
