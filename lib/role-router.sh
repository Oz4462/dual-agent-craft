#!/usr/bin/env bash
# role-router.sh — adaptive who-does-what for dual-agent-craft.
#
# Reads config/roles.json (+ optional task/PLAN text + ledger REVIEW.json) and
# emits a deterministic role assignment:
#   architect, builder, assessor, hardener, security, scout, fortify, eval_k,
#   variants, profile, reasons[], functions map.
#
# Enforces hard invariants:
#   - assessor vendor != builder vendor (cross-vendor moat)
#   - arbiter/guards always gate
#   - builder never assigned as hardener/security for tests
#
# Usage:
#   lib/role-router.sh route [--task T] [--plan PLAN.md] [--profile auto|minimal|…]
#                            [--review ledger/REVIEW.json] [--out FILE] [--json]
#   lib/role-router.sh explain [--assignment FILE]
#   lib/role-router.sh profiles
#   lib/role-router.sh who <function>   # architect|builder|assessor|…
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$_HERE/common.sh"

roles_config_path() {
  if [[ -n "${DUAL_ROLES_CONFIG:-}" ]]; then
    printf '%s\n' "$DUAL_ROLES_CONFIG"
    return
  fi
  local root
  root="$(cd "$_HERE/.." && pwd)"
  if [[ -f "$root/config/roles.json" ]]; then
    printf '%s\n' "$root/config/roles.json"
  else
    printf '%s\n' "$root/config/roles.json"
  fi
}

# Pure Python router — deterministic, offline, no vendor calls.
_role_route_py() {
  ROLES_CFG="$(roles_config_path)" \
  TASK_TEXT="${TASK_TEXT:-}" \
  PLAN_PATH="${PLAN_PATH:-}" \
  PROFILE_REQ="${PROFILE_REQ:-auto}" \
  REVIEW_PATH="${REVIEW_PATH:-}" \
  CLI_BUILDER="${CLI_BUILDER:-}" \
  CLI_ASSESSOR="${CLI_ASSESSOR:-}" \
  python3 - <<'PY'
import json, os, re, sys
from datetime import datetime, timezone

cfg_path = os.environ["ROLES_CFG"]
try:
    cfg = json.load(open(cfg_path, encoding="utf-8"))
except Exception as e:
    print(json.dumps({"error": f"roles config unreadable: {e}"})); sys.exit(2)

task = os.environ.get("TASK_TEXT") or ""
plan_path = os.environ.get("PLAN_PATH") or ""
plan = ""
if plan_path and os.path.isfile(plan_path):
    try:
        plan = open(plan_path, encoding="utf-8", errors="replace").read()
    except OSError:
        plan = ""
blob = (task + "\n" + plan).lower()

profile_req = (os.environ.get("PROFILE_REQ") or "auto").strip().lower()
cli_builder = (os.environ.get("CLI_BUILDER") or "").strip().lower()
cli_assessor = (os.environ.get("CLI_ASSESSOR") or "").strip().lower()
review_path = os.environ.get("REVIEW_PATH") or ""

signals_hit = []
signal_sets = {}
boost_profile = None
only_low = False

for name, spec in (cfg.get("signals") or {}).items():
    kws = spec.get("keywords") or []
    hit = [k for k in kws if k.lower() in blob]
    if not hit:
        continue
    signals_hit.append({"signal": name, "matched": hit[:8]})
    if spec.get("only_if_no_risk"):
        only_low = True
    if spec.get("boost_profile"):
        boost_profile = spec["boost_profile"]
    for k, v in (spec.get("set") or {}).items():
        signal_sets[k] = v

# risk beats low-complexity demotion
has_risk = any(s["signal"] == "risk_high" for s in signals_hit)
has_complex = any(s["signal"] == "complexity_high" for s in signals_hit)
has_sandbox = any(s["signal"] == "needs_sandbox" for s in signals_hit)
has_low = any(s["signal"] == "complexity_low" for s in signals_hit)

profiles = cfg.get("profiles") or {}
reasons = []

if profile_req and profile_req != "auto":
    if profile_req not in profiles:
        print(json.dumps({"error": f"unknown profile '{profile_req}'", "known": list(profiles)}))
        sys.exit(2)
    profile = profile_req
    reasons.append(f"profile forced by caller: {profile}")
else:
    # adaptive profile pick
    profile = "standard"
    reasons.append("baseline profile: standard")
    if has_risk:
        profile = "security"
        reasons.append("signal risk_high → profile security")
    elif has_sandbox:
        profile = "sandbox"
        reasons.append("signal needs_sandbox → profile sandbox")
    elif has_complex:
        profile = "thorough"
        reasons.append("signal complexity_high → profile thorough")
    elif has_low and not has_risk and not has_complex:
        profile = "minimal"
        reasons.append("signal complexity_low (no risk) → profile minimal")
    if boost_profile and not has_risk:
        # allow boost unless risk already forced security
        if profile in ("standard", "minimal") and boost_profile in profiles:
            profile = boost_profile
            reasons.append(f"signal boost_profile → {profile}")

prof = dict(profiles.get(profile) or profiles.get("standard") or {})
# apply signal set overlays (booleans / vendor overrides)
for k, v in signal_sets.items():
    if k == "variants_min":
        prof["variants"] = max(int(prof.get("variants") or 1), int(v))
        reasons.append(f"signal set variants_min={v}")
    elif k in ("fortify", "scout", "security_pass", "adaptive_build"):
        prof[k] = bool(v)
        reasons.append(f"signal set {k}={bool(v)}")
    elif k in ("builder", "assessor"):
        prof[k] = v
        reasons.append(f"signal set {k}={v}")

# CLI overrides win over profile for vendors
builder = (cli_builder or prof.get("builder") or "grok").lower()
assessor = (cli_assessor or prof.get("assessor") or "claude").lower()
architect = (cfg.get("functions", {}).get("architect", {}) or {}).get("default", "claude")
hardener = (cfg.get("functions", {}).get("hardener", {}) or {}).get("default", "claude")
security_agent = (cfg.get("functions", {}).get("security", {}) or {}).get("default", "claude")
scout_agent = (cfg.get("functions", {}).get("scout", {}) or {}).get("default", "ollama")

agents = cfg.get("agents") or {}

def vendor_of(name: str) -> str:
    a = agents.get(name) or {}
    return (a.get("vendor") or name).lower()

# Cross-vendor moat: assessor must differ from builder
if vendor_of(builder) == vendor_of(assessor):
    # swap assessor to first candidate that differs
    cands = (cfg.get("functions", {}).get("assessor", {}) or {}).get("candidates") or ["claude", "codex"]
    swapped = None
    for c in cands:
        if vendor_of(c) != vendor_of(builder):
            swapped = c
            break
    if swapped is None:
        swapped = "claude" if vendor_of(builder) != "claude" else "codex"
    reasons.append(
        f"cross-vendor moat: assessor {assessor}==builder vendor → {swapped}"
    )
    assessor = swapped

# Builder candidate validation
bcands = (cfg.get("functions", {}).get("builder", {}) or {}).get("candidates") or ["grok", "codex"]
if builder not in bcands and builder not in agents:
    reasons.append(f"builder '{builder}' not in candidates; clamping to {bcands[0]}")
    builder = bcands[0]

# Mid-run review adaptation
review_adapt = {"applied": False}
if review_path and os.path.isfile(review_path):
    try:
        rev = json.load(open(review_path, encoding="utf-8"))
    except Exception:
        rev = {}
    verdict = (rev.get("verdict") or "").lower()
    high = rev.get("high") or rev.get("issues_high") or []
    # support list of issue ids or count
    if isinstance(high, list):
        high_n = len(high)
    else:
        try:
            high_n = int(high)
        except Exception:
            high_n = 0
    # also scan issues array
    issues = rev.get("issues") or []
    if isinstance(issues, list):
        high_n = max(high_n, sum(1 for i in issues if str(i.get("severity", "")).lower() in ("high", "critical")))
    conceded = rev.get("conceded") or []
    ties = rev.get("tie") or rev.get("ties") or []

    mid = cfg.get("mid_run") or {}
    on_iss = mid.get("on_review_issues") or {}
    if high_n > 0 and on_iss.get("high_severity_forces_fortify", True):
        prof["fortify"] = True
        prof["security_pass"] = True
        review_adapt = {
            "applied": True,
            "verdict": verdict,
            "high_count": high_n,
            "action": "force_fortify+security",
        }
        reasons.append(f"mid-run REVIEW high_severity={high_n} → fortify+security")
    if conceded and on_iss.get("conceded_suggests_re_render", True):
        review_adapt["re_render_suggested"] = True
        review_adapt["conceded"] = conceded if isinstance(conceded, list) else [conceded]
        reasons.append("mid-run REVIEW conceded issues → re-render suggested")
    if ties and on_iss.get("subjective_tie_suggests_tiebreak", True):
        review_adapt["tiebreak_suggested"] = True
        reasons.append("mid-run REVIEW subjective ties → dual-tiebreak suggested")
    if verdict in ("clean", "pass") and not prof.get("fortify"):
        review_adapt.setdefault("applied", True)
        review_adapt["verdict"] = verdict
        reasons.append("mid-run REVIEW clean — fortify stays profile-default")

# Availability: if ollama not wanted when scout false
scout = bool(prof.get("scout"))
fortify = bool(prof.get("fortify"))
security_pass = bool(prof.get("security_pass"))
adaptive_build = bool(prof.get("adaptive_build", True))
variants = int(prof.get("variants") or 3)
eval_k = int(prof.get("eval_k") or 5)
max_turns = int(prof.get("max_turns") or 40)

assignment = {
    "version": 1,
    "stamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "profile": profile,
    "profile_label": prof.get("label", profile),
    "functions": {
        "architect": architect,
        "scout": scout_agent if scout else None,
        "builder": builder,
        "guards": "gate",
        "assessor": assessor,
        "rebutter": builder,
        "hardener": hardener if fortify else None,
        "security": security_agent if security_pass else None,
        "arbiter": "gate",
    },
    "flags": {
        "scout": scout,
        "fortify": fortify,
        "security_pass": security_pass,
        "adaptive_build": adaptive_build,
        "skip_fortify": not fortify,
    },
    "params": {
        "variants": variants,
        "eval_k": eval_k,
        "max_turns": max_turns,
        "builder": builder,
        "assess_vendor": assessor,
    },
    "signals": signals_hit,
    "reasons": reasons,
    "mid_run": review_adapt,
    "invariants_enforced": cfg.get("invariants") or [],
    "who_matrix": [
        {"phase": "C", "function": "architect", "agent": architect, "does": "Write PLAN.md contract only"},
        {"phase": "R-pre", "function": "scout", "agent": (scout_agent if scout else "—"), "does": "Optional $0 first pass" if scout else "skipped"},
        {"phase": "R", "function": "builder", "agent": builder, "does": "Implement POC in feat/poc (no tests)"},
        {"phase": "G", "function": "guards", "agent": "gate", "does": "import-scan + test-guard + ownership"},
        {"phase": "A", "function": "assessor", "agent": assessor, "does": "Untrusted-code review (cross-vendor)"},
        {"phase": "A2", "function": "rebutter", "agent": builder, "does": "Exactly one rebuttal round"},
        {"phase": "F", "function": "hardener", "agent": (hardener if fortify else "—"), "does": "Tests/harden on feat/harden" if fortify else "skipped"},
        {"phase": "F+", "function": "security", "agent": (security_agent if security_pass else "—"), "does": "Threat/security pass" if security_pass else "skipped"},
        {"phase": "T", "function": "arbiter", "agent": "gate", "does": "pass^k + No-Cut merge"},
    ],
}

print(json.dumps(assignment, indent=2))
PY
}

cmd_route() {
  local out="" json_only=false
  TASK_TEXT=""; PLAN_PATH=""; PROFILE_REQ="auto"; REVIEW_PATH=""
  CLI_BUILDER=""; CLI_ASSESSOR=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task)     TASK_TEXT="${2:?}"; shift 2;;
      --plan)     PLAN_PATH="${2:?}"; shift 2;;
      --profile)  PROFILE_REQ="${2:?}"; shift 2;;
      --review)   REVIEW_PATH="${2:?}"; shift 2;;
      --builder)  CLI_BUILDER="${2:?}"; shift 2;;
      --assessor) CLI_ASSESSOR="${2:?}"; shift 2;;
      --out)      out="${2:?}"; shift 2;;
      --json)     json_only=true; shift;;
      -h|--help)  usage "$0"; exit 0;;
      *) fail "role-router route: unknown arg '$1'";;
    esac
  done
  [[ -f "$(roles_config_path)" ]] || fail "roles config missing: $(roles_config_path)"
  export TASK_TEXT PLAN_PATH PROFILE_REQ REVIEW_PATH CLI_BUILDER CLI_ASSESSOR
  local result
  result="$(_role_route_py)" || fail "role-router failed."
  if printf '%s' "$result" | python3 -c 'import sys,json; o=json.load(sys.stdin); sys.exit(0 if "error" not in o else 2)' 2>/dev/null; then
    :
  else
    printf '%s\n' "$result" >&2
    fail "role-router returned error."
  fi
  if [[ -n "$out" ]]; then
    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$result" >"$out"
  fi
  if [[ "$json_only" == true ]]; then
    printf '%s\n' "$result"
  else
    printf '%s\n' "$result"
  fi
}

cmd_explain() {
  local file=""
  local route_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task|--plan|--profile|--review|--builder|--assessor)
        route_args+=("$1" "${2:?}"); shift 2;;
      --out) file="${2:?}"; shift 2;;
      -*) fail "role-router explain: unknown arg '$1'";;
      *) file="$1"; shift;;
    esac
  done
  if [[ -z "$file" || ! -f "$file" ]]; then
    file="$(mktemp)"
    cmd_route --json --out "$file" "${route_args[@]}" >/dev/null
  fi
  python3 - "$file" <<'PY'
import json,sys
a=json.load(open(sys.argv[1], encoding="utf-8"))
print(f"=== Adaptive who-does-what  (profile: {a['profile']} — {a.get('profile_label','')}) ===")
print()
for row in a.get("who_matrix") or []:
    print(f"  {row['phase']:6}  {row['function']:10}  {str(row['agent']):8}  {row['does']}")
print()
print("reasons:")
for r in a.get("reasons") or []:
    print(f"  • {r}")
if a.get("signals"):
    print("signals:")
    for s in a["signals"]:
        print(f"  • {s['signal']}: {', '.join(s.get('matched') or [])}")
if a.get("mid_run", {}).get("applied"):
    print(f"mid-run: {json.dumps(a['mid_run'], ensure_ascii=False)}")
print()
print("invariants:")
for i in a.get("invariants_enforced") or []:
    print(f"  ✓ {i}")
PY
}

cmd_profiles() {
  python3 - "$(roles_config_path)" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1], encoding="utf-8"))
print(f"{'profile':12} {'builder':8} {'assessor':8} {'fortify':7} {'scout':5} {'sec':5} {'vars':4} {'eval_k':6}  label")
for name,p in (cfg.get("profiles") or {}).items():
    print(f"{name:12} {str(p.get('builder','-')):8} {str(p.get('assessor','-')):8} "
          f"{str(bool(p.get('fortify'))):7} {str(bool(p.get('scout'))):5} {str(bool(p.get('security_pass'))):5} "
          f"{str(p.get('variants','-')):4} {str(p.get('eval_k','-')):6}  {p.get('label','')}")
PY
}

cmd_who() {
  local fn="${1:?function name required}"
  local tmp
  tmp="$(mktemp)"
  cmd_route --json --out "$tmp" --task "${TASK_TEXT:-}" --plan "${PLAN_PATH:-}" --profile "${PROFILE_REQ:-auto}" >/dev/null
  python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); print(a["functions"].get(sys.argv[2]) or "")' "$tmp" "$fn"
  rm -f "$tmp"
}

# --- entry ------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  sub="${1:-}"
  shift || true
  case "$sub" in
    ""|-h|--help)
      cat <<'EOF'
Usage:
  lib/role-router.sh route [--task T] [--plan PLAN.md] [--profile auto|minimal|standard|thorough|security|sandbox]
                           [--builder grok|codex] [--assessor claude|codex]
                           [--review ledger/REVIEW.json] [--out FILE] [--json]
  lib/role-router.sh explain [assignment.json]
  lib/role-router.sh profiles
  lib/role-router.sh who <architect|builder|assessor|hardener|security|scout|arbiter>
EOF
      exit 0
      ;;
    route)    cmd_route "$@" ;;
    explain)  cmd_explain "$@" ;;
    profiles) cmd_profiles "$@" ;;
    who)      cmd_who "$@" ;;
    *) fail "role-router: unknown command '$sub'";;
  esac
fi
