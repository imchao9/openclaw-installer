#!/usr/bin/env bash
# New MacBook one-shot installer for the local OpenClaw team bundle.
#
# Run from this folder:
#   bash install-new-macbook.sh
#
# Useful rerun switches:
#   SKIP_BASE_PKGS=1        skip Node.js
#   SKIP_APPS=1             skip core app installs
#   SKIP_CLASH=1            skip Clash Verge and Clash Party
#   SKIP_EXTRAS=1           skip non-core apps in INSTALL_PHASE=extras
#   SKIP_AWESUN=1           skip AweSun remote-control app
#   SKIP_DINGTALK=1         skip DingTalk
#   SKIP_WEIXIN_LAUNCHER=1  skip installing OpenClaw Weixin launcher to /Applications
#   SKIP_CODEX_CLI=1        skip npm install -g @openai/codex
#   SKIP_OPENCLAW_FIX=1     skip OpenClaw CLI/Gateway repair
#   SKIP_OPENCLAW_SETUP=1   skip installer-core/install.sh
#   SKIP_OFFICE_SKILLS=1    skip data-analysis / Office skills
#   INSTALL_OFFICE_SKILLS_IN_BASE=1
#                           include optional Office skills in base (default: defer)
#   SKIP_CLIPROXY=1         skip CLIProxyAPI install/autostart
#   SKIP_POWER=1            skip pmset sleep setting
#   SKIP_AUTOSTART=1        skip OpenClaw/Clash Party reboot recovery setup
#   INSTALL_EXTRAS_IN_BASE=1
#                           also install non-core apps during base
#   DRY_RUN=1               print the install plan without changing the system
#   INSTALL_PHASE=base      install non-secret software/config only (default)
#   INSTALL_PHASE=extras    install non-core apps: Chrome, Obsidian, CC-Switch, AweSun, DingTalk
#   INSTALL_PHASE=secrets   restore private-secrets only
#   INSTALL_PHASE=cliproxy  install CLIProxyAPI, restore its private files when present, and start LaunchAgent
#   INSTALL_PHASE=cliproxy-config
#                           point ~/.codex and ~/.openclaw at CLIProxyAPI
#   INSTALL_PHASE=deepseek  register DeepSeek as OpenClaw secondary/fallback model
#   INSTALL_PHASE=codex-cli
#                           install/repair Codex CLI and zsh PATH only
#   INSTALL_PHASE=office-skills
#                           install data-analysis / Office skills only
#   INSTALL_PHASE=auth-sync install/refresh Codex Auth Sync Agent
#   INSTALL_PHASE=validate  send hello through OpenClaw and Codex as an acceptance check
#   INSTALL_PHASE=all       run base, then secrets when private-secrets exists
#   PRIVATE_SECRETS_DIR=... path to private-secrets for INSTALL_PHASE=secrets
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT/openclaw-team}"
if [ ! -d "$BUNDLE_DIR" ] && [ -d "$ROOT/openclaw team" ]; then
  BUNDLE_DIR="$ROOT/openclaw team"
fi
SETUP_DIR="$ROOT/installer-core"
if [ ! -d "$SETUP_DIR" ] && [ -d "$ROOT/setup" ]; then
  SETUP_DIR="$ROOT/setup"
fi
CLIPROXY_BUNDLE_DIR="${CLIPROXY_BUNDLE_DIR:-$BUNDLE_DIR/cliproxy}"
CLIPROXY_SOURCE_DIR="${CLIPROXY_SOURCE_DIR:-/Users/cm/Documents/Me/Tool/cliproxy/CLIProxyAPI}"
CLIPROXY_INSTALL_DIR="${CLIPROXY_INSTALL_DIR:-$HOME/.local/bin}"
CLIPROXY_BINARY="$CLIPROXY_INSTALL_DIR/CLIProxyAPI"
CLIPROXY_HOME="${CLIPROXY_HOME:-$HOME/.cli-proxy-api}"
CLIPROXY_CONFIG="$CLIPROXY_HOME/config.yaml"
CLIPROXY_LABEL="${CLIPROXY_LABEL:-local.openclaw-installer.cliproxy}"
CLIPROXY_BASE_URL="${CLIPROXY_BASE_URL:-http://127.0.0.1:8317/v1}"
CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-open-api}"
CLIPROXY_MODEL="${CLIPROXY_MODEL:-gpt-5.5}"
CLIPROXY_CODEX_PROVIDER="${CLIPROXY_CODEX_PROVIDER:-custom}"
CLIPROXY_OPENCLAW_PROVIDER="${CLIPROXY_OPENCLAW_PROVIDER:-cliproxy}"
DEEPSEEK_PROVIDER="${DEEPSEEK_PROVIDER:-deepseek}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-v4-pro}"
DEEPSEEK_MODEL_NAME="${DEEPSEEK_MODEL_NAME:-DeepSeek V4 Pro}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.qnaigc.com/v1}"
DEEPSEEK_ANTHROPIC_BASE_URL="${DEEPSEEK_ANTHROPIC_BASE_URL:-https://anthropic.qnaigc.com}"
DEEPSEEK_API="${DEEPSEEK_API:-openai-completions}"
DEEPSEEK_KEY_NAME="${DEEPSEEK_KEY_NAME:-}"
OFFICE_SKILLS="${OFFICE_SKILLS:-data-analysis-skill data-analysis xlsx-cn excel-xlsx pptx markdown-converter minimax-excel-sheet tencent-docs}"
LOG_FILE="$ROOT/install-new-macbook.log"
INSTALL_PHASE="${INSTALL_PHASE:-base}"
INSTALL_PROBLEMS_FILE="${INSTALL_PROBLEMS_FILE:-$ROOT/install-problems.log}"
OPTIONAL_STEP_TIMEOUT_SECONDS="${OPTIONAL_STEP_TIMEOUT_SECONDS:-600}"
CODEX_CLI_STEP_TIMEOUT_SECONDS="${CODEX_CLI_STEP_TIMEOUT_SECONDS:-180}"
OPENCLAW_FIX_STEP_TIMEOUT_SECONDS="${OPENCLAW_FIX_STEP_TIMEOUT_SECONDS:-30}"
OPENCLAW_SETUP_STEP_TIMEOUT_SECONDS="${OPENCLAW_SETUP_STEP_TIMEOUT_SECONDS:-300}"
OFFICE_SKILLS_STEP_TIMEOUT_SECONDS="${OFFICE_SKILLS_STEP_TIMEOUT_SECONDS:-30}"
CLIPROXY_STEP_TIMEOUT_SECONDS="${CLIPROXY_STEP_TIMEOUT_SECONDS:-90}"
AUTOSTART_STEP_TIMEOUT_SECONDS="${AUTOSTART_STEP_TIMEOUT_SECONDS:-30}"
PRIVATE_HELPER_STEP_TIMEOUT_SECONDS="${PRIVATE_HELPER_STEP_TIMEOUT_SECONDS:-90}"
SEEDREAM_STEP_TIMEOUT_SECONDS="${SEEDREAM_STEP_TIMEOUT_SECONDS:-90}"
INSTALL_EXTRAS_IN_BASE="${INSTALL_EXTRAS_IN_BASE:-0}"
INSTALL_OFFICE_SKILLS_IN_BASE="${INSTALL_OFFICE_SKILLS_IN_BASE:-0}"
INSTALL_PHASE_TIMING_FILE="${INSTALL_PHASE_TIMING_FILE:-$ROOT/reports/install-phase-timing.jsonl}"
INSTALL_PROBLEMS=()

INSTALLER_LIB_DIR="$SETUP_DIR/lib"
for lib in installer-common.sh installer-apps.sh installer-cliproxy.sh installer-private.sh installer-phases.sh; do
  # shellcheck source=/dev/null
  . "$INSTALLER_LIB_DIR/$lib"
done

run_timed_phase() {
  local phase="$1" started finished status
  shift
  started="$(date '+%s')"
  set +e
  "$@"
  status="$?"
  set -e
  finished="$(date '+%s')"
  record_phase_timing "$phase" "$started" "$finished" "$status"
  return "$status"
}

main() {
  case "$INSTALL_PHASE" in
    base)
      run_timed_phase base run_base_phase
      ;;
    extras|extra-apps|extra_apps)
      run_timed_phase extras run_extras_phase
      ;;
    secrets|key|keys)
      run_timed_phase secrets run_secrets_phase
      ;;
    cliproxy)
      run_timed_phase cliproxy run_cliproxy_phase
      ;;
    cliproxy-config|cliproxy_config)
      run_timed_phase cliproxy-config run_cliproxy_config_phase
      ;;
    deepseek|deepseek-model|secondary-model)
      run_timed_phase deepseek run_deepseek_phase
      ;;
    codex-cli|codex_cli|codex)
      run_timed_phase codex-cli run_codex_cli_phase
      ;;
    office-skills|office_skills|skills)
      run_timed_phase office-skills run_office_skills_phase
      ;;
    auth-sync|auth_sync|codex-auth-sync)
      run_timed_phase auth-sync run_auth_sync_phase
      ;;
    validate|validation|check)
      run_timed_phase validate run_validate_phase
      ;;
    all)
      run_timed_phase base run_base_phase
      if [ -d "$(resolve_private_secrets_dir)" ]; then
        run_timed_phase secrets run_secrets_phase
      else
        log "Skipping secrets phase because private-secrets was not found"
      fi
      run_timed_phase cliproxy run_cliproxy_phase
      run_timed_phase cliproxy-config run_cliproxy_config_phase
      run_timed_phase extras run_extras_phase
      run_timed_phase validate run_validate_phase
      ;;
    *)
      echo "Unknown INSTALL_PHASE: $INSTALL_PHASE"
      echo "Use INSTALL_PHASE=base, INSTALL_PHASE=extras, INSTALL_PHASE=secrets, INSTALL_PHASE=cliproxy, INSTALL_PHASE=cliproxy-config, INSTALL_PHASE=deepseek, INSTALL_PHASE=codex-cli, INSTALL_PHASE=office-skills, INSTALL_PHASE=auth-sync, INSTALL_PHASE=validate, or INSTALL_PHASE=all."
      exit 1
      ;;
  esac
}

main "$@"
