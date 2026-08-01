#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/openclaw-installer-efficiency.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

test_zstd_preflight() {
  local output
  output="$(bash "$ROOT/scripts/fetch-package-over-http.sh" --check-zstd)"
  assert_contains "$output" 'ZSTD_EXTRACTOR='
}

test_phase_timing_record() {
  # shellcheck source=/dev/null
  source "$ROOT/installer-core/lib/installer-common.sh"
  INSTALL_PHASE_TIMING_FILE="$TMP/timing.jsonl"
  record_phase_timing "base" 100 107 0
  record_phase_timing "validate" 108 111 1
  /usr/bin/python3 - "$INSTALL_PHASE_TIMING_FILE" <<'PY'
import json
import sys

items = [json.loads(line) for line in open(sys.argv[1])]
assert items == [
    {"phase": "base", "status": "pass", "duration_seconds": 7},
    {"phase": "validate", "status": "fail", "duration_seconds": 3},
]
PY
}

test_unified_installer_defaults_to_complete_apps() {
  assert_contains "$(cat "$ROOT/install-openclaw.sh")" 'RUN_EXTRAS="${RUN_EXTRAS:-1}"'
  assert_contains "$(bash "$ROOT/install-openclaw.sh" --help)" '--core-only'
}

test_optional_step_timeout_kills_descendants() {
  # shellcheck source=/dev/null
  source "$ROOT/installer-core/lib/installer-common.sh"
  local child_pid_file="$TMP/descendant.pid" child_pid
  INSTALL_PROBLEMS=()
  INSTALL_PROBLEMS_FILE="$TMP/problems.log"

  spawn_stalled_tree() {
    sleep 30 &
    printf '%s\n' "$!" > "$child_pid_file"
    wait
  }

  run_optional_step "stalled tree" 1 spawn_stalled_tree
  child_pid="$(cat "$child_pid_file")"
  if kill -0 "$child_pid" 2>/dev/null; then
    kill "$child_pid" 2>/dev/null || true
    fail "optional step timeout left a descendant process running"
  fi
  assert_contains "$(cat "$INSTALL_PROBLEMS_FILE")" "timed out after 1s"
}

test_zstd_preflight
test_phase_timing_record
test_unified_installer_defaults_to_complete_apps
test_optional_step_timeout_kills_descendants
printf 'PASS: installer efficiency public seams\n'
