#!/usr/bin/env bash
set -u

PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
export PATH

LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/OpenClaw Dashboard.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

clear
echo "OpenClaw Dashboard"
echo "=================="
echo
echo "This window opens OpenClaw Dashboard in your browser."
echo "Log: $LOG_FILE"
echo

resolve_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    command -v openclaw
    return 0
  fi

  local candidate
  for candidate in \
    "/usr/local/bin/openclaw" \
    "/opt/homebrew/bin/openclaw" \
    "$HOME/.local/bin/openclaw" \
    "$HOME/.nvm/versions/node"/*/bin/openclaw; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

OPENCLAW_BIN="$(resolve_openclaw || true)"
if [ -z "$OPENCLAW_BIN" ]; then
  echo "[ERROR] OpenClaw CLI was not found."
  echo "Run the base installer first, then open this app again."
  echo
  read -r -p "Press Enter to close this window..."
  exit 1
fi

PATH="$(dirname "$OPENCLAW_BIN"):$PATH"
export PATH

echo "OpenClaw CLI: $OPENCLAW_BIN"
"$OPENCLAW_BIN" --version 2>/dev/null || true
echo

echo "Opening dashboard..."
"$OPENCLAW_BIN" dashboard --yes
status="$?"

echo
if [ "$status" -eq 0 ]; then
  echo "Dashboard command completed."
else
  echo "[ERROR] Dashboard command exited with status $status."
fi
echo
read -r -p "Press Enter to close this window..."
exit "$status"
