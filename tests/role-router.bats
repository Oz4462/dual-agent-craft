#!/usr/bin/env bats
# role-router.sh — adaptive who-does-what (profiles, signals, cross-vendor moat).

load helpers/common

setup() {
  setup_scratch
  export DUAL_ROLES_CONFIG="$HARNESS_ROOT/config/roles.json"
}
teardown() { teardown_scratch; }

rr() { "$HARNESS_ROOT/lib/role-router.sh" "$@"; }

@test "profiles lists all adaptive profiles" {
  run rr profiles
  [ "$status" -eq 0 ]
  [[ "$output" == *minimal* ]]
  [[ "$output" == *standard* ]]
  [[ "$output" == *thorough* ]]
  [[ "$output" == *security* ]]
  [[ "$output" == *sandbox* ]]
}

@test "auto: tiny spike → minimal, grok builder, no fortify" {
  run rr route --task "tiny hello world spike prototype only" --profile auto --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" profile)" = "minimal" ]
  [ "$(jfield "$SCRATCH/a.json" functions.builder)" = "grok" ]
  [ "$(jfield "$SCRATCH/a.json" functions.assessor)" = "claude" ]
  [ "$(jfield "$SCRATCH/a.json" flags.fortify)" = "false" ]
  [ "$(jfield "$SCRATCH/a.json" params.eval_k)" = "1" ]
}

@test "auto: OAuth/JWT/payment → security profile, codex builder, fortify+security" {
  run rr route --task "add OAuth JWT auth and payment billing" --profile auto --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" profile)" = "security" ]
  [ "$(jfield "$SCRATCH/a.json" functions.builder)" = "codex" ]
  [ "$(jfield "$SCRATCH/a.json" functions.assessor)" = "claude" ]
  [ "$(jfield "$SCRATCH/a.json" flags.fortify)" = "true" ]
  [ "$(jfield "$SCRATCH/a.json" flags.security_pass)" = "true" ]
  # cross-vendor moat
  [ "$(jfield "$SCRATCH/a.json" functions.builder)" != "$(jfield "$SCRATCH/a.json" functions.assessor)" ]
}

@test "auto: distributed migration pipeline → thorough" {
  run rr route --task "distributed migration pipeline multi-module" --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" profile)" = "thorough" ]
  [ "$(jfield "$SCRATCH/a.json" flags.fortify)" = "true" ]
  [ "$(jfield "$SCRATCH/a.json" flags.scout)" = "true" ]
}

@test "cross-vendor moat: builder=assessor=codex → assessor swapped to claude" {
  run rr route --task "implement feature" --builder codex --assessor codex --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" functions.builder)" = "codex" ]
  [ "$(jfield "$SCRATCH/a.json" functions.assessor)" = "claude" ]
  run bash -c "echo '$output' | grep -q moat || python3 -c 'import json,sys; a=json.load(open(\"$SCRATCH/a.json\")); assert any(\"moat\" in r for r in a[\"reasons\"])'"
  [ "$status" -eq 0 ]
}

@test "forced profile security ignores low-complexity wording" {
  run rr route --task "tiny spike" --profile security --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" profile)" = "security" ]
  [ "$(jfield "$SCRATCH/a.json" functions.builder)" = "codex" ]
}

@test "arbiter and guards are always gate" {
  run rr route --task "anything" --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" functions.arbiter)" = "gate" ]
  [ "$(jfield "$SCRATCH/a.json" functions.guards)" = "gate" ]
}

@test "mid-run REVIEW high severity forces fortify" {
  cat >"$SCRATCH/REVIEW.json" <<'EOF'
{"verdict":"eval-decides","issues":[{"id":"I1","severity":"high","claim":"auth bypass"}],"conceded":["I2"]}
EOF
  run rr route --task "normal feature" --profile standard --review "$SCRATCH/REVIEW.json" --json
  [ "$status" -eq 0 ]
  echo "$output" >"$SCRATCH/a.json"
  [ "$(jfield "$SCRATCH/a.json" flags.fortify)" = "true" ]
  [ "$(jfield "$SCRATCH/a.json" flags.security_pass)" = "true" ]
  [ "$(jfield "$SCRATCH/a.json" mid_run.applied)" = "true" ]
}

@test "explain prints who matrix" {
  run rr explain --task "add authentication"
  [ "$status" -eq 0 ]
  [[ "$output" == *architect* ]]
  [[ "$output" == *builder* ]]
  [[ "$output" == *assessor* ]]
  [[ "$output" == *arbiter* ]]
}

@test "dual-run --who uses role-router" {
  run "$HARNESS_ROOT/dual-run.sh" --who --task "payment token auth"
  [ "$status" -eq 0 ]
  [[ "$output" == *security* ]] || [[ "$output" == *builder* ]]
  [[ "$output" == *who-does-what* ]] || [[ "$output" == *architect* ]] || [[ "$output" == *profile* ]]
}

@test "dual-run --dry-run shows adaptive agents for security task" {
  run "$HARNESS_ROOT/dual-run.sh" --dry-run --task "OAuth secret password auth" \
    --verify true --skip-merge --plan /dev/null 2>&1 || true
  # plan may be missing — use a temp plan
  printf '# PLAN — x\n## 1. Problem\nauth feature\n## 2. Stack / Constraints\n- Sprache/Framework: py\n- Erlaubte Dependencies: stdlib\n- Verbote: none\n## 3. Interface-Contract\nx\n## 4. Akzeptanzkriterien (verifizierbar, binär)\n- [ ] ok\n## 5. Test-Liste (Claude härtet diese in Schritt F)\n- t\n## 6. Out of Scope\nnone\n' >"$SCRATCH/PLAN.md"
  run "$HARNESS_ROOT/dual-run.sh" --dry-run --task "OAuth secret password auth" \
    --verify true --skip-merge --plan "$SCRATCH/PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *builder=codex* ]] || [[ "$output" == *codex* ]]
  [[ "$output" == *profile* ]]
}
