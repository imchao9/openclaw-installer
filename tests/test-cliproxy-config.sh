#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-cliproxy-config-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CLIPROXY_HOME="$WORK/.cli-proxy-api"
CLIPROXY_CONFIG="$CLIPROXY_HOME/config.yaml"
CLIPROXY_API_KEY="open-api"
DRY_RUN=0

is_dry_run() {
  [ "$DRY_RUN" = "1" ]
}

dry_log() {
  :
}

log() {
  :
}

# shellcheck source=../installer-core/lib/installer-cliproxy.sh
source "$ROOT/installer-core/lib/installer-cliproxy.sh"

mkdir -p "$CLIPROXY_HOME"
cat > "$CLIPROXY_CONFIG" <<'YAML'
host: ""
port: 8317
remote-management:
  secret-key: test-placeholder
YAML

ensure_cliproxy_auth_dir
ensure_cliproxy_loopback_host
ensure_cliproxy_api_key
ensure_cliproxy_management_api

grep -qxF 'host: "127.0.0.1"' "$CLIPROXY_CONFIG"
grep -qxF "auth-dir: \"$CLIPROXY_HOME\"" "$CLIPROXY_CONFIG"
grep -qxF '  - open-api' "$CLIPROXY_CONFIG"
grep -qxF '  secret-key: test-placeholder' "$CLIPROXY_CONFIG"
[ "$(cat "$CLIPROXY_HOME/management.key")" = "test-placeholder" ]
grep -qxF '  allow-remote: false' "$CLIPROXY_CONFIG"

before="$(shasum -a 256 "$CLIPROXY_CONFIG" | awk '{print $1}')"
ensure_cliproxy_auth_dir
ensure_cliproxy_loopback_host
ensure_cliproxy_api_key
ensure_cliproxy_management_api
after="$(shasum -a 256 "$CLIPROXY_CONFIG" | awk '{print $1}')"
[ "$before" = "$after" ] || {
  echo "FAIL: CLIProxy config normalization is not idempotent" >&2
  exit 1
}

cat > "$CLIPROXY_CONFIG" <<'YAML'
host: "127.0.0.1"
auth-dir: "/tmp/existing-auth"
api-keys:
  - existing-key
YAML
ensure_cliproxy_api_key
grep -qxF '  - existing-key' "$CLIPROXY_CONFIG"
if grep -qxF '  - open-api' "$CLIPROXY_CONFIG"; then
  echo "FAIL: existing CLIProxy API key was replaced" >&2
  exit 1
fi

HOME="$WORK/home"
export HOME
CLIPROXY_BASE_URL="http://127.0.0.1:8317/v1"
CLIPROXY_MODEL="gpt-5.5"
CLIPROXY_CODEX_PROVIDER="custom"
CLIPROXY_OPENCLAW_PROVIDER="cliproxy"
mkdir -p "$HOME/.codex" "$HOME/.openclaw"
cat > "$HOME/.codex/config.toml" <<'TOML'
model_provider = "legacy"
model = "old-model"
TOML
cat > "$HOME/.codex/auth.json" <<'JSON'
{"OPENAI_API_KEY":"stale-key"}
JSON

configure_cliproxy_agent_configs
configure_cliproxy_agent_configs

/usr/bin/python3 - "$HOME" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
auth = json.loads((home / ".codex/auth.json").read_text())
assert auth == {"OPENAI_API_KEY": "existing-key"}, auth
config = (home / ".codex/config.toml").read_text()
assert 'model_provider = "custom"' in config
assert 'base_url = "http://127.0.0.1:8317/v1"' in config
assert 'wire_api = "responses"' in config
assert 'requires_openai_auth = true' in config
backups = sorted((home / ".codex").glob("config.toml.bak.*"))
assert len(backups) == 1, backups
assert 'model_provider = "legacy"' in backups[0].read_text()
PY

echo "PASS: CLIProxy local config contract"
