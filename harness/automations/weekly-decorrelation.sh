#!/usr/bin/env bash
# weekly-decorrelation.sh — moat trend: average disagreement over the ledger.
set -uo pipefail; export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
f="ledger/DECORRELATION.jsonl"
[[ -f "$f" ]] || { echo "no decorrelation ledger yet"; exit 0; }
python3 - "$f" <<'PY'
import sys, json
vals = []
for line in open(sys.argv[1], encoding="utf-8"):
    try: vals.append(float(json.loads(line)["disagreement"]))
    except Exception: continue
if not vals: print("no data"); raise SystemExit
avg = sum(vals)/len(vals)
print(f"reviews={len(vals)} avg_disagreement={avg:.3f} last={vals[-1]:.3f}")
if avg < 0.15: print("WARN: moat weakening — vendors converging (see decorrelation.sh)")
PY
