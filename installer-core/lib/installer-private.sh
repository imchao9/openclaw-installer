install_deepseek_secondary_model() {
  local secrets_dir="$1" key_file=""

  for candidate in \
    "${DEEPSEEK_KEY_FILE:-}" \
    "$secrets_dir/deepseek-key.csv" \
    "$secrets_dir/deepseek-key.xlsx" \
    "$ROOT/deepseek-key.csv" \
    "$ROOT/../deepseek-key.csv"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      key_file="$candidate"
      break
    fi
  done

  if [ -z "$key_file" ]; then
    log "Skipping DeepSeek secondary model because deepseek-key.csv was not found"
    return
  fi

  if is_dry_run; then
    local dry_full_model="$DEEPSEEK_MODEL"
    case "$dry_full_model" in
      */*) ;;
      *) dry_full_model="${DEEPSEEK_PROVIDER}/${DEEPSEEK_MODEL}" ;;
    esac
    dry_log "Would read DeepSeek key from $key_file and register $dry_full_model as OpenClaw secondary model"
    dry_log "Would use OpenAI BaseURL: $DEEPSEEK_BASE_URL"
    dry_log "Would record Anthropic BaseURL metadata: $DEEPSEEK_ANTHROPIC_BASE_URL"
    return
  fi

  if ! command -v node >/dev/null 2>&1; then
    log "Skipping DeepSeek secondary model because Node.js is not available"
    return
  fi

  local log_full_model="$DEEPSEEK_MODEL"
  case "$log_full_model" in
    */*) ;;
    *) log_full_model="${DEEPSEEK_PROVIDER}/${DEEPSEEK_MODEL}" ;;
  esac
  log "Configuring OpenClaw DeepSeek secondary model: $log_full_model"
  DEEPSEEK_KEY_FILE="$key_file" \
  DEEPSEEK_KEY_NAME="$DEEPSEEK_KEY_NAME" \
  DEEPSEEK_PROVIDER="$DEEPSEEK_PROVIDER" \
  DEEPSEEK_MODEL="$DEEPSEEK_MODEL" \
  DEEPSEEK_MODEL_NAME="$DEEPSEEK_MODEL_NAME" \
  DEEPSEEK_BASE_URL="$DEEPSEEK_BASE_URL" \
  DEEPSEEK_ANTHROPIC_BASE_URL="$DEEPSEEK_ANTHROPIC_BASE_URL" \
  DEEPSEEK_API="$DEEPSEEK_API" \
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');

const keyFile = process.env.DEEPSEEK_KEY_FILE;
const wantedName = (process.env.DEEPSEEK_KEY_NAME || '').trim();
const provider = process.env.DEEPSEEK_PROVIDER || 'deepseek';
const model = process.env.DEEPSEEK_MODEL || 'deepseek-v4-pro';
const modelName = process.env.DEEPSEEK_MODEL_NAME || 'DeepSeek V4 Pro';
const baseUrl = process.env.DEEPSEEK_BASE_URL || 'https://api.qnaigc.com/v1';
const anthropicBaseUrl = process.env.DEEPSEEK_ANTHROPIC_BASE_URL || 'https://anthropic.qnaigc.com';
const api = process.env.DEEPSEEK_API || 'openai-completions';
const openclawConfig = path.join(os.homedir(), '.openclaw', 'openclaw.json');

function fail(message) {
  console.error('ERROR: ' + message);
  process.exit(1);
}

function mask(value) {
  value = value || '';
  if (!value) return '<empty>';
  return `len=${value.length}, prefix=${value.slice(0, 6)}, suffix=${value.slice(-4)}`;
}

function decodeXml(value) {
  return String(value || '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

function colToIndex(ref) {
  const letters = String(ref || '').replace(/[0-9]/g, '').toUpperCase();
  let index = 0;
  for (const ch of letters) index = index * 26 + ch.charCodeAt(0) - 64;
  return index - 1;
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

function unzipText(file, member) {
  const result = cp.spawnSync('/usr/bin/unzip', ['-p', file, member], { encoding: 'utf8' });
  if (result.status !== 0) return '';
  return result.stdout || '';
}

function parseXlsx(file) {
  const sharedXml = unzipText(file, 'xl/sharedStrings.xml');
  const shared = [];
  for (const match of sharedXml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
    const parts = [];
    for (const textMatch of match[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) {
      parts.push(decodeXml(textMatch[1]));
    }
    shared.push(parts.join(''));
  }

  const sheetXml = unzipText(file, 'xl/worksheets/sheet1.xml');
  if (!sheetXml) fail(`Cannot read first worksheet from ${file}`);
  const rows = [];
  for (const rowMatch of sheetXml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = [];
    for (const cellMatch of rowMatch[1].matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = cellMatch[1];
      const body = cellMatch[2];
      const ref = ((attrs.match(/\br="([^"]+)"/) || [])[1]) || '';
      const type = ((attrs.match(/\bt="([^"]+)"/) || [])[1]) || '';
      const v = ((body.match(/<v>([\s\S]*?)<\/v>/) || [])[1]) || '';
      const inline = ((body.match(/<t\b[^>]*>([\s\S]*?)<\/t>/) || [])[1]) || '';
      const col = colToIndex(ref);
      let value = '';
      if (type === 's') value = shared[Number(v)] || '';
      else if (inline) value = decodeXml(inline);
      else value = decodeXml(v);
      if (col >= 0) row[col] = value;
      else row.push(value);
    }
    rows.push(row.map((value) => value || ''));
  }
  return rows;
}

function readRows(file) {
  const first = fs.readFileSync(file).subarray(0, 4).toString('binary');
  if (first === 'PK\u0003\u0004') return parseXlsx(file);
  return parseCsv(fs.readFileSync(file, 'utf8'));
}

function pickKey(file) {
  const rows = readRows(file).filter((row) => row.some((cell) => String(cell || '').trim()));
  if (!rows.length) fail(`DeepSeek key sheet is empty: ${file}`);
  const headers = rows.shift().map((value) => String(value || '').trim().toLowerCase());
  const nameIndex = headers.indexOf('name') >= 0 ? headers.indexOf('name') : 0;
  const keyIndex = headers.indexOf('key') >= 0 ? headers.indexOf('key') : 1;
  if (keyIndex < 0) fail(`DeepSeek key sheet must have a key column: ${file}`);

  let selected = null;
  for (const row of rows) {
    const name = String(row[nameIndex] || '').trim();
    const key = String(row[keyIndex] || '').trim();
    if (!key) continue;
    if (wantedName) {
      if (name === wantedName) {
        selected = { name, key };
        break;
      }
    } else {
      selected = { name: name || '<first>', key };
      break;
    }
  }
  if (!selected) {
    if (wantedName) fail(`Cannot find DeepSeek key name "${wantedName}" in ${file}`);
    fail(`Cannot find a non-empty DeepSeek key in ${file}`);
  }
  return selected;
}

function backup(file) {
  if (!fs.existsSync(file)) return null;
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const dst = `${file}.bak.${stamp}`;
  fs.copyFileSync(file, dst);
  return dst;
}

const selected = pickKey(keyFile);
const openclaw = fs.existsSync(openclawConfig)
  ? JSON.parse(fs.readFileSync(openclawConfig, 'utf8'))
  : {};
openclaw.models = openclaw.models || {};
openclaw.models.mode = openclaw.models.mode || 'merge';
openclaw.models.providers = openclaw.models.providers || {};
const previousProviderConfig = openclaw.models.providers[provider] || {};
const providerConfig = {
  baseUrl,
  apiKey: selected.key,
  api
};
const modelEntry = {
  id: model,
  name: modelName,
  contextWindow: 1000000
};
const existingModels = Array.isArray(previousProviderConfig.models) ? previousProviderConfig.models : [];
providerConfig.models = [
  ...existingModels.filter((entry) => entry && entry.id !== model),
  modelEntry
];
openclaw.models.providers[provider] = providerConfig;

openclaw.agents = openclaw.agents || {};
openclaw.agents.defaults = openclaw.agents.defaults || {};
openclaw.agents.defaults.model = openclaw.agents.defaults.model || {};
openclaw.agents.defaults.models = openclaw.agents.defaults.models || {};
const fullModel = model.includes('/') ? model : `${provider}/${model}`;
openclaw.agents.defaults.models[fullModel] = { alias: 'DeepSeek Pro' };
const fallbacks = Array.isArray(openclaw.agents.defaults.model.fallbacks)
  ? openclaw.agents.defaults.model.fallbacks
  : [];
openclaw.agents.defaults.model.fallbacks = [fullModel, ...fallbacks.filter((item) => item !== fullModel)];

fs.mkdirSync(path.dirname(openclawConfig), { recursive: true });
const backupPath = backup(openclawConfig);
fs.writeFileSync(openclawConfig, `${JSON.stringify(openclaw, null, 2)}\n`, { mode: 0o600 });
fs.chmodSync(openclawConfig, 0o600);
if (backupPath) console.log(`Backup: ${backupPath}`);
console.log(`DeepSeek key: ${selected.name} (${mask(selected.key)})`);
console.log(`OpenClaw secondary model: ${fullModel}`);
console.log(`OpenAI BaseURL: ${baseUrl}`);
console.log(`Anthropic BaseURL reference: ${anthropicBaseUrl}`);
NODE
}

restart_openclaw_gateway_if_available() {
  if is_dry_run; then
    dry_log "Would restart OpenClaw Gateway if openclaw CLI is available"
    return
  fi
  if command -v openclaw >/dev/null 2>&1; then
    log "Restarting OpenClaw Gateway to load model config"
    openclaw gateway restart || log "OpenClaw Gateway restart failed; rerun manually: openclaw gateway restart"
  else
    log "Skipping OpenClaw Gateway restart because openclaw CLI is not available"
  fi
}

install_private_secrets() {
  local secrets_dir private_team_dir legacy_private_team_dir
  secrets_dir="$(resolve_private_secrets_dir)"
  require_file "$secrets_dir"
  private_team_dir="$secrets_dir/openclaw-team"
  legacy_private_team_dir="$secrets_dir/openclaw team"

  log "Installing private files from $secrets_dir"

  restore_first_available "$HOME/.codex/auth.json" 0 \
    "$secrets_dir/setup/dotfiles/.codex/auth.json" \
    "$private_team_dir/auth.json" \
    "$legacy_private_team_dir/auth.json"
  restore_first_available "$HOME/.codex/config.toml" 1 \
    "$secrets_dir/setup/dotfiles/.codex/config.toml" \
    "$private_team_dir/config.toml" \
    "$legacy_private_team_dir/config.toml"
  restore_first_available "$HOME/.openclaw/openclaw.json" 1 \
    "$secrets_dir/setup/dotfiles/.openclaw/openclaw.json" \
    "$private_team_dir/openclaw.json" \
    "$legacy_private_team_dir/openclaw.json"

  install_deepseek_secondary_model "$secrets_dir"
  restart_openclaw_gateway_if_available

  local media_src="$secrets_dir/setup/secrets.env"
  local media_dst="$HOME/.config/openclaw-media/secrets.env"
  if restore_file "$media_src" "$media_dst"; then
    if is_dry_run; then
      dry_log "Would add $media_dst source line to ~/.zshrc"
    else
      local line="[ -f \"$media_dst\" ] && source \"$media_dst\"  # media-gen keys"
      if ! grep -qF "$media_dst" "$HOME/.zshrc" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$HOME/.zshrc"
        log "Added media key source line to $HOME/.zshrc"
      else
        log "$HOME/.zshrc already contains media key source line"
      fi
    fi
  else
    log "Skipping missing media secrets: $media_src"
  fi

  local notes_dir="$HOME/.config/openclaw-installer/private-notes"
  restore_first_available "$notes_dir/key.txt" 0 \
    "$private_team_dir/key.txt" \
    "$legacy_private_team_dir/key.txt" || log "Skipping missing private note: key.txt"
  restore_first_available "$notes_dir/安装.txt" 0 \
    "$private_team_dir/安装.txt" \
    "$legacy_private_team_dir/安装.txt" || log "Skipping missing private note: 安装.txt"

  restore_cliproxy_private_files "$secrets_dir"
  sanitize_cliproxy_config
  ensure_cliproxy_auth_dir
  ensure_cliproxy_loopback_host
  ensure_cliproxy_api_key
  restore_clash_party_runtime_config "$secrets_dir"
  adapt_cliproxy_proxy_url
  configure_cliproxy_launchagent

  if is_dry_run; then
    dry_log "Would install private config helpers, including Clash Party subscription helper"
  elif [ -x "$SETUP_DIR/scripts/install-private-configs.sh" ]; then
    run_optional_step \
      "private config helper setup" \
      "$PRIVATE_HELPER_STEP_TIMEOUT_SECONDS" \
      env PRIVATE_SECRETS_DIR="$secrets_dir" bash "$SETUP_DIR/scripts/install-private-configs.sh"
  fi

  if is_dry_run; then
    dry_log "Would rerun setup-seedream.sh after media secrets are installed"
  elif [ -f "$media_dst" ]; then
    # shellcheck disable=SC1090
    source "$media_dst"
    run_optional_step \
      "Seedream key injection" \
      "$SEEDREAM_STEP_TIMEOUT_SECONDS" \
      bash "$SETUP_DIR/scripts/setup-seedream.sh"
  fi

  # Private restore may overwrite Codex/OpenClaw routing. Re-apply the local
  # CLIProxy contract every time so config.toml and auth.json stay paired with
  # the API key actually accepted by CLIProxyAPI.
  configure_cliproxy_agent_configs
  restart_openclaw_gateway_if_available
}

configure_power() {
  if [ "${SKIP_POWER:-0}" = "1" ]; then
    log "Skipping power settings (SKIP_POWER=1)"
    return
  fi

  if is_dry_run; then
    dry_log "Would run: sudo pmset -c sleep 0"
    dry_log "Would run: sudo pmset -c disksleep 0"
    dry_log "Would run: sudo pmset -c displaysleep ${DISPLAY_SLEEP_MINUTES:-10}"
    dry_log "Would run: sudo pmset -c womp 1"
    dry_log "Would run: sudo pmset -c tcpkeepalive 1"
    return
  fi

  log "Configuring AC power: no system sleep, display sleep only"
  sudo pmset -c sleep 0
  sudo pmset -c disksleep 0
  sudo pmset -c displaysleep "${DISPLAY_SLEEP_MINUTES:-10}"
  sudo pmset -c womp 1
  sudo pmset -c tcpkeepalive 1
}

configure_runtime_recovery() {
  if [ "${SKIP_AUTOSTART:-0}" = "1" ]; then
    log "Skipping OpenClaw/Clash Party reboot recovery setup (SKIP_AUTOSTART=1)"
    return
  fi

  local autostart_script="$ROOT/setup-mac-autostart.sh"
  if [ ! -f "$autostart_script" ] && [ -f "$ROOT/scripts/setup-mac-autostart.sh" ]; then
    autostart_script="$ROOT/scripts/setup-mac-autostart.sh"
  fi
  if [ ! -f "$autostart_script" ] && [ -f "$ROOT/../scripts/setup-mac-autostart.sh" ]; then
    autostart_script="$ROOT/../scripts/setup-mac-autostart.sh"
  fi
  require_file "$autostart_script"
  if is_dry_run; then
    dry_log "Would configure OpenClaw gateway and Clash Party login autostart: $autostart_script"
    return
  fi

  log "Configuring OpenClaw/Clash Party reboot recovery"
  DISPLAY_SLEEP_MINUTES="${DISPLAY_SLEEP_MINUTES:-10}" POWER_SETUP=0 bash "$autostart_script"
}
