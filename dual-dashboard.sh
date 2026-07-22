#!/usr/bin/env bash
# dual-dashboard.sh — generate the harness cockpit (self-contained HTML) from the
# live ledger. Reads ledger/*.json + git state, writes dashboard.html. Zero tokens,
# offline, theme-aware. Open the file in any browser.
#
# Usage:
#   ./dual-dashboard.sh [--out dashboard.html] [--open]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

OUT="$_HERE/dashboard.html"; OPEN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage "$0"; exit 0;;
    --out)     OUT="${2:?value required for $1}"; shift 2;;
    --open)    OPEN=true; shift;;
    *) fail "dual-dashboard: unknown arg '$1'";;
  esac
done

ledger="$_HERE/ledger"
[[ -d "$ledger" ]] || { mkdir -p "$ledger"; warn "no ledger yet — the dashboard will show an empty cockpit."; }

# --- gather git/suite/spend state (deterministic) --------------------------
branch="$(git -C "$_HERE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
has_plan=false; [[ -f "$_HERE/PLAN.md" ]] && has_plan=true
poc_branch=""; git -C "$_HERE" rev-parse --verify feat/poc >/dev/null 2>&1 && poc_branch="feat/poc"
harden_branch=""; git -C "$_HERE" rev-parse --verify feat/harden >/dev/null 2>&1 && harden_branch="feat/harden"
# suite count is best-effort: read a cached marker if present (never run the slow suite here).
suite="${DUAL_DASHBOARD_SUITE:-}"
repo="$(basename "$_HERE")"

state_json="$(mktemp)"
python3 - "$state_json" "$branch" "$has_plan" "$poc_branch" "$harden_branch" "$suite" "$repo" "$(iso_now)" <<'PY'
import sys, json
(out, branch, has_plan, poc, harden, suite, repo, stamp) = sys.argv[1:9]
json.dump({
  "branch": branch, "has_plan": has_plan == "true",
  "poc_branch": poc or None, "harden_branch": harden or None,
  "suite": suite or None, "repo": repo, "stamp": stamp,
}, open(out, "w"))
PY

# --- render ----------------------------------------------------------------
if python3 "$_HERE/harness/lib/dashboard_render.py" "$ledger" "$state_json" > "$OUT"; then
  rm -f "$state_json"
  bytes=$(wc -c < "$OUT" | tr -d ' ')
  ok "dashboard written -> $OUT (${bytes} bytes, self-contained)"
  log "  open it: file://$OUT"
  if [[ "$OPEN" == true ]]; then
    (command -v xdg-open >/dev/null 2>&1 && xdg-open "$OUT" 2>/dev/null &) || \
    (command -v open >/dev/null 2>&1 && open "$OUT" 2>/dev/null &) || \
    warn "no opener found — open $OUT manually."
  fi
else
  rm -f "$state_json"
  fail "dashboard render failed."
fi
