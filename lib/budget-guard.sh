#!/usr/bin/env bash
# budget-guard.sh — fail BLOCKED before the headless credit pool is exhausted.
#
# Sums this month's metered Claude spend from ledger/SPEND.jsonl (written by
# claude-call.sh) and refuses to proceed if spent+estimate would exceed
# cap*safety. Converts the "requests silently STOP mid-merge" failure into a
# clean early BLOCKED. Refuses only; never weakens a call -> quality-neutral.
#
# Exit 0 = within budget, exit 2 = BLOCKED.
#
# Usage: lib/budget-guard.sh [--cap 100] [--safety 0.9] [--estimate 0] [--spend-file FILE]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

CAP=100; SAFETY=0.9; ESTIMATE=0; SPEND_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cap)        CAP="$2"; shift 2;;
    --safety)     SAFETY="$2"; shift 2;;
    --estimate)   ESTIMATE="$2"; shift 2;;
    --spend-file) SPEND_FILE="$2"; shift 2;;
    *) fail "budget-guard: unknown arg '$1'";;
  esac
done
[[ -z "$SPEND_FILE" ]] && SPEND_FILE="$(repo_root)/ledger/SPEND.jsonl"

MONTH="$(date -u +%Y%m)"
read -r spent limit would ok < <(python3 - "$SPEND_FILE" "$MONTH" "$CAP" "$SAFETY" "$ESTIMATE" <<'PY'
import sys, json, os
path, month, cap, safety, est = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
spent = 0.0
if os.path.exists(path):
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        stamp = str(e.get("stamp", ""))
        # stamp is either 20260721-... (utc_stamp) or ISO 2026-07-21T...; normalise to YYYYMM
        ym = stamp[:6] if stamp[:6].isdigit() else stamp[:7].replace("-", "")
        if ym == month and e.get("cost_usd") is not None:
            spent += float(e["cost_usd"])
limit = cap * safety
would = spent + est
print(round(spent,4), round(limit,4), round(would,4), int(would <= limit))
PY
)

if [[ "$ok" == 1 ]]; then col="$C_GREEN"; status="OK"; else col="$C_RED"; status="BLOCKED"; fi
printf '%sbudget-guard [%s]: spent=%.2f + est=%.2f = %.2f USD  vs limit=%.2f (cap=%s x %s) -> %s%s\n' \
  "$col" "$MONTH" "$spent" "$ESTIMATE" "$would" "$limit" "$CAP" "$SAFETY" "$status" "$C_RESET"

if [[ "$ok" != 1 ]]; then
  over=$(awk -v w="$would" -v l="$limit" 'BEGIN{printf "%.2f", w-l}')
  warn "would exceed budget by $over USD. Raise --cap or wait for the monthly reset."
  exit 2
fi
exit 0
