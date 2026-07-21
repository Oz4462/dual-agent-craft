#!/usr/bin/env bats
# budget-guard.sh — fail BLOCKED before the credit pool is exhausted.

load helpers/common

setup()    { setup_scratch; MONTH="$(date -u +%Y%m)"; }
teardown() { teardown_scratch; }

mk_spend() { # args: lines...
  SPEND="$SCRATCH/SPEND.jsonl"
  printf '%s\n' "$@" > "$SPEND"
}

@test "under cap -> OK exit 0" {
  mk_spend "{\"stamp\":\"${MONTH}01-000000\",\"cost_usd\":3.50}" \
           "{\"stamp\":\"${MONTH}02-000000\",\"cost_usd\":1.25}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --estimate 2 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=4.75"* ]]
  [[ "$output" == *OK* ]]
}

@test "over cap -> BLOCKED exit 2" {
  mk_spend "{\"stamp\":\"${MONTH}01-000000\",\"cost_usd\":4.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 5 --estimate 2 --spend-file "$SPEND"
  [ "$status" -eq 2 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "only the CURRENT month is summed" {
  mk_spend "{\"stamp\":\"20190101-000000\",\"cost_usd\":9999}" \
           "{\"stamp\":\"${MONTH}05-000000\",\"cost_usd\":1.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=1.00"* ]]
}

@test "malformed lines are skipped, not fatal" {
  mk_spend "not json at all" "{\"stamp\":\"${MONTH}05-000000\",\"cost_usd\":2.00}" ""
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=2.00"* ]]
}

@test "missing spend file -> spent=0, OK" {
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SCRATCH/nope.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=0.00"* ]]
}

@test "safety margin blocks BEFORE the hard cap (90% default)" {
  mk_spend "{\"stamp\":\"${MONTH}01-000000\",\"cost_usd\":91.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 2 ]
}

@test "AUDIT-FIX: malformed cost_usd is skipped; valid entries still summed" {
  mk_spend "{\"stamp\":\"${MONTH}01-000000\",\"cost_usd\":\"oops\"}" \
           "{\"stamp\":\"${MONTH}02-000000\",\"cost_usd\":2.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=2.00"* ]]
}
