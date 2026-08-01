#!/usr/bin/env bash
# Validate that Codex and OpenClaw can produce a real model reply.
set -u

PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT_SECONDS:-60}"
CODEX_ENDPOINT_TIMEOUT_SECONDS="${CODEX_ENDPOINT_TIMEOUT_SECONDS:-90}"
CODEX_VALIDATION_MODE="${CODEX_VALIDATION_MODE:-endpoint}"
CODEX_ENDPOINT_MODEL="${CODEX_ENDPOINT_MODEL:-}"
OPENCLAW_TIMEOUT_SECONDS="${OPENCLAW_TIMEOUT_SECONDS:-90}"
CODEX_HELLO_PROMPT="${CODEX_HELLO_PROMPT:-你好你是谁}"
OPENCLAW_HELLO_PROMPT="${OPENCLAW_HELLO_PROMPT:-你好你是谁}"
OPENCLAW_TEST_MODEL="${OPENCLAW_TEST_MODEL:-}"
EXPECTED_TEXT="${EXPECTED_TEXT:-}"
VALIDATE_CODEX="${VALIDATE_CODEX:-1}"
VALIDATE_OPENCLAW="${VALIDATE_OPENCLAW:-1}"
REPAIR_OPENCLAW_CONFIG="${REPAIR_OPENCLAW_CONFIG:-1}"
CHECK_OPENCLAW_CONFIG_SHAPE="${CHECK_OPENCLAW_CONFIG_SHAPE:-1}"
OPENCLAW_VALIDATION_ROUTE="${OPENCLAW_VALIDATION_ROUTE:-auto}"
VALIDATION_REPORT_PATH="${VALIDATION_REPORT_PATH:-}"
if [ -z "$VALIDATION_REPORT_PATH" ] && [ -n "${OPENCLAW_RUN_DIR:-}" ]; then
  VALIDATION_REPORT_PATH="$OPENCLAW_RUN_DIR/reports/validation-report.json"
fi

OPENCLAW_STATUS="skipped"
OPENCLAW_EXIT_CODE="null"
OPENCLAW_ERROR=""
OPENCLAW_REPAIRED=false
OPENCLAW_CONFIG_SHAPE_STATUS="skipped"
CODEX_STATUS="skipped"
CODEX_EXIT_CODE="null"
CODEX_ERROR=""
CODEX_USED_PROXY=false
VALIDATION_STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
VALIDATION_STARTED_EPOCH="$(date '+%s')"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

json_escape() {
  printf '%s' "$1" | LC_ALL=C LANG=C perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
}

file_tail() {
  local file="$1"
  [ -s "$file" ] || return 0
  tail -n 60 "$file"
}

validation_reason_code() {
  local status="$1" error="$2"
  if [ "$status" = "pass" ]; then
    printf ok
  elif [ "$status" = "skipped" ]; then
    printf skipped
  elif printf '%s' "$error" | grep -Eqi 'auth_unavailable|invalid_refresh_token|token_expired|no auth available|invalid refresh token'; then
    printf auth_unavailable
  elif printf '%s' "$error" | grep -Eqi 'command not found|CLI not found'; then
    printf not_installed
  elif printf '%s' "$error" | grep -Eqi 'timed out|timeout|alarm'; then
    printf timeout
  elif printf '%s' "$error" | grep -Eqi 'reconnecting|stream disconnected|stream closed before'; then
    printf stream_reconnect
  else
    printf validation_failed
  fi
}

write_validation_report() {
  local path="$VALIDATION_REPORT_PATH"
  local finished_at finished_epoch duration_seconds codex_reason openclaw_reason
  [ -n "$path" ] || return 0
  finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  finished_epoch="$(date '+%s')"
  duration_seconds=$((finished_epoch - VALIDATION_STARTED_EPOCH))
  codex_reason="$(validation_reason_code "$CODEX_STATUS" "$CODEX_ERROR")"
  openclaw_reason="$(validation_reason_code "$OPENCLAW_STATUS" "$OPENCLAW_ERROR")"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "schema_version": 2,
  "generated_at": "$finished_at",
  "started_at": "$VALIDATION_STARTED_AT",
  "finished_at": "$finished_at",
  "duration_seconds": $duration_seconds,
  "host": "$(json_escape "$(hostname 2>/dev/null || printf unknown)")",
  "user": "$(json_escape "$(whoami 2>/dev/null || printf unknown)")",
  "expected_text": "$(json_escape "$EXPECTED_TEXT")",
  "codex": {
    "requested": $([ "$VALIDATE_CODEX" = "1" ] && printf true || printf false),
    "status": "$(json_escape "$CODEX_STATUS")",
    "reason_code": "$(json_escape "$codex_reason")",
    "exit_code": $CODEX_EXIT_CODE,
    "timeout_seconds": ${CODEX_TIMEOUT_SECONDS:-0},
    "mode": "$(json_escape "$CODEX_VALIDATION_MODE")",
    "used_proxy": $CODEX_USED_PROXY,
    "error_tail": "$(json_escape "$CODEX_ERROR")"
  },
  "openclaw": {
    "requested": $([ "$VALIDATE_OPENCLAW" = "1" ] && printf true || printf false),
    "status": "$(json_escape "$OPENCLAW_STATUS")",
    "reason_code": "$(json_escape "$openclaw_reason")",
    "exit_code": $OPENCLAW_EXIT_CODE,
    "timeout_seconds": ${OPENCLAW_TIMEOUT_SECONDS:-0},
    "test_model": "$(json_escape "$OPENCLAW_TEST_MODEL")",
    "config_shape": "$(json_escape "$OPENCLAW_CONFIG_SHAPE_STATUS")",
    "repaired_config": $OPENCLAW_REPAIRED,
    "error_tail": "$(json_escape "$OPENCLAW_ERROR")"
  }
}
EOF
  log "Validation report written to: $path"
}

find_codex() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi
  if [ -x "/Applications/Codex.app/Contents/Resources/codex" ]; then
    printf '%s\n' "/Applications/Codex.app/Contents/Resources/codex"
    return 0
  fi
  return 1
}

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    # alarm + exec does not work: exec replaces perl and clears its alarm.
    # Keep a parent process that owns a separate process group so that a
    # stalled CLI and any descendants are actually terminated on macOS.
    perl -e '
      my $seconds = shift @ARGV;
      my $pid = fork();
      die "fork failed: $!\n" unless defined $pid;
      if ($pid == 0) {
        setpgrp(0, 0) or die "setpgrp failed: $!\n";
        exec @ARGV or die "exec failed: $!\n";
      }
      local $SIG{ALRM} = sub {
        kill "TERM", -$pid;
        select undef, undef, undef, 1;
        kill "KILL", -$pid;
        waitpid($pid, 0);
        exit 124;
      };
      alarm $seconds;
      waitpid($pid, 0);
      exit($? == -1 ? 1 : $? >> 8);
    ' "$seconds" "$@"
  fi
}

print_limited_file() {
  local label="$1" file="$2"
  if [ ! -s "$file" ]; then
    return
  fi
  printf '%s\n' "$label"
  sed -n '1,80p' "$file"
}

contains_expected_text() {
  local file="$1"
  [ -s "$file" ] && grep -qF "$EXPECTED_TEXT" "$file"
}

contains_nonempty_reply() {
  local file="$1"
  [ -s "$file" ] && grep -q '[^[:space:]]' "$file"
}

validation_output_ok() {
  local file
  if [ -n "$EXPECTED_TEXT" ]; then
    for file in "$@"; do
      contains_expected_text "$file" && return 0
    done
    return 1
  fi

  for file in "$@"; do
    contains_nonempty_reply "$file" && return 0
  done
  return 1
}

pass_message() {
  local label="$1"
  if [ -n "$EXPECTED_TEXT" ]; then
    log "PASS: $label replied with $EXPECTED_TEXT"
  else
    log "PASS: $label produced a non-empty reply"
  fi
}

validate_openclaw_config_shape() {
  if ! command -v node >/dev/null 2>&1; then
    log "WARN: node not found; skipping OpenClaw JSON config shape check"
    OPENCLAW_CONFIG_SHAPE_STATUS="skipped_node_missing"
    return 0
  fi

  node <<'NODE'
const fs = require('fs');
const path = require('path');
const configPath = path.join(process.env.HOME, '.openclaw', 'openclaw.json');
if (!fs.existsSync(configPath)) {
  console.error(`Missing OpenClaw config: ${configPath}`);
  process.exit(1);
}
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const providers = Object.keys(config.models?.providers || {});
const primary = config.agents?.defaults?.model?.primary;
const fallbacks = config.agents?.defaults?.model?.fallbacks || [];
const requestedRoute = process.env.OPENCLAW_VALIDATION_ROUTE || 'auto';
const route = requestedRoute === 'auto'
  ? (String(primary || '').startsWith('matrixrouter/') ? 'matrixrouter' : 'cliproxy')
  : requestedRoute;
if (route === 'matrixrouter') {
  const provider = config.models?.providers?.matrixrouter;
  if (!provider || provider.api !== 'anthropic-messages' || !String(primary || '').startsWith('matrixrouter/')) {
    console.error(`Expected MatrixRouter Anthropic configuration, got primary=${primary || '<none>'}`);
    process.exit(1);
  }
  console.log(`OpenClaw config OK: route=matrixrouter; primary=${primary}`);
  process.exit(0);
}
if (route !== 'cliproxy') {
  console.error(`Unsupported OPENCLAW_VALIDATION_ROUTE=${route}`);
  process.exit(1);
}
if (!providers.includes('cliproxy') || !providers.includes('deepseek')) {
  console.error(`Expected providers cliproxy and deepseek, got: ${providers.join(', ') || '<none>'}`);
  process.exit(1);
}
if (primary !== 'cliproxy/gpt-5.5') {
  console.error(`Expected primary cliproxy/gpt-5.5, got: ${primary || '<none>'}`);
  process.exit(1);
}
if (!fallbacks.includes('deepseek/deepseek-v4-pro')) {
  console.error(`Expected fallback deepseek/deepseek-v4-pro, got: ${fallbacks.join(', ') || '<none>'}`);
  process.exit(1);
}
console.log(`OpenClaw config OK: primary=${primary}; fallbacks=${fallbacks.join(',')}`);
NODE
}

openclaw_installed() {
  command -v openclaw >/dev/null 2>&1 || [ -d "/Applications/OpenClaw.app" ]
}

repair_openclaw_config_if_possible() {
  if [ "$OPENCLAW_VALIDATION_ROUTE" = "matrixrouter" ]; then
    log "MatrixRouter route detected; refusing to replace it with CLIProxy during validation"
    return 1
  fi
  if command -v node >/dev/null 2>&1 && node -e '
    const fs=require("fs"), p=require("path").join(process.env.HOME,".openclaw","openclaw.json");
    if (fs.existsSync(p) && String(JSON.parse(fs.readFileSync(p,"utf8"))?.agents?.defaults?.model?.primary || "").startsWith("matrixrouter/")) process.exit(0);
    process.exit(1);
  ' 2>/dev/null; then
    log "MatrixRouter route detected from current config; refusing CLIProxy repair"
    return 1
  fi
  if [ "$REPAIR_OPENCLAW_CONFIG" != "1" ]; then
    log "OpenClaw config repair disabled (REPAIR_OPENCLAW_CONFIG=$REPAIR_OPENCLAW_CONFIG)"
    return 1
  fi

  if ! openclaw_installed; then
    log "OpenClaw is not installed; cannot repair OpenClaw config"
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    log "Node is not available; cannot repair OpenClaw config"
    return 1
  fi

  log "Repairing OpenClaw model config"
  node <<'NODE'
const fs = require('fs');
const path = require('path');

const home = process.env.HOME;
const configPath = path.join(home, '.openclaw', 'openclaw.json');
const cliproxyBaseUrl = process.env.CLIPROXY_BASE_URL || 'http://127.0.0.1:8317/v1';
const cliproxyApiKey = process.env.CLIPROXY_API_KEY || 'open-api';
const cliproxyModel = process.env.CLIPROXY_MODEL || 'gpt-5.5';
const deepseekBaseUrl = process.env.DEEPSEEK_BASE_URL || 'https://api.qnaigc.com/v1';
const deepseekModel = process.env.DEEPSEEK_MODEL || 'deepseek/deepseek-v4-pro';

function backup(file) {
  if (!fs.existsSync(file)) return;
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  fs.copyFileSync(file, `${file}.bak.${stamp}`);
}

fs.mkdirSync(path.dirname(configPath), { recursive: true });
const config = fs.existsSync(configPath)
  ? JSON.parse(fs.readFileSync(configPath, 'utf8'))
  : {};

config.models = config.models || {};
config.models.providers = config.models.providers || {};
const existingCliproxy = config.models.providers.cliproxy || {};
const existingDeepseek = config.models.providers.deepseek || {};
const existingDeepseekModel = Array.isArray(existingDeepseek.models) ? existingDeepseek.models[0] || {} : {};

config.models.providers = {
  cliproxy: {
    baseUrl: existingCliproxy.baseUrl || cliproxyBaseUrl,
    apiKey: existingCliproxy.apiKey || cliproxyApiKey,
    api: 'openai-completions',
    models: [
      {
        id: cliproxyModel,
        name: 'gpt5.5',
        input: ['text'],
        contextWindow: 272000
      }
    ]
  },
  deepseek: {
    baseUrl: existingDeepseek.baseUrl || deepseekBaseUrl,
    apiKey: existingDeepseek.apiKey || process.env.DEEPSEEK_API_KEY || existingDeepseekModel.apiKey || '',
    api: 'openai-completions',
    models: [
      {
        id: deepseekModel,
        name: existingDeepseekModel.name || 'DeepSeek V4 Pro',
        input: existingDeepseekModel.input || ['text'],
        contextWindow: existingDeepseekModel.contextWindow || 64000
      }
    ]
  }
};

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = `cliproxy/${cliproxyModel}`;
config.agents.defaults.model.fallbacks = [deepseekModel];
config.agents.defaults.models = config.agents.defaults.models || {};
config.agents.defaults.models[`cliproxy/${cliproxyModel}`] = { alias: 'gpt5.5' };
config.agents.defaults.models[deepseekModel] = { alias: 'DeepSeek Pro' };
config.agents.defaults.thinkingDefault = 'off';

backup(configPath);
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
fs.chmodSync(configPath, 0o600);
console.log(`OpenClaw config repaired: ${configPath}`);
NODE
}

validate_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    log "FAIL: openclaw command not found"
    OPENCLAW_STATUS="fail"
    OPENCLAW_EXIT_CODE=127
    OPENCLAW_ERROR="openclaw command not found"
    return 1
  fi

  if [ "$CHECK_OPENCLAW_CONFIG_SHAPE" = "1" ]; then
    log "Validating OpenClaw config shape"
    if ! validate_openclaw_config_shape; then
      OPENCLAW_CONFIG_SHAPE_STATUS="fail"
      if ! repair_openclaw_config_if_possible; then
        OPENCLAW_STATUS="fail"
        OPENCLAW_EXIT_CODE=1
        OPENCLAW_ERROR="OpenClaw config shape check failed and repair was not possible"
        return 1
      fi
      OPENCLAW_REPAIRED=true
      if ! validate_openclaw_config_shape; then
        OPENCLAW_STATUS="fail"
        OPENCLAW_EXIT_CODE=1
        OPENCLAW_ERROR="OpenClaw config shape check failed after repair"
        return 1
      fi
      OPENCLAW_CONFIG_SHAPE_STATUS="repaired"
    else
      OPENCLAW_CONFIG_SHAPE_STATUS="pass"
    fi
  else
    log "Skipping OpenClaw config shape check (CHECK_OPENCLAW_CONFIG_SHAPE=$CHECK_OPENCLAW_CONFIG_SHAPE)"
    OPENCLAW_CONFIG_SHAPE_STATUS="skipped"
  fi

  local tmp status retry_tmp retry_status
  tmp="$(mktemp -d /tmp/openclaw-validate.XXXXXX)"
  if [ -n "$OPENCLAW_TEST_MODEL" ]; then
    log "Validating OpenClaw model reply via $OPENCLAW_TEST_MODEL"
  else
    log "Validating OpenClaw model reply via default model"
  fi
  set +e
  if [ -n "$OPENCLAW_TEST_MODEL" ]; then
    run_with_timeout "$OPENCLAW_TIMEOUT_SECONDS" \
      openclaw infer model run \
        --model "$OPENCLAW_TEST_MODEL" \
        --prompt "$OPENCLAW_HELLO_PROMPT" \
        --thinking off \
        --json >"$tmp/openclaw.out" 2>"$tmp/openclaw.err"
  else
    run_with_timeout "$OPENCLAW_TIMEOUT_SECONDS" \
      openclaw infer model run \
        --prompt "$OPENCLAW_HELLO_PROMPT" \
        --thinking off \
        --json >"$tmp/openclaw.out" 2>"$tmp/openclaw.err"
  fi
  status="$?"
  OPENCLAW_EXIT_CODE="$status"
  set -e

  if validation_output_ok "$tmp/openclaw.out"; then
    OPENCLAW_STATUS="pass"
    pass_message "OpenClaw"
    rm -rf "$tmp"
    return 0
  fi

  log "FAIL: OpenClaw validation failed with status $status"
  OPENCLAW_ERROR="$(file_tail "$tmp/openclaw.err")
$(file_tail "$tmp/openclaw.out")"
  print_limited_file "-- OpenClaw stderr --" "$tmp/openclaw.err"
  print_limited_file "-- OpenClaw stdout --" "$tmp/openclaw.out"
  rm -rf "$tmp"

  if ! repair_openclaw_config_if_possible; then
    OPENCLAW_STATUS="fail"
    return 1
  fi
  OPENCLAW_REPAIRED=true
  retry_tmp="$(mktemp -d /tmp/openclaw-validate-retry.XXXXXX)"
  log "Retrying OpenClaw model reply after config repair"
  set +e
  if [ -n "$OPENCLAW_TEST_MODEL" ]; then
    run_with_timeout "$OPENCLAW_TIMEOUT_SECONDS" \
      openclaw infer model run \
        --model "$OPENCLAW_TEST_MODEL" \
        --prompt "$OPENCLAW_HELLO_PROMPT" \
        --thinking off \
        --json >"$retry_tmp/openclaw.out" 2>"$retry_tmp/openclaw.err"
  else
    run_with_timeout "$OPENCLAW_TIMEOUT_SECONDS" \
      openclaw infer model run \
        --prompt "$OPENCLAW_HELLO_PROMPT" \
        --thinking off \
        --json >"$retry_tmp/openclaw.out" 2>"$retry_tmp/openclaw.err"
  fi
  retry_status="$?"
  OPENCLAW_EXIT_CODE="$retry_status"
  set -e

  if validation_output_ok "$retry_tmp/openclaw.out"; then
    OPENCLAW_STATUS="pass"
    pass_message "OpenClaw after config repair"
    rm -rf "$retry_tmp"
    return 0
  fi

  log "FAIL: OpenClaw validation failed after config repair with status $retry_status"
  OPENCLAW_STATUS="fail"
  OPENCLAW_ERROR="$(file_tail "$retry_tmp/openclaw.err")
$(file_tail "$retry_tmp/openclaw.out")"
  print_limited_file "-- OpenClaw retry stderr --" "$retry_tmp/openclaw.err"
  print_limited_file "-- OpenClaw retry stdout --" "$retry_tmp/openclaw.out"
  rm -rf "$retry_tmp"
  return 1
}

validate_codex() {
  local codex_bin tmp status
  local proxy_env=()
  if ! codex_bin="$(find_codex)"; then
    log "FAIL: Codex CLI not found"
    CODEX_STATUS="fail"
    CODEX_EXIT_CODE=127
    CODEX_ERROR="Codex CLI not found"
    return 1
  fi

  if [ "$CODEX_VALIDATION_MODE" = "endpoint" ]; then
    validate_codex_endpoint "$codex_bin"
    return "$?"
  fi
  if [ "$CODEX_VALIDATION_MODE" != "exec" ]; then
    log "FAIL: unsupported CODEX_VALIDATION_MODE=$CODEX_VALIDATION_MODE (use endpoint or exec)"
    CODEX_STATUS="fail"
    CODEX_EXIT_CODE=2
    CODEX_ERROR="Unsupported CODEX_VALIDATION_MODE=$CODEX_VALIDATION_MODE"
    return 1
  fi

  tmp="$(mktemp -d /tmp/codex-validate.XXXXXX)"
  log "Validating Codex model reply via $codex_bin"
  if command -v curl >/dev/null 2>&1 && curl --socks5-hostname 127.0.0.1:7890 --connect-timeout 2 --max-time 4 -sSI https://chatgpt.com >/dev/null 2>&1; then
    proxy_env=(env HTTPS_PROXY=socks5h://127.0.0.1:7890 ALL_PROXY=socks5h://127.0.0.1:7890)
    CODEX_USED_PROXY=true
    log "Using local socks proxy for Codex validation: 127.0.0.1:7890"
  fi
  set +e
  if [ "${#proxy_env[@]}" -gt 0 ]; then
    run_with_timeout "$CODEX_TIMEOUT_SECONDS" \
      "${proxy_env[@]}" "$codex_bin" exec \
        --skip-git-repo-check \
        --output-last-message "$tmp/codex.last" \
        "$CODEX_HELLO_PROMPT" \
        </dev/null >"$tmp/codex.out" 2>"$tmp/codex.err"
  else
    run_with_timeout "$CODEX_TIMEOUT_SECONDS" \
      "$codex_bin" exec \
        --skip-git-repo-check \
        --output-last-message "$tmp/codex.last" \
        "$CODEX_HELLO_PROMPT" \
        </dev/null >"$tmp/codex.out" 2>"$tmp/codex.err"
  fi
  status="$?"
  CODEX_EXIT_CODE="$status"
  set -e

  if validation_output_ok "$tmp/codex.last" "$tmp/codex.out"; then
    CODEX_STATUS="pass"
    pass_message "Codex"
    rm -rf "$tmp"
    return 0
  fi

  log "FAIL: Codex validation failed with status $status"
  CODEX_STATUS="fail"
  CODEX_ERROR="$(file_tail "$tmp/codex.err")
$(file_tail "$tmp/codex.out")
$(file_tail "$tmp/codex.last")"
  print_limited_file "-- Codex stderr --" "$tmp/codex.err"
  print_limited_file "-- Codex stdout --" "$tmp/codex.out"
  print_limited_file "-- Codex last message --" "$tmp/codex.last"
  rm -rf "$tmp"
  return 1
}

validate_codex_endpoint() {
  local codex_bin="$1"
  local tmp status

  tmp="$(mktemp -d /tmp/codex-endpoint-validate.XXXXXX)"
  log "Validating Codex CLI presence via $codex_bin"
  "$codex_bin" --version >"$tmp/codex.version" 2>"$tmp/codex.version.err" || true

  log "Validating Codex Responses endpoint with a minimal POST"
  set +e
  CODEX_ENDPOINT_MODEL="$CODEX_ENDPOINT_MODEL" \
  CODEX_ENDPOINT_TIMEOUT_SECONDS="$CODEX_ENDPOINT_TIMEOUT_SECONDS" \
    python3 <<'PY' >"$tmp/codex-endpoint.out" 2>"$tmp/codex-endpoint.err"
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

home = Path.home()
config_path = home / ".codex" / "config.toml"
auth_path = home / ".codex" / "auth.json"
if not config_path.exists():
    raise SystemExit(f"Missing Codex config: {config_path}")

config = config_path.read_text()

def toml_string(name, default=""):
    matches = re.findall(rf'(?m)^\s*{re.escape(name)}\s*=\s*"([^"]*)"', config)
    return matches[-1] if matches else default

model = os.environ.get("CODEX_ENDPOINT_MODEL") or toml_string("model", "gpt-5.5")
provider = toml_string("model_provider", "")
wire_api = toml_string("wire_api", "")
base_url = toml_string("base_url", "").rstrip("/")
if not base_url:
    raise SystemExit("Missing base_url in Codex config")
if wire_api and wire_api != "responses":
    raise SystemExit(f"Unexpected Codex wire_api={wire_api}; expected responses")

api_key = os.environ.get("CLIPROXY_API_KEY") or "open-api"
if auth_path.exists():
    try:
        api_key = json.loads(auth_path.read_text()).get("OPENAI_API_KEY") or api_key
    except Exception as exc:
        raise SystemExit(f"Failed to parse Codex auth.json: {exc}")

payload = {
    "model": model,
    "input": "Reply exactly: OK",
    "stream": False,
}
req = urllib.request.Request(
    f"{base_url}/responses",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    },
    method="POST",
)
timeout = int(os.environ.get("CODEX_ENDPOINT_TIMEOUT_SECONDS") or "90")
try:
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read(4096).decode("utf-8", "replace")
        print(json.dumps({
            "status": resp.status,
            "provider": provider,
            "wire_api": wire_api or "responses",
            "base_url": base_url,
            "model": model,
            "body_prefix": body[:240],
        }, ensure_ascii=False))
except urllib.error.HTTPError as exc:
    body = exc.read(4096).decode("utf-8", "replace")
    print(body, file=sys.stderr)
    raise SystemExit(f"HTTP {exc.code} from {base_url}/responses")
except Exception as exc:
    raise SystemExit(str(exc))
PY
  status="$?"
  CODEX_EXIT_CODE="$status"
  set -e

  if [ "$status" = "0" ]; then
    CODEX_STATUS="pass"
    log "PASS: Codex CLI exists and /v1/responses accepted a minimal request"
    rm -rf "$tmp"
    return 0
  fi

  log "FAIL: Codex endpoint validation failed with status $status"
  CODEX_STATUS="fail"
  CODEX_ERROR="$(file_tail "$tmp/codex.version.err")
$(file_tail "$tmp/codex-endpoint.err")
$(file_tail "$tmp/codex-endpoint.out")"
  print_limited_file "-- Codex version stderr --" "$tmp/codex.version.err"
  print_limited_file "-- Codex endpoint stderr --" "$tmp/codex-endpoint.err"
  print_limited_file "-- Codex endpoint stdout --" "$tmp/codex-endpoint.out"
  rm -rf "$tmp"
  return 1
}

main() {
  local failed=0
  set -e

  if [ "$VALIDATE_OPENCLAW" = "1" ]; then
    validate_openclaw || failed=1
  else
    log "Skipping OpenClaw validation (VALIDATE_OPENCLAW=0)"
  fi

  if [ "$VALIDATE_CODEX" = "1" ]; then
    validate_codex || failed=1
  else
    log "Skipping Codex validation (VALIDATE_CODEX=0)"
  fi

  if [ "$failed" = "0" ]; then
    log "Validation passed"
  else
    log "Validation failed"
  fi
  write_validation_report
  return "$failed"
}

main "$@"
