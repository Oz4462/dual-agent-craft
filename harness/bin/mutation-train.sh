#!/usr/bin/env bash
# mutation-train.sh — controlled regressive self-improvement (mutation testing).
#
# Brain-based training for the harness: inject a deliberate fault into a critical
# fail-closed module; the test suite MUST catch it (go RED). A SURVIVING mutation
# (suite stays green) is a TEST GAP — a weak muscle — and prints as a finding.
# Every mutation is reverted via `git checkout` afterwards; exits non-zero if any
# mutation survived, so CI/loops can gate on "no gaps".
#
# Requires a clean working tree (it restores by checkout). Run from repo root.
set -uo pipefail
export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

[[ -z "$(git status --porcelain)" ]] || { echo "BLOCKED: working tree not clean (mutation-train restores via checkout — commit/stash first)."; exit 1; }

# CRITICAL (self-found): if this tool is KILLED mid-mutation (SIGTERM from a
# timeout, Ctrl-C), the per-mutation `git checkout` restore never runs and leaves
# a MUTATED file on disk — silently weakening a live guard. An EXIT/INT/TERM trap
# guarantees the tree is always restored, whatever kills us.
MUT_TARGETS=(lib dual-merge.sh dual-review.sh dual-build.sh harness)
restore_all() { git checkout -- "${MUT_TARGETS[@]}" 2>/dev/null || true; }
trap 'restore_all; echo "mutation-train: interrupted — tree restored." >&2; exit 130' INT TERM
trap restore_all EXIT

survivors=0; killed=0; skipped=0
run_suite() { tests/run.sh >/dev/null 2>&1; }

# mutate <file> <sed-expr> <description>
mutate() {
  local file="$1" expr="$2" desc="$3" before after
  before=$(md5sum "$file")
  sed -i "$expr" "$file"
  after=$(md5sum "$file")
  if [[ "$before" == "$after" ]]; then
    # A no-op sed means the module changed out from under the mutation -> this
    # mutation no longer tests anything. That is a COVERAGE REGRESSION, not a
    # pass (fail-open otherwise: all-skipped would read as "all killed").
    printf 'SKIP! (sed no-op — module refactored, mutation stale) %s\n' "$desc"
    skipped=$((skipped+1)); git checkout -- "$file" 2>/dev/null; return
  fi
  if run_suite; then
    printf 'SURVIVED  %-52s <- TEST GAP\n' "$desc"; survivors=$((survivors+1))
  else
    printf 'killed    %s\n' "$desc"; killed=$((killed+1))
  fi
  git checkout -- "$file" 2>/dev/null
}

echo "=== Mutation training — every mutation MUST be killed by the suite ==="

mutate lib/import-scan.sh 's/\[\[ "\$blocked" == true \]\] && exit 2 || exit 0/exit 0/' \
  "import-scan: never block invented packages"
mutate lib/import-scan.sh "s/\[A-Za-z_\]\[A-Za-z0-9_.\]\*)\\\\s+import/[A-Za-z_][A-Za-z0-9_]*)\\\\s+import/" \
  "import-scan: revert dotted from-import scan"
mutate lib/eval-harness.sh 's/int(passes==k)/int(passes>=1)/' \
  "eval-harness: pass^k downgraded to pass@k"
mutate lib/eval-harness.sh 's/early_stopped=true; break/early_stopped=true/' \
  "eval-harness: lossless early-stop no longer breaks"
mutate lib/test-guard.sh 's/fail_code 2 "test-guard: bad ref/: # &/' \
  "test-guard: bad-ref no longer blocks (fail-open)"
mutate dual-merge.sh 's/\[\[ "\$verify_ok" == true \]\] || fail/true || fail/' \
  "dual-merge: verify gate always green"
mutate harness/operations/hooks/guard-bad-calls.sh 's/is_dangerous_rm "\$cmd"       && block/false \&\& block/' \
  "guard: rm-guard disabled"
mutate harness/operations/hooks/guard-bad-calls.sh 's/\[\[ "\$cmd" =~ \$re_fpush1 \]\]    && block/false \&\& block/' \
  "guard: force-push-to-main check disabled"
mutate lib/budget-guard.sh 's/int(would <= limit)/int(would <= limit*1000)/' \
  "budget-guard: cap effectively removed"
mutate lib/claude-call.sh 's/\[\[ "\$is_error" == "true" && "\$exit_code" == 0 \]\] && exit_code=1/:/' \
  "claude-call: is_error ignored"
mutate dual-review.sh 's/fail "Claude.s ASSESS reply contained no parseable/echo soft # &/' \
  "dual-review: garbage reply no longer blocks"
mutate harness/bin/loop-runner.sh 's/if (( stall >= 1 )); then/if false; then/' \
  "loop-runner: STALLED detection disabled"

# (EXIT trap already restores the tree.)

echo ""
echo "=== RESULT: killed=$killed  survived=$survivors  skipped=$skipped ==="
if [[ $survivors -eq 0 && $skipped -eq 0 ]]; then
  echo "ALL MUTATIONS KILLED — fail-closed muscles strong."; exit 0
elif [[ $skipped -gt 0 ]]; then
  echo "STALE MUTATIONS: $skipped no-op sed(s) — a module was refactored, its mutation no longer tests anything. Update the mutation set, then re-run."; exit 1
else
  echo "GAPS FOUND: $survivors surviving mutation(s) — add tests, then re-run."; exit 1
fi
