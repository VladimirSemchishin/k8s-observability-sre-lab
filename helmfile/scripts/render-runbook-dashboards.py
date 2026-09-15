#!/usr/bin/env python3
"""Turn helmfile/dashboards/runbooks text files into Grafana dashboard JSON.

Authors copy _TEMPLATE.md, fill it in, and commit. This script (called from
apply-grafana-dashboards.sh) wraps each file in a large Markdown text panel
and substitutes {{publicBaseURL}}. Files matching _TEMPLATE* are skipped.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SKIP_TEMPLATE = re.compile(r"^_TEMPLATE", re.IGNORECASE)
UID_UNSAFE = re.compile(r"[^a-zA-Z0-9_-]+")
TEXT_SUFFIXES = {".md", ".txt"}


def grafana_uid(stem: str) -> str:
    uid = UID_UNSAFE.sub("-", stem).strip("-_")
    if not uid:
        raise SystemExit(f"cannot derive Grafana uid from {stem!r}")
    return uid[:40]


def dashboard_title(text: str, fallback: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("<!--"):
            continue
        return stripped.lstrip("#").strip() or fallback
    return fallback


def should_skip(path: Path) -> bool:
    name = path.name
    if name.startswith("."):
        return True
    if SKIP_TEMPLATE.match(name):
        return True
    if path.suffix.lower() not in TEXT_SUFFIXES:
        return True
    return False


def render_dashboard(path: Path, public_base_url: str) -> dict:
    raw = path.read_text(encoding="utf-8")
    content = raw.replace("{{publicBaseURL}}", public_base_url)
    title = dashboard_title(content, path.stem)
    return {
        "editable": True,
        "schemaVersion": 39,
        "tags": ["runbook"],
        "title": title,
        "uid": grafana_uid(path.stem),
        "timezone": "browser",
        "refresh": "",
        "time": {"from": "now-6h", "to": "now"},
        "templating": {"list": []},
        "annotations": {"list": []},
        "links": [],
        "panels": [
            {
                "id": 1,
                "type": "text",
                "title": "Runbook",
                "gridPos": {"h": 32, "w": 24, "x": 0, "y": 0},
                "transparent": True,
                "options": {
                    "mode": "markdown",
                    "code": {
                        "language": "markdown",
                        "showLineNumbers": False,
                        "showMiniMap": False,
                    },
                    "content": content,
                },
            }
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", required=True, type=Path, help="runbooks source directory")
    parser.add_argument("--dst", required=True, type=Path, help="directory for generated JSON")
    parser.add_argument(
        "--public-base-url",
        required=True,
        help="lab.publicBaseURL (scheme+host, no trailing slash)",
    )
    args = parser.parse_args()
    public_base_url = args.public_base_url.strip().rstrip("/")
    if not public_base_url:
        print("public-base-url is empty", file=sys.stderr)
        return 1
    if not args.src.is_dir():
        print(f"no runbooks directory at {args.src}, skipping", file=sys.stderr)
        args.dst.mkdir(parents=True, exist_ok=True)
        return 0

    args.dst.mkdir(parents=True, exist_ok=True)
    rendered = 0
    for path in sorted(args.src.iterdir()):
        if not path.is_file() or should_skip(path):
            continue
        dashboard = render_dashboard(path, public_base_url)
        out = args.dst / f"{path.stem}.json"
        out.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"rendered runbook {path.name} -> {out.name} uid={dashboard['uid']}")
        rendered += 1
    if rendered == 0:
        print(f"no runbook files rendered from {args.src} (template-only is OK)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
