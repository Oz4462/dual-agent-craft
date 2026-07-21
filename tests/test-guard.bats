#!/usr/bin/env bats
# test-guard.sh — deterministic PROTOCOL invariant-7 enforcement.

load helpers/common

setup()    { setup_scratch; }
teardown() { teardown_scratch; }

guard() { run "$HARNESS_ROOT/lib/test-guard.sh" --out "$SCRATCH/tg.json" "$@"; }

@test "implementation-only diff -> PASS exit 0" {
  guard --diff-files $'src/main.py\nsrc/util.py\nREADME.md'
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/tg.json" verdict)" = "PASS" ]
}

@test "pytest test file -> BLOCK exit 2" {
  guard --diff-files $'src/main.py\ntests/test_main.py'
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/tg.json" verdict)" = "BLOCK" ]
  [ "$(jfield "$SCRATCH/tg.json" violations.0)" = "tests/test_main.py" ]
}

@test "conftest.py -> BLOCK" {
  guard --diff-files "conftest.py"
  [ "$status" -eq 2 ]
}

@test "jest spec + __tests__ dir -> BLOCK" {
  guard --diff-files $'src/app.ts\nsrc/app.spec.ts'
  [ "$status" -eq 2 ]
  guard --diff-files $'__tests__/app.js'
  [ "$status" -eq 2 ]
}

@test "go/rust test files -> BLOCK" {
  guard --diff-files "pkg/foo_test.go"
  [ "$status" -eq 2 ]
  guard --diff-files "src/lib_test.rs"
  [ "$status" -eq 2 ]
}

@test "verify/ dir -> BLOCK" {
  guard --diff-files "verify/acceptance.sh"
  [ "$status" -eq 2 ]
}

@test "lookalike impl names do NOT block (contest.py, protest.js)" {
  guard --diff-files $'src/contest.py\nsrc/protest.js\nsrc/latest.ts'
  [ "$status" -eq 0 ]
}

@test "--extra-pattern extends the net" {
  guard --diff-files "quality/checks.yaml" --extra-pattern '(^|/)quality/'
  [ "$status" -eq 2 ]
}

@test "real git diff mode works end-to-end" {
  make_repo "$SCRATCH/repo"
  git -C "$SCRATCH/repo" checkout -qb feat/poc
  mkdir -p "$SCRATCH/repo/tests"
  echo x > "$SCRATCH/repo/tests/test_x.py"
  git -C "$SCRATCH/repo" add -A
  git -C "$SCRATCH/repo" commit -qm poc
  cd "$SCRATCH/repo"
  guard --poc feat/poc --base main
  [ "$status" -eq 2 ]
}
