#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$(id -un)}"
USER_ID="$(id -u "$USER_NAME")"
GROUP_NAME="$(id -gn "$USER_NAME")"
HOME_DIR="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk '{print $2}')"

PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_NPM_PACKAGE="${OPENCLAW_NPM_PACKAGE:-openclaw@latest}"
OPENCLAW_NPM_CACHE_ARCHIVE="${OPENCLAW_NPM_CACHE_ARCHIVE:-$SCRIPT_DIR/openclaw-npm-cache.tgz}"

run_admin() {
  local cmd="$1"
  if [ -n "${SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' /bin/sh -c "$cmd"
  else
    sudo /bin/sh -c "$cmd"
  fi
}

info() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

info "Fixing ownership for OpenClaw state and user launchd directories"
run_admin "mkdir -p '$HOME_DIR/.openclaw' '$HOME_DIR/.npm' '$HOME_DIR/Library/LaunchAgents'; chown -R '$USER_NAME:$GROUP_NAME' '$HOME_DIR/.openclaw' '$HOME_DIR/.npm' '$HOME_DIR/Library/LaunchAgents'; chmod 700 '$HOME_DIR/.openclaw'"

if [ -d "$HOME_DIR/clawd" ]; then
  info "Fixing ownership for $HOME_DIR/clawd"
  run_admin "chown -R '$USER_NAME:$GROUP_NAME' '$HOME_DIR/clawd'; mkdir -p '$HOME_DIR/clawd/.openclaw'; chown -R '$USER_NAME:$GROUP_NAME' '$HOME_DIR/clawd/.openclaw'; chmod 700 '$HOME_DIR/clawd/.openclaw'"
fi

info "Fixing npm global install directories"
run_admin "mkdir -p /usr/local/bin /usr/local/lib/node_modules; chown -R '$USER_NAME:$GROUP_NAME' /usr/local/bin /usr/local/lib/node_modules"

info "Checking Node.js and npm"
node -v
npm -v

install_openclaw_online() {
  info "Installing OpenClaw CLI from npm registry: $OPENCLAW_NPM_PACKAGE"
  npm --script-shell=/bin/sh \
    --loglevel warn \
    --no-fund \
    --no-audit \
    --min-release-age=0 \
    install -g "$OPENCLAW_NPM_PACKAGE"
}

install_openclaw_offline() {
  local tmp cache_dir
  [ -f "$OPENCLAW_NPM_CACHE_ARCHIVE" ] || return 1
  tmp="$(mktemp -d /tmp/openclaw-npm-cache.XXXXXX)"
  tar -xzf "$OPENCLAW_NPM_CACHE_ARCHIVE" -C "$tmp"
  cache_dir="$tmp/npm-cache"
  if [ ! -d "$cache_dir" ]; then
    rm -rf "$tmp"
    return 1
  fi
  info "Installing OpenClaw CLI from offline npm cache: $OPENCLAW_NPM_CACHE_ARCHIVE"
  set +e
  npm --offline \
    --cache "$cache_dir" \
    --script-shell=/bin/sh \
    --loglevel warn \
    --no-fund \
    --no-audit \
    install -g "$OPENCLAW_NPM_PACKAGE"
  local status=$?
  set -e
  rm -rf "$tmp"
  return "$status"
}

if ! install_openclaw_offline; then
  info "WARN: Offline OpenClaw npm cache unavailable or failed; falling back to online npm"
  install_openclaw_online
fi

info "Verifying CLI"
command -v openclaw
openclaw --version

info "Installing and starting local Gateway LaunchAgent"
openclaw gateway install || info "WARN: OpenClaw gateway install failed; continue for headless/SSH install"
openclaw gateway start || info "WARN: OpenClaw gateway start failed; continue for headless/SSH install"

info "Waiting for Gateway"
sleep 4

info "Gateway status"
openclaw gateway status || info "WARN: OpenClaw gateway status failed"

info "Gateway health"
openclaw gateway health || info "WARN: OpenClaw gateway health failed"

info "Done. In the OpenClaw app, click Recheck or restart the app if the Settings page still shows a stale pending state."
