#!/usr/bin/env bats
# eval-harness.sh — pass@k / pass^k scorer + lossless early-stop.

load helpers/common

setup()    { setup_scratch; }
teardown() { teardown_scratch; }

@test "always-green K=5 -> pass^k=1, all runs executed, exit 0" {
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "true" --k 5 --out "$SCRATCH/e.json"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/e.json" pass_pow_k)" = "1" ]
  [ "$(jfield "$SCRATCH/e.json" pass_at_k)" = "1" ]
  [ "$(jfield "$SCRATCH/e.json" runs_executed)" = "5" ]
  [ "$(jfield "$SCRATCH/e.json" early_stopped)" = "false" ]
}

@test "always-red K=5 -> pass^k=0 AND lossless early-stop after run 1, exit 1" {
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "false" --k 5 --out "$SCRATCH/e.json"
  [ "$status" -eq 1 ]
  [ "$(jfield "$SCRATCH/e.json" pass_pow_k)" = "0" ]
  [ "$(jfield "$SCRATCH/e.json" pass_at_k)" = "0" ]
  [ "$(jfield "$SCRATCH/e.json" runs_executed)" = "1" ]
  [ "$(jfield "$SCRATCH/e.json" early_stopped)" = "true" ]
}

@test "flaky (fails once, then passes) -> pass@k=1 but pass^k=0 (graded catches flake)" {
  # First invocation fails, subsequent ones pass (state via marker file).
  cat > "$SCRATCH/flaky.sh" <<EOF
#!/usr/bin/env bash
if [[ ! -f "$SCRATCH/ran" ]]; then touch "$SCRATCH/ran"; exit 1; fi
exit 0
EOF
  chmod +x "$SCRATCH/flaky.sh"
  # threshold 0 disables strict early-stop so all K runs execute
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "$SCRATCH/flaky.sh" --k 4 --threshold 0.5 --out "$SCRATCH/e.json"
  [ "$(jfield "$SCRATCH/e.json" pass_at_k)" = "1" ]
  [ "$(jfield "$SCRATCH/e.json" pass_pow_k)" = "0" ]
  [ "$(jfield "$SCRATCH/e.json" runs_executed)" = "4" ]
}

@test "verify runs in --cwd (not the caller's dir)" {
  mkdir -p "$SCRATCH/target"
  touch "$SCRATCH/target/marker"
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "test -f marker" --k 2 --cwd "$SCRATCH/target" --out "$SCRATCH/e.json"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/e.json" pass_pow_k)" = "1" ]
}

@test "missing --verify is BLOCKED" {
  run "$HARNESS_ROOT/lib/eval-harness.sh" --k 3
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "AUDIT-FIX: nonexistent --cwd is a distinct setup BLOCK, not K red runs" {
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "true" --k 3 --cwd "$SCRATCH/does-not-exist" --out "$SCRATCH/e.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"setup error"* ]]
  [ ! -f "$SCRATCH/e.json" ]
}

@test "AUDIT-P2: non-strict threshold — score_ok true but pass^k=0 (strict gate still decides)" {
  # 2 pass, 2 fail over K=4 -> rate 0.5. threshold 0.5 -> score_ok true, but strict gate exit 1.
  cat > "$SCRATCH/half.sh" <<SH
#!/usr/bin/env bash
c="$SCRATCH/n"; n=\$(cat "\$c" 2>/dev/null || echo 0); echo \$((n+1)) > "\$c"
[ \$((n % 2)) -eq 0 ] && exit 0 || exit 1
SH
  chmod +x "$SCRATCH/half.sh"
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "$SCRATCH/half.sh" --k 4 --threshold 0.5 --out "$SCRATCH/e.json"
  [ "$status" -ne 0 ]                                        # strict pass^k gate: exit 1
  [ "$(jfield "$SCRATCH/e.json" pass_pow_k)" = "0" ]
  [ "$(jfield "$SCRATCH/e.json" score_ok)" = "true" ]       # threshold grade: passed
}

@test "AUDIT-P2: threshold boundary — 0.51 over a 0.5 rate -> score_ok false" {
  echo 0 > "$SCRATCH/n"
  cat > "$SCRATCH/half.sh" <<SH
#!/usr/bin/env bash
c="$SCRATCH/n"; n=\$(cat "\$c"); echo \$((n+1)) > "\$c"
[ \$((n % 2)) -eq 0 ] && exit 0 || exit 1
SH
  chmod +x "$SCRATCH/half.sh"
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "$SCRATCH/half.sh" --k 4 --threshold 0.51 --out "$SCRATCH/e.json"
  [ "$(jfield "$SCRATCH/e.json" score_ok)" = "false" ]
}

@test "AUDIT-P2: K<1 is clamped to 1" {
  run "$HARNESS_ROOT/lib/eval-harness.sh" --verify "true" --k 0 --out "$SCRATCH/e.json"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/e.json" k)" = "1" ]
}
