sudo() {
  if [ -n "${SUDO_PASSWORD:-}" ] && [ "${1:-}" != "-S" ]; then
    printf '%s\n' "$SUDO_PASSWORD" | command sudo -S -p "" "$@"
  else
    command sudo "$@"
  fi
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

record_phase_timing() {
  local phase="$1" started_epoch="$2" finished_epoch="$3" status="$4"
  local duration_seconds result report
  report="${INSTALL_PHASE_TIMING_FILE:-${ROOT:-.}/reports/install-phase-timing.jsonl}"
  duration_seconds=$((finished_epoch - started_epoch))
  [ "$duration_seconds" -ge 0 ] || duration_seconds=0
  if [ "$status" = "0" ]; then
    result="pass"
  else
    result="fail"
  fi
  if is_dry_run; then
    dry_log "Would record phase timing: $phase $result ${duration_seconds}s"
    return 0
  fi
  mkdir -p "$(dirname "$report")"
  printf '{"phase":"%s","status":"%s","duration_seconds":%s}\n' \
    "$phase" "$result" "$duration_seconds" >> "$report"
  log "Phase timing: $phase $result ${duration_seconds}s ($report)"
}

record_problem() {
  local msg="$*"
  INSTALL_PROBLEMS+=("$msg")
  log "WARN: $msg"
  if ! is_dry_run; then
    mkdir -p "$(dirname "$INSTALL_PROBLEMS_FILE")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$INSTALL_PROBLEMS_FILE"
  fi
}

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
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

run_optional_step() {
  local label="$1" timeout="$2" pid status elapsed monitor_was_on
  shift
  shift

  if is_dry_run; then
    "$@"
    return 0
  fi

  log "Starting optional step: $label (timeout ${timeout}s)"
  set +e
  monitor_was_on=0
  case "$-" in
    *m*) monitor_was_on=1 ;;
  esac
  # Monitor mode gives the background subshell its own process group. This
  # lets a timeout terminate the whole installer tree instead of only its
  # immediate shell and leaving npm/hdiutil/installer descendants running.
  set -m
  ( set +m; set -e; "$@" ) &
  pid="$!"
  if [ "$monitor_was_on" = "0" ]; then
    set +m
  fi
  elapsed=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      kill -TERM -- "-$pid" >/dev/null 2>&1 || kill "$pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -9 "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1
      status=124
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ -z "${status:-}" ]; then
    wait "$pid"
    status="$?"
  fi
  set -e

  if [ "$status" = "0" ]; then
    log "Optional step completed: $label"
  elif [ "$status" = "124" ]; then
    record_problem "$label timed out after ${timeout}s; continuing with remaining install steps"
  else
    record_problem "$label failed with status $status; continuing with remaining install steps"
  fi
  return 0
}

print_install_problem_summary() {
  if [ "${#INSTALL_PROBLEMS[@]}" -eq 0 ]; then
    log "No non-blocking install problems recorded in this phase"
    return
  fi
  log "Install completed with non-blocking problems:"
  local item
  for item in "${INSTALL_PROBLEMS[@]}"; do
    printf '  - %s\n' "$item"
  done
  log "Problem log: $INSTALL_PROBLEMS_FILE"
}

is_dry_run() {
  [ "${DRY_RUN:-0}" = "1" ]
}

dry_log() {
  log "[dry-run] $*"
}

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "This installer only supports macOS."
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo "Missing required file: $path"
    exit 1
  fi
}

restore_file() {
  local src="$1" dst="$2"
  local rewrite_home="${3:-0}"
  if [ ! -f "$src" ]; then
    return 1
  fi
  if is_dry_run; then
    dry_log "Would restore $src -> $dst"
    if [ "$rewrite_home" = "1" ]; then
      dry_log "Would rewrite captured source-machine home paths in $dst to $HOME"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    local bak="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$dst" "$bak"
    log "Backed up existing file -> $bak"
  fi
  cp "$src" "$dst"
  if [ "$rewrite_home" = "1" ]; then
    LC_ALL=C LANG=C NEW_HOME="$HOME" perl -0pi -e 's#/Users/(cm|mac)(?=/|$)#$ENV{NEW_HOME}#g' "$dst"
  fi
  chmod 600 "$dst"
  log "Restored $dst"
}

restore_first_available() {
  local dst="$1"
  local rewrite_home="$2"
  shift
  shift
  local src
  for src in "$@"; do
    if [ -f "$src" ]; then
      restore_file "$src" "$dst" "$rewrite_home"
      return 0
    fi
  done
  log "Skipping missing private file for $dst"
}

resolve_private_secrets_dir() {
  if [ -n "${PRIVATE_SECRETS_DIR:-}" ]; then
    printf '%s\n' "$PRIVATE_SECRETS_DIR"
  elif [ -d "$ROOT/private-secrets" ]; then
    printf '%s\n' "$ROOT/private-secrets"
  elif [ -d "$ROOT/../private-secrets" ]; then
    printf '%s\n' "$ROOT/../private-secrets"
  else
    printf '%s\n' "$ROOT/private-secrets"
  fi
}

resolve_cliproxy_bundle_dir() {
  local candidate
  for candidate in \
    "$CLIPROXY_BUNDLE_DIR" \
    "$ROOT/install-files/openclaw-team/cliproxy" \
    "$ROOT/../install-files/openclaw-team/cliproxy" \
    "$ROOT/dist/openclaw-team/cliproxy" \
    "$ROOT/../dist/openclaw-team/cliproxy" \
    "$CLIPROXY_SOURCE_DIR/bin"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate/CLIProxyAPI" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_sudo() {
  if is_dry_run; then
    dry_log "Would request administrator permission"
    return
  fi

  log "Requesting administrator permission"
  if [ -n "${SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p "" -v
  else
    sudo -v
  fi
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done 2>/dev/null &
  SUDO_KEEPALIVE_PID="$!"
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

install_pkg_file() {
  local label="$1" pkg="$2"
  require_file "$pkg"
  if is_dry_run; then
    dry_log "Would install $label from PKG: $pkg"
    return
  fi

  log "Installing $label"
  run_installer "$label" "$pkg"
}

run_installer() {
  local label="$1" pkg="$2" output status
  output="$(mktemp "/tmp/${label// /_}.installer.XXXXXX.log")"
  set +e
  sudo installer -pkg "$pkg" -target / 2>&1 | tee "$output"
  status="${PIPESTATUS[0]}"
  set -e

  if [ "$status" -ne 0 ] || LC_ALL=C grep -Eqi \
    'Cannot install|The install failed|Installation failed|requires macOS|需要macOS|安装失败|disabled' \
    "$output"; then
    cat "$output" >&2
    rm -f "$output"
    echo "Installer failed for $label: $pkg" >&2
    return 1
  fi

  rm -f "$output"
}

mount_dmg() {
  local dmg="$1" mount="$2"
  require_file "$dmg"
  unmount_dmg "$mount"
  rm -rf "$mount" 2>/dev/null || true
  mkdir -p "$mount"
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" >/dev/null
}

unmount_dmg() {
  local mount="$1"
  local real_mount="$mount"
  if [ -e "$mount" ]; then
    real_mount="$(cd "$mount" 2>/dev/null && pwd -P || printf '%s\n' "$mount")"
  fi

  hdiutil detach "$mount" -quiet 2>/dev/null \
    || hdiutil detach "$real_mount" -quiet 2>/dev/null \
    || hdiutil detach "$mount" -force -quiet 2>/dev/null \
    || hdiutil detach "$real_mount" -force -quiet 2>/dev/null \
    || true

  if mount | grep -qF " on $mount " || mount | grep -qF " on $real_mount "; then
    log "Leaving mounted DMG at $mount because it is still busy"
    return
  fi

  rm -rf "$mount" 2>/dev/null || true
}

install_pkg_from_dmg() {
  local label="$1" dmg="$2"
  require_file "$dmg"
  if is_dry_run; then
    dry_log "Would mount $dmg and install $label from the first .pkg inside"
    return
  fi

  local mount
  mount="$(mktemp -d "/tmp/${label// /_}.XXXXXX")"
  log "Installing $label from DMG"
  mount_dmg "$dmg" "$mount"
  local pkg
  pkg="$(find "$mount" -maxdepth 4 -name '*.pkg' -print -quit)"
  if [ -z "$pkg" ]; then
    unmount_dmg "$mount"
    echo "No .pkg found in $dmg"
    exit 1
  fi
  set +e
  run_installer "$label" "$pkg"
  local status="$?"
  set -e
  unmount_dmg "$mount"
  if [ "$status" -ne 0 ]; then
    exit "$status"
  fi
}

macos_at_least() {
  local need_major="$1" need_minor="$2" version major minor
  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  [ -n "$minor" ] || minor=0

  if [ "$major" -gt "$need_major" ]; then
    return 0
  fi
  if [ "$major" -eq "$need_major" ] && [ "$minor" -ge "$need_minor" ]; then
    return 0
  fi
  return 1
}

install_command_line_tools() {
  local arch clt_dmg="" candidate
  arch="$(uname -m)"

  if xcode-select -p >/dev/null 2>&1; then
    log "Command Line Tools already available: $(xcode-select -p)"
    return
  fi

  if macos_at_least 26 2; then
    case "$arch" in
      arm64)
        for candidate in \
          "$BUNDLE_DIR/Command_Line_Tools_26.5_Apple_silicon.dmg" \
          "$BUNDLE_DIR/Command_Line_Tools_26.5_Universal.dmg" \
          "$ROOT/Command_Line_Tools_26.5_Universal.dmg"; do
          if [ -f "$candidate" ]; then
            clt_dmg="$candidate"
            break
          fi
        done
        ;;
      x86_64)
        for candidate in \
          "$BUNDLE_DIR/Command_Line_Tools_26.5_Universal.dmg" \
          "$ROOT/Command_Line_Tools_26.5_Universal.dmg" \
          "$BUNDLE_DIR/Command_Line_Tools_26.5_Intel.dmg"; do
          if [ -f "$candidate" ]; then
            clt_dmg="$candidate"
            break
          fi
        done
        ;;
      *)
        log "Unknown Mac architecture for Command Line Tools selection: $arch"
        ;;
    esac
  elif macos_at_least 15 0; then
    for candidate in \
      "$BUNDLE_DIR/Command_Line_Tools_for_Xcode_16.4.dmg" \
      "$ROOT/Command_Line_Tools_for_Xcode_16.4.dmg"; do
      if [ -f "$candidate" ]; then
        clt_dmg="$candidate"
        break
      fi
    done
  else
    log "Skipping bundled Command Line Tools because macOS $(sw_vers -productVersion) is below 15.0"
    log "If developer tools are needed on this Mac, install a compatible version manually: xcode-select --install"
    return
  fi

  if [ -n "$clt_dmg" ]; then
    log "Selected Command Line Tools for macOS $(sw_vers -productVersion) on $arch: $clt_dmg"
    install_pkg_from_dmg "Command Line Tools" "$clt_dmg"
  else
    log "Skipping Command Line Tools because no compatible offline DMG was found for macOS $(sw_vers -productVersion) on $arch"
    log "If a later step needs developer tools, run manually: xcode-select --install"
  fi
}

ensure_user_path_file() {
  local file="$1"
  local marker="# openclaw-installer PATH"
  local line='export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH" # openclaw-installer PATH'

  if is_dry_run; then
    dry_log "Would ensure /usr/local/bin, /opt/homebrew/bin, and ~/.local/bin in $file"
    return
  fi

  touch "$file"
  if ! grep -qF "$marker" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
    log "Added OpenClaw installer PATH line to $file"
  else
    log "$file already contains OpenClaw installer PATH line"
  fi
}

shell_path_expr() {
  local path="$1"
  case "$path" in
    "$HOME")
      printf '$HOME'
      ;;
    "$HOME"/*)
      printf '$HOME/%s' "${path#"$HOME"/}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

ensure_user_path_dir_file() {
  local file="$1" dir="$2" label="$3"
  local marker="# openclaw-installer PATH: $label"
  local expr

  if [ -z "$dir" ]; then
    return
  fi

  expr="$(shell_path_expr "$dir")"
  if is_dry_run; then
    dry_log "Would ensure $dir is in $file"
    return
  fi

  touch "$file"
  if ! grep -qF "$marker" "$file"; then
    printf '\nexport PATH="%s:$PATH" %s\n' "$expr" "$marker" >> "$file"
    log "Added $dir to $file"
  else
    log "$file already contains PATH line for $label"
  fi
}

ensure_current_path_dir() {
  local dir="$1"
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) export PATH="$dir:$PATH" ;;
    esac
  fi
}

ensure_user_shell_path() {
  ensure_user_path_file "$HOME/.zshenv"
  ensure_user_path_file "$HOME/.zshrc"
}

ensure_user_shell_path_dir() {
  local dir="$1" label="$2"
  ensure_user_path_dir_file "$HOME/.zshenv" "$dir" "$label"
  ensure_user_path_dir_file "$HOME/.zshrc" "$dir" "$label"
  ensure_current_path_dir "$dir"
}

find_npm_binary() {
  if command -v npm >/dev/null 2>&1; then
    command -v npm
  elif [ -x /usr/local/bin/npm ]; then
    printf '%s\n' /usr/local/bin/npm
  elif [ -x /opt/homebrew/bin/npm ]; then
    printf '%s\n' /opt/homebrew/bin/npm
  else
    return 1
  fi
}

npm_global_bin_dir() {
  local npm_bin="$1"
  local prefix
  prefix="$("$npm_bin" config get prefix 2>/dev/null || true)"
  if [ -n "$prefix" ] && [ "$prefix" != "undefined" ] && [ "$prefix" != "null" ]; then
    printf '%s/bin\n' "$prefix"
  fi
}

ensure_codex_command_available() {
  local npm_bin_dir="${1:-}"
  local candidate dir link="$HOME/.local/bin/codex"

  hash -r 2>/dev/null || true
  if command -v codex >/dev/null 2>&1; then
    log "Codex CLI available: $(codex --version 2>/dev/null || printf 'version check failed')"
    return
  fi

  for candidate in \
    "$npm_bin_dir/codex" \
    "/usr/local/bin/codex" \
    "/opt/homebrew/bin/codex" \
    "$HOME/.local/bin/codex" \
    "/Applications/ChatGPT.app/Contents/Resources/codex" \
    "/Applications/ChatGPT.app/Contents/Resources/native/codex-macos" \
    "/Applications/Codex.app/Contents/Resources/codex"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      if [[ "$candidate" == /Applications/*.app/Contents/Resources/* ]]; then
        if is_dry_run; then
          dry_log "Would link Codex.app CLI to $link"
        else
          mkdir -p "$HOME/.local/bin"
          ln -sf "$candidate" "$link"
          candidate="$link"
          log "Linked Codex.app CLI to $link"
        fi
      fi

      dir="$(dirname "$candidate")"
      ensure_user_shell_path_dir "$dir" "codex-cli"
      hash -r 2>/dev/null || true
      if command -v codex >/dev/null 2>&1; then
        log "Codex CLI available: $(codex --version 2>/dev/null || printf 'version check failed')"
        return
      fi
    fi
  done

  log "WARN: Codex CLI is still not on PATH. Try a new terminal, then run: command -v codex"
}

install_codex_cli() {
  if [ "${SKIP_CODEX_CLI:-0}" = "1" ]; then
    log "Skipping Codex npm CLI install (SKIP_CODEX_CLI=1)"
    return
  fi

  if is_dry_run; then
    dry_log "Would run npm install -g @openai/codex"
    return
  fi

  local npm_bin
  local npm_bin_dir=""
  if ! npm_bin="$(find_npm_binary)"; then
    log "Skipping Codex npm CLI install because npm is not available"
    ensure_codex_command_available ""
    return
  fi
  npm_bin_dir="$(npm_global_bin_dir "$npm_bin" || true)"
  if [ -n "$npm_bin_dir" ]; then
    ensure_user_shell_path_dir "$npm_bin_dir" "npm-global"
  fi

  if command -v codex >/dev/null 2>&1; then
    log "Codex CLI currently available: $(codex --version 2>/dev/null || printf 'version check failed')"
  fi

  log "Installing Codex CLI from npm: npm install -g @openai/codex"
  if ! "$npm_bin" install -g @openai/codex; then
    log "npm global install failed without sudo; retrying with sudo"
    sudo "$npm_bin" install -g @openai/codex
  fi

  hash -r 2>/dev/null || true
  ensure_codex_command_available "$npm_bin_dir"
}
