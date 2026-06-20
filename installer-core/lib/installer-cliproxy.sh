write_minimal_cliproxy_config() {
  if [ -f "$CLIPROXY_CONFIG" ]; then
    return
  fi
  mkdir -p "$CLIPROXY_HOME"
  cat > "$CLIPROXY_CONFIG" <<EOF
host: "127.0.0.1"
port: 8317
auth-dir: "$CLIPROXY_HOME"
api-keys:
  - $CLIPROXY_API_KEY
debug: false
logging-to-file: true
EOF
  chmod 600 "$CLIPROXY_CONFIG"
  log "Wrote minimal CLIProxyAPI config: $CLIPROXY_CONFIG"
}

install_cliproxy_runtime() {
  if [ "${SKIP_CLIPROXY:-0}" = "1" ]; then
    log "Skipping CLIProxyAPI install (SKIP_CLIPROXY=1)"
    return
  fi

  local cliproxy_bundle_dir
  if ! cliproxy_bundle_dir="$(resolve_cliproxy_bundle_dir)"; then
    log "Skipping CLIProxyAPI install because bundled binary was not found"
    log "Checked: $CLIPROXY_BUNDLE_DIR/CLIProxyAPI"
    log "Checked: $ROOT/install-files/openclaw-team/cliproxy/CLIProxyAPI"
    log "Checked: $ROOT/../install-files/openclaw-team/cliproxy/CLIProxyAPI"
    log "Checked: $ROOT/dist/openclaw-team/cliproxy/CLIProxyAPI"
    log "Checked: $ROOT/../dist/openclaw-team/cliproxy/CLIProxyAPI"
    log "Checked: $CLIPROXY_SOURCE_DIR/bin/CLIProxyAPI"
    return
  fi

  if is_dry_run; then
    dry_log "Would install CLIProxyAPI from $cliproxy_bundle_dir -> $CLIPROXY_BINARY"
    dry_log "Would ensure CLIProxyAPI config at $CLIPROXY_CONFIG"
    return
  fi

  log "Installing CLIProxyAPI from $cliproxy_bundle_dir"
  mkdir -p "$CLIPROXY_INSTALL_DIR" "$CLIPROXY_HOME" "$HOME/Library/Logs"
  cp "$cliproxy_bundle_dir/CLIProxyAPI" "$CLIPROXY_BINARY"
  chmod 755 "$CLIPROXY_BINARY"
  if [ -d "$cliproxy_bundle_dir/static" ]; then
    rm -rf "$CLIPROXY_HOME/static"
    cp -R "$cliproxy_bundle_dir/static" "$CLIPROXY_HOME/static"
  fi
  write_minimal_cliproxy_config
}

restore_cliproxy_private_files() {
  local secrets_dir="$1"
  local cliproxy_dir="$secrets_dir/cliproxy"

  if [ ! -d "$cliproxy_dir" ]; then
    log "Skipping CLIProxyAPI private files because $cliproxy_dir was not found"
    return
  fi

  if is_dry_run; then
    dry_log "Would restore CLIProxyAPI private config/auth from $cliproxy_dir -> $CLIPROXY_HOME"
    return
  fi

  mkdir -p "$CLIPROXY_HOME"
  restore_file "$cliproxy_dir/config.yaml" "$CLIPROXY_CONFIG" 1 || log "Skipping missing CLIProxyAPI config.yaml"

  local restored=0 auth_src
  if [ -d "$cliproxy_dir/auth" ]; then
    while IFS= read -r auth_src; do
      [ -n "$auth_src" ] || continue
      restore_file "$auth_src" "$CLIPROXY_HOME/$(basename "$auth_src")" 0 || true
      restored=1
    done < <(find "$cliproxy_dir/auth" -maxdepth 1 -type f -name '*.json' -print)
  fi
  while IFS= read -r auth_src; do
    [ -n "$auth_src" ] || continue
    restore_file "$auth_src" "$CLIPROXY_HOME/$(basename "$auth_src")" 0 || true
    restored=1
  done < <(find "$cliproxy_dir" -maxdepth 1 -type f -name '*.json' -print)

  if [ "$restored" = "0" ]; then
    log "Skipping missing CLIProxyAPI auth json under $cliproxy_dir"
  fi
}

repair_clash_party_user_data_permissions() {
  local app_dir="$HOME/Library/Application Support/mihomo-party"
  local logs_dir="$app_dir/logs"
  local stamp

  [ -d "$app_dir" ] || return

  if sudo -n true >/dev/null 2>&1; then
    sudo chown -R "$(id -un):staff" "$app_dir" 2>/dev/null || true
  fi

  if [ -d "$logs_dir" ] && [ ! -w "$logs_dir" ]; then
    stamp="$(date +%Y%m%d%H%M%S)"
    mv "$logs_dir" "$app_dir/logs.not-writable.$stamp" 2>/dev/null || true
  fi

  mkdir -p "$logs_dir"
  chmod -R u+rwX "$logs_dir" 2>/dev/null || true
  rm -f "$app_dir/test/cache.db" "$app_dir/work/cache.db" 2>/dev/null || true
}

restore_clash_party_runtime_config() {
  local secrets_dir="$1"
  local src="$secrets_dir/clash-party/mihomo-party-config.tgz"
  local profiles_src="$secrets_dir/clash-party/profiles"
  local profiles_dst="$HOME/Library/Application Support/mihomo-party/profiles"

  if [ ! -f "$src" ] && [ ! -d "$profiles_src" ]; then
    log "Skipping Clash Party runtime config because neither $src nor $profiles_src was found"
    return
  fi

  if is_dry_run; then
    [ -f "$src" ] && dry_log "Would restore Clash Party runtime config from $src"
    [ -d "$profiles_src" ] && dry_log "Would copy Clash Party profiles from $profiles_src to $profiles_dst"
    return
  fi

  log "Restoring Clash Party runtime config"
  mkdir -p "$HOME/Library/Application Support/mihomo-party"
  if [ -f "$src" ]; then
    tar -xzf "$src" -C "$HOME"
  fi
  if [ -d "$profiles_src" ]; then
    mkdir -p "$profiles_dst"
    cp -R "$profiles_src/." "$profiles_dst/"
  fi
  if [ -d "$profiles_dst" ]; then
    log "Clash Party profiles restored to $profiles_dst"
    find "$profiles_dst" -maxdepth 1 -type f -name '*.yaml' -print | sed -n '1,20p'
  fi
  repair_clash_party_user_data_permissions

  if [ -d "/Applications/Clash Party.app" ]; then
    pkill -f "/Applications/Clash Party.app" >/dev/null 2>&1 || true
    pkill -f "mihomo-party/work" >/dev/null 2>&1 || true
    sleep 2
    if ! open -a "Clash Party" >/dev/null 2>&1; then
      launchctl asuser "$(id -u)" /usr/bin/open -a "Clash Party" >/dev/null 2>&1 \
        || log "Clash Party config restored, but the app could not be opened from this session"
    fi
  fi

  local wait_i
  for wait_i in 1 2 3 4; do
    if command -v curl >/dev/null 2>&1 && curl --socks5-hostname 127.0.0.1:7890 --connect-timeout 2 --max-time 4 -sSI https://chatgpt.com >/dev/null 2>&1; then
      log "Clash Party socks proxy is healthy on 127.0.0.1:7890"
      return
    fi
    sleep 1
  done

  local sidecar="/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo"
  local work_dir="$HOME/Library/Application Support/mihomo-party/work"
  if [ -x "$sidecar" ] && [ -f "$work_dir/config.yaml" ]; then
    log "Starting Clash Party mihomo sidecar fallback"
    pkill -f "mihomo-party/work" >/dev/null 2>&1 || true
    nohup "$sidecar" -d "$work_dir" >"/tmp/mihomo-party-sidecar.out.log" 2>"/tmp/mihomo-party-sidecar.err.log" </dev/null &

    local plist="$HOME/Library/LaunchAgents/local.openclaw-installer.mihomo-core.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.openclaw-installer.mihomo-core</string>
  <key>ProgramArguments</key>
  <array>
    <string>${sidecar}</string>
    <string>-d</string>
    <string>${work_dir}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/mihomo-party-sidecar.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/mihomo-party-sidecar.err.log</string>
</dict>
</plist>
EOF
    plutil -lint "$plist" >/dev/null
    launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true

    for wait_i in 1 2 3 4; do
      if command -v curl >/dev/null 2>&1 && curl --socks5-hostname 127.0.0.1:7890 --connect-timeout 2 --max-time 4 -sSI https://chatgpt.com >/dev/null 2>&1; then
        log "Clash Party mihomo sidecar fallback is healthy on 127.0.0.1:7890"
        return
      fi
      sleep 1
    done
  fi

  log "WARN: Clash Party socks proxy was not healthy on 127.0.0.1:7890"
}

sanitize_cliproxy_config() {
  if [ ! -f "$CLIPROXY_CONFIG" ]; then
    return
  fi
  if ! grep -qE 'your-api-key-[0-9]+' "$CLIPROXY_CONFIG"; then
    return
  fi
  if is_dry_run; then
    dry_log "Would remove template api-keys from $CLIPROXY_CONFIG"
    return
  fi

  log "Removing template api-keys from $CLIPROXY_CONFIG"
  cp "$CLIPROXY_CONFIG" "$CLIPROXY_CONFIG.bak.$(date +%Y%m%d_%H%M%S)"
  awk '
    /^api-keys:/ { in_keys=1; print; next }
    in_keys && /^[^[:space:]-]/ { in_keys=0 }
    in_keys && $0 ~ /your-api-key-[0-9]+/ { next }
    { print }
  ' "$CLIPROXY_CONFIG" > "$CLIPROXY_CONFIG.tmp"
  mv "$CLIPROXY_CONFIG.tmp" "$CLIPROXY_CONFIG"
  chmod 600 "$CLIPROXY_CONFIG"
}

adapt_cliproxy_proxy_url() {
  if [ ! -f "$CLIPROXY_CONFIG" ]; then
    return
  fi

  local proxy_url proxy_port
  proxy_url="$(awk -F': ' '/^[[:space:]]*proxy-url:/ { gsub(/"/, "", $2); print $2; exit }' "$CLIPROXY_CONFIG")"
  if [ -z "$proxy_url" ]; then
    return
  fi
  case "$proxy_url" in
    socks5://127.0.0.1:*|socks5h://127.0.0.1:*)
      proxy_port="${proxy_url##*:}"
      ;;
    *)
      log "Keeping CLIProxyAPI proxy-url because it is not a local socks proxy: $proxy_url"
      return
      ;;
  esac

  if nc -z 127.0.0.1 "$proxy_port" >/dev/null 2>&1; then
    if command -v curl >/dev/null 2>&1 && curl --socks5-hostname "127.0.0.1:${proxy_port}" --connect-timeout 3 --max-time 6 -sSI https://chatgpt.com >/dev/null 2>&1; then
      log "Keeping CLIProxyAPI proxy-url: $proxy_url"
      return
    fi
    log "Removing CLIProxyAPI proxy-url because local socks proxy did not pass connectivity check: $proxy_url"
  else
    log "Removing CLIProxyAPI proxy-url because local socks port is not listening: $proxy_url"
  fi

  if is_dry_run; then
    dry_log "Would remove proxy-url from $CLIPROXY_CONFIG"
    return
  fi
  cp "$CLIPROXY_CONFIG" "$CLIPROXY_CONFIG.bak.$(date +%Y%m%d_%H%M%S)"
  awk '$0 !~ /^[[:space:]]*proxy-url:/ { print }' "$CLIPROXY_CONFIG" > "$CLIPROXY_CONFIG.tmp"
  mv "$CLIPROXY_CONFIG.tmp" "$CLIPROXY_CONFIG"
  chmod 600 "$CLIPROXY_CONFIG"
}

configure_cliproxy_launchagent() {
  if [ "${SKIP_CLIPROXY:-0}" = "1" ]; then
    return
  fi
  if is_dry_run; then
    dry_log "Would write and load CLIProxyAPI LaunchAgent: $HOME/Library/LaunchAgents/${CLIPROXY_LABEL}.plist"
    return
  fi
  if [ ! -x "$CLIPROXY_BINARY" ]; then
    log "Skipping CLIProxyAPI LaunchAgent because binary is missing: $CLIPROXY_BINARY"
    return
  fi

  local plist uid
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$CLIPROXY_HOME"
  plist="$HOME/Library/LaunchAgents/${CLIPROXY_LABEL}.plist"
  uid="$(id -u)"

  log "Writing CLIProxyAPI LaunchAgent: $plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${CLIPROXY_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${CLIPROXY_BINARY}</string>
    <string>-config</string>
    <string>${CLIPROXY_CONFIG}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${CLIPROXY_HOME}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/${CLIPROXY_LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/${CLIPROXY_LABEL}.err.log</string>
</dict>
</plist>
EOF

  plutil -lint "$plist" >/dev/null
  launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/${uid}" "$plist"; then
    launchctl kickstart -k "gui/${uid}/${CLIPROXY_LABEL}" >/dev/null 2>&1 || true
  else
    log "CLIProxyAPI LaunchAgent was written but not loaded immediately; starting a session fallback now"
    pkill -f "$CLIPROXY_BINARY.*-config $CLIPROXY_CONFIG" >/dev/null 2>&1 || true
    nohup "$CLIPROXY_BINARY" -config "$CLIPROXY_CONFIG" >"${HOME}/Library/Logs/${CLIPROXY_LABEL}.fallback.out.log" 2>"${HOME}/Library/Logs/${CLIPROXY_LABEL}.fallback.err.log" </dev/null &
  fi

  local wait_i
  for wait_i in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z 127.0.0.1 8317 >/dev/null 2>&1; then
      log "CLIProxyAPI is listening on 127.0.0.1:8317"
      return
    fi
    sleep 1
  done
  log "WARN: CLIProxyAPI is not listening on 127.0.0.1:8317 yet"
}

configure_cliproxy_agent_configs() {
  if is_dry_run; then
    dry_log "Would point ~/.codex/config.toml and ~/.openclaw/openclaw.json at $CLIPROXY_BASE_URL using model $CLIPROXY_MODEL"
    dry_log "Would write ~/.codex/auth.json with OPENAI_API_KEY=$CLIPROXY_API_KEY"
    return
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to configure Codex/OpenClaw for CLIProxyAPI."
    exit 1
  fi

  log "Configuring Codex and OpenClaw to use CLIProxyAPI"
  CLIPROXY_BASE_URL="$CLIPROXY_BASE_URL" \
  CLIPROXY_API_KEY="$CLIPROXY_API_KEY" \
  CLIPROXY_MODEL="$CLIPROXY_MODEL" \
  CLIPROXY_CODEX_PROVIDER="$CLIPROXY_CODEX_PROVIDER" \
  CLIPROXY_OPENCLAW_PROVIDER="$CLIPROXY_OPENCLAW_PROVIDER" \
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const os = require('os');

const home = os.homedir();
const baseUrl = process.env.CLIPROXY_BASE_URL;
const apiKey = process.env.CLIPROXY_API_KEY;
const model = process.env.CLIPROXY_MODEL;
const codexProvider = process.env.CLIPROXY_CODEX_PROVIDER || 'custom';
const openclawProvider = process.env.CLIPROXY_OPENCLAW_PROVIDER || 'cliproxy';

function backup(file) {
  if (!fs.existsSync(file)) return;
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  fs.copyFileSync(file, `${file}.bak.${stamp}`);
}

function ensureDir(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function setTopLevelToml(src, key, value) {
  const line = `${key} = ${JSON.stringify(value)}`;
  const re = new RegExp(`^${key}\\s*=.*$`, 'm');
  if (re.test(src)) return src.replace(re, line);
  return `${line}\n${src}`;
}

function setTomlTable(src, tableName, body) {
  const tableHeader = `[${tableName}]`;
  const escaped = tableHeader.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`\\n?${escaped}\\n[\\s\\S]*?(?=\\n\\[[^\\]]+\\]\\n|$)`, 'm');
  const block = `\n${tableHeader}\n${body.trim()}\n`;
  if (re.test(src)) return src.replace(re, block);
  return `${src.replace(/\s*$/, '')}${block}`;
}

const codexDir = path.join(home, '.codex');
const codexConfig = path.join(codexDir, 'config.toml');
const codexAuth = path.join(codexDir, 'auth.json');
fs.mkdirSync(codexDir, { recursive: true });
let toml = fs.existsSync(codexConfig) ? fs.readFileSync(codexConfig, 'utf8') : '';
toml = setTopLevelToml(toml, 'model_provider', codexProvider);
toml = setTopLevelToml(toml, 'model_reasoning_effort', 'medium');
toml = setTopLevelToml(toml, 'model', model);
toml = setTomlTable(toml, `model_providers.${codexProvider}`, `
name = ${JSON.stringify(codexProvider)}
wire_api = "responses"
requires_openai_auth = true
base_url = ${JSON.stringify(baseUrl)}
`);
backup(codexConfig);
fs.writeFileSync(codexConfig, toml);
backup(codexAuth);
fs.writeFileSync(codexAuth, `${JSON.stringify({ OPENAI_API_KEY: apiKey }, null, 2)}\n`, { mode: 0o600 });
fs.chmodSync(codexAuth, 0o600);

const openclawConfig = path.join(home, '.openclaw', 'openclaw.json');
ensureDir(openclawConfig);
const openclaw = fs.existsSync(openclawConfig)
  ? JSON.parse(fs.readFileSync(openclawConfig, 'utf8'))
  : {};
openclaw.models = openclaw.models || {};
openclaw.models.providers = openclaw.models.providers || {};
openclaw.models.providers[openclawProvider] = {
  baseUrl,
  apiKey,
  api: 'openai-completions',
  models: [
    {
      id: model,
      name: 'gpt5.5',
      input: ['text'],
      contextWindow: 272000
    }
  ]
};
for (const provider of ['matrixrouter', 'anthropic']) {
  delete openclaw.models.providers[provider];
}
openclaw.agents = openclaw.agents || {};
openclaw.agents.defaults = openclaw.agents.defaults || {};
openclaw.agents.defaults.model = openclaw.agents.defaults.model || {};
openclaw.agents.defaults.model.primary = `${openclawProvider}/${model}`;
openclaw.agents.defaults.models = openclaw.agents.defaults.models || {};
openclaw.agents.defaults.models[`${openclawProvider}/${model}`] = { alias: 'gpt5.5' };
openclaw.agents.defaults.thinkingDefault = 'off';
backup(openclawConfig);
fs.writeFileSync(openclawConfig, `${JSON.stringify(openclaw, null, 2)}\n`);

console.log(`Codex provider: ${codexProvider} -> ${baseUrl} (${model})`);
console.log(`OpenClaw provider: ${openclawProvider} -> ${baseUrl} (${model})`);
NODE
}
