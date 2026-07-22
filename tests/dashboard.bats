#!/usr/bin/env bats
# dual-dashboard.sh + dashboard_render.py — the cockpit generator.
# Deterministic, offline: builds a throwaway ledger and asserts the HTML.

load helpers/common

setup()    { setup_scratch; }
teardown() { teardown_scratch; }

render() { # render <ledger_dir> -> HTML on stdout
  python3 "$HARNESS_ROOT/harness/lib/dashboard_render.py" "$1" "$2"
}

@test "renders a self-contained, doctype'd, theme-aware page with valid injected JSON" {
  mkdir -p "$SCRATCH/ledger"
  echo '{"branch":"feat/x","has_plan":true,"suite":"143/143","stamp":"now","repo":"r"}' > "$SCRATCH/state.json"
  run render "$SCRATCH/ledger" "$SCRATCH/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == '<!doctype html>'* ]]
  [[ "$output" == *'window.LEDGER = {'* ]]
  [[ "$output" == *'prefers-color-scheme:dark'* ]]
  [[ "$output" == *'data-theme="dark"'* ]]
  [[ "$output" == *'data-theme="light"'* ]]
  # the injected LEDGER object parses as JSON
  printf '%s' "$output" | python3 -c '
import sys, re, json
h=sys.stdin.read()
m=re.search(r"window\.LEDGER = (\{.*?\}) \|\| \{\}", h, re.S)
assert m, "no LEDGER"
json.loads(m.group(1))
'
}

@test "reflects real ledger verdicts (import-scan BLOCK, pass^k, tie winner)" {
  L="$SCRATCH/ledger"; mkdir -p "$L"
  echo '{"verdict":"BLOCK","scanned":3,"invented":[{"pkg":"x"}],"off_contract":[],"supply_chain":[],"stamp":"s"}' > "$L/IMPORT-SCAN.json"
  echo '{"passes":3,"k":3,"pass_pow_k":1,"pass_at_k":1,"rate":1.0,"early_stopped":false}' > "$L/EVAL.json"
  echo '{"winner":"A","issue_id":"I3","A":{"passes":3,"pass_pow_k":1},"B":{"passes":1,"pass_pow_k":0}}' > "$L/TIEBREAK.json"
  echo '{"branch":"main","stamp":"now"}' > "$SCRATCH/state.json"
  run render "$L" "$SCRATCH/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'BLOCK'* ]]
  [[ "$output" == *'"pass_pow_k": 1'* ]]
  [[ "$output" == *'"winner": "A"'* ]]
}

@test "empty ledger -> still a valid page (idle cockpit), no crash" {
  mkdir -p "$SCRATCH/ledger"
  echo '{"branch":"main","stamp":"now"}' > "$SCRATCH/state.json"
  run render "$SCRATCH/ledger" "$SCRATCH/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == '<!doctype html>'* ]]
  # CRAFT pipeline always present even with no runs
  [[ "$output" == *'CRAFT pipeline'* ]]
}

@test "no unescaped template placeholder leaks into the output" {
  mkdir -p "$SCRATCH/ledger"
  echo '{"stamp":"now"}' > "$SCRATCH/state.json"
  run render "$SCRATCH/ledger" "$SCRATCH/state.json"
  [[ "$output" != *'__LEDGER'* ]]
  [[ "$output" != *'插'* ]]   # the stray char that was caught in review
}

@test "the wrapper generates dashboard.html and reports the path" {
  # run the real wrapper against the repo's own ledger into a scratch out
  run "$HARNESS_ROOT/dual-dashboard.sh" --out "$SCRATCH/dash.html"
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH/dash.html" ]
  [[ "$output" == *'self-contained'* ]]
  head -c 15 "$SCRATCH/dash.html" | grep -q '<!doctype html>'
}
