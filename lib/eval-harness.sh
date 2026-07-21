#!/usr/bin/env bash
# eval-harness.sh — graded acceptance scorer for the merge gate (pass@k / pass^k).
#
# Runs a verify command K times and reports two metrics, grounded in tau-bench
# (Yao et al. 2024): pass@k (>=1 of K passed -> CAN solve it) and pass^k (ALL K
# passed -> solves it RELIABLY, the honest merge criterion). "Green once" is NOT
# "done". This is the objective referee that decides merges and breaks debate
# ties, so neither agent can win by rhetoric.
#
# Writes EVAL.json (UTF-8) and prints a summary line. Exit 0 if pass^k==1 under
# the strict threshold, else 1 -- so a caller can gate on the exit code too.
#
# Usage:
#   lib/eval-harness.sh --verify "pytest -q" --k 5 --cwd "$WT" [--threshold 1.0] [--out FILE]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

VERIFY=""; K=5; CWD="$(pwd)"; THRESHOLD="1.0"; OUTFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)    VERIFY="$2"; shift 2;;
    --k)         K="$2"; shift 2;;
    --cwd)       CWD="$2"; shift 2;;
    --threshold) THRESHOLD="$2"; shift 2;;
    --out)       OUTFILE="$2"; shift 2;;
    *) fail "eval-harness: unknown arg '$1'";;
  esac
done
[[ -n "$VERIFY" ]] || fail "eval-harness: --verify is required."
# Setup errors must surface distinctly, not masquerade as K red test runs
# (audit finding: bad --cwd looked identical to a genuinely failing candidate).
[[ -d "$CWD" ]] || fail "eval-harness: --cwd does not exist: $CWD (setup error, NOT a red run)."
[[ "$K" -ge 1 ]] 2>/dev/null || K=1

passes=0
early_stopped=false
runs_executed=0
runs_json="[]"

# strict gate == threshold >= 1.0 (float compare via awk).
strict=$(awk -v t="$THRESHOLD" 'BEGIN{print (t>=1.0)?1:0}')

for (( i=1; i<=K; i++ )); do
  ( cd "$CWD" && eval "$VERIFY" ) >/dev/null 2>&1
  code=$?
  runs_executed=$((runs_executed+1))
  pass=false
  if [[ $code -eq 0 ]]; then passes=$((passes+1)); pass=true; fi
  runs_json=$(python3 - "$runs_json" "$i" "$code" "$pass" <<'PY'
import sys, json
runs = json.loads(sys.argv[1]); runs.append({"run": int(sys.argv[2]), "exit": int(sys.argv[3]), "pass": sys.argv[4]=="true"})
print(json.dumps(runs))
PY
)
  # Lossless early-stop: under the strict pass^k gate a single red already forces
  # pass_pow_k=0 -- no remaining run can change the verdict. Saves up to (K-1)/K
  # verify runs on every failing build; the merge decision is bit-identical.
  if [[ "$pass" == false && "$strict" == 1 ]]; then early_stopped=true; break; fi
done

# Compute metrics with python for clean float handling + JSON write.
[[ -z "$OUTFILE" ]] && { ledger="$(repo_root)/ledger"; mkdir -p "$ledger"; OUTFILE="$ledger/EVAL.json"; }
read -r rate pass_at_k pass_pow_k score_ok < <(python3 - "$passes" "$K" "$THRESHOLD" <<'PY'
import sys
passes, k, thr = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
rate = round(passes / k, 4)
print(rate, int(passes>=1), int(passes==k), int(rate>=thr))
PY
)

python3 - "$OUTFILE" "$VERIFY" "$K" "$passes" "$rate" "$pass_at_k" "$pass_pow_k" \
  "$THRESHOLD" "$score_ok" "$runs_json" "$runs_executed" "$early_stopped" "$(iso_now)" <<'PY'
import sys, json
(out, verify, k, passes, rate, pak, ppk, thr, sok, runs, rexec, early, stamp) = sys.argv[1:14]
obj = {
  "verify": verify, "k": int(k), "passes": int(passes), "rate": float(rate),
  "pass_at_k": int(pak), "pass_pow_k": int(ppk), "threshold": float(thr),
  "score_ok": bool(int(sok)), "runs": json.loads(runs),
  "runs_executed": int(rexec), "early_stopped": early == "true", "stamp": stamp,
}
open(out, "w", encoding="utf-8").write(json.dumps(obj, indent=2))
PY

if [[ "$pass_pow_k" == 1 ]]; then col="$C_GREEN"
elif [[ "$pass_at_k" == 1 ]]; then col="$C_YELLOW"
else col="$C_RED"; fi
printf '%seval: %s/%s passed  rate=%s  pass@k=%s  pass^k=%s  score_ok=%s%s\n' \
  "$col" "$passes" "$K" "$rate" "$pass_at_k" "$pass_pow_k" "$score_ok" "$C_RESET"

[[ "$pass_pow_k" == 1 ]] && exit 0 || exit 1
