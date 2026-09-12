#!/usr/bin/env bash
# Official Traefik CRDs only (traefik.io). The full traefik-crds Helm chart
# exceeds the 1MiB Helm release Secret limit.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
kubectl apply -f "$DIR/helm-charts/traefik-crds/crds-files/traefik/"
