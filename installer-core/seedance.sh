#!/usr/bin/env bash
# Seedance video generation helper (Volcengine Ark)
# Usage:
#   ./seedance.sh create '<json-body>' [outdir]   # create task, poll, download
#   ./seedance.sh status <task_id>                # check one task
#   ./seedance.sh wait <task_id> [outdir]         # poll existing task + download
#   ./seedance.sh list [status]                   # list tasks
#   ./seedance.sh delete <task_id>                # cancel/delete task
#
# Requires env ARK_API_KEY.
set -euo pipefail

BASE="https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks"
: "${ARK_API_KEY:?Error: ARK_API_KEY not set}"

auth=(-H "Authorization: Bearer ${ARK_API_KEY}")
json=(-H "Content-Type: application/json")

poll_and_download() {
  local task_id="$1" outdir="${2:-$HOME/clawd}"
  echo "Task: $task_id"
  while true; do
    local res status
    res=$(curl -s --max-time 30 -X GET "${BASE}/${task_id}" "${auth[@]}")
    status=$(echo "$res" | python3 -c "import sys,json;print(json.load(sys.stdin).get('status','?'))" 2>/dev/null || echo "?")
    case "$status" in
      succeeded)
        local url
        url=$(echo "$res" | python3 -c "import sys,json;print(json.load(sys.stdin)['content']['video_url'])")
        local out="${outdir}/seedance_$(date +%Y%m%d_%H%M%S).mp4"
        echo "Succeeded. Downloading -> $out"
        curl -s -o "$out" "$url"
        echo "Saved: $out"
        ls -la "$out"
        return 0;;
      failed|expired)
        echo "Task $status:"; echo "$res" | python3 -m json.tool; return 1;;
      *)
        echo "Status: $status ... waiting 15s"; sleep 15;;
    esac
  done
}

cmd="${1:-}"; shift || true
case "$cmd" in
  create)
    body="${1:?need json body}"; outdir="${2:-$HOME/clawd}"
    res=$(curl -s --max-time 60 -X POST "$BASE" "${json[@]}" "${auth[@]}" -d "$body")
    echo "$res" | python3 -m json.tool
    tid=$(echo "$res" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    [ -z "$tid" ] && { echo "No task id returned (see error above)."; exit 1; }
    poll_and_download "$tid" "$outdir";;
  status)
    curl -s --max-time 30 -X GET "${BASE}/${1:?need task id}" "${auth[@]}" | python3 -m json.tool;;
  wait)
    poll_and_download "${1:?need task id}" "${2:-$HOME/clawd}";;
  list)
    q="page_num=1&page_size=10"; [ -n "${1:-}" ] && q="${q}&filter.status=$1"
    curl -s --max-time 30 -X GET "${BASE}?${q}" "${auth[@]}" | python3 -m json.tool;;
  delete)
    curl -s --max-time 30 -X DELETE "${BASE}/${1:?need task id}" "${auth[@]}"; echo;;
  *)
    echo "Usage: $0 {create <json>|status <id>|wait <id>|list [status]|delete <id>}"; exit 1;;
esac
