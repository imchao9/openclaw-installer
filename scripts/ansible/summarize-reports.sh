#!/usr/bin/env bash
# Summarize fetched OpenClaw installer JSON reports into a compact table.
set -euo pipefail

REPORT_ROOT="${1:-ansible/reports}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to summarize reports" >&2
  exit 1
fi

if [ ! -d "$REPORT_ROOT" ]; then
  echo "Missing report directory: $REPORT_ROOT" >&2
  exit 1
fi

pick_report() {
  local dir="$1"
  for name in final-install-report.json post-install-report.json install-report.json scan-install-report.json initial-install-report.json; do
    if [ -f "$dir/$name" ]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  find "$dir" -maxdepth 1 -name '*install-report.json' -print | sort | tail -n 1
}

json_value() {
  local file="$1" filter="$2" fallback="$3"
  if [ -f "$file" ]; then
    jq -r "$filter" "$file" 2>/dev/null || printf '%s\n' "$fallback"
  else
    printf '%s\n' "$fallback"
  fi
}

printf 'host\tpreflight\tbase\tsecrets\tcliproxy\tclash\tcodex_cfg\topenclaw_cfg\tinstall\tcodex_val\topenclaw_val\tmanual\treasons\n'

find "$REPORT_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort | while IFS= read -r host_dir; do
  report="$(pick_report "$host_dir")"
  [ -n "$report" ] && [ -f "$report" ] || continue

  install_result="$host_dir/install-result.json"
  validation_report="$host_dir/validation-report.json"
  preflight_report="$host_dir/preflight-report.json"
  install_status="$(json_value "$install_result" '.status // "not_run"' "not_run")"
  codex_validation="$(json_value "$validation_report" '.codex.status // "not_run"' "not_run")"
  openclaw_validation="$(json_value "$validation_report" '.openclaw.status // "not_run"' "not_run")"
  preflight_status="$(json_value "$preflight_report" 'if (.enough_disk == false) then "disk_low" elif (.sudo_checked == true and .sudo_noninteractive_ok == false and .applications_writable == false) then "sudo_prompt" else "ok" end' "no_report")"

  jq -r \
    --arg install_status "$install_status" \
    --arg codex_validation "$codex_validation" \
    --arg openclaw_validation "$openclaw_validation" \
    --arg preflight_status "$preflight_status" '
      [
        .host,
        $preflight_status,
        (if .plan.run_base then "need" else "ok" end),
        (if .plan.needs_secrets then "missing" elif .plan.run_secrets then "need" else "ok" end),
        (if .cliproxy.listening_8317 then "ok" else "need" end),
        (if .clash.socks_7890_healthy then "ok" elif .plan.needs_manual_clash_gui then "needs_gui" else "need" end),
        (if .configs.codex_cliproxy_config then "ok" else "need" end),
        (if .configs.openclaw_cliproxy_config then "ok" else "need" end),
        $install_status,
        $codex_validation,
        $openclaw_validation,
        (if .plan.needs_manual_clash_gui then "open_clash_gui" else "" end),
        (.plan.reasons // "")
      ] | @tsv
    ' "$report"
done
