#!/usr/bin/env bash
# Print lab.publicBaseURL from helmfile/values/lab.yaml (scheme+host, no trailing slash).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/values/lab.yaml"
if [[ ! -f "$FILE" ]]; then
  echo "missing $FILE" >&2
  exit 1
fi
url="$(awk '
  $1 == "publicBaseURL:" {
    v = $2
    gsub(/["\047]/, "", v)
    sub(/\/+$/, "", v)
    print v
    exit
  }
' "$FILE")"
if [[ -z "$url" ]]; then
  echo "lab.publicBaseURL is empty in $FILE" >&2
  exit 1
fi
printf '%s\n' "$url"
