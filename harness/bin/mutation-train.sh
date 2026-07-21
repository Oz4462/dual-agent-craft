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

survivors=0; killed=0
run_suite() { tests/run.sh >/dev/null 2>&1; }

# mutate <file> <sed-expr> <description>
mutate() {
  local file="$1" expr="$2" desc="$3" before after
  before=$(md5sum "$file")
  sed -i "$expr" "$file"
  after=$(md5sum "$file")
  if [[ "$before" == "$after" ]]; then
    printf 'SKIP  (sed no-op — module changed?) %s\n' "$desc"
    git checkout -- "$file" 2>/dev/null; return
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
mutate lib/test-guard.sh 's/if ! DIFF_FILES=/DIFF_FILES=/; s/git diff --name-only "\$BASE...\$POC" 2>&1)"; then/git diff --name-only "$BASE...$POC" 2>\/dev\/null || true)"/' \
  "test-guard: swallow git-diff error (bad branch -> PASS)"
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

# safety net: restore anything the loop might have left mutated on an error
git checkout -- lib dual-merge.sh dual-review.sh harness 2>/dev/null || true

echo ""
echo "=== RESULT: killed=$killed  survived=$survivors ==="
if [[ $survivors -eq 0 ]]; then
  echo "ALL MUTATIONS KILLED — fail-closed muscles strong."; exit 0
else
  echo "GAPS FOUND: $survivors surviving mutation(s) — add tests, then re-run."; exit 1
fi
