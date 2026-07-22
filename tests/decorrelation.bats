#!/usr/bin/env bats
# decorrelation.sh — cross-vendor moat telemetry.

load helpers/common

setup()    { setup_scratch; }
teardown() { teardown_scratch; }

@test "disagreement = 1 - conceded/raised" {
  printf '{"stamp":"s1","issues":[{"id":"I1"},{"id":"I2"},{"id":"I3"},{"id":"I4"}],"conceded":["I1"]}' > "$SCRATCH/REVIEW.json"
  run "$HARNESS_ROOT/lib/decorrelation.sh" --review "$SCRATCH/REVIEW.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disagreement=0.75"* ]]
  # appended to the jsonl next to the review file
  [ -f "$SCRATCH/DECORRELATION.jsonl" ]
}

@test "low disagreement triggers the convergence warning" {
  printf '{"stamp":"s2","issues":[{"id":"I1"},{"id":"I2"}],"conceded":["I1","I2"]}' > "$SCRATCH/REVIEW.json"
  run "$HARNESS_ROOT/lib/decorrelation.sh" --review "$SCRATCH/REVIEW.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"moat weakening"* ]]
}

@test "healthy disagreement does NOT warn" {
  printf '{"stamp":"s3","issues":[{"id":"I1"},{"id":"I2"}],"conceded":[]}' > "$SCRATCH/REVIEW.json"
  run "$HARNESS_ROOT/lib/decorrelation.sh" --review "$SCRATCH/REVIEW.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"moat weakening"* ]]
}

@test "zero issues -> disagreement 0, no crash, no warn" {
  printf '{"stamp":"s4","issues":[],"conceded":[]}' > "$SCRATCH/REVIEW.json"
  run "$HARNESS_ROOT/lib/decorrelation.sh" --review "$SCRATCH/REVIEW.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"moat weakening"* ]]
}

@test "missing REVIEW.json is a graceful no-op" {
  run "$HARNESS_ROOT/lib/decorrelation.sh" --review "$SCRATCH/nope.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no REVIEW.json yet"* ]]
}
