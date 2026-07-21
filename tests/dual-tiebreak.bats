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
