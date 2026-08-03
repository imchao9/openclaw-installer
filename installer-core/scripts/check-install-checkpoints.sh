#!/usr/bin/env bash
# Scan an OpenClaw Mac install and emit a machine-readable report plus a
# conservative install plan. This script does not modify the target machine.
set -u

PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

RUN_DIR="${OPENCLAW_RUN_DIR:-$HOME/openclaw-installer-run}"
OUTPUT_PATH=""
PLAN_PATH=""
CHECK_REAL_MODEL_REQUEST="${CHECK_REAL_MODEL_REQUEST:-0}"

usage() {
  cat <<'EOF'
Usage:
  bash installer-core/scripts/check-install-checkpoints.sh [--run-dir DIR] [--output FILE] [--plan FILE] [--real-model-request]

Outputs:
  - install-report.json: checkpoint state for this machine
  - install-plan.env: shell env consumed by Ansible/install-openclaw.sh

The scan is read-only except for an explicitly requested real model call.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --plan)
      PLAN_PATH="$2"
      shift 2
      ;;
    --real-model-request)
      CHECK_REAL_MODEL_REQUEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPORT_DIR="$RUN_DIR/reports"
[ -n "$OUTPUT_PATH" ] || OUTPUT_PATH="$REPORT_DIR/install-report.json"
[ -n "$PLAN_PATH" ] || PLAN_PATH="$REPORT_DIR/install-plan.env"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool() {
  if "$@" >/dev/null 2>&1; then
    printf 'true'
  else
    printf 'false'
  fi
}

status() {
  if "$@" >/dev/null 2>&1; then
    printf 'installed'
  else
    printf 'missing'
  fi
}

app_exists() {
  local name="$1"
  [ -d "/Applications/$name.app" ]
}

any_app_exists() {
  local name
  for name in "$@"; do
    app_exists "$name" && return 0
  done
  return 1
}

find_app_bundle() {
  local name candidate
  for name in "$@"; do
    case "$name" in
      /*.app) candidate="$name" ;;
      *) candidate="/Applications/$name.app" ;;
    esac
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

app_executable_path() {
  local app="$1" executable
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$executable" ] || return 1
  printf '%s\n' "$app/Contents/MacOS/$executable"
}

app_ready() {
  local app executable archs
  app="$(find_app_bundle "$@")" || return 1
  executable="$(app_executable_path "$app")" || return 1
  [ -x "$executable" ] || return 1
  archs="$(lipo -archs "$executable" 2>/dev/null || true)"
  [ -n "$archs" ] && printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx "$arch"
}

app_validation_json() {
  local app app_name executable version archs arch_match=false launch_services=false ready=false
  app="$(find_app_bundle "$@" 2>/dev/null || true)"
  if [ -n "$app" ]; then
    executable="$(app_executable_path "$app" 2>/dev/null || true)"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ -n "$version" ] || version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || true)"
    if [ -n "$executable" ] && [ -x "$executable" ]; then
      archs="$(lipo -archs "$executable" 2>/dev/null || true)"
      if [ -n "$archs" ] && printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx "$arch"; then
        arch_match=true
        ready=true
      fi
    fi
    app_name="$(basename "$app" .app)"
    if open -Ra "$app_name" >/dev/null 2>&1; then
      launch_services=true
    fi
  fi
  printf '{"path":"%s","version":"%s","archs":"%s","arch_matches_machine":%s,"launch_services_resolvable":%s,"ready":%s}' \
    "$(json_escape "$app")" "$(json_escape "$version")" "$(json_escape "$archs")" \
    "$arch_match" "$launch_services" "$ready"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

path_file_contains() {
  local file="$1" needle="$2"
  [ -f "$file" ] && grep -qF "$needle" "$file"
}

port_listening() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

http_ok() {
  local url="$1"
  command_exists curl || return 1
  curl --noproxy '*' --connect-timeout 2 --max-time 4 -sSI "$url" | grep -qE '^HTTP/[0-9.]+ 2[0-9][0-9]'
}

http_get_ok() {
  local url="$1"
  command_exists curl || return 1
  curl --noproxy '*' --connect-timeout 2 --max-time 5 -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -qE '^2[0-9][0-9]$'
}

clash_socks_ok() {
  command_exists curl || return 1
  curl --socks5-hostname 127.0.0.1:7890 --connect-timeout 5 --max-time 12 \
    -sS -o /dev/null https://api.openai.com/v1/models >/dev/null 2>&1 \
    || curl --socks5-hostname 127.0.0.1:7890 --connect-timeout 5 --max-time 12 \
      -sS -o /dev/null https://chatgpt.com >/dev/null 2>&1
}

process_matches() {
  pgrep -af "$1" >/dev/null 2>&1
}

file_exists() {
  [ -f "$1" ]
}

dir_exists() {
  [ -d "$1" ]
}

profiles_count() {
  local dir="$HOME/Library/Application Support/mihomo-party/profiles"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | wc -l | tr -d ' '
  else
    printf '0'
  fi
}

clash_current_profile_value() {
  local cfg="$HOME/Library/Application Support/mihomo-party/profile.yaml" value
  [ -f "$cfg" ] || return 1
  value="$(awk -F': *' '/^current:/ { print $2; exit }' "$cfg")"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

cliproxy_management_key_value() {
  local key_file="$HOME/.cli-proxy-api/management.key" key
  [ -f "$key_file" ] || return 1
  IFS= read -r key < "$key_file" || true
  [ -n "$key" ] || return 1
  printf '%s\n' "$key"
}

cliproxy_management_configured() {
  local cfg="$HOME/.cli-proxy-api/config.yaml"
  [ -f "$cfg" ] || return 1
  awk '
    /^remote-management:/ { in_block=1; next }
    in_block && /^[^[:space:]]/ { exit(found ? 0 : 1) }
    in_block && /^[[:space:]]+secret-key:[[:space:]]*[^[:space:]]/ { found=1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$cfg"
}

cliproxy_management_api_ok() {
  local key code
  key="$(cliproxy_management_key_value)" || return 1
  code="$(curl --noproxy '*' --connect-timeout 2 --max-time 6 -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $key" -H "X-Management-Key: $key" \
    http://127.0.0.1:8317/v0/management/config 2>/dev/null || true)"
  printf '%s\n' "$code" | grep -qE '^2[0-9][0-9]$'
}

cliproxy_real_model_ok() {
  local api_key response
  api_key="$(cliproxy_api_key_value)" || return 1
  response="$(mktemp "${TMPDIR:-/tmp}/cliproxy-real-model.XXXXXX")"
  curl --noproxy '*' --connect-timeout 3 --max-time 60 -fsS \
    -H 'Content-Type: application/json' -H "Authorization: Bearer $api_key" \
    -d '{"model":"gpt-5.5","input":"Reply exactly HELLO_OK","stream":false}' \
    http://127.0.0.1:8317/v1/responses > "$response" 2>/dev/null || { rm -f "$response"; return 1; }
  grep -qF 'HELLO_OK' "$response"
  local result=$?
  rm -f "$response"
  return "$result"
}

openclaw_config_shape_ok() {
  local cfg="$HOME/.openclaw/openclaw.json"
  [ -f "$cfg" ] || return 1
  grep -qF 'cliproxy' "$cfg" || return 1
  grep -qF 'gpt-5.5' "$cfg" || return 1
  grep -qF 'deepseek-v4-pro' "$cfg" || return 1
}

codex_config_shape_ok() {
  local cfg="$HOME/.codex/config.toml"
  [ -f "$cfg" ] || return 1
  grep -Eq '^model_provider[[:space:]]*=[[:space:]]*"custom"' "$cfg" || return 1
  grep -qF '127.0.0.1:8317' "$cfg" || return 1
  grep -Eq '^wire_api[[:space:]]*=[[:space:]]*"responses"' "$cfg" || return 1
}

cliproxy_api_key_value() {
  local cfg="$HOME/.cli-proxy-api/config.yaml" key
  [ -f "$cfg" ] || return 1
  key="$(awk '
    /^api-keys:/ { in_keys=1; next }
    in_keys && /^[^[:space:]-]/ { exit }
    in_keys && /^[[:space:]]*-[[:space:]]*[^[:space:]]/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$cfg")"
  case "$key" in
    \"*\") key="${key#\"}"; key="${key%\"}" ;;
    \'*\') key="${key#\'}"; key="${key%\'}" ;;
  esac
  [ -n "$key" ] || return 1
  printf '%s\n' "$key"
}

codex_auth_cliproxy_ok() {
  local auth="$HOME/.codex/auth.json" expected actual
  [ -f "$auth" ] || return 1
  expected="$(cliproxy_api_key_value)" || return 1
  actual="$(/usr/bin/python3 - "$auth" <<'PY'
import json
import sys

try:
    value = json.load(open(sys.argv[1])).get("OPENAI_API_KEY", "")
except (OSError, ValueError, AttributeError):
    value = ""
print(value)
PY
)"
  [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

macos_version="$(sw_vers -productVersion 2>/dev/null || printf unknown)"
arch="$(uname -m 2>/dev/null || printf unknown)"
host="$(hostname 2>/dev/null || printf unknown)"
disk_available_kb="$(df -k / 2>/dev/null | awk 'NR==2 {print $4}' || printf 0)"
profile_count="$(profiles_count)"

layout_script=0
[ -f "$RUN_DIR/install-openclaw.sh" ] && layout_script=1
layout_dist=0
[ -f "$RUN_DIR/install-files/install-new-macbook.sh" ] && layout_dist=1
[ -f "$RUN_DIR/install-files/install-new-macbook.sh" ] && layout_dist=1
SECRETS_DIR="${PRIVATE_SECRETS_DIR:-$RUN_DIR/private-secrets}"
SECRETS_TEAM_DIR="$SECRETS_DIR/openclaw-team"
SECRETS_LEGACY_TEAM_DIR="$SECRETS_DIR/openclaw team"
layout_secrets=0
[ -d "$SECRETS_DIR" ] && layout_secrets=1
source_codex_auth_ok=0; { file_exists "$SECRETS_TEAM_DIR/auth.json" || file_exists "$SECRETS_LEGACY_TEAM_DIR/auth.json"; } && source_codex_auth_ok=1
source_codex_config_ok=0; { file_exists "$SECRETS_TEAM_DIR/config.toml" || file_exists "$SECRETS_LEGACY_TEAM_DIR/config.toml"; } && source_codex_config_ok=1
source_openclaw_config_ok=0; { file_exists "$SECRETS_TEAM_DIR/openclaw.json" || file_exists "$SECRETS_LEGACY_TEAM_DIR/openclaw.json"; } && source_openclaw_config_ok=1
source_media_secrets_ok=0; file_exists "$SECRETS_DIR/installer-core/secrets.env" && source_media_secrets_ok=1
source_cliproxy_config_ok=0; file_exists "$SECRETS_DIR/cliproxy/config.yaml" && source_cliproxy_config_ok=1
source_cliproxy_auth_ok=0
if [ -d "$SECRETS_DIR/cliproxy/auth" ] && find "$SECRETS_DIR/cliproxy/auth" -maxdepth 1 -type f -name '*.json' 2>/dev/null | grep -q .; then
  source_cliproxy_auth_ok=1
fi
source_deepseek_key_ok=0; file_exists "$SECRETS_DIR/deepseek-key.csv" && source_deepseek_key_ok=1
source_clash_profiles_ok=0
if [ -d "$SECRETS_DIR/clash-party/profiles" ] && find "$SECRETS_DIR/clash-party/profiles" -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | grep -q .; then
  source_clash_profiles_ok=1
fi
source_person_key_commands_ok=0; file_exists "$SECRETS_DIR/person-key-commands.md" && source_person_key_commands_ok=1

node_ok=0; command_exists node && node_ok=1
npm_ok=0; command_exists npm && npm_ok=1
codex_cli_ok=0; command_exists codex && codex_cli_ok=1
openclaw_cli_ok=0; command_exists openclaw && openclaw_cli_ok=1
path_ok=0
if path_file_contains "$HOME/.zshenv" "/usr/local/bin" || path_file_contains "$HOME/.zshrc" "/usr/local/bin"; then
  path_ok=1
fi

chrome_ok=0; app_ready "Google Chrome" && chrome_ok=1
codex_app_ok=0; app_ready "ChatGPT" "Codex" && codex_app_ok=1
openclaw_app_ok=0; app_ready "OpenClaw" && openclaw_app_ok=1
obsidian_ok=0; app_ready "Obsidian" && obsidian_ok=1
cc_switch_ok=0; app_ready "CC-Switch" "CC Switch" && cc_switch_ok=1
clash_party_app_ok=0; app_ready "Clash Party" && clash_party_app_ok=1
dingtalk_ok=0; app_ready "DingTalk" "钉钉" && dingtalk_ok=1
awesun_ok=0; app_ready "AweSun" "SunloginClient" "向日葵远程控制" && awesun_ok=1
doubao_ok=0
if [ -d "/Library/Input Methods/DoubaoIme.app" ] || [ -d "$HOME/Library/Input Methods/DoubaoIme.app" ] || any_app_exists "DoubaoImeInstaller_v0.9.1" "DoubaoImeInstaller_v0.9.0"; then
  doubao_ok=1
fi
doubao_app="/Library/Input Methods/DoubaoIme.app"
doubao_user_app="$HOME/Library/Input Methods/DoubaoIme.app"
doubao_bundle_id="com.bytedance.inputmethod.doubaoime"
doubao_input_mode="com.bytedance.inputmethod.doubaoime.pinyin"
doubao_pref="$HOME/Library/Preferences/com.apple.HIToolbox.plist"
doubao_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
doubao_version="$(defaults read "$doubao_app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
doubao_version_ok=0
[ -d "$doubao_app" ] && [ "$doubao_version" = "0.9.1" ] && doubao_version_ok=1
doubao_no_user_duplicate_ok=1
[ -d "$doubao_user_app" ] && doubao_no_user_duplicate_ok=0
doubao_input_source_ok=0
if defaults read "$doubao_pref" AppleEnabledInputSources 2>/dev/null | grep -qF "$doubao_input_mode"; then
  doubao_input_source_ok=1
fi
doubao_menu_ok=0
if defaults read com.apple.systemuiserver menuExtras 2>/dev/null | grep -qF "TextInput.menu"; then
  doubao_menu_ok=1
fi
doubao_microphone_ok=0
if command_exists sqlite3 && [ -f "$doubao_tcc" ]; then
  doubao_tcc_row="$(sqlite3 "$doubao_tcc" "select auth_value || '|' || length(csreq) from access where service='kTCCServiceMicrophone' and client='$doubao_bundle_id' order by last_modified desc limit 1;" 2>/dev/null || true)"
  case "$doubao_tcc_row" in
    2\|[1-9]*)
      doubao_microphone_ok=1
      ;;
  esac
fi
doubao_config_ok=0
if [ "$doubao_version_ok" = "1" ] && [ "$doubao_no_user_duplicate_ok" = "1" ] && \
   [ "$doubao_input_source_ok" = "1" ] && [ "$doubao_menu_ok" = "1" ] && \
   [ "$doubao_microphone_ok" = "1" ]; then
  doubao_config_ok=1
fi

codex_auth_ok=0; file_exists "$HOME/.codex/auth.json" && codex_auth_ok=1
codex_config_ok=0; file_exists "$HOME/.codex/config.toml" && codex_config_ok=1
codex_auth_cliproxy_ok_flag=0; codex_auth_cliproxy_ok && codex_auth_cliproxy_ok_flag=1
codex_cliproxy_config_ok=0
if codex_config_shape_ok && [ "$codex_auth_cliproxy_ok_flag" = "1" ]; then
  codex_cliproxy_config_ok=1
fi
openclaw_config_ok=0; file_exists "$HOME/.openclaw/openclaw.json" && openclaw_config_ok=1
openclaw_cliproxy_config_ok=0; openclaw_config_shape_ok && openclaw_cliproxy_config_ok=1
media_secrets_ok=0; file_exists "$HOME/.config/openclaw-media/secrets.env" && media_secrets_ok=1

cliproxy_binary_archs="$(lipo -archs "$HOME/.local/bin/CLIProxyAPI" 2>/dev/null || true)"
cliproxy_binary_arch_ok=0
if [ -n "$cliproxy_binary_archs" ] && printf '%s\n' "$cliproxy_binary_archs" | tr ' ' '\n' | grep -qx "$arch"; then
  cliproxy_binary_arch_ok=1
fi
cliproxy_binary_ok=0
if file_exists "$HOME/.local/bin/CLIProxyAPI" && [ "$cliproxy_binary_arch_ok" = "1" ]; then
  cliproxy_binary_ok=1
fi
cliproxy_config_ok=0; file_exists "$HOME/.cli-proxy-api/config.yaml" && cliproxy_config_ok=1
cliproxy_launchagent_ok=0; file_exists "$HOME/Library/LaunchAgents/local.openclaw-installer.cliproxy.plist" && cliproxy_launchagent_ok=1
cliproxy_listening_ok=0; port_listening 8317 && cliproxy_listening_ok=1
cliproxy_http_ok=0; http_get_ok "http://127.0.0.1:8317/" && cliproxy_http_ok=1
cliproxy_management_config_ok=0; cliproxy_management_configured && cliproxy_management_config_ok=1
cliproxy_management_api_ok_flag=0; cliproxy_management_api_ok && cliproxy_management_api_ok_flag=1
cliproxy_real_model_status="skipped"
if [ "$CHECK_REAL_MODEL_REQUEST" = "1" ]; then
  cliproxy_real_model_status="failed"
  cliproxy_real_model_ok && cliproxy_real_model_status="passed"
fi

clash_current_profile="$(clash_current_profile_value 2>/dev/null || true)"
clash_current_profile_file_ok=0
if [ -n "$clash_current_profile" ] && [ -f "$HOME/Library/Application Support/mihomo-party/profiles/$clash_current_profile.yaml" ]; then
  clash_current_profile_file_ok=1
fi
clash_profiles_ok=0
if [ "$profile_count" -gt 0 ] 2>/dev/null && [ "$clash_current_profile_file_ok" = "1" ]; then
  clash_profiles_ok=1
fi
clash_process_ok=0
if process_matches "Clash Party" || process_matches "mihomo-party"; then
  clash_process_ok=1
fi
clash_socks_ok_flag=0; clash_socks_ok && clash_socks_ok_flag=1

auth_sync_root="$HOME/Library/Application Support/Codex Auth Sync"
auth_sync_installed_ok=0
[ -x "$auth_sync_root/bin/codex-auth-sync" ] && auth_sync_installed_ok=1
auth_sync_registered_ok=0
[ -f "$auth_sync_root/device.json" ] && auth_sync_registered_ok=1

PLAN_RUN_BASE=0
PLAN_INSTALL_NODE=0
PLAN_INSTALL_CORE_APPS=0
PLAN_INSTALL_EXTRA_APPS=0
PLAN_INSTALL_DINGTALK=0
PLAN_FIX_PATH=0
PLAN_REPAIR_OPENCLAW=0
PLAN_CONFIGURE_DOUBAO=0
PLAN_RUN_CODEX_CLI=0
PLAN_RUN_CLIPROXY=0
PLAN_RUN_SECRETS=0
PLAN_RUN_CLIPROXY_CONFIG=0
PLAN_RUN_VALIDATE=1
PLAN_NEEDS_SECRETS=0
PLAN_NEEDS_MANUAL_CLASH_GUI=0
PLAN_REASONS=""

add_reason() {
  if [ -z "$PLAN_REASONS" ]; then
    PLAN_REASONS="$1"
  else
    PLAN_REASONS="$PLAN_REASONS; $1"
  fi
}

if [ "$node_ok" = "0" ] || [ "$npm_ok" = "0" ]; then
  PLAN_INSTALL_NODE=1
  add_reason "node/npm missing"
fi

if [ "$codex_app_ok" = "0" ] || [ "$openclaw_app_ok" = "0" ] || [ "$clash_party_app_ok" = "0" ]; then
  PLAN_INSTALL_CORE_APPS=1
  add_reason "one or more core apps missing"
fi

required_extra_apps_missing=0
if [ "$chrome_ok" = "0" ] || [ "$obsidian_ok" = "0" ] || [ "$cc_switch_ok" = "0" ]; then
  required_extra_apps_missing=1
fi
if [ "$awesun_ok" = "0" ]; then
  required_extra_apps_missing=1
fi
if [ "$required_extra_apps_missing" = "1" ]; then
  PLAN_INSTALL_EXTRA_APPS=1
  add_reason "one or more required non-core apps missing"
fi

if [ "$dingtalk_ok" = "0" ]; then
  PLAN_INSTALL_DINGTALK=1
  add_reason "DingTalk missing"
fi

if [ "$doubao_config_ok" = "0" ]; then
  PLAN_CONFIGURE_DOUBAO=1
  add_reason "Doubao input source or microphone permission incomplete"
fi

if [ "$path_ok" = "0" ]; then
  PLAN_FIX_PATH=1
  add_reason "shell PATH incomplete"
fi

if [ "$openclaw_cli_ok" = "0" ] && [ "$openclaw_app_ok" = "1" ]; then
  PLAN_REPAIR_OPENCLAW=1
  add_reason "OpenClaw CLI/Gateway repair may be required"
fi

if [ "$PLAN_INSTALL_NODE" = "1" ] || [ "$PLAN_INSTALL_CORE_APPS" = "1" ] || \
   [ "$PLAN_FIX_PATH" = "1" ] || \
   [ "$PLAN_REPAIR_OPENCLAW" = "1" ]; then
  PLAN_RUN_BASE=1
fi

if [ "$codex_cli_ok" = "0" ] && { [ "$node_ok" = "1" ] || [ "$PLAN_INSTALL_NODE" = "1" ]; }; then
  PLAN_RUN_CODEX_CLI=1
  add_reason "codex cli missing"
fi

if [ "$cliproxy_binary_ok" = "0" ] || [ "$cliproxy_config_ok" = "0" ] || \
   [ "$cliproxy_launchagent_ok" = "0" ] || [ "$cliproxy_listening_ok" = "0" ] || \
   [ "$cliproxy_management_config_ok" = "0" ] || [ "$cliproxy_management_api_ok_flag" = "0" ]; then
  PLAN_RUN_CLIPROXY=1
  add_reason "cliproxy runtime incomplete"
fi

if [ "$layout_secrets" = "1" ]; then
  if [ "$codex_auth_ok" = "0" ] || [ "$codex_config_ok" = "0" ] || \
     [ "$openclaw_config_ok" = "0" ] || [ "$media_secrets_ok" = "0" ] || \
     [ "$clash_profiles_ok" = "0" ]; then
    PLAN_RUN_SECRETS=1
    add_reason "private config or Clash profiles missing"
  fi
else
  if [ "$codex_auth_ok" = "0" ] || [ "$openclaw_config_ok" = "0" ] || [ "$media_secrets_ok" = "0" ]; then
    PLAN_NEEDS_SECRETS=1
    add_reason "private-secrets required but not present"
  fi
fi

if [ "$codex_cliproxy_config_ok" = "0" ] || [ "$openclaw_cliproxy_config_ok" = "0" ]; then
  PLAN_RUN_CLIPROXY_CONFIG=1
  add_reason "Codex/OpenClaw not configured for CLIProxyAPI"
fi

if [ "$clash_party_app_ok" = "1" ] && { [ "$clash_process_ok" = "0" ] || [ "$clash_socks_ok_flag" = "0" ]; }; then
  PLAN_NEEDS_MANUAL_CLASH_GUI=1
  add_reason "Clash Party installed but not healthy; GUI login/open may be required"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")" "$(dirname "$PLAN_PATH")"

cat > "$PLAN_PATH" <<EOF
# Generated by check-install-checkpoints.sh. Safe to source.
PLAN_RUN_BASE=$PLAN_RUN_BASE
PLAN_INSTALL_NODE=$PLAN_INSTALL_NODE
PLAN_INSTALL_CORE_APPS=$PLAN_INSTALL_CORE_APPS
PLAN_INSTALL_EXTRA_APPS=$PLAN_INSTALL_EXTRA_APPS
PLAN_INSTALL_DINGTALK=$PLAN_INSTALL_DINGTALK
PLAN_FIX_PATH=$PLAN_FIX_PATH
PLAN_REPAIR_OPENCLAW=$PLAN_REPAIR_OPENCLAW
PLAN_CONFIGURE_DOUBAO=$PLAN_CONFIGURE_DOUBAO
PLAN_RUN_CODEX_CLI=$PLAN_RUN_CODEX_CLI
PLAN_RUN_CLIPROXY=$PLAN_RUN_CLIPROXY
PLAN_RUN_SECRETS=$PLAN_RUN_SECRETS
PLAN_RUN_CLIPROXY_CONFIG=$PLAN_RUN_CLIPROXY_CONFIG
PLAN_RUN_VALIDATE=$PLAN_RUN_VALIDATE
PLAN_NEEDS_SECRETS=$PLAN_NEEDS_SECRETS
PLAN_NEEDS_MANUAL_CLASH_GUI=$PLAN_NEEDS_MANUAL_CLASH_GUI
PLAN_REASONS="$(json_escape "$PLAN_REASONS")"
EOF

cat > "$OUTPUT_PATH" <<EOF
{
  "schema_version": 1,
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "host": "$(json_escape "$host")",
  "user": "$(json_escape "$(whoami 2>/dev/null || printf unknown)")",
  "home": "$(json_escape "$HOME")",
  "run_dir": "$(json_escape "$RUN_DIR")",
  "preflight": {
    "ssh_reached": true,
    "sudo_checked": false,
    "macos_version": "$(json_escape "$macos_version")",
    "arch": "$(json_escape "$arch")",
    "disk_available_kb": ${disk_available_kb:-0}
  },
  "package_layout": {
    "install_openclaw_sh": $([ "$layout_script" = "1" ] && printf true || printf false),
    "dist_install_new_macbook_sh": $([ "$layout_dist" = "1" ] && printf true || printf false),
    "private_secrets_present": $([ "$layout_secrets" = "1" ] && printf true || printf false)
  },
  "secrets_manifest": {
    "source_dir": "$(json_escape "$SECRETS_DIR")",
    "present": $([ "$layout_secrets" = "1" ] && printf true || printf false),
    "codex_auth": $([ "$source_codex_auth_ok" = "1" ] && printf true || printf false),
    "codex_config": $([ "$source_codex_config_ok" = "1" ] && printf true || printf false),
    "openclaw_config": $([ "$source_openclaw_config_ok" = "1" ] && printf true || printf false),
    "media_secrets": $([ "$source_media_secrets_ok" = "1" ] && printf true || printf false),
    "cliproxy_config": $([ "$source_cliproxy_config_ok" = "1" ] && printf true || printf false),
    "cliproxy_auth": $([ "$source_cliproxy_auth_ok" = "1" ] && printf true || printf false),
    "deepseek_key": $([ "$source_deepseek_key_ok" = "1" ] && printf true || printf false),
    "clash_profiles": $([ "$source_clash_profiles_ok" = "1" ] && printf true || printf false),
    "person_key_commands": $([ "$source_person_key_commands_ok" = "1" ] && printf true || printf false)
  },
  "commands": {
    "node": "$(status command_exists node)",
    "npm": "$(status command_exists npm)",
    "codex": "$(status command_exists codex)",
    "openclaw": "$(status command_exists openclaw)",
    "path_profile": $([ "$path_ok" = "1" ] && printf true || printf false)
  },
  "apps": {
    "chrome": $([ "$chrome_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "codex": $([ "$codex_app_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "openclaw": $([ "$openclaw_app_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "obsidian": $([ "$obsidian_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "cc_switch": $([ "$cc_switch_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "clash_party": $([ "$clash_party_app_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "dingtalk": $([ "$dingtalk_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "awesun": $([ "$awesun_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "doubao_input": $([ "$doubao_ok" = "1" ] && printf '"installed"' || printf '"missing"'),
    "doubao_configured": $([ "$doubao_config_ok" = "1" ] && printf true || printf false),
    "doubao_version": "$(json_escape "$doubao_version")",
    "doubao_input_source": $([ "$doubao_input_source_ok" = "1" ] && printf true || printf false),
    "doubao_menu": $([ "$doubao_menu_ok" = "1" ] && printf true || printf false),
    "doubao_microphone": $([ "$doubao_microphone_ok" = "1" ] && printf true || printf false),
    "doubao_user_duplicate_absent": $([ "$doubao_no_user_duplicate_ok" = "1" ] && printf true || printf false)
  },
  "app_validation": {
    "chrome": $(app_validation_json "Google Chrome"),
    "codex": $(app_validation_json "ChatGPT" "Codex"),
    "openclaw": $(app_validation_json "OpenClaw"),
    "obsidian": $(app_validation_json "Obsidian"),
    "cc_switch": $(app_validation_json "CC-Switch" "CC Switch"),
    "clash_party": $(app_validation_json "Clash Party"),
    "dingtalk": $(app_validation_json "DingTalk" "钉钉"),
    "awesun": $(app_validation_json "AweSun" "SunloginClient" "向日葵远程控制"),
    "doubao_input": $(app_validation_json "/Library/Input Methods/DoubaoIme.app" "$HOME/Library/Input Methods/DoubaoIme.app")
  },
  "configs": {
    "codex_auth": $([ "$codex_auth_ok" = "1" ] && printf true || printf false),
    "codex_auth_cliproxy": $([ "$codex_auth_cliproxy_ok_flag" = "1" ] && printf true || printf false),
    "codex_config": $([ "$codex_config_ok" = "1" ] && printf true || printf false),
    "codex_cliproxy_config": $([ "$codex_cliproxy_config_ok" = "1" ] && printf true || printf false),
    "openclaw_config": $([ "$openclaw_config_ok" = "1" ] && printf true || printf false),
    "openclaw_cliproxy_config": $([ "$openclaw_cliproxy_config_ok" = "1" ] && printf true || printf false),
    "media_secrets": $([ "$media_secrets_ok" = "1" ] && printf true || printf false)
  },
  "cliproxy": {
    "binary": $([ "$cliproxy_binary_ok" = "1" ] && printf true || printf false),
    "binary_archs": "$(json_escape "$cliproxy_binary_archs")",
    "binary_arch_matches_machine": $([ "$cliproxy_binary_arch_ok" = "1" ] && printf true || printf false),
    "config": $([ "$cliproxy_config_ok" = "1" ] && printf true || printf false),
    "launchagent": $([ "$cliproxy_launchagent_ok" = "1" ] && printf true || printf false),
    "listening_8317": $([ "$cliproxy_listening_ok" = "1" ] && printf true || printf false),
    "http_root_ok": $([ "$cliproxy_http_ok" = "1" ] && printf true || printf false),
    "management_configured": $([ "$cliproxy_management_config_ok" = "1" ] && printf true || printf false),
    "management_api_authenticated": $([ "$cliproxy_management_api_ok_flag" = "1" ] && printf true || printf false),
    "real_model_request": "$cliproxy_real_model_status"
  },
  "clash": {
    "profiles_count": ${profile_count:-0},
    "profiles_present": $([ "$profile_count" -gt 0 ] 2>/dev/null && printf true || printf false),
    "current_profile": "$(json_escape "$clash_current_profile")",
    "current_profile_file_valid": $([ "$clash_current_profile_file_ok" = "1" ] && printf true || printf false),
    "process_running": $([ "$clash_process_ok" = "1" ] && printf true || printf false),
    "socks_7890_healthy": $([ "$clash_socks_ok_flag" = "1" ] && printf true || printf false)
  },
  "auth_sync": {
    "installed": $([ "$auth_sync_installed_ok" = "1" ] && printf true || printf false),
    "registered": $([ "$auth_sync_registered_ok" = "1" ] && printf true || printf false)
  },
  "plan": {
    "run_base": $([ "$PLAN_RUN_BASE" = "1" ] && printf true || printf false),
    "install_node": $([ "$PLAN_INSTALL_NODE" = "1" ] && printf true || printf false),
    "install_core_apps": $([ "$PLAN_INSTALL_CORE_APPS" = "1" ] && printf true || printf false),
    "install_extra_apps": $([ "$PLAN_INSTALL_EXTRA_APPS" = "1" ] && printf true || printf false),
    "install_dingtalk": $([ "$PLAN_INSTALL_DINGTALK" = "1" ] && printf true || printf false),
    "fix_path": $([ "$PLAN_FIX_PATH" = "1" ] && printf true || printf false),
    "repair_openclaw": $([ "$PLAN_REPAIR_OPENCLAW" = "1" ] && printf true || printf false),
    "configure_doubao": $([ "$PLAN_CONFIGURE_DOUBAO" = "1" ] && printf true || printf false),
    "run_codex_cli": $([ "$PLAN_RUN_CODEX_CLI" = "1" ] && printf true || printf false),
    "run_cliproxy": $([ "$PLAN_RUN_CLIPROXY" = "1" ] && printf true || printf false),
    "run_secrets": $([ "$PLAN_RUN_SECRETS" = "1" ] && printf true || printf false),
    "run_cliproxy_config": $([ "$PLAN_RUN_CLIPROXY_CONFIG" = "1" ] && printf true || printf false),
    "run_validate": $([ "$PLAN_RUN_VALIDATE" = "1" ] && printf true || printf false),
    "needs_secrets": $([ "$PLAN_NEEDS_SECRETS" = "1" ] && printf true || printf false),
    "needs_manual_clash_gui": $([ "$PLAN_NEEDS_MANUAL_CLASH_GUI" = "1" ] && printf true || printf false),
    "reasons": "$(json_escape "$PLAN_REASONS")"
  },
  "manual_tasks": {
    "needs_secrets": $([ "$PLAN_NEEDS_SECRETS" = "1" ] && printf true || printf false),
    "needs_clash_gui_open_or_login": $([ "$PLAN_NEEDS_MANUAL_CLASH_GUI" = "1" ] && printf true || printf false),
    "weixin_qr_login_is_manual": true,
    "doubao_microphone_permission_is_automated": true,
    "macos_tcc_permissions_are_manual": true
  }
}
EOF

echo "Report written to: $OUTPUT_PATH"
echo "Plan written to: $PLAN_PATH"
cat "$PLAN_PATH"
