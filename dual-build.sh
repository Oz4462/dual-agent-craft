#!/usr/bin/env bash
# dual-build.sh — CRAFT Render phase: Grok builds a POC against PLAN.md.
#
# Claude writes PLAN.md (the contract). This script runs Grok headless in an
# ISOLATED git worktree and builds N variants (--best-of-n). It does NOT merge --
# review + hardening stay with Claude/you.
#
# Runs on the Grok subscription (OAuth), NO xAI API key needed.
#
# Usage:
#   ./dual-build.sh [--plan PLAN.md] [--variants 3] [--branch feat/poc]
#     [--into main] [--model M] [--max-turns 40] [--adaptive] [--verify "pytest -q"]
#     [--dry-run]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

PLAN="./PLAN.md"; VARIANTS=3; BRANCH="feat/poc"; INTO="main"; MODEL=""
MAX_TURNS=40; ADAPTIVE=false; VERIFY=""; DRYRUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)      PLAN="${2:?value required for $1}"; shift 2;;
    --variants)  VARIANTS="${2:?value required for $1}"; shift 2;;
    --branch)    BRANCH="${2:?value required for $1}"; shift 2;;
    --into)      INTO="${2:?value required for $1}"; shift 2;;
    --model)     MODEL="${2:?value required for $1}"; shift 2;;
    --max-turns) MAX_TURNS="${2:?value required for $1}"; shift 2;;
    --adaptive)  ADAPTIVE=true; shift;;
    --verify)    VERIFY="${2:?value required for $1}"; shift 2;;
    --dry-run)   DRYRUN=true; shift;;
    *) fail "dual-build: unknown arg '$1'";;
  esac
done

# --- Phase 0: preconditions ------------------------------------------------
command -v grok >/dev/null 2>&1 || fail "grok CLI not in PATH."
command -v git  >/dev/null 2>&1 || fail "git not in PATH."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repo. Run 'git init' + first commit."
[[ -f "$PLAN" ]] || fail "Contract missing: $PLAN (Claude must write PLAN.md first)."
plan_text="$(tr -d '\r' <"$PLAN")"
[[ -n "${plan_text// }" ]] || fail "$PLAN is empty."
grep -qE '<Feature-Name>|<Was soll gebaut' <<<"$plan_text" && fail "$PLAN is still the template — fill it in first."

# --- Phase 1: composed prompt ----------------------------------------------
tmpdir="$_HERE/.dual-agent/tmp"; logdir="$_HERE/.dual-agent/logs"
mkdir -p "$tmpdir" "$logdir"
stamp="$(utc_stamp)"
promptfile="$tmpdir/prompt-$stamp.txt"
cat > "$promptfile" <<EOF
You are the BUILDER in a dual-agent workflow. Build a working POC that satisfies the
contract below EXACTLY. Do not exceed the Out-of-Scope section. Prefer the smallest
correct implementation. No secrets, no network unless the contract allows it.
Write ONLY implementation files (src/ etc.). NEVER edit test/verify files — they are
pinned by the reviewer and untrusted-input to you (PROTOCOL invariant 7; a deterministic
test-guard will block it). A reviewer will harden your output afterwards.

=== CONTRACT (PLAN.md) ===
$plan_text
EOF

# worktree path: sibling of the REPO TOPLEVEL (not $(pwd)) — running dual-build
# from a subdir would otherwise nest a full checkout INSIDE the repo, which the
# next WIP `git add -A` would then commit (audit P1). Toplevel is deterministic.
repo_top="$(git rev-parse --show-toplevel)"
wtpath="$(dirname "$repo_top")/wt-${BRANCH//[\/:]/-}"

info "=== Dual-Agent / Render (Grok) ==="
log "Contract : $PLAN"
log "Branch   : $BRANCH  (worktree: $wtpath)"
log "Variants : $VARIANTS"
log "Log-Dir  : .dual-agent/logs  (grok-*.out.json + grok-*.err.log separated)"

if [[ "$DRYRUN" == true ]]; then warn "DryRun — no call."; exit 0; fi

# WIP-base: a worktree branches from a COMMIT, not the working tree. To let Grok
# see current (uncommitted) work, commit WIP to a feature branch first (no push);
# $INTO stays clean.
if [[ -n "$(git status --porcelain)" ]]; then
  cur="$(git rev-parse --abbrev-ref HEAD)"
  # Detached HEAD (mid-rebase/bisect/manual checkout) returns literal "HEAD" —
  # committing there would strand WIP on an unnamed commit (audit finding):
  # park it on a wip branch exactly like the $INTO case.
  if [[ "$cur" == "$INTO" || "$cur" == "HEAD" ]]; then
    wip="feat/wip-$stamp"
    git switch -c "$wip" >/dev/null 2>&1 || fail "could not create WIP branch $wip."
    log "${C_DIM}WIP -> new branch $wip ($INTO stays clean, no push).${C_RESET}"
  fi
  git add -A
  # Honest reporting (audit finding): only claim "WIP committed" if it WAS.
  if git commit -q -m "wip: dual-agent base $stamp [no-push]" >/dev/null 2>&1; then
    log "${C_DIM}WIP committed -> Grok sees the current basis.${C_RESET}"
  else
    fail "WIP commit failed (hook rejection / disk?) — Grok would build from a STALE base. Fix and re-run."
  fi
fi

# fresh worktree from HEAD; clean any same-named leftover.
git worktree remove --force "$wtpath" >/dev/null 2>&1 || true
git branch -D "$BRANCH" >/dev/null 2>&1 || true
git worktree add -b "$BRANCH" "$wtpath" HEAD >/dev/null 2>&1 || fail "worktree add failed ($BRANCH from HEAD)."

deny=('Bash(rm -rf *)' 'Bash(git push *)' 'Bash(curl *)' 'Bash(wget *)')
render() {
  local n="$1"; local -a a=(--prompt-file "$promptfile" --cwd "$wtpath" --max-turns "$MAX_TURNS" --best-of-n "$n" --always-approve --tag grok)
  [[ -n "$MODEL" ]] && a+=(--model "$MODEL")
  for d in "${deny[@]}"; do a+=(--deny "$d"); done
  "$_HERE/lib/grok-call.sh" "${a[@]}"
}

# Adaptive: render N=1 first, escalate to full -Variants only on failed acceptance.
effective_n="$VARIANTS"
[[ "$ADAPTIVE" == true && "$VARIANTS" -gt 1 ]] && effective_n=1
log "Render   : best-of-$effective_n$([[ "$ADAPTIVE" == true ]] && echo ' (adaptive: N=1 first)')"
result="$(render "$effective_n")"
grok_exit="$(printf '%s' "$result" | json_field_stdin exit_code 2>/dev/null || echo 1)"
grok_exit="${grok_exit:-1}"
printf '%s' "$result" | python3 -c "import sys,json;d=json.load(sys.stdin);print('\nGrok result (noise-free):');print(d['text'].strip()[:2000])" 2>/dev/null || true

if [[ "$ADAPTIVE" == true && "$VARIANTS" -gt 1 && -n "$VERIFY" && "$grok_exit" == 0 ]]; then
  if ( cd "$wtpath" && eval "$VERIFY" ) >/dev/null 2>&1; then
    ok "Adaptive : N=1 passed acceptance -> saved $((VARIANTS-1)) variants."
  else
    warn "Adaptive : N=1 failed acceptance ($VERIFY) -> escalating to best-of-$VARIANTS"
    result="$(render "$VARIANTS")"
    grok_exit="$(printf '%s' "$result" | json_field_stdin exit_code 2>/dev/null || echo 1)"
  fi
fi

# --- Phase 3: handoff -> commit POC ---------------------------------------
info "\n=== Render done (grok exit=$grok_exit) ==="
log "Worktree: $wtpath"
# strip harness/session artifacts Grok's run leaves behind (NOT part of the POC;
# else they pollute the review diff — live-test found 24 files instead of 1).
for junk in mcps .dual-agent .claude/last_session.md; do
  rm -rf "$wtpath/$junk" 2>/dev/null || true
done
# __pycache__/.pyc are NESTED (src/__pycache__, tests/__pycache__) -> recursive
# strip (Linux live-smoke finding: top-level-only left .pyc in the review diff).
find "$wtpath" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$wtpath" -name '*.pyc' -delete 2>/dev/null || true
git -C "$wtpath" add -A 2>/dev/null || true
if [[ -n "$(git -C "$wtpath" status --porcelain)" ]]; then
  # Commit even on a failed render (forensics), but LABEL it honestly (audit
  # finding: a partial crash-state must not look identical to a clean build).
  pocmsg="poc: grok build $stamp"
  [[ "$grok_exit" != 0 ]] && pocmsg="poc(INCOMPLETE, grok exit=$grok_exit): grok build $stamp"
  git -C "$wtpath" commit -q -m "$pocmsg" >/dev/null 2>&1 || warn "POC commit on $BRANCH failed — worktree left dirty for inspection."
  log "Uncommitted POC changes committed on $BRANCH."
fi
log "\nDiff-Stat (POC vs $INTO):"
git -C "$wtpath" diff --stat "$INTO" 2>/dev/null || true

# NEXT steps only on success (audit finding: a failed render used to print the
# full go-ahead banner first and the warning after) — and the script's own exit
# code now propagates the render result so `dual-build.sh && ...` chains work.
if [[ "$grok_exit" == 0 ]]; then
  ok "\nNEXT for Claude (CRAFT A+F):"
  log "  1. import-scan:  ./lib/import-scan.sh --poc $BRANCH --base $INTO --allow \"<PLAN 'Erlaubte Dependencies'>\""
  log "  2. test-guard:   ./lib/test-guard.sh --poc $BRANCH --base $INTO"
  log "  3. cross-review: ./dual-review.sh --poc $BRANCH --base $INTO"
  log "  4. merge:        ./dual-merge.sh --from $BRANCH --into $INTO --verify \"<test>\" --eval-k 5 --test-guard"
  exit 0
fi

# Failure path: distinguish the benign turn-cap case (work often complete, grok
# still exits 1) from real refusals/tool errors (Linux live-smoke finding).
lasterr="$(ls -t "$logdir"/grok-*.err.log 2>/dev/null | head -1)"
if [[ -n "$lasterr" ]] && grep -qi 'max turns reached' "$lasterr" 2>/dev/null; then
  warn "grok exit != 0: MAX TURNS REACHED — the POC may still be complete (check the diff above); raise --max-turns if it is not, then re-run the guards/review manually."
else
  warn "grok exit != 0 (refusal/tool error?) — read the log: $lasterr"
fi
exit "$grok_exit"
