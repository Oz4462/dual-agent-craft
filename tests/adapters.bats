#!/usr/bin/env bats
# Vendor adapters — contract shape via stubbed CLIs (no billed calls, no network).
# Every adapter must print {exit_code, text, json_log, stdout_log} on stdout.

load helpers/common

setup() {
  setup_scratch
  install_fake_clis
  PROMPT="$SCRATCH/prompt.txt"
  echo "do the thing" > "$PROMPT"
}
teardown() { teardown_scratch; }

text_of()  { python3 -c 'import sys,json;print(json.load(sys.stdin)["text"].strip())'; }
exit_of()  { python3 -c 'import sys,json;print(json.load(sys.stdin)["exit_code"])'; }

@test "grok-call: contract JSON with extracted text; noise stays out of result" {
  run "$HARNESS_ROOT/lib/grok-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | text_of)" = "GROK_FAKE_OK" ]
  [[ "$output" != *AuthorizationRequired* ]]
}

@test "claude-call: contract JSON + SPEND.jsonl cost telemetry" {
  rm -f "$HARNESS_ROOT/ledger/SPEND.jsonl.bak"
  [ -f "$HARNESS_ROOT/ledger/SPEND.jsonl" ] && cp "$HARNESS_ROOT/ledger/SPEND.jsonl" "$HARNESS_ROOT/ledger/SPEND.jsonl.bak"
  run "$HARNESS_ROOT/lib/claude-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | text_of)" = "CLAUDE_FAKE_OK" ]
  tail -1 "$HARNESS_ROOT/ledger/SPEND.jsonl" | grep -q '"cost_usd": 0.13'
  # restore ledger state
  if [ -f "$HARNESS_ROOT/ledger/SPEND.jsonl.bak" ]; then
    mv "$HARNESS_ROOT/ledger/SPEND.jsonl.bak" "$HARNESS_ROOT/ledger/SPEND.jsonl"
  else
    rm -f "$HARNESS_ROOT/ledger/SPEND.jsonl"
  fi
}

@test "codex-call: clean text via -o last-message file" {
  run "$HARNESS_ROOT/lib/codex-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | text_of)" = "CODEX_FAKE_OK" ]
}

@test "missing prompt file -> BLOCKED exit 1 (all adapters)" {
  for a in grok-call claude-call codex-call local-call; do
    run "$HARNESS_ROOT/lib/$a.sh" --prompt-file "$SCRATCH/nope.txt"
    [ "$status" -eq 1 ]
  done
}

@test "claude-call: is_error=true in response -> non-zero exit" {
  cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"result","result":"boom","is_error":true}'
EOF
  chmod +x "$FAKEBIN/claude"
  run "$HARNESS_ROOT/lib/claude-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -ne 0 ]
}

@test "local-call: unreachable Ollama -> honest BLOCKED exit 1" {
  run "$HARNESS_ROOT/lib/local-call.sh" --prompt-file "$PROMPT" --endpoint "http://127.0.0.1:59999/api/chat" --timeout 2
  [ "$status" -eq 1 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "grok-call dry-run makes no call and exits 0" {
  rm -f "$FAKEBIN/grok.called"
  cat > "$FAKEBIN/grok" <<EOF
#!/usr/bin/env bash
touch "$FAKEBIN/grok.called"
echo '{}'
EOF
  chmod +x "$FAKEBIN/grok"
  run "$HARNESS_ROOT/lib/grok-call.sh" --prompt-file "$PROMPT" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$FAKEBIN/grok.called" ]
}

@test "AUDIT-FIX: claude is_error:true surfaces in the EMITTED contract exit_code" {
  cat > "$FAKEBIN/claude" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo '{"result":"boom","is_error":true}'
STUB
  chmod +x "$FAKEBIN/claude"
  run "$HARNESS_ROOT/lib/claude-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | exit_of)" != "0" ]
}

@test "AUDIT-FIX(low): claude-call writes cost to DUAL_AGENT_SPEND_FILE when set" {
  EXT="$SCRATCH/outside/SPEND.jsonl"
  DUAL_AGENT_SPEND_FILE="$EXT" run "$HARNESS_ROOT/lib/claude-call.sh" --prompt-file "$PROMPT" --tag t
  [ "$status" -eq 0 ]
  [ -f "$EXT" ]
  grep -q '"cost_usd": 0.13' "$EXT"
}

@test "codex-call(P1): --full-auto never emits a sandbox-bypass flag (argv check)" {
  out="$("$HARNESS_ROOT/lib/codex-call.sh" --prompt-file "$PROMPT" --full-auto --dry-run 2>&1)"
  [[ "$out" != *dangerously* ]]
  [[ "$out" == *"workspace-write"* ]]
}

@test "backlog-C: dual-review --assess-vendor codex routes ASSESS to codex-call" {
  grep -q 'ASSESS_VENDOR" == codex' "$HARNESS_ROOT/dual-review.sh"
  grep -q 'codex-call.sh' "$HARNESS_ROOT/dual-review.sh"
  grep -q 'sandbox read-only' "$HARNESS_ROOT/dual-review.sh"
}
@test "backlog-C: dual-build --builder codex routes render to codex-call, forces n=1" {
  grep -q 'BUILDER" == codex' "$HARNESS_ROOT/dual-build.sh"
  grep -q 'codex-call.sh' "$HARNESS_ROOT/dual-build.sh"
}
@test "backlog-C: invalid --assess-vendor / --builder is rejected" {
  S=$(mktemp -d); git init -q -b main "$S/r" >/dev/null; cd "$S/r"; git config user.email t@t; git config user.name t
  echo x>a; git add -A; git commit -qm b; echo "real plan">PLAN.md; git add -A; git commit -qm p; git checkout -qb feat/poc; echo y>b; git add -A; git commit -qm poc; git checkout -q main
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main --assess-vendor gpt
  [ "$status" -ne 0 ]; [[ "$output" == *"claude or codex"* ]]
  cd - >/dev/null; rm -rf "$S"
}
