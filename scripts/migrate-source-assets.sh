#!/usr/bin/env bash
# Move ignored DMG/PKG/TGZ source assets into their single canonical location.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROM="$ROOT/openclaw-team"
TO="${OPENCLAW_ASSET_SOURCE_DIR:-$ROOT/upload-packages/source-assets/openclaw-team}"
APPLY=0

usage() {
  cat <<'EOF'
Usage: bash scripts/migrate-source-assets.sh [--apply]

Without --apply, prints the assets that would be moved. With --apply, moves only
ignored DMG, PKG and TGZ files into upload-packages/source-assets/openclaw-team/.
Git-tracked scripts and application launchers stay in openclaw-team/.
EOF
}

case "${1:-}" in
  '') ;;
  --apply) APPLY=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

assets=()
while IFS= read -r -d '' path; do
  assets+=("$path")
done < <(find "$FROM" -maxdepth 1 -type f \( -name '*.dmg' -o -name '*.pkg' -o -name '*.tgz' \) -print0 | sort -z)

[ "${#assets[@]}" -gt 0 ] || { echo "No source assets to migrate."; exit 0; }
for source in "${assets[@]}"; do
  target="$TO/${source##*/}"
  if [ -e "$target" ]; then
    echo "CONFLICT: destination already exists: $target" >&2
    exit 1
  fi
done

if [ "$APPLY" != "1" ]; then
  printf 'Would move %d source assets to %s:\n' "${#assets[@]}" "$TO"
  printf '  %s\n' "${assets[@]#$FROM/}"
  exit 0
fi

mkdir -p "$TO"
for source in "${assets[@]}"; do
  mv "$source" "$TO/${source##*/}"
done
rm -f "$FROM/.DS_Store"
printf 'Moved %d source assets to %s\n' "${#assets[@]}" "$TO"
