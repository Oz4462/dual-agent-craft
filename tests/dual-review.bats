#!/usr/bin/env bats
# dual-review.sh — bounded cross-review orchestration with STUBBED CLIs.
# Validates the full pipeline: assess-JSON extraction -> rebuttal -> grounding
# gate (defend w/o citation -> unsure) -> classification -> ledger.

load helpers/common

setup() {
  setup_scratch
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  cp "$HARNESS_ROOT/PLAN.template.md" "$REPO/PLAN.md"
  sed -i 's/<Feature-Name>/smoke/; s/<Was soll gebaut werden.*/test feature/' "$REPO/PLAN.md" 2>/dev/null || true
  echo "problem: test feature" >> "$REPO/PLAN.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm plan
  git -C "$REPO" checkout -qb feat/poc
  mkdir -p "$REPO/src"; echo "impl" > "$REPO/src/app.py"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm poc
  git -C "$REPO" checkout -q main
  FAKEBIN="$SCRATCH/bin"; mkdir -p "$FAKEBIN"; export PATH="$FAKEBIN:$PATH"
}
teardown() { teardown_scratch; }

# Stub claude to return a fixed issues[] (fenced, to prove extraction robustness).
stub_claude_issues() {
  cat > "$FAKEBIN/claude" <<EOF
#!/usr/bin/env bash
cat >/dev/null
python3 - <<'PY'
import json
issues = $1
print(json.dumps({"type":"result","result":"\`\`\`json\n"+json.dumps({"issues":issues})+"\n\`\`\`","is_error":False}))
PY
EOF
  chmod +x "$FAKEBIN/claude"
}

stub_grok_rebuttals() {
  cat > "$FAKEBIN/grok" <<EOF
#!/usr/bin/env bash
python3 - <<'PY'
import json
rebs = $1
print(json.dumps({"text": json.dumps({"rebuttals": rebs})}))
PY
EOF
  chmod +x "$FAKEBIN/grok"
}

@test "clean diff (no issues) -> verdict clean, exit 0, no grok call" {
  stub_claude_issues '[]'
  printf '#!/usr/bin/env bash\nexit 99\n' > "$FAKEBIN/grok"; chmod +x "$FAKEBIN/grok"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Clean diff"* ]]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" verdict)" = "clean" ]
}

@test "concede routes to conceded; grounded defend+decidable -> eval-decides" {
  stub_claude_issues '[{"id":"I1","severity":"high","file":"src/app.py","kind":"drift","claim":"c1","eval_decidable":True},{"id":"I2","severity":"med","file":"src/app.py","kind":"style","claim":"c2","eval_decidable":True}]'
  stub_grok_rebuttals '[{"id":"I1","verdict":"concede","citation":"none","reason":"r"},{"id":"I2","verdict":"defend","citation":"PLAN-4.1","reason":"r"}]'
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -eq 0 ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" conceded.0)" = "I1" ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" eval_decides.0)" = "I2" ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" verdict)" = "eval-decides" ]
}

@test "grounding gate: defend WITHOUT citation auto-downgrades to unsure" {
  stub_claude_issues '[{"id":"I1","severity":"med","file":"src/app.py","kind":"drift","claim":"c","eval_decidable":True}]'
  stub_grok_rebuttals '[{"id":"I1","verdict":"defend","citation":"none","reason":"bluff"}]'
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -eq 0 ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" unsure.0)" = "I1" ]
}

@test "grounded defend + subjective -> tie -> tiebreak recommended" {
  stub_claude_issues '[{"id":"I1","severity":"low","file":"src/app.py","kind":"style","claim":"naming","eval_decidable":False}]'
  stub_grok_rebuttals '[{"id":"I1","verdict":"defend","citation":"PLAN-3","reason":"r"}]'
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -eq 0 ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" ties.0)" = "I1" ]
  [[ "$output" == *"dual-tiebreak"* ]]
}

@test "no rebuttal answer -> defend w/o citation -> grounding gate routes it to unsure" {
  # Matches the PS original's ACTUAL semantics: an unanswered issue becomes an
  # ungrounded defend, which the anti-bluff gate downgrades to unsure (never
  # silently dropped, never accepted by silence).
  stub_claude_issues '[{"id":"I1","severity":"med","file":"src/app.py","kind":"drift","claim":"c","eval_decidable":True}]'
  stub_grok_rebuttals '[]'
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -eq 0 ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" unsure.0)" = "I1" ]
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" verdict)" = "clarify-unknowns" ]
}

@test "empty diff -> BLOCKED" {
  cd "$REPO"
  git checkout -qb feat/empty
  git checkout -q main
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/empty --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "AUDIT-FIX: garbage/prose assess reply -> BLOCK, never 'clean'" {
  cat > "$FAKEBIN/claude" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo '{"result":"I am sorry, I cannot review this right now.","is_error":false}'
STUB
  chmod +x "$FAKEBIN/claude"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"fail-closed"* ]]
}

@test "AUDIT-FIX: is_error:true with process exit 0 -> assess BLOCKED" {
  cat > "$FAKEBIN/claude" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo '{"result":"budget exceeded","is_error":true}'
STUB
  chmod +x "$FAKEBIN/claude"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"Assess"*"failed"* ]]
}

@test "AUDIT-P1(#4): a failed rebuttal call BLOCKS (fail-closed), REVIEW.json not overwritten clean" {
  stub_claude_issues '[{"id":"I1","severity":"high","file":"src/app.py","kind":"drift","claim":"c","eval_decidable":True}]'
  # grok stub prints nothing and exits 1 -> rebuttal call must fail the run
  printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKEBIN/grok"; chmod +x "$FAKEBIN/grok"
  # seed a prior clean REVIEW.json to prove it is NOT clobbered into a false verdict
  mkdir -p "$HARNESS_ROOT/ledger"
  echo '{"verdict":"prior"}' > "$HARNESS_ROOT/ledger/REVIEW.json"
  cd "$REPO"
  run "$HARNESS_ROOT/dual-review.sh" --plan PLAN.md --poc feat/poc --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *Rebuttal* ]] || [[ "$output" == *BLOCKED* ]]
  # prior ledger must be untouched (no unsure/clean rewrite on a failed rebuttal)
  [ "$(jfield "$HARNESS_ROOT/ledger/REVIEW.json" verdict)" = "prior" ]
  cd - >/dev/null
}
