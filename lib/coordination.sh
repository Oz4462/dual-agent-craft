#!/usr/bin/env bash
# coordination.sh — baton, exclusive lock, phase machine, ownership fine-tuning.
#
# Sourceable library AND CLI:
#   source lib/coordination.sh   # functions available
#   lib/coordination.sh <cmd>    # see --help
#
# Loads config/coordination.json (override: DUAL_COORDINATION_CONFIG).
# Enforces PROTOCOL invariants 1–2 structurally so Claude and Grok cannot
# overlap: one exclusive dual-run lock, one BATON holder, one PHASE at a time.
set -uo pipefail

_COORD_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$_COORD_HERE/common.sh"

# --- config load ------------------------------------------------------------
coordination_config_path() {
  if [[ -n "${DUAL_COORDINATION_CONFIG:-}" ]]; then
    printf '%s\n' "$DUAL_COORDINATION_CONFIG"
    return
  fi
  local root
  # Prefer harness root (parent of lib/) so tests can point DUAL_COORDINATION_CONFIG
  # at a fixture without depending on cwd.
  root="$(cd "$_COORD_HERE/.." && pwd)"
  printf '%s\n' "$root/config/coordination.json"
}

# coordination_get <dotted.path> [default]
# Prints the JSON scalar/object (compact) at path, or default if missing.
coordination_get() {
  local path="$1" default="${2:-}"
  local cfg
  cfg="$(coordination_config_path)"
  [[ -f "$cfg" ]] || { printf '%s\n' "$default"; return 0; }
  CFG="$cfg" PATH_D="$path" DEF="$default" python3 - <<'PY'
import json, os, sys
cfg = os.environ["CFG"]
path = os.environ["PATH_D"]
default = os.environ.get("DEF", "")
try:
    obj = json.load(open(cfg, encoding="utf-8"))
except Exception:
    print(default); sys.exit(0)
cur = obj
for part in path.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(default); sys.exit(0)
if isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(",", ":")))
elif cur is None:
    print(default)
else:
    print(cur)
PY
}

# --- paths ------------------------------------------------------------------
_coord_root() {
  # Working project root = git toplevel if available, else harness root.
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    cd "$_COORD_HERE/.." && pwd
  fi
}

coordination_state_path() {
  local root rel
  root="$(_coord_root)"
  rel="$(coordination_get anti_overlap.state_file '.dual-agent/run-state.json')"
  printf '%s/%s\n' "$root" "$rel"
}

coordination_lock_path() {
  local root rel
  root="$(_coord_root)"
  rel="$(coordination_get anti_overlap.lock_file '.dual-agent/dual-run.lock')"
  printf '%s/%s\n' "$root" "$rel"
}

# --- exclusive lock (anti double-run / double-work) -------------------------
# coordination_lock_acquire [run_id]
# Fail-closed if another live dual-run holds the lock.
coordination_lock_acquire() {
  local run_id="${1:-$$}" lock dir pid
  lock="$(coordination_lock_path)"
  dir="$(dirname "$lock")"
  mkdir -p "$dir"

  if [[ -f "$lock" ]]; then
    # shellcheck disable=SC1090
    pid="$(awk -F= '/^pid=/{print $2}' "$lock" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # Same PID re-entry (nested source) is OK.
      if [[ "$pid" != "$$" ]]; then
        fail_code 3 "dual-run lock held by live PID $pid ($lock) — another dual task is active. No overlapping work (anti_overlap.exclusive_run_lock)."
      fi
    else
      warn "stale dual-run lock (PID ${pid:-?} dead) — reclaiming."
      rm -f "$lock"
    fi
  fi

  # Atomic create: O_EXCL via noclobber.
  (
    set -o noclobber
    cat >"$lock" <<EOF
pid=$$
run_id=$run_id
started=$(iso_now)
host=$(hostname 2>/dev/null || echo unknown)
EOF
  ) 2>/dev/null || fail_code 3 "could not create exclusive lock $lock — concurrent dual-run?"
}

coordination_lock_release() {
  local lock pid
  lock="$(coordination_lock_path)"
  [[ -f "$lock" ]] || return 0
  pid="$(awk -F= '/^pid=/{print $2}' "$lock" 2>/dev/null || true)"
  # Only the holder (or a dead-pid cleanup) may release.
  if [[ -z "$pid" || "$pid" == "$$" ]] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$lock"
  fi
}

# --- machine state (baton + phase) ------------------------------------------
# coordination_state_init <run_id> [task]
coordination_state_init() {
  local run_id="$1" task="${2:-}" sp dir
  sp="$(coordination_state_path)"
  dir="$(dirname "$sp")"
  mkdir -p "$dir"
  RUN_ID="$run_id" TASK="$task" SP="$sp" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state = {
    "run_id": os.environ["RUN_ID"],
    "task": os.environ.get("TASK", ""),
    "baton": "claude",
    "phase": "C",
    "active_agent": "claude",
    "status": "running",
    "history": [{"at": now, "phase": "C", "baton": "claude", "event": "init"}],
    "updated_at": now,
}
open(os.environ["SP"], "w", encoding="utf-8").write(json.dumps(state, indent=2) + "\n")
PY
}

# coordination_state_get <field>
coordination_state_get() {
  local field="$1" sp
  sp="$(coordination_state_path)"
  [[ -f "$sp" ]] || { printf '\n'; return 0; }
  json_field "$sp" "$field"
}

# coordination_state_set_phase <phase> <baton> [event]
coordination_state_set_phase() {
  local phase="$1" baton="$2" event="${3:-advance}" sp
  sp="$(coordination_state_path)"
  [[ -f "$sp" ]] || fail "run-state missing — call coordination_state_init first."
  SP="$sp" PHASE="$phase" BATON="$baton" EVENT="$event" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
sp = os.environ["SP"]
st = json.load(open(sp, encoding="utf-8"))
st["phase"] = os.environ["PHASE"]
st["baton"] = os.environ["BATON"]
st["active_agent"] = os.environ["BATON"]
st["updated_at"] = now
hist = st.setdefault("history", [])
hist.append({"at": now, "phase": st["phase"], "baton": st["baton"], "event": os.environ["EVENT"]})
if os.environ["PHASE"] == "done" or os.environ["BATON"] == "done":
    st["status"] = "done"
open(sp, "w", encoding="utf-8").write(json.dumps(st, indent=2) + "\n")
PY
}

# coordination_require_baton <agent>
# Fail-closed if the named agent does not hold the baton (invariant 2).
coordination_require_baton() {
  local agent="$1" require holder
  require="$(coordination_get anti_overlap.require_baton true)"
  [[ "$require" == "true" ]] || return 0
  holder="$(coordination_state_get baton)"
  [[ -n "$holder" ]] || fail "no baton state — refuse to act (invariant 2)."
  [[ "$holder" == "$agent" || "$holder" == "gate" && "$agent" == "gate" ]] \
    || fail "BATON is '$holder', not '$agent' — no overlapping turn (invariant 2)."
}

# coordination_assert_phase <expected>
coordination_assert_phase() {
  local expected="$1" cur
  cur="$(coordination_state_get phase)"
  [[ "$cur" == "$expected" ]] \
    || fail "phase is '$cur', expected '$expected' — refuse double/out-of-order work (anti_overlap.no_parallel_phases)."
}

# coordination_phase_agent <phase> -> agent name
coordination_phase_agent() {
  coordination_get "phase_agent.$1" "unknown"
}

# coordination_next_phase <phase>
coordination_next_phase() {
  coordination_get "phase_next.$1" "done"
}

# coordination_baton_after <phase>
coordination_baton_after() {
  coordination_get "baton_after_phase.$1" "done"
}

# --- ownership (path allowed for agent in phase?) ---------------------------
# _coord_path_matches <relpath> <json-array-of-globs> -> exit 0 if match
_coord_path_matches() {
  REL="$1" PATS="$2" python3 - <<'PY'
import json, os, fnmatch, sys
rel = os.environ["REL"].lstrip("./")
patterns = json.loads(os.environ["PATS"])
for p in patterns:
    p = p.lstrip("./")
    if fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(rel, "*/" + p):
        sys.exit(0)
    if p.endswith("/**") and (rel == p[:-3].rstrip("/") or rel.startswith(p[:-2])):
        sys.exit(0)
sys.exit(1)
PY
}

# coordination_path_denied_for_builder <relpath>
# Exit 0 if path is on the builder never-list (should be blocked), 1 if allowed.
# Orchestration surfaces (HANDOFF, PLAN, .dual-agent, ledger) are exempt — they
# are written by dual-run / Claude contract, not by the builder (anti false-positive).
coordination_path_denied_for_builder() {
  local relpath="$1"
  local never exempt
  exempt="$(coordination_get anti_overlap.orchestration_exempt '[]')"
  if _coord_path_matches "$relpath" "$exempt"; then
    return 1  # allowed (orchestration)
  fi
  never="$(coordination_get ownership.grok.never '[]')"
  _coord_path_matches "$relpath" "$never"
}

# coordination_check_builder_paths <file...>
# Fail-closed if any path is on ownership.grok.never.
coordination_check_builder_paths() {
  local f bad=()
  for f in "$@"; do
    if coordination_path_denied_for_builder "$f"; then
      bad+=("$f")
    fi
  done
  if [[ ${#bad[@]} -gt 0 ]]; then
    fail_code 2 "builder ownership violation (would double/overlap Claude surfaces): ${bad[*]}"
  fi
}

# --- HANDOFF.md human ledger -----------------------------------------------
# coordination_handoff_append <agent> <phase> <body-lines>
# Header BATON = who may act NEXT (baton_after phase), not who just finished.
# Header PHASE = next phase (phase_next), so the staffelstab is always current.
coordination_handoff_append() {
  local agent="$1" phase="$2" body="$3"
  local root hf ts next_baton next_phase
  root="$(_coord_root)"
  hf="$root/$(coordination_get defaults.handoff HANDOFF.md)"
  ts="$(iso_now)"
  next_baton="$(coordination_baton_after "$phase")"
  next_phase="$(coordination_next_phase "$phase")"
  if [[ ! -f "$hf" ]]; then
    # Bootstrap from template if present.
    local tmpl="$root/HANDOFF.template.md"
    if [[ -f "$tmpl" ]]; then
      cp "$tmpl" "$hf"
    else
      cat >"$hf" <<EOF
# HANDOFF

BATON: $next_baton
PHASE: $next_phase

---

## Turn-Log (neueste unten)
EOF
    fi
  fi
  # Update header BATON/PHASE in place (first occurrence only) → next holder.
  python3 - "$hf" "$next_baton" "$next_phase" <<'PY'
import sys, re
path, baton, phase = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
text2, n1 = re.subn(r"(?m)^BATON:\s*\S+", f"BATON: {baton}", text, count=1)
text3, n2 = re.subn(r"(?m)^PHASE:\s*\S+", f"PHASE: {phase}", text2, count=1)
if n1 == 0:
    text3 = f"BATON: {baton}\nPHASE: {phase}\n\n" + text3
open(path, "w", encoding="utf-8").write(text3)
PY
  {
    printf '\n### [%s] %s — %s\n' "$ts" "$agent" "$phase"
    printf '%s\n' "$body"
    printf -- '- BATON -> %s\n' "$next_baton"
  } >>"$hf"
}

# --- validate config shape --------------------------------------------------
coordination_validate_config() {
  local cfg
  cfg="$(coordination_config_path)"
  [[ -f "$cfg" ]] || fail "coordination config missing: $cfg"
  CFG="$cfg" python3 - <<'PY'
import json, os, sys
cfg = os.environ["CFG"]
try:
    o = json.load(open(cfg, encoding="utf-8"))
except Exception as e:
    print(f"BLOCKED: invalid JSON in {cfg}: {e}", file=sys.stderr); sys.exit(1)
for key in ("version", "roles", "branches", "phases", "phase_agent", "anti_overlap", "defaults"):
    if key not in o:
        print(f"BLOCKED: coordination config missing key '{key}'", file=sys.stderr); sys.exit(1)
phases = o["phases"]
pa = o["phase_agent"]
for p in phases:
    if p not in pa:
        print(f"BLOCKED: phase_agent missing entry for '{p}'", file=sys.stderr); sys.exit(1)
# sequential uniqueness: no two consecutive phases share a write-capable vendor
# when anti_overlap.one_agent_active — structural check only for R vs A/F.
if o.get("anti_overlap", {}).get("one_agent_active", True):
    if pa.get("R") == pa.get("A") and pa.get("R") not in ("gate",):
        # same agent OK if sequential (claude can do A then F); builders must not
        # share R with another write phase of same agent without baton — informational.
        pass
print("ok")
PY
}

# --- status report ----------------------------------------------------------
coordination_status() {
  local cfg sp lock
  cfg="$(coordination_config_path)"
  sp="$(coordination_state_path)"
  lock="$(coordination_lock_path)"
  info "=== dual coordination ==="
  log "config : $cfg"
  log "roles  : architect=$(coordination_get roles.architect) builder=$(coordination_get roles.builder) assessor=$(coordination_get roles.assessor) arbiter=$(coordination_get roles.arbiter)"
  log "branch : base=$(coordination_get branches.base) poc=$(coordination_get branches.poc) harden=$(coordination_get branches.harden)"
  log "phases : $(coordination_get phases)"
  if [[ -f "$sp" ]]; then
    log "state  : phase=$(coordination_state_get phase) baton=$(coordination_state_get baton) status=$(coordination_state_get status) run=$(coordination_state_get run_id)"
  else
    log "state  : (none — no dual-run active)"
  fi
  if [[ -f "$lock" ]]; then
    local pid
    pid="$(awk -F= '/^pid=/{print $2}' "$lock" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      warn "lock   : HELD by PID $pid ($lock)"
    else
      log "lock   : stale file $lock (PID ${pid:-?} dead)"
    fi
  else
    ok "lock   : free"
  fi
}

# --- CLI entrypoint (only when executed, not sourced) -----------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-status}"
  shift || true
  case "$cmd" in
    -h|--help|help)
      cat <<'EOF'
Usage: lib/coordination.sh <command>

  status              show roles, baton, phase, lock
  validate            validate config/coordination.json
  get <dotted.path>   print a config value
  lock-acquire [id]   take exclusive dual-run lock
  lock-release        release lock if we hold it
  state-init <id> [task]
  state-get <field>
  require-baton <agent>
  assert-phase <P>
  path-denied <path>  exit 0 if builder must not write path
  check-builder-paths <path...>
EOF
      exit 0
      ;;
    status)   coordination_status ;;
    validate) coordination_validate_config; ok "coordination config valid." ;;
    get)      coordination_get "${1:?path required}" "${2:-}" ;;
    lock-acquire) coordination_lock_acquire "${1:-$$}" ;;
    lock-release) coordination_lock_release ;;
    state-init)   coordination_state_init "${1:?run_id}" "${2:-}" ;;
    state-get)    coordination_state_get "${1:?field}" ;;
    require-baton) coordination_require_baton "${1:?agent}" ;;
    assert-phase)  coordination_assert_phase "${1:?phase}" ;;
    path-denied)
      if coordination_path_denied_for_builder "${1:?path}"; then
        echo "denied"; exit 0
      else
        echo "allowed"; exit 1
      fi
      ;;
    check-builder-paths) coordination_check_builder_paths "$@" ;;
    *) fail "coordination: unknown command '$cmd' (try --help)" ;;
  esac
fi
