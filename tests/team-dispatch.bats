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

# --- fail-closed: done without files is forbidden --------------------------

# Minimal single-package WORK for isolated execute tests (avoids multi-CLI order).
write_single_pkg_work() {
  local out="$1" plan="$2" assignee="${3:-claude}" paths="${4:-src/pkg00/}"
  python3 - "$out" "$plan" "$assignee" "$paths" <<'PY'
import json, sys
from datetime import datetime, timezone
out, plan, who, paths = sys.argv[1:5]
path_list = [p for p in paths.split(",") if p]
work = {
  "version": 1,
  "stamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "plan": plan,
  "task": "fail-closed-demo",
  "phase": "assigned",
  "packages": [{
    "id": "WP01",
    "kind": "core_impl",
    "title": "Write one file under owned path",
    "paths": path_list,
    "allows_tests": False,
    "tags": ["core_impl"],
    "status": "assigned",
    "assignee": who,
    "evidence": None,
  }],
  "assignment": {who: 1},
  "roster": {who: ["WP01"]},
}
open(out, "w", encoding="utf-8").write(json.dumps(work, indent=2) + "\n")
PY
}

# Fake CLIs that exit 0 but write nothing (the historical hole).
install_text_only_clis() {
  FAKEBIN="$SCRATCH/bin"
  mkdir -p "$FAKEBIN"
  cat >"$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"result","result":"text only, no files","is_error":false,"session_id":"t","total_cost_usd":0.01}'
EOF
  cat >"$FAKEBIN/grok" <<'EOF'
#!/usr/bin/env bash
echo '{"text":"text only","stopReason":"end","sessionId":"s1"}'
EOF
  cat >"$FAKEBIN/codex" <<'EOF'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && echo "text only" > "$a"
  prev="$a"
done
cat >/dev/null
echo '{"type":"item.completed"}'
EOF
  chmod +x "$FAKEBIN"/*
  export PATH="$FAKEBIN:$PATH"
}

# Fake CLIs that write a real file under --cwd (or process cwd for claude).
install_writing_clis() {
  FAKEBIN="$SCRATCH/bin"
  mkdir -p "$FAKEBIN"
  cat >"$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src/pkg00
echo "impl-from-claude" > src/pkg00/main.py
echo '{"type":"result","result":"wrote files","is_error":false,"session_id":"w","total_cost_usd":0.02}'
EOF
  cat >"$FAKEBIN/grok" <<'EOF'
#!/usr/bin/env bash
cwd="."
prev=""
for a in "$@"; do
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  prev="$a"
done
mkdir -p "$cwd/src/pkg00"
echo "impl-from-grok" > "$cwd/src/pkg00/main.py"
echo '{"text":"wrote","stopReason":"end","sessionId":"s1"}'
EOF
  cat >"$FAKEBIN/codex" <<'EOF'
#!/usr/bin/env bash
cwd="."
prev=""
for a in "$@"; do
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  [[ "$prev" == "-o" ]] && echo "CODEX_OK" > "$a"
  prev="$a"
done
mkdir -p "$cwd/src/pkg00"
echo "impl-from-codex" > "$cwd/src/pkg00/main.py"
echo '{"type":"item.completed"}'
EOF
  chmod +x "$FAKEBIN"/*
  export PATH="$FAKEBIN:$PATH"
}

@test "execute FAIL-CLOSED: exit 0 without file changes → package failed, not done" {
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  cp "$PLAN" "$REPO/PLAN.md"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm plan
  write_single_pkg_work "$REPO/WORK.json" "$REPO/PLAN.md" "claude" "src/pkg00/"
  install_text_only_clis

  # Spend/logs stay inside scratch repo (claude-call resolves git root from cwd).
  export DUAL_AGENT_SPEND_FILE="$REPO/ledger/SPEND.jsonl"
  mkdir -p "$REPO/ledger" "$REPO/.dual-agent/logs" "$REPO/.dual-agent/tmp"

  cd "$REPO"
  run td execute --work "$REPO/WORK.json" --plan "$REPO/PLAN.md"
  cd - >/dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *fail-closed* ]] || [[ "$output" == *"no file changes"* ]]
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
p=w["packages"][0]
assert p["status"]=="failed", p
assert "fail-closed" in (p.get("evidence") or ""), p
' "$REPO/WORK.json"
  # no fake success commit
  ! git -C "$REPO" log --oneline | grep -q 'team(claude): WP01'
}

@test "execute SUCCESS: worker writes files → done + team commit + evidence" {
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  cp "$PLAN" "$REPO/PLAN.md"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm plan
  write_single_pkg_work "$REPO/WORK.json" "$REPO/PLAN.md" "grok" "src/pkg00/"
  install_writing_clis

  export DUAL_AGENT_SPEND_FILE="$REPO/ledger/SPEND.jsonl"
  mkdir -p "$REPO/ledger" "$REPO/.dual-agent/logs" "$REPO/.dual-agent/tmp"

  cd "$REPO"
  run td execute --work "$REPO/WORK.json" --plan "$REPO/PLAN.md"
  cd - >/dev/null

  [ "$status" -eq 0 ]
  [ -f "$REPO/src/pkg00/main.py" ]
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
assert w["phase"]=="executed"
p=w["packages"][0]
assert p["status"]=="done", p
assert "files committed" in (p.get("evidence") or ""), p
assert p.get("files_changed"), p
assert any("src/pkg00" in f for f in p["files_changed"]), p
assert p.get("commit_sha"), p
' "$REPO/WORK.json"
  git -C "$REPO" log --oneline | grep -q 'team(grok): WP01'
}

@test "execute FAIL-CLOSED: trespass outside owned paths" {
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  cp "$PLAN" "$REPO/PLAN.md"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm plan
  write_single_pkg_work "$REPO/WORK.json" "$REPO/PLAN.md" "grok" "src/pkg00/"
  FAKEBIN="$SCRATCH/bin"; mkdir -p "$FAKEBIN"
  # writes under owned path AND trespasses into other/
  cat >"$FAKEBIN/grok" <<'EOF'
#!/usr/bin/env bash
cwd="."
prev=""
for a in "$@"; do
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  prev="$a"
done
mkdir -p "$cwd/src/pkg00" "$cwd/other"
echo ok > "$cwd/src/pkg00/main.py"
echo bad > "$cwd/other/secret.py"
echo '{"text":"trespass","stopReason":"end","sessionId":"s1"}'
EOF
  chmod +x "$FAKEBIN/grok"
  export PATH="$FAKEBIN:$PATH"
  export DUAL_AGENT_SPEND_FILE="$REPO/ledger/SPEND.jsonl"
  mkdir -p "$REPO/ledger" "$REPO/.dual-agent/logs"

  cd "$REPO"
  run td execute --work "$REPO/WORK.json" --plan "$REPO/PLAN.md"
  cd - >/dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *trespass* ]]
  python3 -c '
import json,sys
p=json.load(open(sys.argv[1]))["packages"][0]
assert p["status"]=="failed", p
assert "trespass" in (p.get("evidence") or ""), p
' "$REPO/WORK.json"
}

@test "assign FAIL-CLOSED: overlapping package paths" {
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  cat >"$REPO/WORK.json" <<'EOF'
{
  "version": 1,
  "plan": "PLAN.md",
  "phase": "decomposed",
  "packages": [
    {"id":"WP01","kind":"core_impl","title":"a","paths":["src/api/"],"status":"pending","assignee":null},
    {"id":"WP02","kind":"core_impl","title":"b","paths":["src/api/handlers/"],"status":"pending","assignee":null}
  ]
}
EOF
  install_fake_clis
  run td assign --work "$REPO/WORK.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *overlap* ]] || [[ "$output" == *path-disjoint* ]] || [[ "$output" == *BLOCKED* ]]
}
