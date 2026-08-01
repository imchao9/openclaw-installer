#!/usr/bin/env bash
# Install or refresh the Codex Auth Sync Agent without persisting a registration code.
set -euo pipefail
umask 077

DEFAULT_INSTALL_URL="https://43.138.216.106/codex-auth-sync/install-agent-v2.sh"
DEFAULT_INSTALL_SHA256="6ca53379e2c6223d2fd5eabf3f0e9c0a8a74d839bdceb3d41d170d5e55abc8b2"
INSTALL_URL="${CODEX_AUTH_SYNC_INSTALL_URL:-$DEFAULT_INSTALL_URL}"
EXPECTED_SHA256="${CODEX_AUTH_SYNC_INSTALL_SHA256:-}"
APP_ROOT="$HOME/Library/Application Support/Codex Auth Sync"
AGENT_BIN="$APP_ROOT/bin/codex-auth-sync"
DEVICE_FILE="$APP_ROOT/device.json"

case "$INSTALL_URL" in
  https://*) ;;
  *)
    echo "CODEX_AUTH_SYNC_INSTALL_URL must use https" >&2
    exit 2
    ;;
esac

if [ -z "$EXPECTED_SHA256" ] && [ "$INSTALL_URL" = "$DEFAULT_INSTALL_URL" ]; then
  EXPECTED_SHA256="$DEFAULT_INSTALL_SHA256"
fi
if [[ ! "$EXPECTED_SHA256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "A custom installer URL requires CODEX_AUTH_SYNC_INSTALL_SHA256." >&2
  exit 2
fi

if [ ! -f "$DEVICE_FILE" ] && [[ ! "${CODEX_AUTH_SYNC_CODE:-}" =~ ^[a-f0-9]{32}$ ]]; then
  echo "First install requires CODEX_AUTH_SYNC_CODE with a 32-character one-time registration code." >&2
  exit 2
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-auth-sync-installer.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

installer="$work_dir/install-agent-v2.sh"
curl --fail --silent --show-error --location \
  --connect-timeout 10 --max-time 45 "$INSTALL_URL" -o "$installer"
actual_sha256="$(shasum -a 256 "$installer" | awk '{print $1}')"
if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
  echo "Codex Auth Sync installer SHA-256 mismatch." >&2
  exit 1
fi
bash -n "$installer"
chmod 0700 "$installer"

CODEX_AUTH_SYNC_CODE="${CODEX_AUTH_SYNC_CODE:-}" bash "$installer"

if [ ! -x "$AGENT_BIN" ]; then
  echo "Codex Auth Sync Agent binary was not installed: $AGENT_BIN" >&2
  exit 1
fi

"$AGENT_BIN" status --mode cliproxy --root "$APP_ROOT" || true
