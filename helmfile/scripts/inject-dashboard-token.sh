#!/usr/bin/env bash
# Apply Traefik middleware that injects the lab admin-user SA token.
# Token is not stored in git; read from the bound Secret at sync time.
set -euo pipefail
NS=kubernetes-dashboard
SECRET=admin-user-token
TOKEN_B64=""
for _ in $(seq 1 30); do
  TOKEN_B64=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.token}' 2>/dev/null || true)
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
echo "dashboard-inject-token applied"
