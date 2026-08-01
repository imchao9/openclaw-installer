#!/usr/bin/env bash
# Target-side downloader for OpenClaw installer archives and layered packages.
set -euo pipefail

PACKAGE_URL="${PACKAGE_URL:-${1:-}}"
CHECKSUM_URL="${CHECKSUM_URL:-${2:-}}"
PACKAGE_PROFILE="${PACKAGE_PROFILE:-}"
PACKAGE_BASE_URL="${PACKAGE_BASE_URL:-}"
LAYER_INDEX_URL="${LAYER_INDEX_URL:-}"
LAYER_INDEX_CHECKSUM_URL="${LAYER_INDEX_CHECKSUM_URL:-}"
ASSEMBLER_SCRIPT="${ASSEMBLER_SCRIPT:-/tmp/assemble-layered-package.sh}"
REMOTE_RUN_DIR="${REMOTE_RUN_DIR:-$HOME/openclaw-installer-run}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/.cache/openclaw-installer}"
INSTALL_ZSTD_IF_MISSING="${INSTALL_ZSTD_IF_MISSING:-0}"
ZSTD_INSTALL_PID=""
ZSTD_EXTRACTOR=""
ZSTD_PROBE_BASE64='KLUv/WQAD0UKABJPNzRQbdMB0GZm2rT8LKLEzEzNhicmozZqDPumGR6CaD8t2aJsS1ha3mTvvSUNdVlV2HxasDYFtQLTstgtMUcTl4qyZJYSow1vm4sGPc9nYaoeporTto2GnAJERVkwU0J12SkjCuQZn3zsGjaMTyLMrtQrY7uWYWgvuyH3gVYtaKVC1IECEYkI+Rgx+ETyanVop3JgWuYqJ8uouzCLQDLwvwOj0Uwev+f/+y/wXYnNNKxFGf7JAwoAllMrBuiymK/RbePD+ynBbl4453v94JO9MD5mZpbS3BglZr4GRuECKCDwgpGisMAN/Qsq+E6BXWCrarIBVId3MwAMCMPlNwEGsq7uvMVBPGaI7PQGq27scIAdwy2wEzKVKkif/A3ftVZtgIz68Hd4eSw4wzZKCtYshyXDAnCKToVKkAfwap4juXJurM3T1QLiFg11'

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

decode_zstd_probe() {
  local output="$1"
  if base64 --help 2>&1 | grep -q -- '-d'; then
    printf '%s' "$ZSTD_PROBE_BASE64" | base64 -d > "$output"
  else
    printf '%s' "$ZSTD_PROBE_BASE64" | base64 -D > "$output"
  fi
}

detect_zstd_extractor() {
  local probe
  if command -v zstd >/dev/null 2>&1; then
    printf 'zstd\n'
    return 0
  fi
  probe="$(mktemp "${TMPDIR:-/tmp}/openclaw-zstd-probe.XXXXXX.tar.zst")"
  decode_zstd_probe "$probe"
  if tar -tf "$probe" >/dev/null 2>&1; then
    rm -f "$probe"
    printf 'tar\n'
    return 0
  fi
  rm -f "$probe"
  return 1
}

prepare_zstd_extractor() {
  if ZSTD_EXTRACTOR="$(detect_zstd_extractor)"; then
    log "ZSTD_EXTRACTOR=$ZSTD_EXTRACTOR"
    return 0
  fi
  if [ "$INSTALL_ZSTD_IF_MISSING" = "1" ] && command -v brew >/dev/null 2>&1; then
    log "zstd extractor missing; starting explicit Homebrew install in parallel with download"
    brew install zstd &
    ZSTD_INSTALL_PID="$!"
    ZSTD_EXTRACTOR="pending-homebrew"
    return 0
  fi
  echo "No tar.zst extractor is available. Install zstd, use a compatible tar, or set INSTALL_ZSTD_IF_MISSING=1 when Homebrew is available." >&2
  return 3
}

wait_for_zstd_extractor() {
  if [ -n "$ZSTD_INSTALL_PID" ]; then
    wait "$ZSTD_INSTALL_PID"
    ZSTD_INSTALL_PID=""
  fi
  ZSTD_EXTRACTOR="$(detect_zstd_extractor)" || {
    echo "zstd preparation finished without a usable extractor" >&2
    return 3
  }
  log "ZSTD_EXTRACTOR=$ZSTD_EXTRACTOR"
}

if [ "${1:-}" = "--check-zstd" ]; then
  prepare_zstd_extractor
  wait_for_zstd_extractor
  exit 0
fi

if [ -z "$PACKAGE_PROFILE" ] && [ -z "$PACKAGE_URL" ]; then
  echo "Usage: PACKAGE_PROFILE=macos15-arm64 PACKAGE_BASE_URL=http://host:8765 bash fetch-package-over-http.sh" >&2
  echo "Legacy: PACKAGE_URL=http://host:8765/openclaw-macos15-arm64.tar.zst bash fetch-package-over-http.sh" >&2
  exit 1
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command curl
require_command tar
require_command shasum
prepare_zstd_extractor

replace_remote_run_dir() {
  local source_dir="$1"
  local pending_dir="${REMOTE_RUN_DIR}.layered-new.$$"

  rm -rf "$pending_dir"
  mkdir -p "$pending_dir"
  cp -R "$source_dir/." "$pending_dir/"
  chmod +x "$pending_dir/install-openclaw.sh" "$pending_dir/install-files/install-new-macbook.sh" "$pending_dir/install-files/install-openclaw.sh" "$pending_dir/dist/install-new-macbook.sh" "$pending_dir/dist/install-openclaw.sh" 2>/dev/null || true
  rm -rf "$REMOTE_RUN_DIR"
  mv "$pending_dir" "$REMOTE_RUN_DIR"
}

if [ -n "$PACKAGE_PROFILE" ]; then
  require_command /usr/bin/python3
  [ -x "$ASSEMBLER_SCRIPT" ] || {
    echo "Layer assembler is missing or not executable: $ASSEMBLER_SCRIPT" >&2
    exit 1
  }

  if [ -z "$LAYER_INDEX_URL" ]; then
    [ -n "$PACKAGE_BASE_URL" ] || {
      echo "PACKAGE_BASE_URL or LAYER_INDEX_URL is required for layered download" >&2
      exit 1
    }
    LAYER_INDEX_URL="${PACKAGE_BASE_URL%/}/openclaw-layer-index.json"
  fi
  if [ -z "$PACKAGE_BASE_URL" ]; then
    PACKAGE_BASE_URL="${LAYER_INDEX_URL%/*}"
  fi
  if [ -z "$LAYER_INDEX_CHECKSUM_URL" ]; then
    LAYER_INDEX_CHECKSUM_URL="${LAYER_INDEX_URL%.json}.sha256"
  fi

  mkdir -p "$DOWNLOAD_DIR"
  index_path="$DOWNLOAD_DIR/openclaw-layer-index.json"
  index_checksum_path="$DOWNLOAD_DIR/openclaw-layer-index.sha256"

  log "Downloading layer index: $LAYER_INDEX_URL"
  curl --noproxy '*' -fL --retry 3 --retry-delay 2 -o "$index_path" "$LAYER_INDEX_URL"
  log "Downloading layer index checksum: $LAYER_INDEX_CHECKSUM_URL"
  curl --noproxy '*' -fL --retry 3 --retry-delay 2 -o "$index_checksum_path" "$LAYER_INDEX_CHECKSUM_URL"
  (
    cd "$DOWNLOAD_DIR"
    shasum -a 256 -c "$(basename "$index_checksum_path")"
  )

  layer_records="$(
    /usr/bin/python3 - "$index_path" "$PACKAGE_PROFILE" <<'PY'
import json
import sys
from pathlib import Path

index = json.loads(Path(sys.argv[1]).read_text())
profile_name = sys.argv[2]
profile = index.get("profiles", {}).get(profile_name)
if not profile:
    raise SystemExit(f"profile missing from layer index: {profile_name}")
layer_ids = profile.get("layers")
if not isinstance(layer_ids, list) or not layer_ids:
    raise SystemExit(f"profile has no layers: {profile_name}")
for layer_id in layer_ids:
    layer = index.get("layers", {}).get(layer_id)
    if not layer:
        raise SystemExit(f"layer missing from index: {layer_id}")
    filename = layer.get("file", "")
    if not filename or Path(filename).name != filename:
        raise SystemExit(f"unsafe layer filename: {filename!r}")
    print(f"{filename}\t{layer['size_bytes']}\t{layer['sha256']}")
PY
  )"

  while IFS=$'\t' read -r layer_name expected_size expected_sha256; do
    [ -n "$layer_name" ] || continue
    layer_path="$DOWNLOAD_DIR/$layer_name"
    layer_url="${PACKAGE_BASE_URL%/}/$layer_name"

    layer_valid=0
    if [ -f "$layer_path" ]; then
      actual_size="$(stat -f '%z' "$layer_path")"
      actual_sha256="$(shasum -a 256 "$layer_path" | awk '{print $1}')"
      if [ "$actual_size" = "$expected_size" ] && [ "$actual_sha256" = "$expected_sha256" ]; then
        layer_valid=1
        log "Using verified cached layer: $layer_name"
      elif [ "$actual_size" -ge "$expected_size" ]; then
        log "Discarding invalid complete layer before retry: $layer_name"
        rm -f "$layer_path"
      fi
    fi

    if [ "$layer_valid" != "1" ]; then
      log "Downloading layer with resume: $layer_url"
      curl --noproxy '*' -fL --retry 3 --retry-delay 2 -C - -o "$layer_path" "$layer_url"
    fi

    /usr/bin/python3 - "$layer_path" "$expected_size" "$expected_sha256" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_size = int(sys.argv[2])
expected_sha256 = sys.argv[3]
if path.stat().st_size != expected_size:
    raise SystemExit(f"layer size mismatch: {path}")
digest = hashlib.sha256()
with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != expected_sha256:
    raise SystemExit(f"layer checksum mismatch: {path}")
PY
  done <<EOF
$layer_records
EOF

  assembled_dir="$DOWNLOAD_DIR/assembled/openclaw-$PACKAGE_PROFILE"
  wait_for_zstd_extractor
  log "Assembling layered package for $PACKAGE_PROFILE"
  OVERWRITE_ASSEMBLED=1 bash "$ASSEMBLER_SCRIPT" \
    --profile "$PACKAGE_PROFILE" \
    --index "$index_path" \
    --packages-dir "$DOWNLOAD_DIR" \
    --output-dir "$assembled_dir"

  log "Publishing assembled package to $REMOTE_RUN_DIR"
  replace_remote_run_dir "$assembled_dir"
  log "Layered package ready: $REMOTE_RUN_DIR"
  exit 0
fi

archive_name="$(basename "$PACKAGE_URL")"
archive_path="$DOWNLOAD_DIR/$archive_name"
checksum_name="${archive_name%.tar.zst}.sha256"
checksum_path="$DOWNLOAD_DIR/$checksum_name"
extract_dir="$DOWNLOAD_DIR/extract-${archive_name%.tar.zst}"

mkdir -p "$DOWNLOAD_DIR"

log "Downloading package with resume: $PACKAGE_URL"
curl --noproxy '*' -fL --retry 3 --retry-delay 2 -C - -o "$archive_path" "$PACKAGE_URL"

if [ -n "$CHECKSUM_URL" ]; then
  log "Downloading checksum: $CHECKSUM_URL"
  curl --noproxy '*' -fL --retry 3 --retry-delay 2 -o "$checksum_path" "$CHECKSUM_URL"
  (
    cd "$DOWNLOAD_DIR"
    shasum -a 256 -c "$checksum_name"
  )
fi

log "Extracting package to $REMOTE_RUN_DIR"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
wait_for_zstd_extractor
if [ "$ZSTD_EXTRACTOR" = "zstd" ]; then
  zstd -dc "$archive_path" | tar -xf - -C "$extract_dir"
else
  tar -xf "$archive_path" -C "$extract_dir"
fi

package_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -name 'openclaw-*' -print -quit)"
if [ -z "$package_root" ] || [ ! -f "$package_root/install-openclaw.sh" ]; then
  echo "Extracted package root with install-openclaw.sh was not found under $extract_dir" >&2
  exit 1
fi

replace_remote_run_dir "$package_root"

log "Package ready: $REMOTE_RUN_DIR"
