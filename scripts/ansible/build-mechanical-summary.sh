#!/usr/bin/env bash
# Build one pure-policy summary per host report directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage=""
report_dir=""
report_root=""
output=""
run_id=""
allow_missing_extra_apps=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage) stage="$2"; shift 2 ;;
    --report-dir) report_dir="$2"; shift 2 ;;
    --report-root) report_root="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --allow-missing-extra-apps) allow_missing_extra_apps=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$stage" ] || { echo "--stage is required" >&2; exit 2; }

evaluate_one() {
  local dir="$1" out="$2"
  if [ -n "$run_id" ]; then
    if [ "$allow_missing_extra_apps" = "1" ]; then
      /usr/bin/python3 "$SCRIPT_DIR/evaluate-rollout.py" \
        --stage "$stage" --report-dir "$dir" --output "$out" --run-id "$run_id" \
        --allow-missing-extra-apps
    else
      /usr/bin/python3 "$SCRIPT_DIR/evaluate-rollout.py" \
        --stage "$stage" --report-dir "$dir" --output "$out" --run-id "$run_id"
    fi
  else
    if [ "$allow_missing_extra_apps" = "1" ]; then
      /usr/bin/python3 "$SCRIPT_DIR/evaluate-rollout.py" \
        --stage "$stage" --report-dir "$dir" --output "$out" \
        --allow-missing-extra-apps
    else
      /usr/bin/python3 "$SCRIPT_DIR/evaluate-rollout.py" \
        --stage "$stage" --report-dir "$dir" --output "$out"
    fi
  fi
}

if [ -n "$report_dir" ]; then
  [ -n "$output" ] || output="$report_dir/mechanical-$stage-summary.json"
  evaluate_one "$report_dir" "$output"
  exit 0
fi

[ -n "$report_root" ] || { echo "--report-dir or --report-root is required" >&2; exit 2; }
found=0
for dir in "$report_root"/*; do
  [ -d "$dir" ] || continue
  [ -f "$dir/preflight-report.json" ] || continue
  case "$stage" in
    assessment) [ -f "$dir/assessment-install-report.json" ] || continue ;;
    final) [ -f "$dir/final-install-report.json" ] || continue ;;
  esac
  found=1
  evaluate_one "$dir" "$dir/mechanical-$stage-summary.json"
done
[ "$found" = "1" ] || { echo "No eligible report directories under $report_root" >&2; exit 1; }
