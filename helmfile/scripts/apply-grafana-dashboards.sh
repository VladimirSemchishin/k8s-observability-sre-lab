#!/usr/bin/env bash
# One ConfigMap per dashboard JSON. Folder name = directory name (no numeric prefix).
# Runbook sources (dashboards/runbooks/*.md|*.txt) are rendered to JSON first.
# {{publicBaseURL}} in JSON (and generated runbooks) is replaced from values/lab.yaml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=monitoring
SRC="$ROOT/dashboards"
PUBLIC_BASE_URL="$("$ROOT/scripts/public-base-url.sh")"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# drop leftover numbered CMs from the failed first apply
kubectl -n "$NS" delete cm -l grafana_dashboard=1 -l grokbot-dashboard=1 --ignore-not-found >/dev/null || true
for old in grafana-dashboards-000-k8s grafana-dashboards-001-loki grafana-dashboards-005-traefik \
           grafana-dashboards-007-jaeger-opensearch grafana-dashboards-008-alloy grafana-dashboards-009-otel; do
  kubectl -n "$NS" delete cm "$old" --ignore-not-found >/dev/null || true
done

grafana_folder_title() {
  case "$1" in
    runbooks) printf '%s' "Runbooks" ;;
    sla-slo-sli|slo) printf '%s' "SLA/SLO/SLI" ;;
    *) printf '%s' "$1" ;;
  esac
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$ROOT/scripts/render-runbook-dashboards.py" \
  --src "$SRC/runbooks" \
  --dst "$WORK/runbooks" \
  --public-base-url "$PUBLIC_BASE_URL"

apply_json() {
  local folder="$1"
  local f="$2"
  local base name title tmp
  base="$(basename "$f" .json)"
  name="grafana-dash-${folder}-${base}"
  # sanitize DNS-1123
  name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-63)"
  title="$(grafana_folder_title "$folder")"
  tmp="$WORK/${name}.json"
  python3 "$ROOT/scripts/subst-public-base-url.py" --url "$PUBLIC_BASE_URL" "$f" "$tmp"
  kubectl -n "$NS" create configmap "$name" --from-file="${base}.json=${tmp}" --dry-run=client -o yaml \
    | kubectl -n "$NS" apply --server-side --force-conflicts -f - >/dev/null
  kubectl -n "$NS" label configmap "$name" grafana_dashboard=1 grokbot-dashboard=1 --overwrite >/dev/null
  kubectl -n "$NS" annotate configmap "$name" "grafana_folder=${title}" --overwrite >/dev/null
  echo "applied $name -> ${title}/${base}.json"
}

shopt -s nullglob
for dir in "$SRC"/*/; do
  folder="$(basename "$dir")"
  if [[ "$folder" == "runbooks" ]]; then
    for f in "$WORK/runbooks"/*.json; do
      apply_json "$folder" "$f"
    done
    continue
  fi
  for f in "$dir"*.json; do
    apply_json "$folder" "$f"
  done
done

if kubectl -n "$NS" get deploy kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/kube-prometheus-stack-grafana
  kubectl -n "$NS" rollout status deploy/kube-prometheus-stack-grafana --timeout=180s
fi
