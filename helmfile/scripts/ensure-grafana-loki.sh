#!/usr/bin/env bash
# Ensure Grafana has a Loki datasource. Sidecar reload is 403 under anonymous Admin.
set -euo pipefail
for _ in $(seq 1 30); do
  if curl -sk --max-time 5 -u admin:admin https://134.199.251.14/ui/grafana/api/health | grep -q '"database":"ok"'; then
    break
  fi
  sleep 2
done
if curl -sk --max-time 8 -u admin:admin https://134.199.251.14/ui/grafana/api/datasources | grep -q '"type":"loki"'; then
  echo "grafana loki datasource already present"
  exit 0
fi
curl -sk --max-time 15 -u admin:admin -H 'Content-Type: application/json' \
  -X POST https://134.199.251.14/ui/grafana/api/datasources \
  -d '{"name":"Loki","type":"loki","uid":"loki","access":"proxy","url":"http://loki.loki.svc.cluster.local:3100","jsonData":{"timeout":60,"maxLines":1000}}' \
  >/dev/null
echo "grafana loki datasource created"
