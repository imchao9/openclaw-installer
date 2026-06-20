#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/scripts/assets/download-sources.yml"
DRY_RUN=0
ONLY_IDS=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/refresh-download-assets.sh [--dry-run] [--asset id ...]

Downloads public assets whose check_method is "head" in scripts/assets/download-sources.yml.
Manual/page assets such as Apple Command Line Tools, DingTalk, AweSun, and Doubao
are intentionally skipped.

Examples:
  bash scripts/refresh-download-assets.sh --dry-run
  bash scripts/refresh-download-assets.sh
  bash scripts/refresh-download-assets.sh --asset codex-app --asset chrome
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --asset)
      if [[ $# -lt 2 ]]; then
        echo "--asset requires an id" >&2
        exit 1
      fi
      ONLY_IDS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 1
fi

is_selected() {
  local id="$1" selected
  if [[ "${#ONLY_IDS[@]}" -eq 0 ]]; then
    return 0
  fi
  for selected in "${ONLY_IDS[@]}"; do
    [[ "$selected" == "$id" ]] && return 0
  done
  return 1
}

ASSETS_TSV="$(mktemp "${TMPDIR:-/tmp}/openclaw-download-assets.XXXXXX.tsv")"
UPDATES_TSV="$(mktemp "${TMPDIR:-/tmp}/openclaw-download-updates.XXXXXX.tsv")"
cleanup() {
  rm -f "$ASSETS_TSV" "$UPDATES_TSV"
}
trap cleanup EXIT

python3 - "$MANIFEST" > "$ASSETS_TSV" <<'PY'
import re
import sys

manifest = sys.argv[1]
fields = {}

def clean(value):
    return value.strip().strip('"')

def flush():
    if not fields:
        return
    if fields.get("check_method") == "head" and fields.get("local_file") and fields.get("url"):
        print("\t".join([
            fields.get("id", ""),
            fields.get("local_file", ""),
            fields.get("url", ""),
            fields.get("sha256", ""),
        ]))

with open(manifest, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        id_match = re.match(r"\s+- id:\s+(.+?)\s*$", line)
        if id_match:
            flush()
            fields = {"id": clean(id_match.group(1))}
            continue
        item_match = re.match(r"\s+([a-zA-Z0-9_-]+):\s*(.*?)\s*$", line)
        if item_match and fields:
            fields[item_match.group(1)] = clean(item_match.group(2))

flush()
PY

today="$(date +%Y-%m-%d)"
changed=0

while IFS=$'\t' read -r asset_id local_file url old_sha; do
  [[ -n "$asset_id" ]] || continue
  if ! is_selected "$asset_id"; then
    continue
  fi

  target="$ROOT_DIR/$local_file"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/openclaw-${asset_id}.XXXXXX")"
  printf '%-18s %s\n' "$asset_id" "$url"
  printf '  target: %s\n' "$local_file"

  if [[ "$DRY_RUN" == "1" ]]; then
    rm -f "$tmp_file"
    continue
  fi

  mkdir -p "$(dirname "$target")"
  if ! curl -L --fail --show-error --progress-bar --connect-timeout 30 --max-time 1800 -o "$tmp_file" "$url"; then
    rm -f "$tmp_file"
    echo "  FAIL: download failed" >&2
    exit 1
  fi

  new_sha="$(shasum -a 256 "$tmp_file" | awk '{print $1}')"
  current_sha=""
  if [[ -f "$target" ]]; then
    current_sha="$(shasum -a 256 "$target" | awk '{print $1}')"
  fi

  if [[ "$current_sha" == "$new_sha" ]]; then
    rm -f "$tmp_file"
    printf '  unchanged: %s\n' "$new_sha"
  else
    mv "$tmp_file" "$target"
    printf '  updated: %s -> %s\n' "${current_sha:-missing}" "$new_sha"
    changed=1
  fi

  if [[ "$old_sha" != "$new_sha" ]]; then
    printf '%s\t%s\t%s\n' "$asset_id" "$new_sha" "$today" >> "$UPDATES_TSV"
  fi
done < "$ASSETS_TSV"

if [[ "$DRY_RUN" == "1" ]]; then
  exit 0
fi

if [[ -s "$UPDATES_TSV" ]]; then
  python3 - "$MANIFEST" "$UPDATES_TSV" <<'PY'
import sys

manifest, updates_path = sys.argv[1:3]
updates = {}
with open(updates_path, "r", encoding="utf-8") as f:
    for raw in f:
        asset_id, sha, verified_on = raw.rstrip("\n").split("\t")
        updates[asset_id] = {"sha256": sha, "verified_on": verified_on}

out = []
current_id = None
with open(manifest, "r", encoding="utf-8") as f:
    for raw in f:
        stripped = raw.strip()
        if stripped.startswith("- id:"):
            current_id = stripped.split(":", 1)[1].strip().strip('"')
        if current_id in updates and stripped.startswith("sha256:"):
            indent = raw[: len(raw) - len(raw.lstrip())]
            out.append(f'{indent}sha256: "{updates[current_id]["sha256"]}"\n')
            continue
        if current_id in updates and stripped.startswith("verified_on:"):
            indent = raw[: len(raw) - len(raw.lstrip())]
            out.append(f'{indent}verified_on: "{updates[current_id]["verified_on"]}"\n')
            continue
        if current_id in updates and stripped.startswith("verified_status:"):
            indent = raw[: len(raw) - len(raw.lstrip())]
            out.append(f'{indent}verified_status: "downloaded"\n')
            continue
        out.append(raw)

with open(manifest, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
    echo "manifest updated: scripts/assets/download-sources.yml"
fi

if [[ "$changed" == "1" ]]; then
  echo "download assets changed; rebuild install-files/package before upload."
else
  echo "all selected download assets already matched current files."
fi
