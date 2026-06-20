#!/usr/bin/env bash
# Serve built OpenClaw installer archives over LAN HTTP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../install-openclaw.sh" ]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT="$SCRIPT_DIR"
fi
SERVE_DIR="${SERVE_DIR:-$ROOT/upload-packages}"
PORT="${PORT:-8765}"
BIND="${BIND:-0.0.0.0}"
STATE_DIR="$ROOT/.server"
PID_FILE="$STATE_DIR/http-server.pid"
LOG_FILE="$STATE_DIR/http-server.log"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

if [ ! -d "$SERVE_DIR" ]; then
  echo "Missing upload package directory: $SERVE_DIR" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
    log "HTTP server already running: pid $old_pid"
  else
    rm -f "$PID_FILE"
  fi
fi

if [ ! -f "$PID_FILE" ]; then
  log "Starting HTTP server for $SERVE_DIR on $BIND:$PORT"
  nohup python3 -m http.server "$PORT" --bind "$BIND" --directory "$SERVE_DIR" >"$LOG_FILE" 2>&1 &
  echo "$!" > "$PID_FILE"
  sleep 1
fi

pid="$(cat "$PID_FILE")"
if ! kill -0 "$pid" >/dev/null 2>&1; then
  echo "HTTP server failed to start. Log: $LOG_FILE" >&2
  exit 1
fi

log "HTTP server pid: $pid"
log "Log: $LOG_FILE"
log "Candidate URLs:"

printed=0
for iface in en0 en1 bridge100; do
  ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  if [ -n "$ip" ]; then
    printf '  http://%s:%s/\n' "$ip" "$PORT"
    printed=1
  fi
done

if [ "$printed" = "0" ]; then
  printf '  http://<this-mac-ip>:%s/\n' "$PORT"
fi

log "Stop with: kill \$(cat $PID_FILE)"
