#!/usr/bin/env bash
# dual-status.sh — deterministic doctor / status for the harness (zero tokens).
#
# One glance at: which CLIs are present, the latest ledger verdicts, this month's
# spend, and leftover state (stray wt-* worktrees, dirty tree, red-suite flag).
# Never mutates anything. Exit 0 always (it's a report, not a gate).
#
# Usage:
#   ./dual-status.sh
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

[[ "${1:-}" =~ ^(-h|--help)$ ]] && { usage "$0"; exit 0; }

info "=== dual-agent status ==="

# --- doctor: CLIs + tooling -------------------------------------------------
log "\n[doctor] tooling"
for c in git python3 curl claude grok codex ollama tmux bats shellcheck; do
  if command -v "$c" >/dev/null 2>&1; then
    ok "  ok    $c"
  else
    warn "  --    $c (not installed)"
  fi
done

# --- ledger verdicts --------------------------------------------------------
log "\n[ledger] latest verdicts"
led="$_HERE/ledger"
if [[ -d "$led" ]]; then
  for j in REVIEW EVAL IMPORT-SCAN TEST-GUARD TIEBREAK; do
    f="$led/$j.json"
    if [[ -f "$f" ]]; then
      v="$(json_field "$f" verdict)"; [[ -z "$v" ]] && v="$(json_field "$f" winner)"
      [[ -z "$v" ]] && v="$(json_field "$f" pass_pow_k)"
      s="$(json_field "$f" stamp)"
      printf '  %-12s %-18s %s\n' "$j" "${v:-?}" "${s:-}"
    else
      printf '  %-12s %s\n' "$j" "(none yet)"
    fi
  done
else
  log "  (no ledger/ yet — nothing has run)"
fi

# --- spend (this month) -----------------------------------------------------
spend="${DUAL_AGENT_SPEND_FILE:-$led/SPEND.jsonl}"
if [[ -f "$spend" ]]; then
  month="$(date -u +%Y%m)"
  total="$(SPEND="$spend" MONTH="$month" python3 -c '
import os, json
tot=0.0
for line in open(os.environ["SPEND"], encoding="utf-8"):
    line=line.strip()
    if not line: continue
    try:
        e=json.loads(line); st=str(e.get("stamp",""))
        ym=st[:6] if st[:6].isdigit() else st[:7].replace("-","")
        if ym==os.environ["MONTH"] and e.get("cost_usd") is not None: tot+=float(e["cost_usd"])
    except Exception: pass
print(f"{tot:.2f}")')"
  log "\n[spend] $month: \$$total USD (ledger: $spend)"
else
  log "\n[spend] no ledger yet"
fi

# --- hygiene ----------------------------------------------------------------
log "\n[hygiene]"
if git -C "$_HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$_HERE" rev-parse --abbrev-ref HEAD)"
  dirty="$(git -C "$_HERE" status --porcelain | wc -l | tr -d ' ')"
  strays="$(git -C "$_HERE" worktree list 2>/dev/null | grep -c '/wt-' || true)"
  printf '  branch: %s | dirty files: %s | stray wt-* worktrees: %s\n' "$branch" "$dirty" "$strays"
  [[ "$strays" -gt 0 ]] && warn "  leftover wt-* worktrees — 'git worktree prune' or remove them."
else
  log "  (not a git repo)"
fi
flag="$_HERE/.dual-agent/SUITE-RED.flag"
[[ -f "$flag" ]] && warn "  SUITE-RED flag present: $(cat "$flag")" || ok "  no red-suite flag"

exit 0
