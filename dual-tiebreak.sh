#!/usr/bin/env bash
# dual-tiebreak.sh — PROTOCOL invariant 8: subjective tie -> micro-probe, not
# endless debate. (Previously referenced by dual-review / PROTOCOL / README but
# NEVER IMPLEMENTED — this is that missing "choice (c)".)
#
# For a defended + non-eval-decidable (subjective) tie, opinion cannot settle it,
# so we MEASURE: Grok builds BOTH candidate approaches in isolated worktrees, the
# eval-harness scores each (pass^k on the verify; ties broken by wall-clock), and
# the measured winner is recorded. No opinion, no human mediator.
#
# Writes ledger/TIEBREAK.json.
#
# Usage:
#   ./dual-tiebreak.sh --verify "pytest -q" \
#     --approach-a "use a lookup table" --approach-b "compute iteratively" \
#     [--plan PLAN.md] [--base main] [--issue-id I3] [--eval-k 5] [--max-turns 40]
#     [--model M] [--dry-run]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

PLAN="./PLAN.md"; BASE="main"; VERIFY=""; A_DESC=""; B_DESC=""
ISSUE_ID="tie"; EVAL_K=5; MAX_TURNS=40; MODEL=""; DRYRUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)       PLAN="$2"; shift 2;;
    --base)       BASE="$2"; shift 2;;
    --verify)     VERIFY="$2"; shift 2;;
    --approach-a) A_DESC="$2"; shift 2;;
    --approach-b) B_DESC="$2"; shift 2;;
    --issue-id)   ISSUE_ID="$2"; shift 2;;
    --eval-k)     EVAL_K="$2"; shift 2;;
    --max-turns)  MAX_TURNS="$2"; shift 2;;
    --model)      MODEL="$2"; shift 2;;
    --dry-run)    DRYRUN=true; shift;;
    *) fail "dual-tiebreak: unknown arg '$1'";;
  esac
done
command -v grok >/dev/null 2>&1 || fail "grok CLI not in PATH."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repo."
[[ -f "$PLAN" ]] || fail "Contract missing: $PLAN."
[[ -n "$VERIFY" ]] || fail "--verify is required (the eval is the arbiter)."
[[ -n "$A_DESC" && -n "$B_DESC" ]] || fail "Both --approach-a and --approach-b are required."
git rev-parse --verify "$BASE" >/dev/null 2>&1 || fail "Base branch missing: $BASE."
plan_text="$(tr -d '\r' <"$PLAN")"

tmpdir="$_HERE/.dual-agent/tmp"; ledger="$_HERE/ledger"; mkdir -p "$tmpdir" "$ledger"
stamp="$(utc_stamp)"

info "=== Dual-Agent / Tie-Break Micro-Probe (invariant 8) ==="
log "Issue    : $ISSUE_ID"
log "Verify   : $VERIFY   (eval-k=$EVAL_K)"
log "A        : $A_DESC"
log "B        : $B_DESC"
[[ "$DRYRUN" == true ]] && { warn "DryRun — no calls."; exit 0; }

# Build one candidate: fresh worktree from BASE, Grok renders it, then eval it.
# Prints "<status> <pass_pow_k> <passes> <seconds>". status is HONEST (audit
# finding: failures must never masquerade as a measured 0-score):
#   measured      — build ran AND eval-harness produced a real EVAL json
#   build-failed  — worktree or grok render failed; nothing was measured
#   eval-failed   — eval-harness itself failed to score (not a red test run)
build_and_eval() {
  # Separate statements: in `local a="$1" b="...$a..."` bash expands ALL words
  # BEFORE any assignment happens -> $a would be unbound (set -u error).
  local tag="$1" desc="$2"
  local branch="tie-$ISSUE_ID-$tag-$stamp"
  local wt; wt="$(dirname "$(pwd)")/wt-$branch"
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  git worktree add -b "$branch" "$wt" "$BASE" >/dev/null 2>&1 || { echo "build-failed 0 0 0"; return; }
  local pf="$tmpdir/tiebreak-$tag-$stamp.txt"
  cat > "$pf" <<EOF
You are the BUILDER. Implement the contract below using SPECIFICALLY this approach:
  >>> $desc <<<
Smallest correct implementation. Implementation files only (no test/verify edits).

=== CONTRACT (PLAN.md) ===
$plan_text
EOF
  local build_rc=0
  "$_HERE/lib/grok-call.sh" --prompt-file "$pf" --cwd "$wt" --max-turns "$MAX_TURNS" \
     --always-approve ${MODEL:+--model "$MODEL"} --tag "tiebreak-$tag" >/dev/null 2>&1 || build_rc=$?
  if [[ $build_rc -ne 0 ]]; then
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
    echo "build-failed 0 0 0"; return
  fi
  # measure: pass^k + wall-clock of the verify. eval-harness exits 1 on a RED
  # candidate too, so "did it score?" is judged by the EVAL json, not exit code.
  local evalfile="$ledger/EVAL-tie-$tag.json"
  rm -f "$evalfile"
  local t0 t1 secs
  t0=$(date +%s)
  "$_HERE/lib/eval-harness.sh" --verify "$VERIFY" --k "$EVAL_K" --cwd "$wt" \
     --out "$evalfile" >/dev/null 2>&1 || true
  t1=$(date +%s); secs=$((t1 - t0))
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  if [[ ! -s "$evalfile" ]]; then echo "eval-failed 0 0 0"; return; fi
  local ppk passes
  ppk="$(json_field "$evalfile" pass_pow_k)"
  passes="$(json_field "$evalfile" passes)"
  [[ -z "$ppk" || -z "$passes" ]] && { echo "eval-failed 0 0 0"; return; }
  echo "measured $ppk $passes $secs"
}

log "\n[A] building + measuring approach A ..."
read -r a_st a_ppk a_passes a_secs <<<"$(build_and_eval a "$A_DESC")"
log "[B] building + measuring approach B ..."
read -r b_st b_ppk b_passes b_secs <<<"$(build_and_eval b "$B_DESC")"

# Winner: only MEASURED candidates compete (higher pass^k, then passes, then
# faster). A non-measured candidate loses to a measured one by definition;
# if NEITHER was measured there is no verdict — that is a hard failure.
winner="$(python3 - "$a_st" "$a_ppk" "$a_passes" "$a_secs" "$b_st" "$b_ppk" "$b_passes" "$b_secs" <<'PY'
import sys
ast, ap, aps, asec, bst, bp, bps, bsec = sys.argv[1:9]
am, bm = ast == "measured", bst == "measured"
if not am and not bm: print("none"); raise SystemExit
if am != bm: print("A" if am else "B"); raise SystemExit
a = (int(ap), int(aps), -int(asec)); b = (int(bp), int(bps), -int(bsec))
print("A" if a > b else "B" if b > a else "tie")
PY
)"

python3 - "$ledger/TIEBREAK.json" "$stamp" "$ISSUE_ID" "$winner" \
  "$a_st" "$a_ppk" "$a_passes" "$a_secs" "$b_st" "$b_ppk" "$b_passes" "$b_secs" "$A_DESC" "$B_DESC" <<'PY'
import sys, json
(out, stamp, iid, winner, ast, app, aps, asec, bst, bpp, bps, bsec, adesc, bdesc) = sys.argv[1:15]
open(out,"w").write(json.dumps({
  "stamp":stamp,"issue_id":iid,"winner":winner,
  "A":{"desc":adesc,"status":ast,"pass_pow_k":int(app),"passes":int(aps),"seconds":int(asec)},
  "B":{"desc":bdesc,"status":bst,"pass_pow_k":int(bpp),"passes":int(bps),"seconds":int(bsec)},
}, indent=2))
PY

info "\n=== Tie-Break done ==="
log "  A[$a_st]: pass^k=$a_ppk passes=$a_passes ${a_secs}s   |   B[$b_st]: pass^k=$b_ppk passes=$b_passes ${b_secs}s"
case "$winner" in
  none) fail "NEITHER candidate could be built+measured (A: $a_st, B: $b_st) — no verdict fabricated. Fix the build/eval setup and re-run." ;;
  tie)  warn "  WINNER: tie (both measured equal) — architect picks on other grounds; recorded." ;;
  *)    ok "  WINNER: approach $winner (measured, not argued). ledger/TIEBREAK.json" ;;
esac
exit 0
