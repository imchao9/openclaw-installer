#!/usr/bin/env bash
# Restore private config files and install user-facing helpers.
set -euo pipefail

PRIVATE_SECRETS_DIR="${PRIVATE_SECRETS_DIR:-}"
if [ -z "$PRIVATE_SECRETS_DIR" ]; then
  echo "PRIVATE_SECRETS_DIR is required."
  exit 1
fi

if [ ! -d "$PRIVATE_SECRETS_DIR" ]; then
  echo "Missing private-secrets directory: $PRIVATE_SECRETS_DIR"
  exit 1
fi

PRIVATE_SECRETS_DIR="$(cd "$PRIVATE_SECRETS_DIR" && pwd)"
CLASH_DIR="$HOME/.config/openclaw-installer/clash-party"
NOTES_DIR="$HOME/.config/openclaw-installer/private-notes"
USER_APPS_DIR="$HOME/Applications"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

install_file() {
  local src="$1" dst="$2" mode="${3:-600}"
  if [ ! -f "$src" ]; then
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    chmod "$mode" "$dst"
    log "Already current: $dst"
    return 0
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak.$(date +%Y%m%d_%H%M%S)"
  fi
  cp "$src" "$dst"
  chmod "$mode" "$dst"
  log "Restored $dst"
}

extract_clash_subscription_urls() {
  local notes_file="$1" out_file="$2"
  if [ ! -f "$notes_file" ]; then
    return 1
  fi

  mkdir -p "$(dirname "$out_file")"
  grep -Eo 'https?://[^[:space:]<>"'\''()]+' "$notes_file" | awk '!seen[$0]++' > "$out_file" || true
  if [ ! -s "$out_file" ]; then
    rm -f "$out_file"
    return 1
  fi
  chmod 600 "$out_file"
  log "Installed Clash Party subscription URL file: $out_file"
}

write_clash_party_helper_app() {
  local app="$USER_APPS_DIR/OpenClaw Clash Party Setup.app"
  local public_command="$USER_APPS_DIR/OpenClaw Clash Party Setup.command"
  local work
  work="$(mktemp -d /tmp/openclaw-clash-party-helper.XXXXXX)"

  mkdir -p "$USER_APPS_DIR"
  cat > "$public_command" <<'RUNNER'
#!/usr/bin/env bash
set -u

SUB_FILE="$HOME/.config/openclaw-installer/clash-party/subscriptions.txt"
NOTES_FILE="$HOME/.config/openclaw-installer/private-notes/安装.txt"

clear
echo "OpenClaw Clash Party Setup"
echo "=========================="
echo

if [ ! -s "$SUB_FILE" ]; then
  echo "[ERROR] No subscription URL file found:"
  echo "        $SUB_FILE"
  echo
  echo "Run the secrets phase first:"
  echo "  PRIVATE_SECRETS_DIR=/path/to/private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh"
  echo
  read -r -p "Press Enter to close this window..."
  exit 1
fi

first_url="$(head -n 1 "$SUB_FILE")"
printf '%s' "$first_url" | pbcopy
echo "The first Clash Party subscription URL has been copied to clipboard."
echo
echo "Next steps in Clash Party:"
echo "1. Click blank config."
echo "2. Paste the subscription URL into the subscription field."
echo "3. Import it."
echo "4. Turn on System Proxy and Virtual Network/TUN."
echo
if [ -f "$NOTES_FILE" ]; then
  echo "Private notes are also available at:"
  echo "$NOTES_FILE"
fi
echo

open -a "Clash Party" 2>/dev/null || open -a "Clash Verge" 2>/dev/null || true
read -r -p "Press Enter to close this window..."
RUNNER

  chmod +x "$public_command"

  cat > "$work/OpenClaw Clash Party Setup.applescript" <<'APPLESCRIPT'
set runner to POSIX path of (path to resource "OpenClaw Clash Party Setup.command")
do shell script "/usr/bin/open " & quoted form of runner
APPLESCRIPT

  rm -rf "$app"
  osacompile -o "$app" "$work/OpenClaw Clash Party Setup.applescript"
  mkdir -p "$app/Contents/Resources"
  cp "$public_command" "$app/Contents/Resources/OpenClaw Clash Party Setup.command"
  chmod +x "$app/Contents/Resources/OpenClaw Clash Party Setup.command"
  /usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
  /usr/bin/osadecompile "$app" >/dev/null
  rm -rf "$work"
  log "Installed Clash Party helper app: $app"
  log "Installed Clash Party command: $public_command"
}

install_clash_party_private_config() {
  local notes_file="$PRIVATE_SECRETS_DIR/openclaw-team/安装.txt"
  if [ ! -f "$notes_file" ]; then
    notes_file="$PRIVATE_SECRETS_DIR/openclaw team/安装.txt"
  fi
  local dst_notes="$NOTES_DIR/安装.txt"
  local sub_file="$CLASH_DIR/subscriptions.txt"

  install_file "$notes_file" "$dst_notes" 600 || {
    log "Skipping missing Clash/private note: $notes_file"
    return 0
  }

  if extract_clash_subscription_urls "$notes_file" "$sub_file"; then
    write_clash_party_helper_app
  else
    log "No URL found in private note; Clash Party helper app was not installed"
  fi
}

install_clash_party_private_config
