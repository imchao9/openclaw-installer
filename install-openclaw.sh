#!/usr/bin/env bash
# One-command OpenClaw installer wrapper.
#
# Copy a folder that contains this script plus either:
#   - install-files/ and optional 01-Clash.../private-secrets/, or
#   - 02-.../ and optional 01-Clash.../private-secrets/, or
#   - the install-files contents directly.
#
# Then run:
#   bash install-openclaw.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
RUN_CLASH="${RUN_CLASH:-auto}"
RUN_BASE="${RUN_BASE:-1}"
RUN_SECRETS="${RUN_SECRETS:-auto}"
RUN_EXTRAS="${RUN_EXTRAS:-1}"
RUN_OFFICE_SKILLS="${RUN_OFFICE_SKILLS:-0}"
RUN_CLIPROXY_CONFIG="${RUN_CLIPROXY_CONFIG:-1}"
RUN_AUTH_SYNC="${RUN_AUTH_SYNC:-0}"
RUN_VALIDATE="${RUN_VALIDATE:-1}"
SKIP_WEIXIN="${SKIP_WEIXIN:-1}"
SKIP_OFFICE_SKILLS="${SKIP_OFFICE_SKILLS:-0}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.openclaw-install-state}"

usage() {
  cat <<'EOF'
Usage:
  bash install-openclaw.sh [options]

Default flow:
  1. Install Clash when a sibling Clash package is present.
  2. Run base install from install-files/ or 02-新电脑初始化/.
  3. Install Chrome, Obsidian, CC-Switch, DingTalk, and compatible extra apps.
  4. Try data-analysis / Office skills during base with a short timeout.
  5. Restore private-secrets when private-secrets/ is present.
  6. Re-apply Codex/OpenClaw CLIProxy routing after config restore.
  7. Validate OpenClaw and Codex by sending hello.

Options:
  --dry-run                 Print the plan; do not install or write state.
  --force                   Re-run phases even when a done marker exists.
  --skip-clash              Do not run Clash installer.
  --skip-base               Do not run base installer.
  --skip-secrets            Do not restore private-secrets.
  --with-extras             Explicitly enable the default complete extra-app install.
  --core-only               Skip Chrome, Obsidian, CC-Switch, AweSun, and DingTalk.
  --skip-extras             Alias for --core-only.
  --with-office-skills      Re-run data-analysis / Office skills as a separate phase.
  --skip-office-skills      Do not install data-analysis / Office skills.
  --skip-validate           Do not send Codex/OpenClaw hello acceptance checks.
  --with-cliproxy-config    Re-apply the default Codex/OpenClaw CLIProxy routing.
  --with-auth-sync          Install/refresh Codex Auth Sync Agent. First run needs CODEX_AUTH_SYNC_CODE.
  --with-weixin             Run Weixin connector setup now. This may wait for QR scan.
  -h, --help                Show this help.

Useful environment variables:
  PRIVATE_SECRETS_DIR=/path/to/private-secrets
  CLASH_DIR=/path/to/01-Clash单独安装
  STATE_DIR=/path/to/state
  RUN_CLIPROXY_CONFIG=1
  RUN_AUTH_SYNC=1
  RUN_EXTRAS=1
  RUN_OFFICE_SKILLS=1
  RUN_VALIDATE=0
  SKIP_WEIXIN=0
  SKIP_OFFICE_SKILLS=1
  FORCE=1
  DRY_RUN=1

The lower-level installer still accepts SKIP_* switches, for example:
  SKIP_EXTRAS=1 bash install-openclaw.sh
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      ;;
    --skip-clash)
      RUN_CLASH=0
      ;;
    --skip-base)
      RUN_BASE=0
      ;;
    --skip-secrets)
      RUN_SECRETS=0
      ;;
    --with-extras)
      RUN_EXTRAS=1
      ;;
    --core-only|--skip-extras)
      RUN_EXTRAS=0
      ;;
    --with-office-skills)
      RUN_OFFICE_SKILLS=1
      SKIP_OFFICE_SKILLS=0
      ;;
    --skip-office-skills)
      SKIP_OFFICE_SKILLS=1
      RUN_OFFICE_SKILLS=0
      ;;
    --skip-validate)
      RUN_VALIDATE=0
      ;;
    --with-cliproxy-config)
      RUN_CLIPROXY_CONFIG=1
      ;;
    --with-auth-sync)
      RUN_AUTH_SYNC=1
      ;;
    --with-weixin)
      SKIP_WEIXIN=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $arg"
      ;;
  esac
done

export DRY_RUN
export SKIP_WEIXIN
export SKIP_OFFICE_SKILLS

first_existing_dir() {
  local path
  for path in "$@"; do
    if [ -d "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

find_dist_dir() {
  if [ -f "$SCRIPT_DIR/install-new-macbook.sh" ]; then
    printf '%s\n' "$SCRIPT_DIR"
    return 0
  fi

  local found=""
  if found="$(first_existing_dir \
    "$SCRIPT_DIR/install-files" \
    "$SCRIPT_DIR/dist" \
    "$SCRIPT_DIR/02-新电脑初始化" \
    "$SCRIPT_DIR/01-新电脑初始化" \
    "$SCRIPT_DIR/openclaw-install-content-20260607-v2/02-新电脑初始化" \
    "$SCRIPT_DIR/openclaw-install-content-20260607/01-新电脑初始化")"; then
    if [ -f "$found/install-new-macbook.sh" ]; then
      printf '%s\n' "$found"
      return 0
    fi
  fi
  return 1
}

find_clash_dir() {
  if [ -n "${CLASH_DIR:-}" ]; then
    [ -f "$CLASH_DIR/install-clash.sh" ] && printf '%s\n' "$CLASH_DIR" && return 0
    return 1
  fi

  local package_root="$1"
  local dist_dir="$2"
  local path
  for path in \
    "$SCRIPT_DIR/01-Clash单独安装" \
    "$SCRIPT_DIR/05-Clash单独安装" \
    "$SCRIPT_DIR/clash-install" \
    "$package_root/01-Clash单独安装" \
    "$package_root/05-Clash单独安装" \
    "$package_root/clash-install" \
    "$dist_dir/../01-Clash单独安装" \
    "$dist_dir/../05-Clash单独安装" \
    "$SCRIPT_DIR/openclaw-install-content-20260607-v2/01-Clash单独安装" \
    "$SCRIPT_DIR/openclaw-install-content-20260607/05-Clash单独安装"; do
    if [ -f "$path/install-clash.sh" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

find_private_secrets_dir() {
  if [ -n "${PRIVATE_SECRETS_DIR:-}" ]; then
    [ -d "$PRIVATE_SECRETS_DIR" ] && printf '%s\n' "$PRIVATE_SECRETS_DIR" && return 0
    return 1
  fi

  local package_root="$1"
  local dist_dir="$2"
  first_existing_dir \
    "$SCRIPT_DIR/private-secrets" \
    "$package_root/private-secrets" \
    "$dist_dir/private-secrets" \
    "$dist_dir/../private-secrets"
}

phase_done() {
  local name="$1"
  [ "$FORCE" != "1" ] && [ -f "$STATE_DIR/$name.done" ]
}

mark_done() {
  local name="$1"
  if [ "$DRY_RUN" = "1" ]; then
    return
  fi
  mkdir -p "$STATE_DIR"
  date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/$name.done"
}

run_phase() {
  local name="$1"
  shift

  if phase_done "$name"; then
    log "Skipping $name; marker exists at $STATE_DIR/$name.done"
    return
  fi

  log "Running $name"
  "$@"
  mark_done "$name"
  log "$name done"
}

run_or_explain_failure() {
  local status="$1"
  cat <<EOF

Install stopped with status $status.

After fixing the problem, re-run the same command:
  bash install-openclaw.sh

To re-run phases that already completed:
  bash install-openclaw.sh --force
EOF
  exit "$status"
}

main() {
  local dist_dir package_root clash_dir secrets_dir
  dist_dir="$(find_dist_dir)" || die "Cannot find install-new-macbook.sh. Put this script next to install-files/ or inside install-files/."
  package_root="$(dirname "$dist_dir")"

  log "OpenClaw unified installer"
  log "Script dir: $SCRIPT_DIR"
  log "Install dir: $dist_dir"
  log "State dir: $STATE_DIR"
  if [ "$DRY_RUN" = "1" ]; then
    log "Dry-run mode enabled"
  fi

  if [ "$RUN_CLASH" != "0" ]; then
    if clash_dir="$(find_clash_dir "$package_root" "$dist_dir")"; then
      run_phase "clash" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" bash install-clash.sh" "$clash_dir" "$DRY_RUN" || run_or_explain_failure "$?"
    else
      log "No Clash installer folder found; skipping Clash"
      log "Expected one of: 01-Clash单独安装/, 05-Clash单独安装/, or CLASH_DIR=..."
    fi
  else
    log "Skipping Clash by request"
  fi

  if [ "$RUN_BASE" = "1" ]; then
    run_phase "base" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" SKIP_WEIXIN=\"\$2\" INSTALL_PHASE=base bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" "$SKIP_WEIXIN" || run_or_explain_failure "$?"
  else
    log "Skipping base by request"
  fi

  if [ "$RUN_EXTRAS" = "1" ]; then
    run_phase "extras" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" INSTALL_PHASE=extras bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" || run_or_explain_failure "$?"
  else
    log "Skipping non-core apps by explicit core-only request"
  fi

  if [ "$RUN_OFFICE_SKILLS" = "1" ]; then
    run_phase "office-skills" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" INSTALL_PHASE=office-skills bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" || run_or_explain_failure "$?"
  else
    log "Skipping office-skills by request"
  fi

  if [ "$RUN_SECRETS" != "0" ]; then
    if secrets_dir="$(find_private_secrets_dir "$package_root" "$dist_dir")"; then
      run_phase "secrets" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" PRIVATE_SECRETS_DIR=\"\$2\" INSTALL_PHASE=secrets bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" "$secrets_dir" || run_or_explain_failure "$?"
    else
      log "No private-secrets folder found; skipping secrets"
      log "Put private-secrets/ next to install-files/ or pass PRIVATE_SECRETS_DIR=..."
    fi
  else
    log "Skipping secrets by request"
  fi

  if [ "$RUN_CLIPROXY_CONFIG" = "1" ]; then
    run_phase "cliproxy-config" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" || run_or_explain_failure "$?"
  else
    log "Skipping the final cliproxy-config pass because RUN_CLIPROXY_CONFIG=0"
  fi

  if [ "$RUN_AUTH_SYNC" = "1" ]; then
    run_phase "auth-sync" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" INSTALL_PHASE=auth-sync bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" || run_or_explain_failure "$?"
  else
    log "Skipping Codex Auth Sync Agent; enable with --with-auth-sync"
  fi

  if [ "$RUN_VALIDATE" = "1" ]; then
    run_phase "validate" bash -lc "cd \"\$0\" && DRY_RUN=\"\$1\" INSTALL_PHASE=validate bash install-new-macbook.sh" "$dist_dir" "$DRY_RUN" || run_or_explain_failure "$?"
  else
    log "Skipping validation by request"
  fi

  log "Unified install flow finished"
}

main "$@"
