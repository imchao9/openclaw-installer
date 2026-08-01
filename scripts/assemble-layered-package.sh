#!/usr/bin/env bash
# Merge verified OpenClaw layers into one profile-specific install directory.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE=""
OUTPUT_DIR=""
LAYER_DIR="${LAYER_DIR:-$ROOT/upload-packages}"
LAYER_INDEX="${LAYER_INDEX:-$LAYER_DIR/openclaw-layer-index.json}"
OVERWRITE_ASSEMBLED="${OVERWRITE_ASSEMBLED:-0}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/assemble-layered-package.sh --profile PROFILE --output-dir DIR [options]
  bash scripts/assemble-layered-package.sh PROFILE OUTPUT_DIR

Supported profiles:
  macos14-x64, macos15-x64, macos15-arm64, macos26-arm64

Environment:
  LAYER_DIR=/path/to/layers
  LAYER_INDEX=/path/to/openclaw-layer-index.json
  OVERWRITE_ASSEMBLED=1
EOF
}

case "${1:-}" in
  --*|'') ;;
  *)
    PROFILE="${1:-}"
    OUTPUT_DIR="${2:-}"
    shift "$(( $# >= 2 ? 2 : $# ))"
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || { echo "--profile requires a value" >&2; exit 2; }
      PROFILE="$2"
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { echo "--output-dir requires a value" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --packages-dir)
      [ "$#" -ge 2 ] || { echo "--packages-dir requires a value" >&2; exit 2; }
      LAYER_DIR="$2"
      shift 2
      ;;
    --index)
      [ "$#" -ge 2 ] || { echo "--index requires a value" >&2; exit 2; }
      LAYER_INDEX="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$PROFILE" in
  macos14-x64|macos15-x64|macos15-arm64|macos26-arm64) ;;
  '')
    usage
    exit 2
    ;;
  *)
    echo "Unsupported profile: $PROFILE" >&2
    exit 2
    ;;
esac

[ -n "$OUTPUT_DIR" ] || {
  usage >&2
  exit 2
}
[ -f "$LAYER_INDEX" ] || {
  echo "Layer index not found: $LAYER_INDEX" >&2
  exit 1
}

if [ -e "$OUTPUT_DIR" ]; then
  [ "$OVERWRITE_ASSEMBLED" = "1" ] || {
    echo "Output exists; set OVERWRITE_ASSEMBLED=1: $OUTPUT_DIR" >&2
    exit 1
  }
  rm -rf "$OUTPUT_DIR"
fi

index_checksum="${LAYER_INDEX%.json}.sha256"
if [ -f "$index_checksum" ]; then
  (
    cd "$(dirname "$LAYER_INDEX")"
    shasum -a 256 -c "$(basename "$index_checksum")"
  )
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-layer-assemble.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

layer_names="$(
  /usr/bin/python3 - "$LAYER_INDEX" "$LAYER_DIR" "$PROFILE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
layer_dir = Path(sys.argv[2])
profile_name = sys.argv[3]
index = json.loads(index_path.read_text())
profile = index.get("profiles", {}).get(profile_name)
if not profile:
    raise SystemExit(f"profile missing from layer index: {profile_name}")
for layer_id in profile.get("layers", []):
    layer = index.get("layers", {}).get(layer_id)
    if not layer:
        raise SystemExit(f"layer missing from index: {layer_id}")
    path = layer_dir / layer["file"]
    if not path.is_file():
        raise SystemExit(f"layer archive missing: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != layer["sha256"]:
        raise SystemExit(f"layer checksum mismatch: {path}")
    if path.stat().st_size != layer["size_bytes"]:
        raise SystemExit(f"layer size mismatch: {path}")
    print(layer["file"])
PY
)"

while IFS= read -r layer_name; do
  [ -n "$layer_name" ] || continue
  archive="$LAYER_DIR/$layer_name"
  if command -v zstd >/dev/null 2>&1; then
    zstd -dc "$archive" | tar -xf - -C "$work_dir"
  else
    tar -xf "$archive" -C "$work_dir"
  fi
done <<EOF
$layer_names
EOF

package_root="$work_dir/openclaw-layered"
dist="$package_root/install-files"
[ -f "$package_root/install-openclaw.sh" ] || {
  echo "Common layer did not provide install-openclaw.sh" >&2
  exit 1
}
[ -d "$dist/openclaw-team" ] || {
  echo "Layer composition did not provide openclaw-team assets" >&2
  exit 1
}

/usr/bin/python3 - "$LAYER_INDEX" "$PROFILE" "$dist" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
profile_name = sys.argv[2]
dist = Path(sys.argv[3])
index = json.loads(index_path.read_text())
profile = index["profiles"][profile_name]
manifest = profile["dist_manifest"]
(dist / "DIST_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
for asset in manifest.get("required_assets", []):
    path = dist / asset["path"]
    if not path.is_file():
        raise SystemExit(f"required asset missing after assembly: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != asset["sha256"]:
        raise SystemExit(f"required asset checksum mismatch: {asset['path']}")
    if path.stat().st_size != asset["size_bytes"]:
        raise SystemExit(f"required asset size mismatch: {asset['path']}")
print(
    f"assembled profile={profile_name} arch={manifest['target_arch']} "
    f"assets={len(manifest.get('required_assets', []))}"
)
PY

cat > "$dist/DIST_MANIFEST.md" <<EOF
# Layered Dist Manifest

Profile: \`$PROFILE\`
Layer index: \`$(basename "$LAYER_INDEX")\`

This directory was assembled from verified common, architecture, and OS layers.
Use \`DIST_MANIFEST.json\` as the machine-readable asset contract.
EOF

chmod +x \
  "$package_root/install-openclaw.sh" \
  "$dist/install-new-macbook.sh" \
  "$dist/install-openclaw.sh" \
  "$dist/apply-person-key.sh" \
  "$dist/setup-mac-autostart.sh" \
  "$dist/make-package.sh"

mkdir -p "$(dirname "$OUTPUT_DIR")"
mv "$package_root" "$OUTPUT_DIR"
trap - EXIT
rm -rf "$work_dir"
printf 'Layered package ready: %s\n' "$OUTPUT_DIR"
