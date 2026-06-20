#!/usr/bin/env bash
# Install DingTalk from the bundled macOS DMG.
set -euo pipefail

DMG_PATH="${1:-${DINGTALK_DMG:-/tmp/DingTalk_v8.3.30-Installer_55620621_arm64.dmg}}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

if [ -d "/Applications/DingTalk.app" ] || [ -d "/Applications/钉钉.app" ]; then
  log "DingTalk already installed"
  exit 0
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "Missing DingTalk DMG: $DMG_PATH" >&2
  exit 1
fi

mount_dir="$(mktemp -d /tmp/dingtalk-install.XXXXXX)"
cleanup() {
  hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 \
    || hdiutil detach "$mount_dir" -force -quiet >/dev/null 2>&1 \
    || true
  rmdir "$mount_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Mounting DingTalk DMG"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null

pkg_path="$(find "$mount_dir" -maxdepth 3 -name '*.pkg' -print -quit)"
if [ -z "$pkg_path" ]; then
  echo "No .pkg found in DingTalk DMG: $DMG_PATH" >&2
  exit 1
fi

log "Installing DingTalk from $(basename "$pkg_path")"
if [ -n "$SUDO_PASSWORD" ]; then
  printf '%s\n' "$SUDO_PASSWORD" | sudo -S installer -pkg "$pkg_path" -target /
else
  sudo installer -pkg "$pkg_path" -target /
fi

if [ -d "/Applications/DingTalk.app" ] || [ -d "/Applications/钉钉.app" ]; then
  log "DingTalk installed"
else
  echo "DingTalk installer finished, but app was not found in /Applications." >&2
  find /Applications -maxdepth 1 \( -iname '*Ding*' -o -iname '*钉*' \) -print
  exit 1
fi
