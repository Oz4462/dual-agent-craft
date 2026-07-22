#!/usr/bin/env bash
# dual-merge.sh — No-Cut merge gate: merge From->Into ONLY if (a) acceptance is
# green and (b) no git conflict arises. On conflict: abort, never auto-overwrite.
#
# Enforces PROTOCOL invariants 3+4: no silent overwrite, no false "done".
# Verify runs in the CANDIDATE branch (its own temp worktree, so the checkout is
# undisturbed).
#
# Usage:
#   ./dual-merge.sh [--from feat/harden] [--into main] [--verify "pytest -q"]
#     [--eval-k 1] [--test-guard] [--force]
#
#   --eval-k K : graded gate — run verify K times, merge only if pass^k (ALL K
#                green). K>=3 recommended (flakiness detector; "green once" != done).
#   --test-guard : also enforce invariant 7 (builder didn't edit test/verify files).
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"

FROM="feat/harden"; INTO="main"; VERIFY=""; EVAL_K=1; FORCE=false; TESTGUARD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage "$0"; exit 0;;
    --from)       FROM="${2:?value required for $1}"; shift 2;;
    --into)       INTO="${2:?value required for $1}"; shift 2;;
    --verify)     VERIFY="${2:?value required for $1}"; shift 2;;
    --eval-k)     EVAL_K="${2:?value required for $1}"; shift 2
                  [[ "$EVAL_K" =~ ^[0-9]+$ ]] || { echo "BLOCKED: --eval-k must be a positive integer, got '$EVAL_K' (a typo would silently downgrade the pass^k gate to one run)." >&2; exit 1; };;
    --test-guard) TESTGUARD=true; shift;;
    --force)      FORCE=true; shift;;
    *) fail "dual-merge: unknown arg '$1'";;
  esac
done

gitfails() { [[ $? -ne 0 ]] && fail "$1"; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repo."
git rev-parse --verify "$FROM" >/dev/null 2>&1 || fail "Branch missing: $FROM"
git rev-parse --verify "$INTO" >/dev/null 2>&1 || fail "Branch missing: $INTO"
[[ -z "$(git status --porcelain)" ]] || fail "Working tree not clean — commit/stash first."

# --- Ownership / overlap report (transparency before merge) ----------------
base="$(git merge-base "$INTO" "$FROM")"
mapfile -t from_files < <(git diff --name-only "$base" "$FROM")
mapfile -t into_files < <(git diff --name-only "$base" "$INTO")
overlap=()
for f in "${from_files[@]}"; do for g in "${into_files[@]}"; do [[ "$f" == "$g" ]] && overlap+=("$f"); done; done

info "=== No-Cut Merge Gate ==="
log "From: $FROM  Into: $INTO  Base: $base"
log "Files changed in $FROM: ${#from_files[@]}"
if [[ ${#overlap[@]} -gt 0 ]]; then
  warn "WARNING — both sides touched the same files:"
  for o in "${overlap[@]}"; do warn "  ! $o"; done
  log "  (git merges line-by-line; real conflicts abort.)"
else
  ok "No file overlap between $FROM and $INTO — collision-free."
fi

# --- optional invariant-7 guard --------------------------------------------
if [[ "$TESTGUARD" == true ]]; then
  "$_HERE/lib/test-guard.sh" --poc "$FROM" --base "$INTO" || fail "test-guard blocked the merge (invariant 7)."
fi

# --- Verify gate (in the candidate's temp worktree) ------------------------
if [[ -n "$VERIFY" ]]; then
  tmp="$(mktemp -d)/cand"
  git worktree add --detach "$tmp" "$FROM" >/dev/null 2>&1; gitfails "worktree add failed."
  # Cleanup on ANY exit (incl. INT/TERM -> EXIT): the candidate worktree must not
  # leak if verify is interrupted (audit P2 worktree-leak class).
  trap 'git worktree remove --force "$tmp" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1' EXIT
  verify_ok=true
  if [[ "$EVAL_K" -gt 1 ]]; then
    log "\nGraded verify (pass^k, k=$EVAL_K) in candidate: $VERIFY"
    if "$_HERE/lib/eval-harness.sh" --verify "$VERIFY" --k "$EVAL_K" --cwd "$tmp" --out "$_HERE/ledger/EVAL.json"; then
      passes="$(json_field "$_HERE/ledger/EVAL.json" passes)"
      ok "pass^k GREEN ($passes/$EVAL_K) — consistent, no flake."
    else
      verify_ok=false
      warn "pass^k RED — flaky/red, no merge (invariant 4)."
    fi
  else
    log "\nVerify in candidate: $VERIFY"
    ( cd "$tmp" && eval "$VERIFY" ) || verify_ok=false
  fi
  git worktree remove --force "$tmp" >/dev/null 2>&1 || true
  [[ "$verify_ok" == true ]] || fail "Verify RED — no merge (invariant 4)."
  ok "Verify gate green."
elif [[ "$FORCE" != true ]]; then
  fail "No --verify given. Override with --force (not recommended)."
else
  warn "Verify skipped (--force)."
fi

# --- Merge (conflict = abort, never overwrite) -----------------------------
# Guard the checkout (P0 audit finding): if $INTO is held by another linked
# worktree or checkout otherwise fails, an unguarded checkout would leave a
# DIFFERENT branch current and merge into the WRONG target while printing a
# false "MERGED / No-Cut upheld". Every other git step here is guarded; so is this.
git checkout "$INTO" >/dev/null 2>&1 || fail "checkout $INTO failed (checked out in another worktree? stale wt-* leftover?) — no merge."
cur_now="$(git rev-parse --abbrev-ref HEAD)"
[[ "$cur_now" == "$INTO" ]] || fail "expected HEAD=$INTO after checkout but got '$cur_now' — refusing to merge into the wrong branch."
if ! git merge --no-ff --no-edit "$FROM"; then
  git merge --abort
  fail "git conflict — merge aborted. Human decides (invariant 3)."
fi
ok "\nMERGED: $FROM -> $INTO. No-Cut upheld."
git log --oneline -1
