#!/usr/bin/env bash
# Target-side downloader for OpenClaw installer archives.
set -euo pipefail

PACKAGE_URL="${PACKAGE_URL:-${1:-}}"
CHECKSUM_URL="${CHECKSUM_URL:-${2:-}}"
REMOTE_RUN_DIR="${REMOTE_RUN_DIR:-$HOME/openclaw-installer-run}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/.cache/openclaw-installer}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

if [ -z "$PACKAGE_URL" ]; then
  echo "Usage: PACKAGE_URL=http://host:8765/openclaw-macos26-arm64.tar.zst bash fetch-package-over-http.sh" >&2
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
if command -v zstd >/dev/null 2>&1; then
  zstd -dc "$archive_path" | tar -xf - -C "$extract_dir"
else
  tar -xf "$archive_path" -C "$extract_dir"
fi

package_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -name 'openclaw-*' -print -quit)"
if [ -z "$package_root" ] || [ ! -f "$package_root/install-openclaw.sh" ]; then
  echo "Extracted package root with install-openclaw.sh was not found under $extract_dir" >&2
  exit 1
fi

rm -rf "$REMOTE_RUN_DIR"
mkdir -p "$REMOTE_RUN_DIR"
cp -R "$package_root/." "$REMOTE_RUN_DIR/"
chmod +x "$REMOTE_RUN_DIR/install-openclaw.sh" "$REMOTE_RUN_DIR/install-files/install-new-macbook.sh" "$REMOTE_RUN_DIR/install-files/install-openclaw.sh" "$REMOTE_RUN_DIR/dist/install-new-macbook.sh" "$REMOTE_RUN_DIR/dist/install-openclaw.sh" 2>/dev/null || true

log "Package ready: $REMOTE_RUN_DIR"
