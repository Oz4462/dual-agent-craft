#!/usr/bin/env bats
# coordination.sh + config/coordination.json — baton, lock, ownership, no-overlap.

load helpers/common

setup() {
  setup_scratch
  export DUAL_COORDINATION_CONFIG="$HARNESS_ROOT/config/coordination.json"
  # Isolate lock/state under scratch by using a throwaway git repo as cwd root.
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  mkdir -p "$REPO/.dual-agent" "$REPO/config"
  cp "$HARNESS_ROOT/config/coordination.json" "$REPO/config/coordination.json"
  export DUAL_COORDINATION_CONFIG="$REPO/config/coordination.json"
  # Point state/lock into the repo via config overrides would need edit;
  # coordination uses git toplevel for state — run commands from $REPO.
  cd "$REPO"
}
teardown() {
  cd "$HARNESS_ROOT" 2>/dev/null || true
  teardown_scratch
}

coord() { "$HARNESS_ROOT/lib/coordination.sh" "$@"; }

@test "config validates" {
  run coord validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid"* ]]
}

@test "get returns defaults from fine-tuning config" {
  run coord get defaults.eval_k
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
  run coord get roles.builder
  [ "$output" = "grok" ]
  run coord get roles.architect
  [ "$output" = "claude" ]
  run coord get anti_overlap.max_rebuttal_rounds
  [ "$output" = "1" ]
}

@test "builder ownership: tests/ denied; src/ allowed; PLAN/HANDOFF orchestration-exempt" {
  run coord path-denied tests/test_x.py
  [ "$status" -eq 0 ]
  [[ "$output" == *denied* ]]
  # PLAN/HANDOFF are dual-run staffelstab surfaces (Claude/gate), not builder — exempt
  run coord path-denied PLAN.md
  [ "$status" -eq 1 ]
  [[ "$output" == *allowed* ]]
  run coord path-denied HANDOFF.md
  [ "$status" -eq 1 ]
  run coord path-denied src/app.py
  [ "$status" -eq 1 ]
  [[ "$output" == *allowed* ]]
  run coord path-denied dual-merge.sh
  [ "$status" -eq 0 ]
}

@test "check-builder-paths blocks test file (anti double-work / gate gaming)" {
  run coord check-builder-paths src/ok.py tests/evil.py
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]] || [[ "$output" == *ownership* ]]
}

@test "check-builder-paths allows pure implementation paths" {
  run coord check-builder-paths src/app.py lib/helpers.py
  [ "$status" -eq 0 ]
}

@test "exclusive lock: second acquire while PID live fails" {
  # Lock stores the holder PID; simulate a live dual-run with a long-lived process.
  sleep 60 &
  holder=$!
  mkdir -p "$REPO/.dual-agent"
  cat >"$REPO/.dual-agent/dual-run.lock" <<EOF
pid=$holder
run_id=hold-test
started=2026-01-01T00:00:00Z
host=test
EOF
  run coord lock-acquire other
  [ "$status" -ne 0 ]
  [[ "$output" == *lock* ]] || [[ "$output" == *BLOCKED* ]]
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  rm -f "$REPO/.dual-agent/dual-run.lock"
}

@test "stale lock (dead PID) is reclaimed" {
  mkdir -p "$REPO/.dual-agent"
  cat >"$REPO/.dual-agent/dual-run.lock" <<EOF
pid=99999999
run_id=stale
started=1970-01-01T00:00:00Z
host=test
EOF
  run coord lock-acquire reclaim
  [ "$status" -eq 0 ]
  run coord lock-release
  [ "$status" -eq 0 ]
}

@test "baton machine: init → require claude ok → require grok fails" {
  run coord state-init run-test "demo task"
  [ "$status" -eq 0 ]
  run coord state-get baton
  [ "$output" = "claude" ]
  run coord state-get phase
  [ "$output" = "C" ]
  run coord require-baton claude
  [ "$status" -eq 0 ]
  run coord require-baton grok
  [ "$status" -ne 0 ]
  [[ "$output" == *BATON* ]] || [[ "$output" == *BLOCKED* ]]
}

@test "assert-phase rejects out-of-order work" {
  coord state-init run-order
  run coord assert-phase C
  [ "$status" -eq 0 ]
  run coord assert-phase R
  [ "$status" -ne 0 ]
}

@test "phase_agent mapping is Claude/Grok/gate structured" {
  [ "$(coord get phase_agent.C)" = "claude" ]
  [ "$(coord get phase_agent.R)" = "grok" ]
  [ "$(coord get phase_agent.G)" = "gate" ]
  [ "$(coord get phase_agent.A)" = "claude" ]
  [ "$(coord get phase_agent.F)" = "claude" ]
  [ "$(coord get phase_agent.T)" = "gate" ]
}
