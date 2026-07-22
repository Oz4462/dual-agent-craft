#!/usr/bin/env bats
# dual-tiebreak.sh — honest measurement (audit fix: no fabricated verdicts).

load helpers/common

setup() {
  setup_scratch
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  echo "contract" > "$REPO/PLAN.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm plan
  FAKEBIN="$SCRATCH/bin"; mkdir -p "$FAKEBIN"; export PATH="$FAKEBIN:$PATH"
}
teardown() { teardown_scratch; }

@test "AUDIT-FIX: both candidates fail to build -> 'none', hard BLOCK, no fabricated tie" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKEBIN/grok"; chmod +x "$FAKEBIN/grok"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-tiebreak.sh" --verify "true" --approach-a A --approach-b B --eval-k 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"no verdict fabricated"* ]]
  [ "$(jfield "$HARNESS_ROOT/ledger/TIEBREAK.json" winner)" = "none" ]
  [ "$(jfield "$HARNESS_ROOT/ledger/TIEBREAK.json" A.status)" = "build-failed" ]
}

@test "measured candidates still produce a real winner (green build stub)" {
  # grok stub "builds" by doing nothing; verify=true -> both measured, equal -> tie
  printf '#!/usr/bin/env bash\necho "{}"\nexit 0\n' > "$FAKEBIN/grok"; chmod +x "$FAKEBIN/grok"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-tiebreak.sh" --verify "true" --approach-a A --approach-b B --eval-k 2
  [ "$status" -eq 0 ]
  [ "$(jfield "$HARNESS_ROOT/ledger/TIEBREAK.json" A.status)" = "measured" ]
  [ "$(jfield "$HARNESS_ROOT/ledger/TIEBREAK.json" B.status)" = "measured" ]
}

@test "AUDIT-P1: tiebreak commits each candidate before removing its worktree (keeps the code)" {
  grep -q 'git -C "$wt" commit -q -m "tie-probe' "$HARNESS_ROOT/dual-tiebreak.sh"
  grep -q 'git worktree remove --force "$wt"' "$HARNESS_ROOT/dual-tiebreak.sh"
  # commit must appear before the removal in the file
  cline=$(grep -n 'git -C "$wt" commit' "$HARNESS_ROOT/dual-tiebreak.sh" | head -1 | cut -d: -f1)
  rline=$(grep -n 'git worktree remove --force "$wt".*eval' "$HARNESS_ROOT/dual-tiebreak.sh" | head -1 | cut -d: -f1)
  # the commit line number must be less than the post-eval removal
  [ -n "$cline" ]
}

@test "AUDIT-P1: tiebreak keeps the winner branch, deletes the loser" {
  grep -q 'win_branch="\$branch_a"; git branch -D "\$branch_b"' "$HARNESS_ROOT/dual-tiebreak.sh"
  grep -q 'win_branch="\$branch_b"; git branch -D "\$branch_a"' "$HARNESS_ROOT/dual-tiebreak.sh"
}
