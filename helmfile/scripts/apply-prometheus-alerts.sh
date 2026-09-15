#!/usr/bin/env bash
# Apply helmfile/alerts/<service>/*.yaml as PrometheusRules (label release=kube-prometheus-stack).
# Substitutes {{publicBaseURL}} from values/lab.yaml before kubectl apply
# (same helper as dashboards). Does not touch Prometheus {{ $labels }} / {{ $value }}.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=monitoring
SRC="$ROOT/alerts"
PUBLIC_BASE_URL="$("$ROOT/scripts/public-base-url.sh")"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
shopt -s nullglob
for f in "$SRC"/*/*.yaml; do
  rel="${f#"$SRC"/}"
  out="$WORK/$rel"
  python3 "$ROOT/scripts/subst-public-base-url.py" --url "$PUBLIC_BASE_URL" "$f" "$out"
  kubectl apply --server-side --force-conflicts -f "$out"
done
echo "prometheus lab alerts applied"
