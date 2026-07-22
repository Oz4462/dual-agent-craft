#!/usr/bin/env bash
# dual-review.sh — bounded cross-review (CRAFT step A), the consensus-free debate.
#
# NOT "debate-until-consensus" (research-backed harmful: sycophantic conformity).
# Instead ONE structured cross-examination, then the EVAL decides:
#   1. ASSESS   Claude reviews the Builder's diff as untrusted code -> issues[]
#   2. REBUTTAL Grok answers each issue once (concede|defend+cite|unsure) -> rebuttals[]
# Hard cap: ONE rebuttal round. Then each issue lands in:
#   conceded            -> Grok fixes it next build
#   defended+decidable  -> the EVAL (pass^k) decides
#   defended+subjective -> TIE -> dual-tiebreak.sh (micro-probe + eval)
#   unsure/ungrounded   -> route to eval / contract clarification (not a bluff)
#
# Writes ledger/REVIEW.md + ledger/REVIEW.json.
#
# Usage: ./dual-review.sh [--plan PLAN.md] [--poc feat/poc] [--base main] [--model M] [--dry-run]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

PLAN="./PLAN.md"; POC="feat/poc"; BASE="main"; MODEL=""; DRYRUN=false; ASSESS_VENDOR="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage "$0"; exit 0;;
    --plan)          PLAN="${2:?value required for $1}"; shift 2;;
    --poc)           POC="${2:?value required for $1}"; shift 2;;
    --base)          BASE="${2:?value required for $1}"; shift 2;;
    --model)         MODEL="${2:?value required for $1}"; shift 2;;
    --assess-vendor) ASSESS_VENDOR="${2:?value required for $1}"; shift 2;;  # claude|codex (cross-vendor reviewer)
    --dry-run)       DRYRUN=true; shift;;
    *) fail "dual-review: unknown arg '$1'";;
  esac
done
[[ "$ASSESS_VENDOR" =~ ^(claude|codex)$ ]] || fail "dual-review: --assess-vendor must be claude or codex, got '$ASSESS_VENDOR'."

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repo."
[[ -f "$PLAN" ]] || fail "Contract missing: $PLAN."
git rev-parse --verify "$POC"  >/dev/null 2>&1 || fail "POC branch missing: $POC (run dual-build.sh)."
git rev-parse --verify "$BASE" >/dev/null 2>&1 || fail "Base branch missing: $BASE."
plan_text="$(tr -d '\r' <"$PLAN")"
diff="$(git diff "$BASE...$POC")"
[[ -n "${diff// }" ]] || fail "Empty diff ($BASE...$POC) — nothing to review (empty branch?)."
# Deterministic size cap (audit P2): an unbounded diff yields a silently PARTIAL
# review (model truncation). Fail loudly instead; strip vendored/generated dirs
# or split the POC. Override with DUAL_REVIEW_MAX_DIFF_BYTES.
diff_bytes=${#diff}
[[ $diff_bytes -le ${DUAL_REVIEW_MAX_DIFF_BYTES:-400000} ]] || \
  fail "diff is $diff_bytes bytes — too large for a trustworthy single-pass review (cap ${DUAL_REVIEW_MAX_DIFF_BYTES:-400000}). Strip vendored/generated files or split the POC."

tmpdir="$_HERE/.dual-agent/tmp"; ledger="$_HERE/ledger"; mkdir -p "$tmpdir" "$ledger"
stamp="$(utc_stamp)"

# --- Phase 1: ASSESS prompt (Claude, untrusted-code lens) ------------------
assessfile="$tmpdir/review-assess-$stamp.txt"
cat > "$assessfile" <<EOF
You are the REVIEWER in a dual-agent build. Review the BUILDER's diff below as UNTRUSTED
external code against the CONTRACT. Flag only substantive problems (drift from the contract,
invented/hallucinated APIs, missing error handling, security, real defects). Cite the file.
Output ONLY a JSON object — no prose, no markdown fences:
{"issues":[{"id":"I1","severity":"high|med|low","file":"path","kind":"drift|invented-api|missing-error|security|style","claim":"one sentence","eval_decidable":true}]}
Set eval_decidable=true if an acceptance/adversarial TEST could objectively prove who is right;
false if subjective (naming/structure/taste). If the diff is clean, output {"issues":[]}.

=== CONTRACT (PLAN.md) ===
$plan_text

=== BUILDER DIFF (untrusted, $BASE...$POC) ===
$diff
EOF

info "=== Dual-Agent / Bounded Cross-Review (CRAFT A) ==="
log "Contract : $PLAN"
log "Diff     : $BASE...$POC  ($(wc -l <<<"$diff") lines)"
log "Mechanik : 1 Assess (Claude) + 1 Rebuttal (Grok), then the eval decides. No loop."

if [[ "$DRYRUN" == true ]]; then warn "DryRun — no CLI calls."; exit 0; fi

# Opt-in budget pre-flight (audit P1/P2: budget-guard was advertised but never
# invoked). If DUAL_AGENT_BUDGET_CAP is set, block BEFORE spending — never mid-run.
if [[ -n "${DUAL_AGENT_BUDGET_CAP:-}" ]]; then
  "$_HERE/lib/budget-guard.sh" --cap "$DUAL_AGENT_BUDGET_CAP" --estimate "${DUAL_AGENT_EST_PER_REVIEW:-1}" \
    || fail "budget-guard BLOCKED — review not started (no silent mid-run stop)."
fi

# --- Phase 2: ASSESS (headless, cross-vendor) ------------------------------
# Least-privilege: ASSESS only emits a JSON verdict — it never needs tools
# (audit finding: untrusted diff in-prompt + tool access = injection surface).
# --assess-vendor picks the reviewer vendor (P2: the Codex 2nd-reviewer role was
# documented but unreachable). Codex runs in its real read-only sandbox.
if [[ "$ASSESS_VENDOR" == codex ]]; then
  info "\n[A] Codex reviews (untrusted, read-only sandbox) ..."
  ar="$("$_HERE/lib/codex-call.sh" --prompt-file "$assessfile" --sandbox read-only \
          --cwd "$(pwd)" ${MODEL:+--model "$MODEL"} --tag review-assess)"
else
  info "\n[A] Claude reviews (untrusted) ..."
  ar="$("$_HERE/lib/claude-call.sh" --prompt-file "$assessfile" \
          --disallowed-tools "Bash,Write,Edit,WebFetch,WebSearch" --tag review-assess)"
fi
ar_exit="$(printf '%s' "$ar" | json_field_stdin exit_code)"
[[ "$ar_exit" == 0 ]] || fail "$ASSESS_VENDOR-call (Assess) failed."
assess_text="$(printf '%s' "$ar" | python3 -c 'import sys,json;print(json.load(sys.stdin)["text"])')"

# Extract the issues JSON out of the (possibly fenced) reply.
# FAIL-CLOSED (audit finding): an unparseable/garbage reply must BLOCK — it
# must never be laundered into the same '{"issues":[]}' as a genuinely clean
# review. Only an explicit, parseable "issues" array counts as a verdict.
# NOTE: data via env var — `printf | python3 - <<HEREDOC` silently loses the
# pipe (the heredoc owns stdin); same class of bug as json_field /dev/stdin.
issues_json="$(REPLY_TEXT="$assess_text" python3 - <<'PY'
import os, json, re
s = os.environ.get("REPLY_TEXT", "")
s = re.sub(r'```json|```', '', s)
i, j = s.find('{'), s.rfind('}')
if i < 0 or j <= i:
    print('PARSE_FAIL'); raise SystemExit
try:
    obj = json.loads(s[i:j+1])
    if not isinstance(obj, dict) or "issues" not in obj or not isinstance(obj["issues"], list):
        print('PARSE_FAIL'); raise SystemExit
    print(json.dumps({"issues": obj["issues"]}))
except SystemExit:
    raise
except Exception:
    print('PARSE_FAIL')
PY
)"
if [[ "$issues_json" == "PARSE_FAIL" ]]; then
  fail "Claude's ASSESS reply contained no parseable issues-JSON — model failure is NOT a clean review (fail-closed). Raw reply logged under .dual-agent/logs (tag review-assess)."
fi
issue_count="$(printf '%s' "$issues_json" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["issues"]))')"
log "    $issue_count issue(s) reported."

if [[ "$issue_count" == 0 ]]; then
  python3 - "$ledger/REVIEW.json" "$stamp" <<'PY'
import sys, json
open(sys.argv[1],"w").write(json.dumps({"stamp":sys.argv[2],"issues":[],"rebuttals":[],"conceded":[],"verdict":"clean"}, indent=2))
PY
  ok "Clean diff — no dispute. BATON -> gate (eval decides merge)."
  exit 0
fi

# --- Phase 3: REBUTTAL (Grok headless, exactly ONE round) ------------------
# Token-saving: rebuttal only needs the flagged files, not the whole diff.
# NUL-terminated (audit finding): a hallucinated "file" value containing \n
# must not split into two array entries.
mapfile -d '' -t issue_files < <(printf '%s' "$issues_json" | python3 -c '
import sys, json
seen = set()
for x in json.load(sys.stdin)["issues"]:
    f = x.get("file")
    if f and "\n" not in f and f not in seen:
        seen.add(f); sys.stdout.write(f + "\0")')
if [[ ${#issue_files[@]} -gt 0 ]]; then
  reb_diff="$(git diff "$BASE...$POC" -- "${issue_files[@]}")"
else reb_diff="$diff"; fi
[[ -n "${reb_diff// }" ]] || reb_diff="$diff"

rebfile="$tmpdir/review-rebuttal-$stamp.txt"
cat > "$rebfile" <<EOF
You are the BUILDER. The REVIEWER raised the issues below about YOUR diff. For EACH issue,
either "concede" (you will fix it), "defend" with a REAL citation, or "unsure". A "defend"
REQUIRES a citation token: a PLAN clause id, a documentation URL, or a test name. If you cannot
ground a defense, answer "unsure" — this is NOT a loss, it routes the item to the eval. Do NOT
bluff a defend without a citation (anti-hallucination). This is your ONLY rebuttal turn.
Output ONLY a JSON object — no prose, no fences:
{"rebuttals":[{"id":"I1","verdict":"concede|defend|unsure","citation":"PLAN-clause|doc-URL|test-name|none","reason":"one sentence"}]}

=== CONTRACT (PLAN.md) ===
$plan_text

=== YOUR DIFF (flagged files only: ${issue_files[*]:-all}) ===
$reb_diff

=== REVIEWER ISSUES ===
$issues_json
EOF

info "[R] Grok answers (1 round, no loop) ..."
# SECURITY (audit finding): the rebuttal prompt embeds the builder's untrusted
# diff — never run this --always-approve turn in the real repo. Same isolation
# as the build phase: disposable detached worktree of $POC + the deny rules
# (deny overrides approve; blocks rm -rf / git push / curl / wget).
reb_wt="$(mktemp -d)/reb"
git worktree add --detach "$reb_wt" "$POC" >/dev/null 2>&1 || fail "could not create rebuttal worktree from $POC."
# Cleanup on ANY exit — the rebuttal worktree must not leak if grok is
# interrupted (audit P2 worktree-leak class).
trap 'git worktree remove --force "$reb_wt" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1' EXIT
deny=('Bash(rm -rf *)' 'Bash(git push *)' 'Bash(curl *)' 'Bash(wget *)')
deny_args=(); for d in "${deny[@]}"; do deny_args+=(--deny "$d"); done
rr="$("$_HERE/lib/grok-call.sh" --prompt-file "$rebfile" --cwd "$reb_wt" --max-turns 6 \
        --always-approve "${deny_args[@]}" ${MODEL:+--model "$MODEL"} --tag review-rebuttal)"
rr_exit="$(printf '%s' "$rr" | json_field_stdin exit_code)"
git worktree remove --force "$reb_wt" >/dev/null 2>&1 || true
[[ "$rr_exit" == 0 ]] || fail "grok-call (Rebuttal) failed."
reb_text="$(printf '%s' "$rr" | python3 -c 'import sys,json;print(json.load(sys.stdin)["text"])')"
rebuttals_json="$(REPLY_TEXT="$reb_text" python3 - <<'PY'
import os, json, re
s = re.sub(r'```json|```', '', os.environ.get("REPLY_TEXT", ""))
i, j = s.find('{'), s.rfind('}')
try: print(json.dumps({"rebuttals": json.loads(s[i:j+1]).get("rebuttals", [])}))
except Exception: print('{"rebuttals":[]}')
PY
)"

# --- Phase 4: classify + ledger (python does the join) ---------------------
python3 - "$ledger" "$stamp" "$BASE" "$POC" "$issues_json" "$rebuttals_json" <<'PY'
import sys, json, os
ledger, stamp, base, poc, issues_json, reb_json = sys.argv[1:7]
issues = json.loads(issues_json)["issues"]
rebs = {r.get("id"): r for r in json.loads(reb_json)["rebuttals"]}
conceded=[]; eval_decides=[]; ties=[]; unsure=[]
for iss in issues:
    rb = rebs.get(iss.get("id"))
    verdict = (rb.get("verdict","defend") if rb else "defend").lower()
    cite = (rb.get("citation","") if rb else "").strip().lower()
    # grounding gate: defend w/o real citation -> unsure (anti-hallucination)
    if verdict == "defend" and cite in ("", "none"): verdict = "unsure"
    if verdict == "concede": conceded.append(iss)
    elif verdict == "unsure": unsure.append(iss)
    elif iss.get("eval_decidable"): eval_decides.append(iss)
    else: ties.append(iss)
verdict = ("tie-break-needed" if ties else "clarify-unknowns" if unsure
           else "eval-decides" if eval_decides else "fixes-pending")
rec = {"stamp":stamp,"base":base,"poc":poc,"issues":issues,"rebuttals":list(rebs.values()),
       "conceded":[i["id"] for i in conceded],"eval_decides":[i["id"] for i in eval_decides],
       "ties":[i["id"] for i in ties],"unsure":[i["id"] for i in unsure],"verdict":verdict}
open(os.path.join(ledger,"REVIEW.json"),"w").write(json.dumps(rec, indent=2))
def sec(title, items):
    out=[f"## {title}: {len(items)}"]; out+= [f"- [{i['id']}] {i.get('file','')}: {i.get('claim','')}" for i in items]; return "\n".join(out)+"\n"
md = f"# REVIEW — {stamp}  ({base}...{poc})\n\nMechanik: bounded cross-review (1 Assess + 1 Rebuttal). The eval decides, not consensus.\n\n"
md += sec("Conceded (Grok fixes next build)", conceded)+"\n"
md += sec("Eval decides (objective, pass^k)", eval_decides)+"\n"
md += sec("Ties -> micro-probe (dual-tiebreak.sh)", ties)+"\n"
md += sec("Unsure (ungrounded -> eval/contract clarification)", unsure)
open(os.path.join(ledger,"REVIEW.md"),"w").write(md)
print(f"__COUNTS__ {len(conceded)} {len(eval_decides)} {len(ties)} {len(unsure)}")
PY
counts="$(python3 -c 'import json;r=json.load(open("'"$ledger"'/REVIEW.json"));print(len(r["conceded"]),len(r["eval_decides"]),len(r["ties"]),len(r["unsure"]))')"
read -r c e t u <<<"$counts"
info "\n=== Review done ==="
log "  conceded=$c  eval-decides=$e  ties=$t  unsure=$u"
log "  Ledger: ledger/REVIEW.md + ledger/REVIEW.json"
# moat telemetry
"$_HERE/lib/decorrelation.sh" --review "$ledger/REVIEW.json" || true
if [[ "$t" -gt 0 ]]; then
  warn "  NEXT: ./dual-tiebreak.sh for $t subjective tie(s) (micro-probe + eval)."
else
  ok "  NEXT: Grok fixes conceded -> ./dual-merge.sh --eval-k 5 (eval decides)."
fi
exit 0
