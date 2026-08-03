run_base_phase() {
  require_macos
  require_file "$BUNDLE_DIR"
  require_file "$SETUP_DIR"
  ensure_sudo

  if is_dry_run; then
    log "Dry run mode: no DMG mount, no PKG install, no sudo changes, no files modified"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  install_base_packages
  install_core_apps
  ensure_codex_command_available ""
  if ! command -v codex >/dev/null 2>&1 && [ "${SKIP_CODEX_CLI:-0}" != "1" ]; then
    run_optional_step "Codex CLI npm fallback" "$CODEX_CLI_STEP_TIMEOUT_SECONDS" install_codex_cli
  fi
  install_dashboard_launcher
  install_weixin_launcher
  run_optional_step "OpenClaw CLI/Gateway repair" "$OPENCLAW_FIX_STEP_TIMEOUT_SECONDS" run_openclaw_fix
  run_optional_step "OpenClaw/media setup" "$OPENCLAW_SETUP_STEP_TIMEOUT_SECONDS" run_openclaw_setup
  if [ "$INSTALL_OFFICE_SKILLS_IN_BASE" = "1" ]; then
    run_optional_step "OpenClaw Office/data skills" "$OFFICE_SKILLS_STEP_TIMEOUT_SECONDS" install_openclaw_office_skills
  else
    log "Deferring optional Office/data skills; run INSTALL_PHASE=office-skills after core validation"
  fi
  run_optional_step "CLIProxyAPI install/autostart" "$CLIPROXY_STEP_TIMEOUT_SECONDS" install_cliproxy_runtime
  configure_cliproxy_launchagent
  if [ "${SKIP_CLIPROXY:-0}" != "1" ]; then
    configure_cliproxy_agent_configs
  fi
  configure_power
  run_optional_step "OpenClaw/Clash Party reboot recovery" "$AUTOSTART_STEP_TIMEOUT_SECONDS" configure_runtime_recovery
  if [ "$INSTALL_EXTRAS_IN_BASE" = "1" ]; then
    run_optional_step "Non-core app installs" "$OPTIONAL_STEP_TIMEOUT_SECONDS" install_extra_apps
  else
    log "Skipping non-core apps in base phase; run INSTALL_PHASE=extras bash install-new-macbook.sh to install them"
  fi

  log "Base phase done"
  print_install_problem_summary
  cat <<'NEXT_STEPS'

Manual checks after the base phase:
1. Open Codex once so macOS finishes app trust prompts.
2. Open OpenClaw and confirm the app starts.
3. Run non-core app installs when the core toolchain is already usable:
   INSTALL_PHASE=extras bash install-new-macbook.sh
4. Install Doubao input method manually if the user needs it, then enable it in System Settings > Keyboard > Input Sources.
5. Open AweSun after extras and grant Screen Recording / Accessibility permissions when macOS prompts.
6. Run private config restore after private-secrets is available:
   INSTALL_PHASE=secrets bash install-new-macbook.sh
7. After Clash profile restore, recheck OpenClaw login/Gateway state.
8. Confirm or repair the default Codex/OpenClaw CLIProxyAPI routing:
   INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
9. Reboot once and confirm OpenClaw Gateway, CLIProxyAPI, and Clash Party recover after login.
NEXT_STEPS
}

run_codex_cli_phase() {
  require_macos

  if is_dry_run; then
    log "Dry run mode: no Codex CLI or shell PATH changes"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  ensure_user_shell_path
  install_codex_cli
  ensure_codex_command_available ""
  log "Codex CLI repair phase done"
}

run_secrets_phase() {
  require_macos
  require_file "$SETUP_DIR"

  if is_dry_run; then
    log "Dry run mode: no private files restored and no shell files modified"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  install_private_secrets
  log "Secrets phase done"
}

run_cliproxy_phase() {
  require_macos
  if is_dry_run; then
    log "Dry run mode: no CLIProxyAPI files or LaunchAgents modified"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  install_cliproxy_runtime
  if [ -d "$(resolve_private_secrets_dir)/cliproxy" ]; then
    restore_cliproxy_private_files "$(resolve_private_secrets_dir)"
    sanitize_cliproxy_config
    ensure_cliproxy_auth_dir
    ensure_cliproxy_loopback_host
    ensure_cliproxy_api_key
    ensure_cliproxy_management_api
    adapt_cliproxy_proxy_url
  else
    log "No private CLIProxyAPI files found; using existing or minimal config"
    sanitize_cliproxy_config
    ensure_cliproxy_auth_dir
    ensure_cliproxy_loopback_host
    ensure_cliproxy_api_key
    ensure_cliproxy_management_api
    adapt_cliproxy_proxy_url
  fi
  configure_cliproxy_launchagent
  configure_cliproxy_agent_configs
  log "CLIProxyAPI phase done"
}

run_cliproxy_config_phase() {
  require_macos
  if is_dry_run; then
    log "Dry run mode: no Codex/OpenClaw config files modified"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  configure_cliproxy_agent_configs
  log "CLIProxyAPI agent config phase done"
}

run_deepseek_phase() {
  require_macos
  if is_dry_run; then
    log "Dry run mode: no OpenClaw config files modified"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  install_deepseek_secondary_model "$(resolve_private_secrets_dir)"
  restart_openclaw_gateway_if_available
  log "DeepSeek secondary model phase done"
}

run_office_skills_phase() {
  require_macos
  if is_dry_run; then
    log "Dry run mode: no OpenClaw skills installed"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  run_optional_step "OpenClaw Office/data skills" "$OFFICE_SKILLS_STEP_TIMEOUT_SECONDS" install_openclaw_office_skills
  print_install_problem_summary
  log "Office / data-analysis skills phase done"
}

run_auth_sync_phase() {
  require_macos
  local installer="$SETUP_DIR/scripts/install-codex-auth-sync.sh"
  require_file "$installer"
  if is_dry_run; then
    log "Dry run mode: no Codex Auth Sync Agent files or registration changed"
    return
  fi

  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Writing log to $LOG_FILE"
  bash "$installer"
  log "Codex Auth Sync Agent phase done"
}

run_extras_phase() {
  require_macos
  require_file "$BUNDLE_DIR"
  ensure_sudo

  if is_dry_run; then
    log "Dry run mode: no extra app installs"
  else
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Writing log to $LOG_FILE"
  fi

  install_extra_apps
  log "Extras phase done"
}

run_validate_phase() {
  require_macos
  if is_dry_run; then
    log "Dry run mode: no Codex/OpenClaw validation commands run"
    return
  fi

  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Writing log to $LOG_FILE"
  if [ ! -x "$SETUP_DIR/scripts/validate-agent-configs.sh" ]; then
    echo "Missing validation script: $SETUP_DIR/scripts/validate-agent-configs.sh"
    exit 1
  fi
  bash "$SETUP_DIR/scripts/validate-agent-configs.sh"
  log "Codex/OpenClaw validation phase done"
}
