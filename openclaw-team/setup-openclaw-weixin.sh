#!/usr/bin/env bash
set -euo pipefail

DISPLAY_SLEEP_MINUTES="${DISPLAY_SLEEP_MINUTES:-10}"
OPENCLAW_WEIXIN_PLUGIN="${OPENCLAW_WEIXIN_PLUGIN:-@tencent-weixin/openclaw-weixin}"
OPENCLAW_WEIXIN_CHANNEL_CONFIG='{"enabled": true, "accounts": {}}'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENCLAW_TEAM_DIR="${OPENCLAW_TEAM_DIR:-$ROOT_DIR/openclaw-team}"
if [ ! -d "$OPENCLAW_TEAM_DIR" ] && [ -d "$ROOT_DIR/openclaw team" ]; then
  OPENCLAW_TEAM_DIR="$ROOT_DIR/openclaw team"
fi
WEIXIN_LAUNCHER_SRC="$OPENCLAW_TEAM_DIR/OpenClaw Weixin Connect.app/Contents/Resources/connect-openclaw-weixin.command"
SYSTEM_APPLICATIONS_DIR="${SYSTEM_APPLICATIONS_DIR:-/Applications}"
WEIXIN_LAUNCHER_APP="$SYSTEM_APPLICATIONS_DIR/OpenClaw Weixin Connect.app"
WEIXIN_LAUNCHER_COMMAND="$SYSTEM_APPLICATIONS_DIR/OpenClaw Weixin Connect.command"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: $1"
    exit 1
  fi
}

install_weixin_launcher() {
  if [ ! -f "$WEIXIN_LAUNCHER_SRC" ]; then
    echo "[WARN] Weixin launcher source not found: $WEIXIN_LAUNCHER_SRC"
    return
  fi

  echo
  echo "Installing OpenClaw Weixin launcher to $SYSTEM_APPLICATIONS_DIR..."
  sudo mkdir -p "$SYSTEM_APPLICATIONS_DIR"
  sudo rm -rf "$WEIXIN_LAUNCHER_APP" "$WEIXIN_LAUNCHER_COMMAND"

  tmp_app="$(mktemp -d)/OpenClaw Weixin Connect.app"
  osacompile -o "$tmp_app" \
    -e 'set runner to POSIX path of (path to resource "connect-openclaw-weixin.command")' \
    -e 'tell application "Terminal"' \
    -e 'activate' \
    -e 'do script quoted form of runner' \
    -e 'end tell'
  cp "$WEIXIN_LAUNCHER_SRC" "$tmp_app/Contents/Resources/connect-openclaw-weixin.command"
  chmod +x "$tmp_app/Contents/Resources/connect-openclaw-weixin.command"

  sudo ditto "$tmp_app" "$WEIXIN_LAUNCHER_APP"
  sudo cp "$WEIXIN_LAUNCHER_SRC" "$WEIXIN_LAUNCHER_COMMAND"
  sudo chmod -R a+rX "$WEIXIN_LAUNCHER_APP"
  sudo chmod +x "$WEIXIN_LAUNCHER_APP/Contents/MacOS/applet" "$WEIXIN_LAUNCHER_COMMAND"
  sudo xattr -dr com.apple.quarantine "$WEIXIN_LAUNCHER_APP" "$WEIXIN_LAUNCHER_COMMAND" 2>/dev/null || true

  echo "Installed: $WEIXIN_LAUNCHER_APP"
  echo "Installed: $WEIXIN_LAUNCHER_COMMAND"
}

echo "Configuring macOS power settings for AC power..."
echo "- Machine sleep: disabled"
echo "- Display sleep: ${DISPLAY_SLEEP_MINUTES} minute(s)"

sudo pmset -c sleep 0
sudo pmset -c displaysleep "$DISPLAY_SLEEP_MINUTES"

install_weixin_launcher

echo
echo "Installing and enabling OpenClaw Weixin plugin..."
require_command openclaw
openclaw plugins install "$OPENCLAW_WEIXIN_PLUGIN" --force
openclaw config set channels.openclaw-weixin "$OPENCLAW_WEIXIN_CHANNEL_CONFIG" --strict-json --merge
openclaw gateway restart
openclaw status --deep
openclaw channels list

echo
echo "Starting OpenClaw Weixin account connector..."
require_command npx
npx -y @tencent-weixin/openclaw-weixin-cli@latest install

echo
echo "Done. Current AC power settings:"
pmset -g custom | sed -n '/AC Power/,$p'
