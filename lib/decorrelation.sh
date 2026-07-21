#!/usr/bin/env bash
# decorrelation.sh — cross-vendor decorrelation telemetry (is the moat alive?).
#
# The whole point of two vendors (Claude reviewer != Grok builder) is
# UNCORRELATED errors. If Grok concedes every issue Claude raises, the two have
# collapsed into one opinion (sycophancy / capability convergence) and the
# second vendor stops earning its cost. Reads the latest ledger/REVIEW.json,
# computes a disagreement rate, appends to DECORRELATION.jsonl, warns when low.
#
#   disagreement = 1 - conceded/raised   (high = healthy; ~0 = converging)
#
# Usage: lib/decorrelation.sh [--review FILE] [--warn-below 0.15]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

REVIEW=""; WARN_BELOW="0.15"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --review)     REVIEW="$2"; shift 2;;
    --warn-below) WARN_BELOW="$2"; shift 2;;
    *) fail "decorrelation: unknown arg '$1'";;
  esac
done
[[ -z "$REVIEW" ]] && REVIEW="$(repo_root)/ledger/REVIEW.json"
if [[ ! -f "$REVIEW" ]]; then log "decorrelation: no REVIEW.json yet (run dual-review first)."; exit 0; fi

ledger="$(dirname "$REVIEW")"; mkdir -p "$ledger"
read -r raised conceded disagreement stamp < <(python3 - "$REVIEW" <<'PY'
import sys, json
r = json.load(open(sys.argv[1], encoding="utf-8"))
raised = len(r.get("issues", []) or [])
conceded = len(r.get("conceded", []) or [])
dis = round(1 - conceded/raised, 3) if raised > 0 else 0
print(raised, conceded, dis, r.get("stamp", ""))
PY
)

python3 - "$ledger/DECORRELATION.jsonl" "$stamp" "$raised" "$conceded" "$disagreement" <<'PY'
import sys, json
out, stamp, raised, conceded, dis = sys.argv[1:6]
rec = {"stamp": stamp, "raised": int(raised), "conceded": int(conceded), "disagreement": float(dis)}
open(out, "a", encoding="utf-8").write(json.dumps(rec) + "\n")
PY

printf 'decorrelation: raised=%s conceded=%s disagreement=%s\n' "$raised" "$conceded" "$disagreement"
if [[ "$raised" -gt 0 ]] && awk -v d="$disagreement" -v w="$WARN_BELOW" 'BEGIN{exit !(d<w)}'; then
  warn "low cross-vendor disagreement -> vendors converging, moat weakening. Increase prompt/temperature diversity or re-evaluate the second vendor."
fi
exit 0
