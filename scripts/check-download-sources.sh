#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/scripts/assets/download-sources.yml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY' | while IFS=$'\t' read -r asset_id url; do
import re
import sys

manifest = sys.argv[1]
current_id = ""
current_url = ""
current_method = ""

def flush():
    if current_id and current_url and current_method == "head":
        print(f"{current_id}\t{current_url}")

with open(manifest, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        id_match = re.match(r"\s+- id:\s+(.+?)\s*$", line)
        if id_match:
            flush()
            current_id = id_match.group(1).strip().strip('"')
            current_url = ""
            current_method = ""
            continue
        url_match = re.match(r"\s+url:\s+(.+?)\s*$", line)
        if url_match:
            current_url = url_match.group(1).strip().strip('"')
            continue
        method_match = re.match(r"\s+check_method:\s+(.+?)\s*$", line)
        if method_match:
            current_method = method_match.group(1).strip().strip('"')

flush()
PY
  printf '%-18s %s\n' "$asset_id" "$url"
  if curl -L --head --silent --show-error --fail --max-time 30 "$url" >/dev/null; then
    echo "  OK"
  else
    echo "  FAIL"
    exit 1
  fi
done
