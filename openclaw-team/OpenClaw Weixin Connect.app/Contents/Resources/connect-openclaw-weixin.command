#!/usr/bin/env bash
set -u

PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
export PATH

OPENCLAW_WEIXIN_PLUGIN="${OPENCLAW_WEIXIN_PLUGIN:-@tencent-weixin/openclaw-weixin}"
OPENCLAW_WEIXIN_CHANNEL_CONFIG='{"enabled": true, "accounts": {}}'

clear
echo "OpenClaw Weixin Connect"
echo "======================="
echo
echo "This window will connect OpenClaw Weixin."
echo "If the OpenClaw Weixin plugin is already installed, install/refresh will be skipped."
echo "When a QR code appears, scan it with WeChat on your phone."
echo

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] Node.js was not found. Run the base installer first, then open this app again."
  echo
  read -r -p "Press Enter to close this window..."
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "[ERROR] npx was not found. Run the base installer first, then open this app again."
  echo
  read -r -p "Press Enter to close this window..."
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[ERROR] OpenClaw CLI was not found. Run the base installer first, then open this app again."
  echo
  read -r -p "Press Enter to close this window..."
  exit 1
fi

echo "Node: $(node --version)"
echo "OpenClaw: $(openclaw --version 2>/dev/null || true)"
echo
echo "Keeping the Mac awake while connected to power..."
sudo pmset -c sleep 0 >/dev/null 2>&1 || echo "[WARN] Could not change machine sleep setting."
sudo pmset -c displaysleep 10 >/dev/null 2>&1 || echo "[WARN] Could not change display sleep setting."
echo

weixin_installed() {
  openclaw config get channels.openclaw-weixin >/dev/null 2>&1
}

status=0
if weixin_installed; then
  echo "OpenClaw Weixin plugin/channel already installed."
  echo "Skipping plugin install/refresh."
  echo
else
  echo "Installing and enabling OpenClaw Weixin plugin..."
  echo

  openclaw plugins install "$OPENCLAW_WEIXIN_PLUGIN" --force
  status="$?"
  if [ "$status" -eq 0 ]; then
    openclaw config set channels.openclaw-weixin "$OPENCLAW_WEIXIN_CHANNEL_CONFIG" --strict-json --merge
    status="$?"
  fi
  if [ "$status" -eq 0 ]; then
    openclaw gateway restart
    status="$?"
  fi
  if [ "$status" -eq 0 ]; then
    openclaw status --deep
    status="$?"
  fi
  if [ "$status" -eq 0 ]; then
    openclaw channels list
    status="$?"
  fi
fi
if [ "$status" -eq 0 ]; then
  echo
  echo "Starting Weixin account connector..."
  echo
  npx -y @tencent-weixin/openclaw-weixin-cli@latest install
  status="$?"
fi

echo
if [ "$status" -eq 0 ]; then
  echo "Done. If OpenClaw is already open, click Recheck or restart OpenClaw."
else
  echo "[ERROR] Weixin connection exited with status $status."
fi
echo
read -r -p "Press Enter to close this window..."
exit "$status"
