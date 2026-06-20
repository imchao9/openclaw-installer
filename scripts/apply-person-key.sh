#!/usr/bin/env bash
# Apply one person's API keys from private-secrets/key.csv to OpenClaw and Codex local config.
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PATH

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${KEY_CSV:-}" ]; then
  if [ -f "$ROOT/private-secrets/key.csv" ]; then
    KEY_CSV="$ROOT/private-secrets/key.csv"
  else
    KEY_CSV="$ROOT/key.csv"
  fi
fi
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
CODEX_AUTH="${CODEX_AUTH:-$HOME/.codex/auth.json}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
OPENCLAW_PROVIDER="${OPENCLAW_PROVIDER:-auto}"
OPENCLAW_KEY_COLUMN="${OPENCLAW_KEY_COLUMN:-claude-opus-4-8}"
CODEX_KEY_COLUMN="${CODEX_KEY_COLUMN:-gpt-5.5}"
OPENCLAW_API_KEY="${OPENCLAW_API_KEY:-}"
CODEX_API_KEY="${CODEX_API_KEY:-}"
CLAUDE_API_KEY="${CLAUDE_API_KEY:-}"
CODEX_AUTH_KEY="${CODEX_AUTH_KEY:-OPENAI_API_KEY}"
CODEX_WRITE_MODE="${CODEX_WRITE_MODE:-auto}"
OPENCLAW_GPT_PROVIDER="${OPENCLAW_GPT_PROVIDER:-openai}"
OPENCLAW_GPT_MODEL="${OPENCLAW_GPT_MODEL:-gpt-5.5}"
OPENCLAW_GPT_API="${OPENCLAW_GPT_API:-openai-responses}"
OPENCLAW_GPT_ALIAS="${OPENCLAW_GPT_ALIAS:-gpt55}"
OPENCLAW_HEARTBEAT_MODEL="${OPENCLAW_HEARTBEAT_MODEL:-openai/gpt-5.5}"
OPENCLAW_HEARTBEAT_EVERY="${OPENCLAW_HEARTBEAT_EVERY:-55m}"
DISPLAY_SLEEP_MINUTES="${DISPLAY_SLEEP_MINUTES:-10}"
CLASH_APP_NAME="${CLASH_APP_NAME:-Clash Party}"
CLASH_LABEL="${CLASH_LABEL:-local.openclaw-installer.clash-party}"
POWER_SETUP="${POWER_SETUP:-1}"
LOCAL_BYPASS_SETUP="${LOCAL_BYPASS_SETUP:-1}"
OPENCLAW_SETUP="${OPENCLAW_SETUP:-1}"
OPENCLAW_SKILLS_SETUP="${OPENCLAW_SKILLS_SETUP:-1}"
OPENCLAW_SKILLS="${OPENCLAW_SKILLS:-cross-session-tasks}"
CLASH_SETUP="${CLASH_SETUP:-1}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
ENSURE_RUNTIME=0
APPLY=0
LOCAL_ONLY=0
PERSON_NAME="${PERSON_NAME:-}"

usage() {
  cat <<'EOF'
Usage:
  OPENCLAW_API_KEY='sk-...' CODEX_API_KEY='sk-...' bash scripts/apply-person-key.sh [--apply|--dry-run] [--ensure-runtime]

Examples:
  OPENCLAW_API_KEY='sk-...' CODEX_API_KEY='sk-...' bash scripts/apply-person-key.sh --apply --ensure-runtime

Legacy CSV mode:
  KEY_CSV=./key.csv bash scripts/apply-person-key.sh PersonName --apply

Remote example:
  REMOTE_HOST=cm@192.168.0.250 REMOTE_PASSWORD='123456' OPENCLAW_API_KEY='sk-...' CODEX_API_KEY='sk-...' bash scripts/apply-person-key.sh --apply --ensure-runtime

Defaults:
  KEY_CSV=./key.csv
  OPENCLAW_CONFIG=~/.openclaw/openclaw.json
  CODEX_AUTH=~/.codex/auth.json
  CLAUDE_SETTINGS=~/.claude/settings.json
  OPENCLAW_PROVIDER=auto
  OPENCLAW_KEY_COLUMN=claude-opus-4-8
  CODEX_KEY_COLUMN=gpt-5.5
  OPENCLAW_API_KEY=<empty>
  CODEX_API_KEY=<empty>
  CLAUDE_API_KEY=<empty>
  CODEX_WRITE_MODE=auto
  OPENCLAW_GPT_PROVIDER=openai
  OPENCLAW_GPT_MODEL=gpt-5.5
  OPENCLAW_GPT_API=openai-responses
  OPENCLAW_GPT_ALIAS=gpt55
  OPENCLAW_HEARTBEAT_MODEL=openai/gpt-5.5
  OPENCLAW_HEARTBEAT_EVERY=55m
  DISPLAY_SLEEP_MINUTES=10
  CLASH_APP_NAME="Clash Party"
  POWER_SETUP=1
  LOCAL_BYPASS_SETUP=1
  OPENCLAW_SETUP=1
  OPENCLAW_SKILLS_SETUP=1
  OPENCLAW_SKILLS=cross-session-tasks
  CLASH_SETUP=1
  SUDO_PASSWORD=<empty>

Safety:
  - OpenClaw defaults to the current primary model provider and the claude-opus-4-8 CSV column.
  - Claude settings, when present, use the same claude-opus-4-8 key.
  - Codex and OpenClaw's optional openai/gpt-5.5 model default to the gpt-5.5 CSV column.
  - Direct key mode does not use PERSON_NAME or key.csv.
  - Legacy CSV mode is still available when OPENCLAW_API_KEY is not provided.
  - Codex auth is updated only when it already uses OPENAI_API_KEY, unless CODEX_WRITE_MODE=force-api-key.
  - --ensure-runtime configures pmset, local proxy bypass, OpenClaw skills/gateway, and Clash Party login autostart.
  - Runtime setup may ask for sudo for pmset/networksetup.
  - Without --apply, the script only prints a dry-run plan.
  - With --apply, existing JSON files are backed up before writing.
  - API keys are never printed in full.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

run_sudo() {
  if [ -n "$SUDO_PASSWORD" ]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --apply)
      APPLY=1
      ;;
    --dry-run)
      APPLY=0
      ;;
    --local-only)
      LOCAL_ONLY=1
      ;;
    --ensure-runtime)
      ENSURE_RUNTIME=1
      ;;
    --no-ensure-runtime)
      ENSURE_RUNTIME=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $arg"
      ;;
    *)
      if [ -z "$PERSON_NAME" ]; then
        PERSON_NAME="$arg"
      else
        die "Only one person name is supported. Got extra argument: $arg"
      fi
      ;;
  esac
done

run_ssh() {
  local cmd="$1"
  if [ -n "${REMOTE_PASSWORD:-}" ]; then
    command -v expect >/dev/null 2>&1 || die "REMOTE_PASSWORD requires expect, but expect was not found."
    REMOTE_CMD="$cmd" expect <<'EOF'
set timeout 60
set password $env(REMOTE_PASSWORD)
set remote_cmd $env(REMOTE_CMD)
set remote_host $env(REMOTE_HOST)
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $remote_host $remote_cmd
expect {
  -re {(?i)password:} { send "$password\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
  else
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$REMOTE_HOST" "$cmd"
  fi
}

run_scp() {
  local src="$1" dst="$2"
  if [ -n "${REMOTE_PASSWORD:-}" ]; then
    command -v expect >/dev/null 2>&1 || die "REMOTE_PASSWORD requires expect, but expect was not found."
    SCP_SRC="$src" SCP_DST="$dst" expect <<'EOF'
set timeout 60
set password $env(REMOTE_PASSWORD)
set src $env(SCP_SRC)
set dst $env(SCP_DST)
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $src $dst
expect {
  -re {(?i)password:} { send "$password\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
  else
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$src" "$dst"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

remote_mode() {
  if [ -z "$OPENCLAW_API_KEY" ] && [ ! -f "$KEY_CSV" ]; then
    die "Missing key CSV: $KEY_CSV. Or pass OPENCLAW_API_KEY directly."
  fi
  if [ -z "$OPENCLAW_API_KEY" ]; then
    [ -n "$PERSON_NAME" ] || die "Missing OPENCLAW_API_KEY. For CDN commands, pass OPENCLAW_API_KEY and CODEX_API_KEY directly."
  fi

  local remote_tmp remote_script remote_csv apply_flag runtime_flag cmd
  remote_tmp="$(run_ssh "mktemp -d /tmp/openclaw-key-rotate.XXXXXX")"
  remote_script="$remote_tmp/apply-person-key.sh"
  remote_csv="$remote_tmp/key.csv"

  if [ -n "$OPENCLAW_API_KEY" ]; then
    log "Copying script to $REMOTE_HOST:$remote_tmp"
  else
    log "Copying script and key.csv to $REMOTE_HOST:$remote_tmp"
  fi
  run_scp "$0" "$REMOTE_HOST:$remote_script"
  if [ -z "$OPENCLAW_API_KEY" ]; then
    run_scp "$KEY_CSV" "$REMOTE_HOST:$remote_csv"
  fi

  apply_flag="--dry-run"
  [ "$APPLY" = "1" ] && apply_flag="--apply"
  runtime_flag="--no-ensure-runtime"
  [ "$ENSURE_RUNTIME" = "1" ] && runtime_flag="--ensure-runtime"

  cmd="chmod +x $(shell_quote "$remote_script"); KEY_CSV=$(shell_quote "$remote_csv") OPENCLAW_API_KEY=$(shell_quote "$OPENCLAW_API_KEY") CODEX_API_KEY=$(shell_quote "$CODEX_API_KEY") CLAUDE_API_KEY=$(shell_quote "$CLAUDE_API_KEY") OPENCLAW_PROVIDER=$(shell_quote "$OPENCLAW_PROVIDER") OPENCLAW_KEY_COLUMN=$(shell_quote "$OPENCLAW_KEY_COLUMN") CODEX_KEY_COLUMN=$(shell_quote "$CODEX_KEY_COLUMN") CODEX_AUTH_KEY=$(shell_quote "$CODEX_AUTH_KEY") CODEX_WRITE_MODE=$(shell_quote "$CODEX_WRITE_MODE") DISPLAY_SLEEP_MINUTES=$(shell_quote "$DISPLAY_SLEEP_MINUTES") CLASH_APP_NAME=$(shell_quote "$CLASH_APP_NAME") CLASH_LABEL=$(shell_quote "$CLASH_LABEL") POWER_SETUP=$(shell_quote "$POWER_SETUP") LOCAL_BYPASS_SETUP=$(shell_quote "$LOCAL_BYPASS_SETUP") OPENCLAW_SETUP=$(shell_quote "$OPENCLAW_SETUP") OPENCLAW_SKILLS_SETUP=$(shell_quote "$OPENCLAW_SKILLS_SETUP") OPENCLAW_SKILLS=$(shell_quote "$OPENCLAW_SKILLS") CLASH_SETUP=$(shell_quote "$CLASH_SETUP") bash $(shell_quote "$remote_script") --local-only $(shell_quote "$PERSON_NAME") $apply_flag $runtime_flag; status=\$?; rm -rf $(shell_quote "$remote_tmp"); exit \$status"
  run_ssh "$cmd"
}

if [ -n "${REMOTE_HOST:-}" ] && [ "$LOCAL_ONLY" != "1" ]; then
  remote_mode
  exit 0
fi

command -v node >/dev/null 2>&1 || die "node is required. Install Node.js or run the base OpenClaw installer first."

if [ -z "$OPENCLAW_API_KEY" ] && [ ! -f "$KEY_CSV" ]; then
  die "Missing key CSV: $KEY_CSV. Or pass OPENCLAW_API_KEY directly."
fi

if [ -z "$PERSON_NAME" ] && [ -f "$KEY_CSV" ]; then
  log "Available names in $KEY_CSV:"
  KEY_CSV="$KEY_CSV" node <<'JS'
const fs = require('fs');
const text = fs.readFileSync(process.env.KEY_CSV, 'utf8').replace(/^\uFEFF/, '');
function parseCsv(input) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"' && input[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = ''; }
    else field += ch;
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, '')); rows.push(row); }
  return rows;
}
for (const row of parseCsv(text).slice(1)) {
  const name = (row[0] || '').trim();
  if (name) console.log('  - ' + name);
}
JS
  if [ -t 0 ]; then
    printf 'Enter person name to apply key: '
    IFS= read -r PERSON_NAME
  fi
fi

if [ -z "$OPENCLAW_API_KEY" ]; then
  [ -n "$PERSON_NAME" ] || die "Missing OPENCLAW_API_KEY. For CDN commands, pass OPENCLAW_API_KEY and CODEX_API_KEY directly."
fi

if [ "$APPLY" != "1" ]; then
  log "Dry-run mode. Add --apply to write changes."
fi

export PERSON_NAME KEY_CSV OPENCLAW_CONFIG CODEX_AUTH CLAUDE_SETTINGS OPENCLAW_PROVIDER OPENCLAW_KEY_COLUMN CODEX_KEY_COLUMN OPENCLAW_API_KEY CODEX_API_KEY CLAUDE_API_KEY CODEX_AUTH_KEY CODEX_WRITE_MODE OPENCLAW_GPT_PROVIDER OPENCLAW_GPT_MODEL OPENCLAW_GPT_API OPENCLAW_GPT_ALIAS OPENCLAW_HEARTBEAT_MODEL OPENCLAW_HEARTBEAT_EVERY APPLY
node <<'JS'
const fs = require('fs');
const path = require('path');
const os = require('os');

const person = (process.env.PERSON_NAME || '').trim() || '<direct-key>';
const keyCsv = expandUser(process.env.KEY_CSV);
const openclawConfig = expandUser(process.env.OPENCLAW_CONFIG);
const codexAuth = expandUser(process.env.CODEX_AUTH);
const claudeSettings = expandUser(process.env.CLAUDE_SETTINGS);
let provider = process.env.OPENCLAW_PROVIDER;
let openclawCol = process.env.OPENCLAW_KEY_COLUMN;
const codexCol = process.env.CODEX_KEY_COLUMN;
const directOpenclawKey = process.env.OPENCLAW_API_KEY || '';
const directCodexKey = process.env.CODEX_API_KEY || '';
const directClaudeKey = process.env.CLAUDE_API_KEY || '';
const codexAuthKey = process.env.CODEX_AUTH_KEY;
const codexWriteMode = process.env.CODEX_WRITE_MODE;
const openclawGptProvider = process.env.OPENCLAW_GPT_PROVIDER || 'openai';
const openclawGptModel = process.env.OPENCLAW_GPT_MODEL || 'gpt-5.5';
const openclawGptApi = process.env.OPENCLAW_GPT_API || 'openai-responses';
const openclawGptAlias = process.env.OPENCLAW_GPT_ALIAS || '';
const openclawHeartbeatModel = process.env.OPENCLAW_HEARTBEAT_MODEL || '';
const openclawHeartbeatEvery = process.env.OPENCLAW_HEARTBEAT_EVERY || '';
const apply = process.env.APPLY === '1';

function fail(message) {
  console.error('ERROR: ' + message);
  process.exit(1);
}

function expandUser(value) {
  if (value === '~') return os.homedir();
  if (value.startsWith('~/')) return path.join(os.homedir(), value.slice(2));
  return value;
}

function mask(value) {
  value = value || '';
  if (!value) return '<empty>';
  return `len=${value.length}, prefix=${value.slice(0, 6)}, suffix=${value.slice(-4)}`;
}

function parseCsv(input) {
  input = input.replace(/^\uFEFF/, '');
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"' && input[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = ''; }
    else field += ch;
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, '')); rows.push(row); }
  return rows;
}

function loadPersonRow(requiredColumns) {
  const rows = parseCsv(fs.readFileSync(keyCsv, 'utf8'));
  const headers = rows.shift() || [];
  if (!headers.length) fail(`CSV has no header: ${keyCsv}`);
  for (const column of requiredColumns) {
    if (!headers.includes(column)) fail(`Missing key column "${column}". Headers: ${JSON.stringify(headers)}`);
  }
  const matches = [];
  for (const values of rows) {
    const row = Object.fromEntries(headers.map((header, index) => [header, values[index] || '']));
    if ((row[''] || '').trim() === person) matches.push(row);
  }
  if (!matches.length) fail(`Cannot find person "${person}" in ${keyCsv}`);
  if (matches.length > 1) fail(`Found multiple rows for "${person}". Please make the name unique.`);
  return matches[0];
}

function readJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

const openclaw = readJson(openclawConfig, {});
const codex = readJson(codexAuth, {});
const claudeSettingsExists = fs.existsSync(claudeSettings);
const claude = claudeSettingsExists ? readJson(claudeSettings, {}) : null;
const currentProfile = ((openclaw.tools || {}).profile) || '<missing>';
const currentPrimary = (((openclaw.agents || {}).defaults || {}).model || {}).primary || '<missing>';

const models = openclaw.models || (openclaw.models = {});
const providers = models.providers || (models.providers = {});
if (provider === 'auto') {
  if (currentPrimary.includes('/')) provider = currentPrimary.split('/', 1)[0];
  else if (Object.keys(providers).length === 1) provider = Object.keys(providers)[0];
  else provider = 'ma';
}

const providerConfig = providers[provider] || (providers[provider] = {});
const modelId = currentPrimary.startsWith(provider + '/') ? currentPrimary.split('/').slice(1).join('/') : '';
if (openclawCol === 'auto') openclawCol = modelId || 'gpt-5.5';

const codexShouldWrite = (
  codexWriteMode === 'force-api-key'
  || Object.prototype.hasOwnProperty.call(codex, codexAuthKey)
  || Object.keys(codex).length === 0
);
const shouldConfigureOpenclawGpt = Boolean(openclawGptProvider && openclawGptModel);
const requiredColumns = [openclawCol];
if (!directOpenclawKey && (codexShouldWrite || shouldConfigureOpenclawGpt) && !directCodexKey && !requiredColumns.includes(codexCol)) requiredColumns.push(codexCol);

const row = directOpenclawKey ? {} : loadPersonRow(requiredColumns);
const openclawKey = (directOpenclawKey || row[openclawCol] || '').trim();
const gptKey = (directCodexKey || row[codexCol] || '').trim();
const codexKey = codexShouldWrite ? gptKey : '';
const claudeKey = claudeSettingsExists ? (directClaudeKey || openclawKey).trim() : '';
if (!openclawKey) fail(`Empty key in column "${openclawCol}" for ${person}`);
if (codexShouldWrite && !codexKey) fail(`Empty key in column "${codexCol}" for ${person}`);
if (shouldConfigureOpenclawGpt && !gptKey) fail(`Empty key in column "${codexCol}" for OpenClaw ${openclawGptProvider}/${openclawGptModel}`);
if (claudeSettingsExists && !claudeKey) fail(`Empty Claude settings key for ${person}`);

console.log(`Person: ${person}`);
console.log(`OpenClaw target: ${openclawConfig}`);
console.log(`Current OpenClaw tools.profile: ${currentProfile}`);
console.log(`Current OpenClaw primary model: ${currentPrimary}`);
console.log(`OpenClaw provider/key column: ${provider}/${openclawCol} (${mask(openclawKey)})`);
console.log(`Codex auth target: ${codexAuth}`);
if (codexShouldWrite) {
  console.log(`Codex auth key/column: ${codexAuthKey}/${codexCol} (${mask(codexKey)})`);
} else {
  console.log(`Codex auth update: skipped (${codexAuthKey} not present; existing auth looks like login tokens)`);
}
if (shouldConfigureOpenclawGpt) {
  console.log(`OpenClaw GPT model: ${openclawGptProvider}/${openclawGptModel} via ${codexCol} (${mask(gptKey)})`);
  if (openclawHeartbeatModel) console.log(`OpenClaw heartbeat model: ${openclawHeartbeatModel}`);
}
console.log(`Claude settings target: ${claudeSettings}`);
if (claudeSettingsExists) {
  console.log(`Claude settings key path: env.ANTHROPIC_AUTH_TOKEN (${mask(claudeKey)})`);
} else {
  console.log('Claude settings update: skipped (settings.json not found)');
}

console.log(`Existing OpenClaw provider key: ${mask(providerConfig.apiKey || '')}`);
if (codexShouldWrite) console.log(`Existing Codex ${codexAuthKey}: ${mask(codex[codexAuthKey] || '')}`);
if (claudeSettingsExists) console.log(`Existing Claude env.ANTHROPIC_AUTH_TOKEN: ${mask((((claude.env || {}).ANTHROPIC_AUTH_TOKEN) || ''))}`);

providerConfig.apiKey = openclawKey;
if (shouldConfigureOpenclawGpt) {
  const gptProviderConfig = providers[openclawGptProvider] || (providers[openclawGptProvider] = {});
  gptProviderConfig.apiKey = gptKey;
  if (openclawGptApi) gptProviderConfig.api = openclawGptApi;
  const modelEntry = {
    id: openclawGptModel,
    name: openclawGptModel,
    maxTokens: 40960,
    contextWindow: 200000,
    input: ['text', 'image'],
  };
  const existingModels = Array.isArray(gptProviderConfig.models) ? gptProviderConfig.models : [];
  gptProviderConfig.models = [
    ...existingModels.filter((model) => model && model.id !== openclawGptModel),
    modelEntry,
  ];
  openclaw.agents = openclaw.agents || {};
  openclaw.agents.defaults = openclaw.agents.defaults || {};
  if (openclawGptAlias) {
    openclaw.agents.defaults.models = openclaw.agents.defaults.models || {};
    openclaw.agents.defaults.models[`${openclawGptProvider}/${openclawGptModel}`] = { alias: openclawGptAlias };
  }
  if (openclawHeartbeatModel) {
    openclaw.agents.defaults.heartbeat = openclaw.agents.defaults.heartbeat || {};
    openclaw.agents.defaults.heartbeat.model = openclawHeartbeatModel;
    if (openclawHeartbeatEvery) openclaw.agents.defaults.heartbeat.every = openclawHeartbeatEvery;
  }
}
if (codexShouldWrite) codex[codexAuthKey] = codexKey;
if (claudeSettingsExists) {
  claude.env = claude.env || {};
  claude.env.ANTHROPIC_AUTH_TOKEN = claudeKey;
}

function backup(file) {
  if (!fs.existsSync(file)) return null;
  const now = new Date();
  const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}_${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}${String(now.getSeconds()).padStart(2, '0')}`;
  const dst = `${file}.bak.${stamp}`;
  fs.copyFileSync(file, dst);
  return dst;
}

function checkWritableTarget(file) {
  if (fs.existsSync(file)) {
    try { fs.accessSync(file, fs.constants.W_OK); }
    catch { fail(`Cannot write target file: ${file}. Run this script from a normal Terminal session, or allow OpenClaw filesystem write access.`); }
    return;
  }
  const parent = path.dirname(file);
  if (fs.existsSync(parent)) {
    try { fs.accessSync(parent, fs.constants.W_OK); }
    catch { fail(`Cannot create target file under: ${parent}. Run this script from a normal Terminal session, or allow OpenClaw filesystem write access.`); }
    return;
  }
  let nearest = parent;
  while (!fs.existsSync(nearest) && nearest !== path.dirname(nearest)) nearest = path.dirname(nearest);
  try { fs.accessSync(nearest, fs.constants.W_OK); }
  catch { fail(`Cannot create target directory under: ${nearest}. Run this script from a normal Terminal session, or allow OpenClaw filesystem write access.`); }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const backupPath = backup(file);
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, file);
  if (backupPath) console.log(`Backup: ${backupPath}`);
}

if (!apply) {
  console.log('Dry-run complete. No files were changed.');
  process.exit(0);
}

checkWritableTarget(openclawConfig);
if (codexShouldWrite) checkWritableTarget(codexAuth);
if (claudeSettingsExists) checkWritableTarget(claudeSettings);
writeJson(openclawConfig, openclaw);
if (codexShouldWrite) writeJson(codexAuth, codex);
if (claudeSettingsExists) writeJson(claudeSettings, claude);
console.log('Applied key rotation successfully.');
console.log('No full API key was printed.');
JS

require_macos_runtime() {
  if [ "$(uname -s)" != "Darwin" ]; then
    die "--ensure-runtime only supports macOS."
  fi
}

runtime_configure_power() {
  log "Configuring AC power: no system sleep, display sleep only"
  run_sudo pmset -c disablesleep 1
  run_sudo pmset -c sleep 0
  run_sudo pmset -c disksleep 0
  run_sudo pmset -c displaysleep "$DISPLAY_SLEEP_MINUTES"
  run_sudo pmset -c womp 1
  run_sudo pmset -c tcpkeepalive 1
}

runtime_configure_local_proxy_bypass() {
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

  log "Configuring local addresses to bypass system proxy"
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
      run_sudo networksetup -setproxybypassdomains "$service" $merged || log "WARN: failed to set proxy bypass for network service: $service"
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

runtime_configure_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    log "WARN: openclaw CLI not found; skipping OpenClaw gateway setup."
    return
  fi

  log "Configuring OpenClaw tool permissions for unattended local setup"
  openclaw config set tools.profile '"full"' --strict-json
  openclaw config set tools.exec.security '"full"' --strict-json
  openclaw config set agents.defaults.elevatedDefault '"full"' --strict-json
  openclaw config validate

  runtime_install_openclaw_skills

  log "Installing and starting OpenClaw gateway LaunchAgent"
  openclaw gateway install
  openclaw gateway start
}

runtime_install_openclaw_skills() {
  if [ "$OPENCLAW_SKILLS_SETUP" != "1" ]; then
    return
  fi

  local skill
  for skill in $OPENCLAW_SKILLS; do
    [ -n "$skill" ] || continue
    if runtime_openclaw_skill_installed "$skill"; then
      log "OpenClaw skill already installed: $skill"
      continue
    fi

    log "Installing OpenClaw skill globally: $skill"
    if ! openclaw skills install "$skill" --global; then
      log "WARN: failed to install OpenClaw skill: $skill"
    fi
  done
}

runtime_openclaw_skill_installed() {
  local skill="$1" installed_path info_name

  if openclaw skills info "$skill" >/dev/null 2>&1; then
    return 0
  fi

  case "$skill" in
    openclaw-token-save)
      info_name="openclaw-token-optimizer"
      ;;
    *)
      info_name=""
      ;;
  esac
  if [ -n "$info_name" ] && openclaw skills info "$info_name" >/dev/null 2>&1; then
    return 0
  fi

  installed_path="$HOME/.openclaw/skills/$skill"
  [ -d "$installed_path" ]
}

runtime_find_app() {
  local app_name="$1" path

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

runtime_configure_clash_party() {
  local app_path plist uid
  app_path="$(runtime_find_app "$CLASH_APP_NAME")"
  if [ -z "$app_path" ]; then
    log "WARN: ${CLASH_APP_NAME}.app not found; skipping Clash Party login autostart."
    log "WARN: rerun after install with CLASH_APP_NAME=\"${CLASH_APP_NAME}\" bash scripts/apply-person-key.sh <name> --apply --ensure-runtime"
    return
  fi

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  plist="$HOME/Library/LaunchAgents/${CLASH_LABEL}.plist"
  uid="$(id -u)"

  log "Writing Clash Party user LaunchAgent: $plist"
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
  launchctl bootstrap "gui/${uid}" "$plist" || log "WARN: LaunchAgent was written but not loaded immediately; it should run on next user login."
  launchctl kickstart -k "gui/${uid}/${CLASH_LABEL}" >/dev/null 2>&1 || true
}

runtime_print_status() {
  log "Runtime status"
  echo "-- pmset --"
  pmset -g custom | sed -n '/AC Power/,$p' || true
  echo
  echo "-- OpenClaw --"
  if command -v openclaw >/dev/null 2>&1; then
    openclaw gateway status || true
    runtime_print_openclaw_skills_status
    openclaw status --deep || true
  else
    echo "openclaw CLI not found"
  fi
  echo
  echo "-- LaunchAgents --"
  launchctl print "gui/$(id -u)/${CLASH_LABEL}" 2>/dev/null | sed -n '1,80p' || true
}

runtime_print_openclaw_skills_status() {
  local skill info_name
  for skill in $OPENCLAW_SKILLS; do
    [ -n "$skill" ] || continue
    if openclaw skills info "$skill"; then
      continue
    fi
    if [ "$skill" = "openclaw-token-save" ]; then
      info_name="openclaw-token-optimizer"
      openclaw skills info "$info_name" || true
    fi
  done
}

ensure_runtime() {
  if [ "$ENSURE_RUNTIME" != "1" ]; then
    return
  fi

  if [ "$APPLY" != "1" ]; then
    log "Dry-run: runtime setup would configure pmset, local proxy bypass, OpenClaw skills/gateway LaunchAgent, and Clash Party login autostart."
    return
  fi

  require_macos_runtime
  if [ "$POWER_SETUP" = "1" ]; then
    runtime_configure_power
  fi
  if [ "$LOCAL_BYPASS_SETUP" = "1" ]; then
    runtime_configure_local_proxy_bypass
  fi
  if [ "$OPENCLAW_SETUP" = "1" ]; then
    runtime_configure_openclaw
  fi
  if [ "$CLASH_SETUP" = "1" ]; then
    runtime_configure_clash_party
  fi
  runtime_print_status
  log "Runtime setup complete. After reboot, OpenClaw gateway should recover via LaunchAgent; Clash Party opens after user login."
}

ensure_runtime
