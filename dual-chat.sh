#!/usr/bin/env bash
# dual-chat.sh — launch the Dual-Craft Chat Cockpit (professional task UI).
#
# The UI is a LOCAL HTTP server. The terminal must keep running (or use --daemon).
# Open: http://127.0.0.1:8787/   (NOT file://dashboard.html)
#
# Usage:
#   ./dual-chat.sh [--port 8787] [--host 127.0.0.1] [--open|--no-open] [--daemon]
#   ./dual-chat.sh --stop [--port 8787]
#   ./dual-chat.sh --status [--port 8787]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

PORT=8787
HOST=127.0.0.1
OPEN=true
DAEMON=false
ACTION=start
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage "$0"; exit 0;;
    --port) PORT="${2:?value required for $1}"; shift 2;;
    --host) HOST="${2:?value required for $1}"; shift 2;;
    --open) OPEN=true; shift;;
    --no-open) OPEN=false; shift;;
    --daemon|-d) DAEMON=true; shift;;
    --stop) ACTION=stop; shift;;
    --status) ACTION=status; shift;;
    *) fail "dual-chat: unknown arg '$1'";;
  esac
done

command -v python3 >/dev/null 2>&1 || fail "python3 required for the chat UI."
[[ -f "$_HERE/ui/server.py" ]] || fail "ui/server.py missing — pull latest main?"
[[ -f "$_HERE/ui/static/index.html" ]] || fail "ui/static/index.html missing."

URL="http://${HOST}:${PORT}/"
PIDFILE="$_HERE/.dual-agent/chat/dual-chat-${PORT}.pid"
LOGFILE="$_HERE/.dual-agent/chat/dual-chat-${PORT}.log"
mkdir -p "$_HERE/.dual-agent/chat"

health_ok() {
  python3 - "$URL" <<'PY' 2>/dev/null
import sys, urllib.request
url = sys.argv[1].rstrip("/") + "/api/health"
try:
    with urllib.request.urlopen(url, timeout=1.5) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PY
}

port_busy() {
  # true if something accepts TCP on HOST:PORT
  python3 - "$HOST" "$PORT" <<'PY' 2>/dev/null
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket()
s.settimeout(0.4)
try:
    s.connect((host, port))
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
}

open_browser() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
  else
    warn "Open manually: $url"
  fi
}

if [[ "$ACTION" == status ]]; then
  if health_ok; then
    ok "Chat cockpit is UP at $URL"
    [[ -f "$PIDFILE" ]] && log "pid file: $PIDFILE ($(cat "$PIDFILE" 2>/dev/null))"
    exit 0
  fi
  warn "Chat cockpit is DOWN ($URL not responding)."
  exit 1
fi

if [[ "$ACTION" == stop ]]; then
  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$pid" 2>/dev/null || true
      ok "Stopped dual-chat pid $pid"
    else
      warn "Stale pid file (process not running)."
    fi
    rm -f "$PIDFILE"
  else
    # best-effort: kill listeners on port via python / fuser
    if command -v fuser >/dev/null 2>&1; then
      fuser -k "${PORT}/tcp" 2>/dev/null || true
    fi
    warn "No pid file at $PIDFILE — if still running, kill the python ui/server.py process."
  fi
  exit 0
fi

# Already running?
if health_ok; then
  ok "Already running → $URL"
  [[ "$OPEN" == true ]] && open_browser "$URL"
  log "Tip: leave that process running, or use: ./dual-chat.sh --stop"
  exit 0
fi

if port_busy; then
  fail "Port ${PORT} is in use by something that is NOT dual-chat health.\n  Try: ./dual-chat.sh --port 8790\n  Or:  ./dual-chat.sh --stop --port ${PORT}"
fi

info "=== Dual-Craft Chat Cockpit ==="
log "repo : $_HERE"
log "url  : $URL"
log "bind : ${HOST}:${PORT} (local only)"
log "note : keep this terminal open  —  OR use --daemon"
log "stop : ./dual-chat.sh --stop"

start_server() {
  export PYTHONUNBUFFERED=1
  # shellcheck disable=SC2086
  python3 -u "$_HERE/ui/server.py" --host "$HOST" --port "$PORT" --root "$_HERE"
}

wait_ready() {
  local i
  for ((i=1; i<=40; i++)); do
    if health_ok; then return 0; fi
    sleep 0.1
  done
  return 1
}

if [[ "$DAEMON" == true ]]; then
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    ok "Daemon already pid $(cat "$PIDFILE") → $URL"
    [[ "$OPEN" == true ]] && open_browser "$URL"
    exit 0
  fi
  export PYTHONUNBUFFERED=1
  nohup python3 -u "$_HERE/ui/server.py" --host "$HOST" --port "$PORT" --root "$_HERE" \
    >"$LOGFILE" 2>&1 &
  echo $! >"$PIDFILE"
  if wait_ready; then
    ok "Daemon started pid $(cat "$PIDFILE") → $URL"
    log "logs: $LOGFILE"
    [[ "$OPEN" == true ]] && open_browser "$URL"
    exit 0
  fi
  warn "Server did not become healthy. Last log lines:"
  tail -30 "$LOGFILE" 2>/dev/null || true
  rm -f "$PIDFILE"
  fail "dual-chat daemon failed to start — see $LOGFILE"
fi

# Foreground: wait for ready then open browser in background
if [[ "$OPEN" == true ]]; then
  (
    if wait_ready; then
      open_browser "$URL"
    fi
  ) &
fi

# Ensure pid file for --stop even in foreground (cleaned on EXIT)
start_server &
SPID=$!
echo "$SPID" >"$PIDFILE"
trap 'rm -f "$PIDFILE"; kill "$SPID" 2>/dev/null || true' EXIT INT TERM

if ! wait_ready; then
  warn "Server slow to respond — still starting. Open: $URL"
fi

# Wait on server process
wait "$SPID"
ec=$?
rm -f "$PIDFILE"
exit "$ec"
