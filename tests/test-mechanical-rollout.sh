#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/openclaw-mechanical-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_json() {
  local file="$1" expression="$2"
  /usr/bin/python3 - "$file" "$expression" <<'PY'
import json
import sys

path, expression = sys.argv[1:]
data = json.load(open(path))
if not eval(expression, {"__builtins__": {"any": any}}, {"data": data}):
    raise SystemExit(f"assertion failed for {path}: {expression}\n{json.dumps(data, indent=2)}")
PY
}

test_profile_resolution() {
  local resolver="$ROOT/scripts/ansible/resolve-package-profile.sh"
  [ "$(bash "$resolver" 14.7.6 x86_64)" = "macos14-x64" ] || fail "Intel macOS 14 profile"
  [ "$(bash "$resolver" 15.7.7 x86_64)" = "macos15-x64" ] || fail "Intel macOS 15 profile"
  [ "$(bash "$resolver" 15.7.7 arm64)" = "macos15-arm64" ] || fail "arm64 macOS 15 profile"
  [ "$(bash "$resolver" 26.5.1 arm64)" = "macos26-arm64" ] || fail "arm64 macOS 26 profile"
  if bash "$resolver" 14.6.1 arm64 >/dev/null 2>&1; then
    fail "unsupported macOS unexpectedly resolved"
  fi
}

test_runner_phase_boundaries() {
  local runner="$ROOT/scripts/ansible/mechanical-rollout.sh"
  local inventory="$TMP/inventory.ini" output
  printf '[openclaw_macs]\nexample ansible_host=127.0.0.1 ansible_user=mac\n' > "$inventory"

  output="$(MECHANICAL_ROLLOUT_DRY_RUN=1 bash "$runner" assess -i "$inventory")"
  assert_contains "$output" "preflight.yml"
  assert_contains "$output" "scan.yml"
  assert_contains "$output" "scan_label=assessment"
  assert_contains "$output" "validation_report_name=assessment-validation-report.json"
  assert_contains "$output" "build-mechanical-summary.sh"
  assert_not_contains "$output" "sync.yml"
  assert_not_contains "$output" "install-missing.yml"

  if MECHANICAL_ROLLOUT_DRY_RUN=1 bash "$runner" apply -i "$inventory" --run-id test-run >/dev/null 2>&1; then
    fail "apply must require an explicit approved assessment"
  fi

  output="$(MECHANICAL_ROLLOUT_DRY_RUN=1 bash "$runner" apply -i "$inventory" --run-id test-run --approve-assessment)"
  assert_contains "$output" "bootstrap-clt.yml"
  assert_contains "$output" "sync.yml"
  [ "$(grep -c 'install-missing.yml' <<<"$output")" -eq 2 ] || fail "apply must run at most one targeted repair pass"
  assert_contains "$output" "scan_label=repair"
  assert_contains "$output" "validate-agents.yml"
  assert_contains "$output" "scan_label=final"
  assert_contains "$output" "collect-reports.yml"
  assert_contains "$output" "--stage final"
  assert_contains "$output" "install_extra_apps=1"
  assert_not_contains "$output" "--allow-missing-extra-apps"

  output="$(MECHANICAL_ROLLOUT_DRY_RUN=1 bash "$runner" apply -i "$inventory" --run-id test-run --approve-assessment --core-only)"
  assert_contains "$output" "install_extra_apps=0"
  assert_contains "$output" "--allow-missing-extra-apps"

  if MECHANICAL_ROLLOUT_DRY_RUN=1 bash "$runner" assess -i "$inventory" --profile macos26-x64 >/dev/null 2>&1; then
    fail "mechanical rollout accepted the unsupported macos26-x64 profile"
  fi
}

write_ready_assessment_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/preflight-report.json" <<'JSON'
{"schema_version":1,"ssh_reached":true,"macos_version":"15.7.7","arch":"x86_64","enough_disk":true,"gui_session_active":true}
JSON
  cat > "$dir/assessment-install-report.json" <<'JSON'
{"schema_version":1,"plan":{"reasons":"node/npm missing; core apps missing"},"cliproxy":{"listening_8317":false}}
JSON
  cat > "$dir/assessment-validation-report.json" <<'JSON'
{"schema_version":1,"codex":{"status":"fail","error_tail":"Codex CLI not found"},"openclaw":{"status":"fail","error_tail":"openclaw command not found"}}
JSON
}

test_assessment_summary_is_ready_for_clean_machine() {
  local dir="$TMP/assessment" output="$TMP/assessment-summary.json"
  write_ready_assessment_fixture "$dir"
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage assessment --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "ready"'
  assert_json "$output" 'data["expected_profile"] == "macos15-x64"'
  assert_json "$output" 'data["ai_decision_required"] is True'
  assert_json "$output" 'not data["blockers"]'
}

test_assessment_hard_blocks_low_disk() {
  local dir="$TMP/disk-low" output="$TMP/disk-low-summary.json"
  write_ready_assessment_fixture "$dir"
  /usr/bin/python3 - "$dir/preflight-report.json" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1]); d = json.loads(p.read_text()); d["enough_disk"] = False; p.write_text(json.dumps(d))
PY
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage assessment --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "blocked"'
  assert_json "$output" 'any(item["code"] == "disk_low" for item in data["blockers"])'
}

test_assessment_supports_macos14_intel_with_clt() {
  local dir="$TMP/macos14" output="$TMP/macos14-summary.json"
  write_ready_assessment_fixture "$dir"
  /usr/bin/python3 - "$dir/preflight-report.json" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d.update({"macos_version": "14.7.6", "arch": "x86_64", "clt_available": True})
p.write_text(json.dumps(d))
PY
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage assessment --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "ready"'
  assert_json "$output" 'data["expected_profile"] == "macos14-x64"'

  /usr/bin/python3 - "$dir/preflight-report.json" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["clt_available"] = False
p.write_text(json.dumps(d))
PY
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage assessment --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "blocked"'
  assert_json "$output" 'any(item["code"] == "clt_required" for item in data["blockers"])'
}

test_intel_runtime_guardrails_are_present() {
  assert_contains "$(cat "$ROOT/scripts/build-dist.sh")" "GOARCH=amd64"
  assert_contains "$(cat "$ROOT/scripts/build-dist.sh")" 'BUILD_CACHE_ROOT="${BUILD_CACHE_ROOT:-$ROOT/.build-cache}"'
  assert_contains "$(cat "$ROOT/scripts/assets/download-sources.yml")" "dingtalk-universal"
  if grep -q 'ROOT/install-files/openclaw-team/Codex-intel.dmg' "$ROOT/scripts/build-dist.sh"; then
    fail "Intel Codex asset still falls back to generated install-files"
  fi
  assert_contains "$(cat "$ROOT/installer-core/lib/installer-cliproxy.sh")" "CLIProxyAPI architecture mismatch"
  assert_contains "$(cat "$ROOT/installer-core/lib/installer-cliproxy.sh")" "Keeping CLIProxyAPI proxy-url"
  assert_contains "$(cat "$ROOT/installer-core/scripts/install-codex-auth-sync.sh")" "CODEX_AUTH_SYNC_INSTALL_SHA256"
  bash -n "$ROOT/installer-core/scripts/install-codex-auth-sync.sh"
  assert_contains "$(cat "$ROOT/installer-core/scripts/validate-agent-configs.sh")" "Keep a parent process that owns a separate process group"
  assert_contains "$(cat "$ROOT/installer-core/scripts/validate-agent-configs.sh")" "OPENCLAW_VALIDATION_ROUTE"
  assert_contains "$(cat "$ROOT/installer-core/scripts/validate-agent-configs.sh")" "refusing to replace it with CLIProxy"
  assert_contains "$(cat "$ROOT/install-new-macbook.sh")" "run_timed_phase extras run_extras_phase"
  assert_contains "$(cat "$ROOT/scripts/ansible/playbooks/install-missing.yml")" "after CLIProxyAPI and agent configuration"
  assert_contains "$(cat "$ROOT/scripts/ansible/playbooks/install-missing.yml")" "RUN_EXTRAS=0"
  bash -n "$ROOT/installer-core/scripts/validate-agent-configs.sh"
}

test_offline_delivery_contract() {
  local builder="$ROOT/scripts/build-offline-delivery.sh" output
  output="$(bash "$builder" --help)"
  assert_contains "$output" "private-secrets is intentionally never copied"
  if bash "$builder" --profile unsupported >/dev/null 2>&1; then
    fail "offline delivery builder accepted an unsupported profile"
  fi
  grep -qxF 'deliveries/' "$ROOT/.gitignore" || fail "deliveries must be git-ignored"
}

test_source_asset_storage_contract() {
  local resolver="$ROOT/scripts/lib/source-assets.sh"
  local migrator="$ROOT/scripts/migrate-source-assets.sh" output
  [ -f "$resolver" ] || fail "source asset resolver missing"
  assert_contains "$(cat "$resolver")" 'upload-packages/source-assets/openclaw-team'
  assert_contains "$(cat "$ROOT/scripts/build-dist.sh")" 'source "$ROOT/scripts/lib/source-assets.sh"'
  assert_contains "$(cat "$ROOT/scripts/build-layered-dist.sh")" 'source "$ROOT/scripts/lib/source-assets.sh"'
  assert_contains "$(cat "$ROOT/scripts/ansible/playbooks/bootstrap-clt.yml")" 'upload-packages/source-assets/openclaw-team'
  output="$(bash "$migrator" --help)"
  assert_contains "$output" 'Git-tracked scripts and application launchers stay in openclaw-team/'
}

test_final_summary_separates_oauth_and_optional_work() {
  local dir="$TMP/final" output="$TMP/final-summary.json"
  write_ready_assessment_fixture "$dir"
  cat > "$dir/install-result.json" <<'JSON'
{"schema_version":2,"status":"pass","duration_seconds":600,"phases":[{"phase":"base-core-apps","status":"pass","blocking":true,"duration_seconds":120},{"phase":"doubao-config","status":"fail","blocking":false,"duration_seconds":2}]}
JSON
  cat > "$dir/final-install-report.json" <<'JSON'
{"schema_version":1,"commands":{"node":true,"codex":true,"openclaw":true},"cliproxy":{"listening_8317":true},"clash":{"socks_7890":true},"manual_tasks":{"weixin_qr_login_is_manual":true,"macos_tcc_permissions_are_manual":true}}
JSON
  cat > "$dir/validation-report.json" <<'JSON'
{"schema_version":2,"codex":{"status":"fail","reason_code":"auth_unavailable","error_tail":""},"openclaw":{"status":"pass","reason_code":"ok","error_tail":""}}
JSON
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage final --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "manual_action_required"'
  assert_json "$output" 'data["main_chain"]["install"] == "pass"'
  assert_json "$output" 'data["main_chain"]["openclaw"] == "pass"'
  assert_json "$output" 'data["main_chain"]["codex"] == "manual_action_required"'
  assert_json "$output" 'any(item["code"] == "codex_oauth" for item in data["blockers"])'
  assert_json "$output" 'any(item["code"] == "doubao_config" for item in data["optional_issues"])'
}

test_complete_install_rejects_missing_extra_apps() {
  local dir="$TMP/final-missing-extras" output="$TMP/final-missing-extras-summary.json"
  write_ready_assessment_fixture "$dir"
  cat > "$dir/install-result.json" <<'JSON'
{"schema_version":2,"status":"pass","duration_seconds":10,"phases":[]}
JSON
  cat > "$dir/final-install-report.json" <<'JSON'
{"schema_version":1,"plan":{"install_extra_apps":true,"install_dingtalk":true},"manual_tasks":{}}
JSON
  cat > "$dir/validation-report.json" <<'JSON'
{"schema_version":2,"codex":{"status":"pass"},"openclaw":{"status":"pass"}}
JSON
  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage final --report-dir "$dir" --output "$output"
  assert_json "$output" 'data["status"] == "fail"'
  assert_json "$output" 'any(item["code"] == "required_residual" for item in data["blockers"])'

  bash "$ROOT/scripts/ansible/build-mechanical-summary.sh" \
    --stage final --report-dir "$dir" --output "$output" --allow-missing-extra-apps
  assert_json "$output" 'data["status"] == "pass"'
}

test_complete_install_contract_is_wired() {
  local playbook apps checkpoints phases private wrapper
  playbook="$(cat "$ROOT/scripts/ansible/playbooks/install-missing.yml")"
  apps="$(cat "$ROOT/installer-core/lib/installer-apps.sh")"
  checkpoints="$(cat "$ROOT/installer-core/scripts/check-install-checkpoints.sh")"
  phases="$(cat "$ROOT/installer-core/lib/installer-phases.sh")"
  private="$(cat "$ROOT/installer-core/lib/installer-private.sh")"
  wrapper="$(cat "$ROOT/install-openclaw.sh")"
  assert_contains "$playbook" 'PLAN_INSTALL_DINGTALK" = "1"'
  assert_contains "$apps" 'sudo chmod a+rx "$command"'
  assert_contains "$checkpoints" 'cc_switch_ok'
  assert_contains "$checkpoints" 'codex_auth_cliproxy_ok'
  assert_contains "$checkpoints" '"codex_auth_cliproxy"'
  assert_contains "$checkpoints" '[ "$awesun_ok" = "0" ]'
  assert_contains "$checkpoints" 'app_validation'
  assert_contains "$checkpoints" 'management_api_authenticated'
  assert_contains "$checkpoints" 'current_profile_file_valid'
  assert_not_contains "$checkpoints" '[ "$doubao_ok" = "0" ]; then'
  assert_contains "$phases" 'configure_cliproxy_agent_configs'
  assert_not_contains "$private" 'CONFIGURE_CLIPROXY_AGENTS'
  assert_contains "$wrapper" 'RUN_CLIPROXY_CONFIG="${RUN_CLIPROXY_CONFIG:-1}"'
  grep -qxF '.layer-build/' "$ROOT/.gitignore" || fail ".layer-build must be git-ignored"
}

test_profile_resolution
test_runner_phase_boundaries
test_assessment_summary_is_ready_for_clean_machine
test_assessment_hard_blocks_low_disk
test_assessment_supports_macos14_intel_with_clt
test_intel_runtime_guardrails_are_present
test_offline_delivery_contract
test_source_asset_storage_contract
test_final_summary_separates_oauth_and_optional_work
test_complete_install_rejects_missing_extra_apps
test_complete_install_contract_is_wired
printf 'PASS: mechanical rollout public seams\n'
