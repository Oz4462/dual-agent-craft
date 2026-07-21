#!/usr/bin/env bash
# dual-view.sh — split-screen cockpit for the dual-agent workflow (tmux).
#
# The Linux/macOS replacement for the Windows-Terminal (`wt`) cockpit. Opens a
# tmux window with two panes:
#   left  : Claude Code (architect/reviewer) — where you work with Claude.
#   right : Grok's live build log (watch-grok.sh) — you watch Grok build the
#           moment Claude triggers dual-build.sh.
# With --grok the right pane is an INTERACTIVE grok session instead.
#
# Usage: ./dual-view.sh [--grok]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

RIGHT_GROK=false
[[ "${1:-}" == "--grok" ]] && RIGHT_GROK=true

if ! command -v tmux >/dev/null 2>&1; then
  warn "tmux not found. Install it (e.g. 'sudo apt install tmux') or open two terminals manually:"
  log "  left : claude"
  log "  right: $([[ "$RIGHT_GROK" == true ]] && echo grok || echo "$_HERE/watch-grok.sh")"
  exit 1
fi

session="dual-agent"
right_cmd="$_HERE/watch-grok.sh"
[[ "$RIGHT_GROK" == true ]] && right_cmd="grok"

tmux kill-session -t "$session" 2>/dev/null || true
tmux new-session -d -s "$session" -c "$_HERE" -n cockpit "claude"
tmux split-window -h -t "$session:cockpit" -c "$_HERE" "$right_cmd"
tmux select-pane -t "$session:cockpit.0"
ok "Split-view started (left Claude / right $([[ "$RIGHT_GROK" == true ]] && echo Grok || echo Grok-Live-Log))."
tmux attach -t "$session"
