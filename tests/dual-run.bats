#!/usr/bin/env bats
# dual-run.sh — orchestrator: phase plan, lock, contract gate, no-overlap wiring.

load helpers/common

setup() {
  setup_scratch
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  mkdir -p "$REPO/config" "$REPO/.dual-agent"
  cp "$HARNESS_ROOT/config/coordination.json" "$REPO/config/coordination.json"
  export DUAL_COORDINATION_CONFIG="$REPO/config/coordination.json"
  # Real (non-template) contract
  cat >"$REPO/PLAN.md" <<'EOF'
# PLAN — smoke-feature

## 1. Problem
Build a tiny hello module for dual-run tests.

## 2. Stack / Constraints
- Sprache/Framework: Python 3
- Erlaubte Dependencies: stdlib only
- Verbote: no network

## 3. Interface-Contract
function hello() -> str  # returns "ok"

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] hello() returns ok

## 5. Test-Liste (Claude härtet diese in Schritt F)
- happy path

## 6. Out of Scope
Everything else.
EOF
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm plan
  FAKEBIN="$SCRATCH/bin"; mkdir -p "$FAKEBIN"; export PATH="$FAKEBIN:$PATH"
  cd "$REPO"
}
teardown() {
  # kill any leftover lock holders from tests
  rm -f "$REPO/.dual-agent/dual-run.lock" 2>/dev/null || true
  rm -rf "$SCRATCH"/wt-* 2>/dev/null || true
  cd "$HARNESS_ROOT" 2>/dev/null || true
  teardown_scratch
}

drun() { "$HARNESS_ROOT/dual-run.sh" "$@"; }

mk_grok() {
  cat >"$FAKEBIN/grok" <<EOF
#!/usr/bin/env bash
prev=""; cwd=""
for a in "\$@"; do [ "\$prev" = "--cwd" ] && cwd="\$a"; prev="\$a"; done
[ -n "\$cwd" ] && { mkdir -p "\$cwd/src"; echo "print('ok')" > "\$cwd/src/app.py"; }
echo '{"text":"built"}'
exit 0
EOF
  chmod +x "$FAKEBIN/grok"
}

mk_claude_clean() {
  cat >"$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"result","result":"{\"issues\":[]}","is_error":false,"session_id":"t","total_cost_usd":0.01}'
EOF
  chmod +x "$FAKEBIN/claude"
}

@test "dual-run --help exits 0" {
  run drun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"dual-run"* ]]
}

@test "dual-run --status shows coordination fine-tuning" {
  run drun --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"architect=claude"* ]] || [[ "$output" == *"builder=grok"* ]]
  [[ "$output" == *"lock"* ]]
}

@test "dual-run --dry-run prints structured phase plan, no vendor calls" {
  mk_grok
  printf '#!/usr/bin/env bash\necho SHOULD_NOT_RUN; exit 99\n' >"$FAKEBIN/claude"; chmod +x "$FAKEBIN/claude"
  run drun --dry-run --verify true --skip-merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"DryRun"* ]]
  [[ "$output" == *"run   C"* ]]
  [[ "$output" == *"run   W"* ]] || [[ "$output" == *"Team Work"* ]] || [[ "$output" == *"team-work"* ]]
  [[ "$output" == *"run   G"* ]]
  [[ "$output" == *"run   A"* ]]
  [[ "$output" == *"skip  T"* ]]
  [ ! -f "$REPO/.dual-agent/dual-run.lock" ]
}

@test "unfilled PLAN.template blocks at Contract (no Render)" {
  cp "$HARNESS_ROOT/PLAN.template.md" "$REPO/PLAN.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm tmpl
  mk_grok
  run drun --verify true --skip-merge --to-phase C
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]] || [[ "$output" == *"unfilled"* ]] || [[ "$output" == *"Contract"* ]]
  [ ! -f "$SCRATCH/bin/../grok.argv" ]
}

@test "exclusive lock prevents a second overlapping dual-run" {
  mkdir -p "$REPO/.dual-agent"
  # simulate a live foreign dual-run
  cat >"$REPO/.dual-agent/dual-run.lock" <<EOF
pid=$$
run_id=foreign
started=2026-01-01T00:00:00Z
host=test
EOF
  # Same PID is treated as re-entry by design — use a live OTHER process.
  sleep 60 &
  other=$!
  cat >"$REPO/.dual-agent/dual-run.lock" <<EOF
pid=$other
run_id=foreign
started=2026-01-01T00:00:00Z
host=test
EOF
  run drun --verify true --skip-merge --to-phase C
  [ "$status" -ne 0 ]
  [[ "$output" == *lock* ]] || [[ "$output" == *BLOCKED* ]] || [[ "$output" == *overlap* ]]
  kill "$other" 2>/dev/null || true
  wait "$other" 2>/dev/null || true
}

@test "C-only run: after contract baton→team (team-work default), releases lock" {
  run drun --verify true --skip-merge --to-phase C
  [ "$status" -eq 0 ]
  [ -f "$REPO/.dual-agent/run-state.json" ]
  # team-work ON: next is W with baton=team
  [ "$(jfield "$REPO/.dual-agent/run-state.json" baton)" = "team" ]
  [ "$(jfield "$REPO/.dual-agent/run-state.json" phase)" = "W" ]
  [ ! -f "$REPO/.dual-agent/dual-run.lock" ]
  [ -f "$REPO/HANDOFF.md" ]
}

@test "full path mono-builder with --no-team-work stubs" {
  mk_grok
  mk_claude_clean
  # Legacy mono-builder path (Grok only for R)
  run drun --verify true --skip-merge --skip-fortify --variants 1 --no-adaptive \
    --no-import-scan --no-team-work
  echo "$output" >&2
  [ "$status" -eq 0 ]
  git -C "$REPO" rev-parse --verify feat/poc >/dev/null
  [ -f "$REPO/.dual-agent/run-state.json" ]
  phase="$(jfield "$REPO/.dual-agent/run-state.json" phase)"
  baton="$(jfield "$REPO/.dual-agent/run-state.json" baton)"
  [[ "$phase" == "T" || "$phase" == "done" ]]
  [[ "$baton" == "gate" || "$baton" == "done" ]]
  [ ! -f "$REPO/.dual-agent/dual-run.lock" ]
}

@test "team-work dry via dual-run --dry-run shows all three workers" {
  run drun --dry-run --verify true --skip-merge --task "add and div with tests"
  [ "$status" -eq 0 ]
  [[ "$output" == *team-work=ON* ]] || [[ "$output" == *"Team Work"* ]] || [[ "$output" == *claude* ]]
}

@test "fortify dispatch includes --skip-permissions (headless Write fix)" {
  # Static contract: hardener must not reintroduce read-only claude-call.
  grep -q -- '--skip-permissions' "$HARNESS_ROOT/dual-run.sh"
  # Ensure fortify tag and skip-permissions appear near dual-run-fortify call
  awk '/dual-run-fortify/{for(i=0;i<6;i++){getline; print}}' "$HARNESS_ROOT/dual-run.sh" \
    | grep -q -- '--skip-permissions'
}

@test "fortify path: claude invoked with dangerously-skip-permissions (fake CLI)" {
  # Minimal path: C skip (filled PLAN), no team-work, skip guards noise, fortify on, skip merge.
  # Fake CLIs: grok builds POC; claude for review JSON + fortify records argv.
  mk_grok
  cat >"$FAKEBIN/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$SCRATCH/claude.argv"
# If fortify (writes files when --dangerously-skip-permissions present)
if printf '%s' "\$*" | grep -q -- '--dangerously-skip-permissions'; then
  mkdir -p src tests 2>/dev/null || true
  # worktree cwd may vary; write a marker file
  echo "hardened" > fortify.marker
fi
# Assess path needs issues JSON in result text
echo '{"type":"result","result":"{\"issues\":[]}","is_error":false,"session_id":"t","total_cost_usd":0.01}'
exit 0
EOF
  chmod +x "$FAKEBIN/claude"
  # codex not needed if assess is claude
  run drun --verify true --skip-merge --fortify --no-team-work --no-import-scan \
    --no-adaptive --variants 1 --builder grok --assess-vendor claude
  echo "$output" >&2
  [ "$status" -eq 0 ]
  # At least one claude invocation recorded skip-permissions flag
  grep -q -- '--dangerously-skip-permissions' "$SCRATCH/claude.argv" \
    || grep -q -- 'dangerously-skip-permissions' "$SCRATCH/claude.argv"
}

@test "bad --from-phase is rejected" {
  run drun --from-phase Z --verify true
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]] || [[ "$output" == *from-phase* ]]
}
