#!/usr/bin/env bash
# Configure a Mac to recover OpenClaw and Clash Party after reboot/login.
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PATH

DISPLAY_SLEEP_MINUTES="${DISPLAY_SLEEP_MINUTES:-10}"
CLASH_APP_NAME="${CLASH_APP_NAME:-Clash Party}"
CLASH_LABEL="${CLASH_LABEL:-local.openclaw-installer.clash-party}"
OPENCLAW_SETUP="${OPENCLAW_SETUP:-1}"
POWER_SETUP="${POWER_SETUP:-1}"
CLASH_SETUP="${CLASH_SETUP:-1}"
LOCAL_BYPASS_SETUP="${LOCAL_BYPASS_SETUP:-1}"

usage() {
  cat <<'EOF'
用法:
  bash scripts/setup-mac-autostart.sh

可选环境变量:
  DISPLAY_SLEEP_MINUTES=10     接电时屏幕多久后关闭
  CLASH_APP_NAME="Clash Party" 要自动启动的 Clash App 名称
  POWER_SETUP=0                跳过防休眠设置
  OPENCLAW_SETUP=0             跳过 OpenClaw gateway 安装/启动
  CLASH_SETUP=0                跳过 Clash Party 登录启动
  LOCAL_BYPASS_SETUP=0         跳过 localhost/127.0.0.1 代理绕过设置

说明:
  - 只配置用户级启动项和 pmset，不修改系统文件。
  - OpenClaw 使用自身 gateway LaunchAgent。
  - Clash Party 使用用户级 LaunchAgent，在用户登录后自动 open -a。
  - localhost/127.0.0.1/::1 默认不走系统代理。
  - MacBook 合盖仍可能睡眠；长期运行建议接电、开盖或使用合盖外接模式。
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "[ERROR] This script only supports macOS." >&2
    exit 1
  fi
}

configure_power() {
  log "配置接电时不休眠，只息屏"
  sudo pmset -c sleep 0
  sudo pmset -c disksleep 0
  sudo pmset -c displaysleep "$DISPLAY_SLEEP_MINUTES"
  sudo pmset -c womp 1
  sudo pmset -c tcpkeepalive 1
}

configure_local_proxy_bypass() {
  local bypass_domains no_proxy_value rc marker_begin marker_end env_file services service existing merged

  bypass_domains=(
    "localhost"
    "127.0.0.1"
    "::1"
    "0.0.0.0"
    "*.local"
    "local"
  )
  no_proxy_value="localhost,127.0.0.1,::1,0.0.0.0,.local,*.local"

  log "配置本地地址不走系统代理/Clash Party"
  services="$(networksetup -listallnetworkservices 2>/dev/null | sed '1d; s/^\\*//')"
  while IFS= read -r service; do
    [ -n "$service" ] || continue
    existing="$(networksetup -getproxybypassdomains "$service" 2>/dev/null | grep -v "There aren't any bypass domains" || true)"
    merged="$(
      {
        printf '%s\n' "$existing"
        printf '%s\n' "${bypass_domains[@]}"
      } | awk 'NF && !seen[$0]++'
    )"
    if [ -n "$merged" ]; then
      # shellcheck disable=SC2086
      sudo networksetup -setproxybypassdomains "$service" $merged || warn "设置网络服务代理绕过失败：$service"
    fi
  done <<EOF
$services
EOF

  mkdir -p "$HOME/.config/openclaw-installer/proxy"
  env_file="$HOME/.config/openclaw-installer/proxy/no_proxy.env"
  cat > "$env_file" <<EOF
export NO_PROXY="${no_proxy_value},\${NO_PROXY:-}"
export no_proxy="${no_proxy_value},\${no_proxy:-}"
EOF
  chmod 600 "$env_file"

  rc="$HOME/.zshrc"
  marker_begin="# >>> openclaw-installer local proxy bypass >>>"
  marker_end="# <<< openclaw-installer local proxy bypass <<<"
  touch "$rc"
  if grep -qF "$marker_begin" "$rc"; then
    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$rc" > "$rc.tmp.$$"
    mv "$rc.tmp.$$" "$rc"
  fi
  cat >> "$rc" <<EOF

$marker_begin
[ -f "$env_file" ] && source "$env_file"
$marker_end
EOF
}

configure_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    warn "未找到 openclaw CLI，跳过 OpenClaw gateway 自启动配置。"
    return
  fi

  log "设置 OpenClaw 默认完整工具权限"
  openclaw config set tools.profile '"full"' --strict-json
  openclaw config set tools.exec.security '"full"' --strict-json
  openclaw config set agents.defaults.elevatedDefault '"full"' --strict-json
  openclaw config validate

  log "安装并启动 OpenClaw gateway LaunchAgent"
  openclaw gateway install || warn "OpenClaw gateway install 失败；可能需要目标用户已登录 GUI，会在后续登录后再处理。"
  openclaw gateway start || warn "OpenClaw gateway start 失败；可能需要目标用户已登录 GUI，会在后续登录后再处理。"
}

find_app() {
  local app_name="$1"
  local path

  path="/Applications/${app_name}.app"
  if [ -d "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  path="$HOME/Applications/${app_name}.app"
  if [ -d "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  mdfind "kMDItemKind == 'Application' && kMDItemFSName == '${app_name}.app'" 2>/dev/null | head -n 1
}

configure_clash_party() {
  local app_path plist uid
  app_path="$(find_app "$CLASH_APP_NAME")"
  if [ -z "$app_path" ]; then
    warn "未找到 ${CLASH_APP_NAME}.app，跳过 Clash Party 登录启动。"
    warn "安装后可重新运行：CLASH_APP_NAME=\"${CLASH_APP_NAME}\" bash scripts/setup-mac-autostart.sh"
    return
  fi

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  plist="$HOME/Library/LaunchAgents/${CLASH_LABEL}.plist"
  uid="$(id -u)"

  log "写入 Clash Party 用户级 LaunchAgent: $plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${CLASH_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>${app_path}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/${CLASH_LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/${CLASH_LABEL}.err.log</string>
</dict>
</plist>
EOF

  plutil -lint "$plist" >/dev/null
  launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/${uid}" "$plist" || warn "LaunchAgent 已写入，但当前会话未能立即加载；下次用户登录会自动生效。"
  launchctl kickstart -k "gui/${uid}/${CLASH_LABEL}" >/dev/null 2>&1 || true

  if command -v osascript >/dev/null 2>&1; then
    osascript >/dev/null 2>&1 <<EOF || warn "未能写入系统登录项；LaunchAgent 已保留为自启兜底。"
tell application "System Events"
  if not (exists login item "${CLASH_APP_NAME}") then
    make login item at end with properties {path:"${app_path}", hidden:false}
  end if
end tell
EOF
  fi
}

print_status() {
  log "当前状态"
  echo "-- pmset --"
  pmset -g custom | sed -n '/AC Power/,$p' || true
  echo
  echo "-- OpenClaw --"
  if command -v openclaw >/dev/null 2>&1; then
    openclaw gateway status || true
    openclaw status --deep || true
  else
    echo "openclaw CLI not found"
  fi
  echo
  echo "-- LaunchAgents --"
  launchctl print "gui/$(id -u)/${CLASH_LABEL}" 2>/dev/null | sed -n '1,80p' || true
}

require_macos

if [ "$POWER_SETUP" = "1" ]; then
  configure_power
fi

if [ "$LOCAL_BYPASS_SETUP" = "1" ]; then
  configure_local_proxy_bypass
fi

if [ "$OPENCLAW_SETUP" = "1" ]; then
  configure_openclaw
fi

if [ "$CLASH_SETUP" = "1" ]; then
  configure_clash_party
fi

print_status

log "完成。重启后：用户登录时 Clash Party 会自动打开，OpenClaw gateway 会由 LaunchAgent 恢复。"
