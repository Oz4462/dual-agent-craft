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

@test "AUDIT-FIX(low): DUAL_AGENT_SPEND_FILE env moves the ledger for reader + writer" {
  # reader side
  EXT="$SCRATCH/outside/SPEND.jsonl"; mkdir -p "$SCRATCH/outside"
  printf '{"stamp":"%s01-000000","cost_usd":1.50}\n' "$MONTH" > "$EXT"
  DUAL_AGENT_SPEND_FILE="$EXT" run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=1.50"* ]]
}

@test "AUDIT-FIX(low): missing flag value fails with a clear message, not raw unbound" {
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap
  [ "$status" -ne 0 ]
  [[ "$output" == *"value required for --cap"* ]]
}

@test "AUDIT-P2: ISO-8601 stamps (2026-07-05T..) are summed for the current month" {
  ISO="$(date -u +%Y-%m)-05T12:00:00Z"
  mk_spend "{\"stamp\":\"$ISO\",\"cost_usd\":4.00}" \
           "{\"stamp\":\"${MONTH}02-000000\",\"cost_usd\":1.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=5.00"* ]]
}

@test "AUDIT-P2: ISO stamp from a PAST month is excluded" {
  mk_spend "{\"stamp\":\"2019-01-01T00:00:00Z\",\"cost_usd\":999}" \
           "{\"stamp\":\"${MONTH}02-000000\",\"cost_usd\":2.00}"
  run "$HARNESS_ROOT/lib/budget-guard.sh" --cap 100 --spend-file "$SPEND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spent=2.00"* ]]
}
