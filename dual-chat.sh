#!/usr/bin/env bash
# dual-chat.sh — launch the Dual-Craft Chat Cockpit (professional task UI).
#
# Localhost-only HTTP UI that accepts plain-language tasks and drives dual-run.sh
# (Claude + Grok + Codex team path). No API keys stored in the UI.
#
# Usage:
#   ./dual-chat.sh [--port 8787] [--host 127.0.0.1] [--open] [--no-open]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

PORT=8787
HOST=127.0.0.1
OPEN=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage "$0"; exit 0;;
    --port) PORT="${2:?value required for $1}"; shift 2;;
    --host) HOST="${2:?value required for $1}"; shift 2;;
    --open) OPEN=true; shift;;
    --no-open) OPEN=false; shift;;
    *) fail "dual-chat: unknown arg '$1'";;
  esac
done

command -v python3 >/dev/null 2>&1 || fail "python3 required for the chat UI."
[[ -f "$_HERE/ui/server.py" ]] || fail "ui/server.py missing."
[[ -f "$_HERE/ui/static/index.html" ]] || fail "ui/static/index.html missing."

info "=== Dual-Craft Chat Cockpit ==="
log "repo : $_HERE"
log "url  : http://${HOST}:${PORT}/"
log "bind : ${HOST} (local only by default)"

if [[ "$OPEN" == true ]]; then
  (
    sleep 0.6
    url="http://${HOST}:${PORT}/"
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1
    elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1
    fi
  ) &
fi

exec python3 "$_HERE/ui/server.py" --host "$HOST" --port "$PORT" --root "$_HERE"
