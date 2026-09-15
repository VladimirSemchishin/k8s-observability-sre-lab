#!/usr/bin/env python3
"""Replace {{publicBaseURL}} with lab.publicBaseURL. Leave Prometheus {{ $value }} alone."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

PLACEHOLDER = "{{publicBaseURL}}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="scheme+host, no trailing slash")
    parser.add_argument("src", type=Path)
    parser.add_argument("dst", type=Path)
    args = parser.parse_args()
    url = args.url.strip().rstrip("/")
    if not url:
        print("empty public base URL", file=sys.stderr)
        return 1
    text = args.src.read_text(encoding="utf-8")
    out = text.replace(PLACEHOLDER, url)
    if PLACEHOLDER in out:
        print(f"leftover {PLACEHOLDER} in {args.src}", file=sys.stderr)
        return 1
    args.dst.parent.mkdir(parents=True, exist_ok=True)
    args.dst.write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
