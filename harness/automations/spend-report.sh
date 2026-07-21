#!/usr/bin/env bash
# spend-report.sh — weekly spend rollup from the ledger (honours DUAL_AGENT_SPEND_FILE).
set -uo pipefail; export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SPEND="${DUAL_AGENT_SPEND_FILE:-ledger/SPEND.jsonl}"
[[ -f "$SPEND" ]] || { echo "no spend ledger at $SPEND"; exit 0; }
python3 - "$SPEND" <<'PY'
import sys, json, collections
tot = collections.defaultdict(float); month = collections.defaultdict(float)
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line); c = float(e.get("cost_usd") or 0)
    except Exception: continue
    tot[e.get("tag","?")] += c
    month[str(e.get("stamp",""))[:6]] += c
print("== spend by tag =="); [print(f"  {k:24s} {v:8.2f} USD") for k,v in sorted(tot.items(), key=lambda x:-x[1])]
print("== spend by month =="); [print(f"  {k:24s} {v:8.2f} USD") for k,v in sorted(month.items())]
PY
