#!/usr/bin/env bats
# team-dispatch — Claude + Grok + Codex all get work packages and execute.

load helpers/common

setup() {
  setup_scratch
  export DUAL_TEAM_WORK_CONFIG="$HARNESS_ROOT/config/team-work.json"
  PLAN="$SCRATCH/PLAN.md"
  cat >"$PLAN" <<'EOF'
# PLAN — team-demo
## 1. Problem
Build a small calculator module for team dispatch tests.
## 2. Stack / Constraints
- Sprache/Framework: Python 3
- Erlaubte Dependencies: stdlib only
- Verbote: no network
## 3. Interface-Contract
function add(a, b) -> number
function div(a, b) -> number
## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] add returns sum of two numbers
- [ ] div fails closed on zero divisor
- [ ] auth token rejected when missing
## 5. Test-Liste (Claude härtet diese in Schritt F)
- happy path add
- zero division
## 6. Out of Scope
UI
EOF
  WORK="$SCRATCH/WORK.json"
}
teardown() { teardown_scratch; }

td() { "$HARNESS_ROOT/lib/team-dispatch.sh" "$@"; }

@test "decompose yields ≥3 path-disjoint packages including tests" {
  run td decompose --plan "$PLAN" --out "$WORK" --task calculator
  [ "$status" -eq 0 ]
  [ -f "$WORK" ]
  n="$(python3 -c 'import json;print(len(json.load(open("'"$WORK"'"))["packages"]))')"
  [ "$n" -ge 3 ]
  # tests package present
  python3 -c 'import json,sys; ps=json.load(open(sys.argv[1]))["packages"];
assert any(p.get("kind")=="tests" or p.get("allows_tests") for p in ps)' "$WORK"
}

@test "assign gives work to claude AND grok AND codex" {
  td decompose --plan "$PLAN" --out "$WORK" >/dev/null
  run td assign --work "$WORK"
  [ "$status" -eq 0 ]
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
a=w["assignment"]
assert a.get("claude",0)>=1, a
assert a.get("grok",0)>=1, a
assert a.get("codex",0)>=1, a
# architect works (not only management)
assert "claude" in str(w.get("roster",{})), w
# tests not assigned to grok/codex
for p in w["packages"]:
    if p.get("kind")=="tests" or p.get("allows_tests"):
        assert p.get("assignee")=="claude", p
' "$WORK"
}

@test "execute --dry-run marks all packages dry-ok" {
  td run --plan "$PLAN" --task calculator --dry-run --out "$WORK" >/dev/null
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
assert w["phase"]=="executed-dry"
assert all(p["status"]=="dry-ok" for p in w["packages"])
assert w["assignment"]["claude"]>=1
assert w["assignment"]["grok"]>=1
assert w["assignment"]["codex"]>=1
' "$WORK"
}

@test "status prints roster" {
  td run --plan "$PLAN" --dry-run --out "$WORK" >/dev/null
  run td status "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *claude* ]]
  [[ "$output" == *grok* ]]
  [[ "$output" == *codex* ]]
}

@test "never assign tests package to grok" {
  td decompose --plan "$PLAN" --out "$WORK" >/dev/null
  td assign --work "$WORK" >/dev/null
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
for p in w["packages"]:
    if p.get("kind")=="tests":
        assert p["assignee"]=="claude", p
' "$WORK"
}
