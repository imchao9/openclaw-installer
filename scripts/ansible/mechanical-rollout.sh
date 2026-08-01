#!/usr/bin/env bash
# Deterministic controller for inspect -> approved apply -> final evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR/playbooks"
DRY_RUN="${MECHANICAL_ROLLOUT_DRY_RUN:-0}"

usage() {
  cat <<'EOF'
Usage:
  mechanical-rollout.sh assess -i INVENTORY [options]
  mechanical-rollout.sh apply  -i INVENTORY --run-id ID --approve-assessment [options]

Modes:
  assess  Read-only preflight, checkpoint scan, short existing-runtime probe,
          and decision summary. This is the AI decision boundary.
  apply   Recheck identity, bootstrap prerequisites, sync the selected profile,
          install mechanically, repair at most once, validate, and collect.

Options:
  -i, --inventory PATH       Ansible inventory (required)
  --limit PATTERN            Limit target hosts
  --profile PROFILE          auto (default), macos14-x64, macos15-x64, macos15-arm64,
                             or macos26-arm64
  --sync-transport MODE      auto (default), rsync, or http
  --private-secrets          Sync private-secrets
  --extra-apps               Install non-core apps (default for a complete install)
  --core-only                Skip non-core apps such as Chrome and Obsidian
  --optional-components      Attempt optional/manual-adjacent components
  --approve-assessment       Required acknowledgement before apply
  --run-id ID                Stable run id for append-only evidence
  --ask-pass                 Forward to ansible-playbook
  --ask-become-pass          Forward to ansible-playbook
  --prompt-ssh-password      Prompt once and reuse SSH password from a 0600 temp file
  --prompt-sudo-password     Prompt once and reuse sudo password from a 0600 temp file
  --                         Forward remaining arguments to ansible-playbook

Passwords and tokens are intentionally not accepted as command-line values.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

shell_join() {
  local arg
  printf 'RUN'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run_command() {
  if [ "$DRY_RUN" = "1" ]; then
    shell_join "$@"
    return 0
  fi
  "$@"
}

run_playbook() {
  local playbook="$1"
  local -a cmd
  shift
  cmd=(ansible-playbook -i "$inventory" "$PLAYBOOK_DIR/$playbook")
  if [ "${#limit_args[@]}" -gt 0 ]; then
    cmd+=("${limit_args[@]}")
  fi
  if [ "${#ansible_args[@]}" -gt 0 ]; then
    cmd+=("${ansible_args[@]}")
  fi
  cmd+=(-e "local_report_dir=$run_report_root")
  cmd+=("$@")
  run_command "${cmd[@]}"
}

mode="${1:-}"
case "$mode" in
  assess|apply)
    shift
    ;;
  -h|--help|'')
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown mode: $mode"
    ;;
esac

inventory=""
limit=""
profile="auto"
sync_transport="auto"
sync_private_secrets=0
install_extra_apps=1
install_optional_components=0
approved=0
prompt_ssh_password=0
prompt_sudo_password=0
run_id="$(date -u '+%Y%m%dT%H%M%SZ')"
run_id_explicit=0
ansible_args=()
limit_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -i|--inventory)
      [ "$#" -ge 2 ] || die "$1 requires a path"
      inventory="$2"
      shift 2
      ;;
    --limit)
      [ "$#" -ge 2 ] || die "$1 requires a pattern"
      limit="$2"
      shift 2
      ;;
    --profile)
      [ "$#" -ge 2 ] || die "$1 requires a profile"
      profile="$2"
      shift 2
      ;;
    --sync-transport)
      [ "$#" -ge 2 ] || die "$1 requires a mode"
      sync_transport="$2"
      shift 2
      ;;
    --private-secrets)
      sync_private_secrets=1
      shift
      ;;
    --extra-apps)
      install_extra_apps=1
      shift
      ;;
    --core-only)
      install_extra_apps=0
      shift
      ;;
    --optional-components)
      install_optional_components=1
      shift
      ;;
    --approve-assessment)
      approved=1
      shift
      ;;
    --run-id)
      [ "$#" -ge 2 ] || die "$1 requires an id"
      run_id="$2"
      run_id_explicit=1
      shift 2
      ;;
    --ask-pass|--ask-become-pass)
      ansible_args+=("$1")
      shift
      ;;
    --prompt-ssh-password)
      prompt_ssh_password=1
      shift
      ;;
    --prompt-sudo-password)
      prompt_sudo_password=1
      shift
      ;;
    --)
      shift
      ansible_args+=("$@")
      break
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$inventory" ] || die "inventory is required (-i PATH)"
[ -f "$inventory" ] || die "inventory not found: $inventory"
case "$profile" in auto|macos14-x64|macos15-x64|macos15-arm64|macos26-arm64) ;; *) die "unsupported profile: $profile" ;; esac
case "$sync_transport" in auto|rsync|http) ;; *) die "unsupported sync transport: $sync_transport" ;; esac
if [ -n "$limit" ]; then
  limit_args=(--limit "$limit")
fi

cd "$ROOT"
run_report_root="$SCRIPT_DIR/runs/$run_id/reports"
credentials_file=""
cleanup() {
  if [ -n "$credentials_file" ] && [ -f "$credentials_file" ]; then
    rm -f "$credentials_file"
  fi
}
trap cleanup EXIT

if [ "$DRY_RUN" != "1" ] && { [ "$prompt_ssh_password" = "1" ] || [ "$prompt_sudo_password" = "1" ]; }; then
  ssh_password=""
  sudo_password=""
  if [ "$prompt_ssh_password" = "1" ]; then
    read -r -s -p "SSH password: " ssh_password
    printf '\n'
  fi
  if [ "$prompt_sudo_password" = "1" ]; then
    read -r -s -p "sudo password: " sudo_password
    printf '\n'
  fi
  credentials_file="$(mktemp /tmp/openclaw-ansible-vars.XXXXXX)"
  chmod 600 "$credentials_file"
  OPENCLAW_TEMP_SSH_PASSWORD="$ssh_password" \
  OPENCLAW_TEMP_SUDO_PASSWORD="$sudo_password" \
    /usr/bin/python3 - "$credentials_file" <<'PY'
import json
import os
import sys

ssh_password = os.environ.get("OPENCLAW_TEMP_SSH_PASSWORD", "")
sudo_password = os.environ.get("OPENCLAW_TEMP_SUDO_PASSWORD", "")
data = {}
if ssh_password:
    data["ansible_password"] = ssh_password
if sudo_password:
    data["ansible_become_password"] = sudo_password
    data["install_sudo_password"] = sudo_password
with open(sys.argv[1], "w") as handle:
    json.dump(data, handle)
PY
  unset ssh_password sudo_password
  ansible_args+=(-e "@$credentials_file")
fi
if [ "$DRY_RUN" != "1" ]; then
  mkdir -p "$run_report_root"
  chmod 700 "$SCRIPT_DIR/runs/$run_id" "$run_report_root"
fi

if [ "$mode" = "assess" ]; then
  printf 'Mechanical rollout run_id: %s\n' "$run_id"
  run_playbook preflight.yml
  run_playbook scan.yml -e scan_label=assessment
  run_playbook validate-agents.yml \
    -e validation_report_name=assessment-validation-report.json \
    -e codex_timeout_seconds=8 \
    -e openclaw_timeout_seconds=8 \
    -e repair_openclaw_config=0 \
    -e check_openclaw_config_shape=0
  run_command bash "$SCRIPT_DIR/build-mechanical-summary.sh" \
    --stage assessment --report-root "$run_report_root" --run-id "$run_id"
  exit 0
fi

[ "$approved" = "1" ] || die "apply requires --approve-assessment after AI/human review"
[ "$run_id_explicit" = "1" ] || die "apply requires the --run-id emitted by assess"
if [ "$DRY_RUN" != "1" ]; then
  /usr/bin/python3 - "$run_report_root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
summaries = list(root.glob("*/mechanical-assessment-summary.json"))
if not summaries:
    raise SystemExit("No assessment summary exists for this run id")
blocked = []
for path in summaries:
    report = json.loads(path.read_text())
    if report.get("status") != "ready":
        blocked.append(f"{path.parent.name}:{report.get('status')}")
if blocked:
    raise SystemExit("Assessment is not ready: " + ", ".join(blocked))
PY
fi

# Recheck the target at the state-changing boundary, then run without AI
# intervention until a final evidence bundle is available.
run_playbook preflight.yml -e enforce_preflight_gates=true
run_playbook bootstrap-clt.yml
run_playbook sync.yml \
  -e "package_profile=$profile" \
  -e "sync_transport=$sync_transport" \
  -e "sync_private_secrets=$sync_private_secrets"
run_playbook install-missing.yml \
  -e validate_after_install=false \
  -e "install_extra_apps=$install_extra_apps" \
  -e "install_optional_components=$install_optional_components" \
  -e "mechanical_run_id=$run_id" \
  -e install_attempt=1
run_playbook scan.yml -e scan_label=repair
run_playbook install-missing.yml \
  -e validate_after_install=false \
  -e "install_extra_apps=$install_extra_apps" \
  -e "install_optional_components=$install_optional_components" \
  -e "mechanical_run_id=$run_id" \
  -e install_attempt=2
run_playbook validate-agents.yml \
  -e validation_report_name=validation-report.json \
  -e repair_openclaw_config=0 \
  -e check_openclaw_config_shape=0
run_playbook scan.yml -e scan_label=final
run_playbook collect-reports.yml
if [ "$install_extra_apps" = "0" ]; then
  run_command bash "$SCRIPT_DIR/build-mechanical-summary.sh" \
    --stage final --report-root "$run_report_root" --run-id "$run_id" \
    --allow-missing-extra-apps
else
  run_command bash "$SCRIPT_DIR/build-mechanical-summary.sh" \
    --stage final --report-root "$run_report_root" --run-id "$run_id"
fi
if [ "$DRY_RUN" != "1" ]; then
  /usr/bin/python3 - "$run_report_root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
reports = [json.loads(path.read_text()) for path in root.glob("*/mechanical-final-summary.json")]
if not reports:
    raise SystemExit(30)
statuses = {report.get("status") for report in reports}
if "fail" in statuses:
    raise SystemExit(30)
if "manual_action_required" in statuses:
    raise SystemExit(10)
raise SystemExit(0)
PY
fi
