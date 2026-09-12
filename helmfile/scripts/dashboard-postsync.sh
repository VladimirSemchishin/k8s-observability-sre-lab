#!/usr/bin/env bash
# Cookie gate + SA token inject. Do not print secrets.
set -euo pipefail
NS=kubernetes-dashboard
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! kubectl -n "$NS" get secret dashboard-gate >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic dashboard-gate \
    --from-literal=user=admin \
    --from-literal=pass=admin \
    --from-literal=secret="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
fi

kubectl -n "$NS" create configmap dashboard-gate \
  --from-file=dashboard-gate.py="$ROOT/scripts/dashboard-gate.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl apply -f "$ROOT/manifests/dashboard-gate.yaml" >/dev/null
kubectl -n "$NS" rollout status deploy/dashboard-gate --timeout=180s >/dev/null

TOKEN_B64=""
for _ in $(seq 1 30); do
  TOKEN_B64=$(kubectl -n "$NS" get secret admin-user-token -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [ -n "$TOKEN_B64" ]; then
    break
  fi
  sleep 2
done
if [ -z "$TOKEN_B64" ]; then
  echo "admin-user-token not ready" >&2
  exit 1
fi
BEARER=$(printf '%s' "$TOKEN_B64" | base64 -d)
kubectl apply -f - >/dev/null <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: dashboard-inject-token
  namespace: ${NS}
spec:
  headers:
    customRequestHeaders:
      Authorization: "Bearer ${BEARER}"
EOF
echo "dashboard gate + token inject ready"
