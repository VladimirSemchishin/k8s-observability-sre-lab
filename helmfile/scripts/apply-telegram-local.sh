#!/usr/bin/env bash
# Patch Alertmanager secret from gitignored telegram.local.yaml. Do not print secrets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL="$ROOT/values/kube-prometheus-stack/telegram.local.yaml"
NS=monitoring
SECRET=alertmanager-kube-prometheus-stack-alertmanager

if [ ! -f "$LOCAL" ]; then
  echo "telegram.local.yaml absent; leaving placeholder AM config"
  exit 0
fi

python3 - "$LOCAL" "$NS" "$SECRET" << 'PY'
import json, re, subprocess, sys, tempfile, os

local, ns, secret = sys.argv[1:]
text = open(local).read()
m_tok = re.search(r"bot_token:\s*[\"']?([^\"'\s]+)[\"']?", text)
m_chat = re.search(r"chat_id:\s*(\S+)", text)
if not m_tok or not m_chat:
    print("telegram.local.yaml missing bot_token or chat_id", file=sys.stderr)
    sys.exit(1)
token, chat = m_tok.group(1), m_chat.group(1).strip().strip("\"'")
if "REPLACE" in token or chat in ("0",):
    print("telegram.local.yaml still placeholder", file=sys.stderr)
    sys.exit(1)

raw = subprocess.check_output(["kubectl", "-n", ns, "get", "secret", secret, "-o", "json"])
obj = json.loads(raw)
data = obj["data"]
import base64
key = "alertmanager.yaml" if "alertmanager.yaml" in data else next(iter(data))
cfg = base64.b64decode(data[key]).decode()
out = []
for line in cfg.splitlines():
    if "bot_token:" in line:
        out.append(re.sub(r"bot_token:\s*.*$", f"bot_token: {token}", line))
    elif re.search(r"chat_id:", line):
        out.append(re.sub(r"chat_id:\s*.*$", f"chat_id: {chat}", line))
    else:
        out.append(line)
cfg = "\n".join(out) + "\n"
if "REPLACE" in cfg:
    print("token placeholder remains", file=sys.stderr)
    sys.exit(1)
if re.search(r"chat_id:\s*0\b", cfg):
    print("chat_id still 0", file=sys.stderr)
    sys.exit(1)

fd, path = tempfile.mkstemp(prefix="am-cfg-", suffix=".yaml")
os.write(fd, cfg.encode())
os.close(fd)
try:
    subprocess.run(
        [
            "kubectl", "-n", ns, "create", "secret", "generic", secret,
            f"--from-file={key}={path}",
            "--dry-run=client", "-o", "yaml",
        ],
        check=True,
        stdout=open("/tmp/am-secret.yaml", "wb"),
    )
    subprocess.run(["kubectl", "-n", ns, "apply", "-f", "/tmp/am-secret.yaml"], check=True, stdout=subprocess.DEVNULL)
finally:
    os.remove(path)
    try:
        os.remove("/tmp/am-secret.yaml")
    except OSError:
        pass
print("alertmanager telegram overlay applied")
PY
