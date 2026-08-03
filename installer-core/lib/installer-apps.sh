install_app_from_dmg() {
  local label="$1" dmg="$2" expected="${3:-}"
  require_file "$dmg"
  if is_dry_run; then
    local target_name="${expected:-first *.app found in DMG}"
    dry_log "Would mount $dmg and copy $target_name to /Applications"
    return
  fi

  local mount
  mount="$(mktemp -d "/tmp/${label// /_}.XXXXXX")"
  log "Installing $label from DMG"
  mount_dmg "$dmg" "$mount"

  local app=""
  if [ -n "$expected" ] && [ -d "$mount/$expected" ]; then
    app="$mount/$expected"
  else
    app="$(find "$mount" -maxdepth 4 -type d -name '*.app' -print -quit)"
  fi

  if [ -z "$app" ]; then
    unmount_dmg "$mount"
    echo "No .app found in $dmg"
    exit 1
  fi

  # Newer Codex DMGs are still distributed as Codex.dmg but contain
  # ChatGPT.app. Preserve the bundle's real name when the expected legacy
  # name is not present instead of creating a misleading Codex.app directory.
  local target_name
  if [ -n "$expected" ] && [ -d "$mount/$expected" ]; then
    target_name="$expected"
  else
    target_name="$(basename "$app")"
  fi
  local target="/Applications/$target_name"
  if [ -d "$target" ]; then
    log "Replacing existing $(basename "$target")"
    sudo rm -rf "$target"
  fi
  set +e
  sudo ditto "$app" "$target"
  local status="$?"
  set -e
  if [ "$status" -eq 0 ]; then
    sudo xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
  fi
  unmount_dmg "$mount"
  if [ "$status" -ne 0 ]; then
    exit "$status"
  fi
}

installed_app_ready() {
  local name app executable machine_arch archs
  machine_arch="$(uname -m)"
  for name in "$@"; do
    app="/Applications/$name.app"
    [ -d "$app" ] || continue
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ -n "$executable" ] && [ -x "$app/Contents/MacOS/$executable" ] || continue
    archs="$(lipo -archs "$app/Contents/MacOS/$executable" 2>/dev/null || true)"
    if [ -n "$archs" ] && printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx "$machine_arch"; then
      return 0
    fi
  done
  return 1
}

install_app_dmgs_parallel() {
  local status_dir pids="" jobs_file failure=0 idx=0
  status_dir="$(mktemp -d "/tmp/openclaw-app-installs.XXXXXX")"
  jobs_file="$status_dir/jobs.tsv"
  : > "$jobs_file"

  while [ "$#" -gt 0 ]; do
    local label="$1" dmg="$2" expected="${3:-}" log_file
    shift 3
    idx=$((idx + 1))
    log_file="$status_dir/$idx.log"
    log "Starting parallel app install: $label"
    (
      install_app_from_dmg "$label" "$dmg" "$expected"
    ) >"$log_file" 2>&1 &
    local pid="$!"
    pids="$pids $pid"
    printf '%s\t%s\t%s\t%s\n' "$pid" "$idx" "$label" "$log_file" >> "$jobs_file"
  done

  local pid job_idx label log_file
  while IFS="$(printf '\t')" read -r pid job_idx label log_file; do
    [ -n "$pid" ] || continue
    if wait "$pid"; then
      log "Parallel app install completed: $label"
    else
      failure=1
      log "Parallel app install failed: $label"
      cat "$log_file" >&2
    fi
  done < "$jobs_file"

  rm -rf "$status_dir"
  return "$failure"
}

install_base_packages() {
  if [ "${SKIP_BASE_PKGS:-0}" = "1" ]; then
    log "Skipping base packages (SKIP_BASE_PKGS=1)"
    return
  fi

  install_command_line_tools

  log "Skipping Homebrew install in this no-Homebrew package"

  if is_dry_run; then
    dry_log "Would check current Node.js version"
  elif command -v node >/dev/null 2>&1; then
    log "Node.js currently available: $(node --version)"
  fi
  install_pkg_file "Node.js v24.16.0" "$BUNDLE_DIR/node-v24.16.0.pkg"
  ensure_user_shell_path
}

install_core_apps() {
  if [ "${SKIP_APPS:-0}" = "1" ]; then
    log "Skipping core app installs (SKIP_APPS=1)"
    return
  fi

  local clash_party_pkg=""

  install_app_dmgs_parallel \
    "Codex" "$BUNDLE_DIR/Codex.dmg" "Codex.app" \
    "OpenClaw" "$BUNDLE_DIR/OpenClaw-2026.5.26.dmg" "OpenClaw.app"

  if [ "${SKIP_CLASH:-0}" = "1" ]; then
    log "Skipping Clash installs (SKIP_CLASH=1)"
  elif clash_party_pkg="$(find "$BUNDLE_DIR" -maxdepth 1 -type f -name 'clash-party-macos-*.pkg' -print | sort | tail -n 1)" && [ -n "$clash_party_pkg" ]; then
    install_pkg_file "Clash Party" "$clash_party_pkg"
  else
    log "Skipping Clash Party because Clash Party pkg is not in this bundle"
    log "Install them separately from 05-Clash单独安装/"
  fi
}

install_extra_apps() {
  if [ "${SKIP_EXTRAS:-0}" = "1" ]; then
    log "Skipping non-core app installs (SKIP_EXTRAS=1)"
    return
  fi

  local app_jobs=()
  local dingtalk_dmg=""
  if installed_app_ready "Google Chrome"; then
    log "Already installed and compatible: Google Chrome"
  elif [ -f "$BUNDLE_DIR/googlechrome.dmg" ]; then
    app_jobs+=("Google Chrome" "$BUNDLE_DIR/googlechrome.dmg" "Google Chrome.app")
  else
    log "Skipping Google Chrome because googlechrome.dmg is not in this bundle"
  fi
  if installed_app_ready "Obsidian"; then
    log "Already installed and compatible: Obsidian"
  elif [ -f "$BUNDLE_DIR/Obsidian-1.12.7.dmg" ]; then
    app_jobs+=("Obsidian" "$BUNDLE_DIR/Obsidian-1.12.7.dmg" "Obsidian.app")
  else
    log "Skipping Obsidian because Obsidian-1.12.7.dmg is not in this bundle"
  fi
  if installed_app_ready "CC-Switch" "CC Switch"; then
    log "Already installed and compatible: CC-Switch"
  elif [ -f "$BUNDLE_DIR/CC-Switch-v3.15.0-macOS.dmg" ]; then
    app_jobs+=("CC-Switch" "$BUNDLE_DIR/CC-Switch-v3.15.0-macOS.dmg" "")
  else
    log "Skipping CC-Switch because CC-Switch-v3.15.0-macOS.dmg is not in this bundle"
  fi
  if [ "${SKIP_CLASH:-0}" != "1" ] && [ -f "$BUNDLE_DIR/Clash Verge 2.5.1.dmg" ]; then
    app_jobs+=("Clash Verge" "$BUNDLE_DIR/Clash Verge 2.5.1.dmg" "")
  fi

  if [ "${#app_jobs[@]}" -gt 0 ]; then
    install_app_dmgs_parallel "${app_jobs[@]}"
  fi

  local awesun_dmg="" machine_arch
  machine_arch="$(uname -m)"
  if [ "$machine_arch" = "x86_64" ]; then
    awesun_dmg="$(find "$BUNDLE_DIR" -maxdepth 1 -type f \( -iname 'AweSun*x86_64*.dmg' -o -iname 'AweSun*x64*.dmg' \) -print | sort | tail -n 1)"
  else
    awesun_dmg="$(find "$BUNDLE_DIR" -maxdepth 1 -type f -iname 'AweSun*arm64*.dmg' -print | sort | tail -n 1)"
  fi
  if [ "${SKIP_AWESUN:-0}" = "1" ]; then
    log "Skipping AweSun (SKIP_AWESUN=1)"
  elif installed_app_ready "AweSun" "SunloginClient" "向日葵远程控制"; then
    log "Already installed and compatible: AweSun"
  elif [ -n "$awesun_dmg" ]; then
    install_pkg_from_dmg "AweSun" "$awesun_dmg"
  else
    log "Skipping AweSun because no $machine_arch-compatible AweSun DMG is in this bundle"
  fi

  if [ "${SKIP_DINGTALK:-0}" = "1" ]; then
    log "Skipping DingTalk (SKIP_DINGTALK=1)"
  elif installed_app_ready "DingTalk" "钉钉"; then
    log "Already installed and compatible: DingTalk"
  elif dingtalk_dmg="$(find "$BUNDLE_DIR" -maxdepth 1 -type f -iname 'DingTalk*.dmg' -print | sort | tail -n 1)" && [ -n "$dingtalk_dmg" ]; then
    install_pkg_from_dmg "DingTalk" "$dingtalk_dmg"
  else
    log "Skipping DingTalk because no DingTalk DMG is in this bundle"
  fi

  log "Skipping Doubao input method; install it manually if needed"
}

run_openclaw_fix() {
  if [ "${SKIP_OPENCLAW_FIX:-0}" = "1" ]; then
    log "Skipping OpenClaw CLI/Gateway repair (SKIP_OPENCLAW_FIX=1)"
    return
  fi

  require_file "$BUNDLE_DIR/fix-openclaw-install.sh"
  if is_dry_run; then
    dry_log "Would run OpenClaw CLI/Gateway repair: $BUNDLE_DIR/fix-openclaw-install.sh"
    return
  fi

  log "Installing OpenClaw CLI and Gateway"
  bash "$BUNDLE_DIR/fix-openclaw-install.sh"
}

install_weixin_launcher() {
  if [ "${SKIP_WEIXIN_LAUNCHER:-0}" = "1" ]; then
    log "Skipping OpenClaw Weixin launcher install (SKIP_WEIXIN_LAUNCHER=1)"
    return
  fi

  local runner="$BUNDLE_DIR/OpenClaw Weixin Connect.app/Contents/Resources/connect-openclaw-weixin.command"
  local app="/Applications/OpenClaw Weixin Connect.app"
  local command="/Applications/OpenClaw Weixin Connect.command"
  if [ ! -f "$runner" ]; then
    log "Skipping OpenClaw Weixin launcher because source is missing: $runner"
    return
  fi

  if is_dry_run; then
    dry_log "Would install OpenClaw Weixin launcher to $app and $command"
    return
  fi

  log "Installing OpenClaw Weixin launcher to /Applications"
  local tmp_dir tmp_app
  tmp_dir="$(mktemp -d)"
  tmp_app="$tmp_dir/OpenClaw Weixin Connect.app"
  osacompile -o "$tmp_app" \
    -e 'set runner to POSIX path of (path to resource "connect-openclaw-weixin.command")' \
    -e 'tell application "Terminal"' \
    -e 'activate' \
    -e 'do script quoted form of runner' \
    -e 'end tell'
  cp "$runner" "$tmp_app/Contents/Resources/connect-openclaw-weixin.command"
  chmod +x "$tmp_app/Contents/Resources/connect-openclaw-weixin.command"

  sudo rm -rf "$app" "$command"
  sudo ditto "$tmp_app" "$app"
  sudo cp "$runner" "$command"
  sudo chmod -R a+rX "$app"
  sudo chmod +x "$app/Contents/MacOS/applet"
  sudo chmod a+rx "$command"
  sudo xattr -dr com.apple.quarantine "$app" "$command" 2>/dev/null || true
  rm -rf "$tmp_dir"
  log "Installed $app"
  log "Installed $command"
}

install_dashboard_launcher() {
  if [ "${SKIP_DASHBOARD_LAUNCHER:-0}" = "1" ]; then
    log "Skipping OpenClaw Dashboard launcher install (SKIP_DASHBOARD_LAUNCHER=1)"
    return
  fi

  local source_app="$BUNDLE_DIR/OpenClaw Dashboard.app"
  local runner="$source_app/Contents/Resources/openclaw-dashboard.command"
  local app="/Applications/OpenClaw Dashboard.app"
  local command="/Applications/OpenClaw Dashboard.command"
  if [ ! -d "$source_app" ] || [ ! -f "$runner" ]; then
    log "Skipping OpenClaw Dashboard launcher because source is missing: $source_app"
    return
  fi

  if is_dry_run; then
    dry_log "Would install OpenClaw Dashboard launcher to $app and $command"
    return
  fi

  log "Installing OpenClaw Dashboard launcher to /Applications"
  sudo rm -rf "$app" "$command"
  sudo ditto "$source_app" "$app"
  sudo cp "$runner" "$command"
  sudo chmod -R a+rX "$app"
  sudo chmod +x "$app/Contents/MacOS/OpenClaw Dashboard" "$app/Contents/Resources/openclaw-dashboard.command"
  sudo chmod a+rx "$command"
  sudo xattr -dr com.apple.quarantine "$app" "$command" 2>/dev/null || true
  log "Installed $app"
  log "Installed $command"
}

run_openclaw_setup() {
  if [ "${SKIP_OPENCLAW_SETUP:-0}" = "1" ]; then
    log "Skipping installer-core/install.sh (SKIP_OPENCLAW_SETUP=1)"
    return
  fi

  require_file "$SETUP_DIR/install.sh"
  if is_dry_run; then
    dry_log "Would run OpenClaw/media setup: $SETUP_DIR/install.sh"
    dry_log "Would pass SKIP_DOTFILES=1 SKIP_SECRETS=1 for non-secret first phase"
    return
  fi

  log "Running OpenClaw/media setup"
  SKIP_DOTFILES=1 SKIP_SECRETS=1 SKIP_WEIXIN="${SKIP_WEIXIN:-0}" bash "$SETUP_DIR/install.sh"
}

openclaw_skill_installed() {
  local skill="$1"

  if openclaw skills info "$skill" >/dev/null 2>&1; then
    return 0
  fi

  [ -d "$HOME/.openclaw/skills/$skill" ] || \
    [ -d "$HOME/.openclaw/workspace/skills/$skill" ] || \
    [ -d "$HOME/clawd/skills/$skill" ]
}

install_openclaw_office_skills() {
  if [ "${SKIP_OFFICE_SKILLS:-0}" = "1" ]; then
    log "Skipping data-analysis / Office skills (SKIP_OFFICE_SKILLS=1)"
    return
  fi

  if is_dry_run; then
    dry_log "Would install OpenClaw data-analysis / Office skills: $OFFICE_SKILLS"
    return
  fi

  if ! command -v openclaw >/dev/null 2>&1; then
    log "Skipping data-analysis / Office skills because openclaw CLI is not available"
    return
  fi

  local skill
  for skill in $OFFICE_SKILLS; do
    [ -n "$skill" ] || continue
    if openclaw_skill_installed "$skill"; then
      log "OpenClaw skill already installed: $skill"
      continue
    fi

    log "Installing OpenClaw skill globally: $skill"
    if ! openclaw skills install "$skill" --global; then
      log "WARN: failed to install OpenClaw skill: $skill"
    fi
  done
}
