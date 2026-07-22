#!/usr/bin/env bash
# dual-run.sh — one-command CRAFT orchestrator (Claude ↔ Grok, structured, no overlap).
#
# Runs the dual-agent loop as a sequential staffelstab:
#   C Contract → R Render → G Guards → A Assess → F Fortify → T Merge
#
# WHO-DOES-WHAT is adaptive (config/roles.json + lib/role-router.sh):
#   task/PLAN signals pick a profile (minimal|standard|thorough|security|sandbox),
#   assign builder/assessor/hardener/scout, force cross-vendor moat, and can
#   re-route after REVIEW (high issues → fortify+security). Explicit CLI flags
#   always win over adaptive picks.
#
# Coordination lock/baton/ownership: config/coordination.json.
#
# Usage:
#   ./dual-run.sh --verify "pytest -q" [--plan PLAN.md] [--task "…"]
#     [--profile auto|minimal|standard|thorough|security|sandbox]
#     [--from-phase C|R|G|A|F|T] [--to-phase R|G|A|F|T]
#     [--skip-fortify] [--skip-merge] [--fortify] [--auto-plan]
#     [--variants N] [--eval-k K] [--adaptive] [--builder grok|codex]
#     [--assess-vendor claude|codex] [--scout] [--no-role-adaptive]
#     [--dry-run] [--status] [--who]
#
#   --profile       adaptive who-does-what profile (default: auto from task/PLAN)
#   --task TEXT     task summary (feeds role-router signals + HANDOFF)
#   --who           print adaptive assignment matrix and exit
#   --no-role-adaptive  freeze static defaults (disable signal routing)
#   --team-work / --no-team-work  after PLAN: Claude+Grok+Codex ALL execute packages
#                                 (default ON — architect also codes, not only plans)
#   --fortify / --skip-fortify / --builder / --assess-vendor override adaptive picks
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/lib/common.sh"
# shellcheck source=lib/coordination.sh
source "$_HERE/lib/coordination.sh"

# --- defaults from coordination config -------------------------------------
PLAN="$(coordination_get defaults.plan PLAN.md)"
VERIFY="$(coordination_get defaults.verify "")"
VARIANTS="$(coordination_get defaults.variants 3)"
ADAPTIVE="$(coordination_get defaults.adaptive true)"
MAX_TURNS="$(coordination_get defaults.max_turns 40)"
EVAL_K="$(coordination_get defaults.eval_k 5)"
TEST_GUARD="$(coordination_get defaults.test_guard true)"
IMPORT_SCAN="$(coordination_get defaults.import_scan true)"
IMPORT_PROV="$(coordination_get defaults.import_scan_provenance true)"
BUILDER="$(coordination_get defaults.builder grok)"
ASSESS_VENDOR="$(coordination_get defaults.assess_vendor claude)"
SCOUT="$(coordination_get defaults.scout false)"
SKIP_FORTIFY="$(coordination_get defaults.skip_fortify true)"
SKIP_MERGE="$(coordination_get defaults.skip_merge false)"
INTO="$(coordination_get defaults.into main)"
POC_BRANCH="$(coordination_get branches.poc feat/poc)"
HARDEN_BRANCH="$(coordination_get branches.harden feat/harden)"
BASE_BRANCH="$(coordination_get branches.base main)"

FROM_PHASE="C"
TO_PHASE="T"
TASK=""
AUTO_PLAN=false
DRYRUN=false
STATUS_ONLY=false
WHO_ONLY=false
MODEL=""
PROFILE="auto"
ROLE_ADAPTIVE=true
TEAM_WORK=true          # default: all three workers execute after PLAN
TEAM_WORK_DONE=false
# Track explicit CLI overrides so adaptive routing cannot clobber them.
CLI_BUILDER=false; CLI_ASSESSOR=false; CLI_FORTIFY=false
CLI_SCOUT=false; CLI_VARIANTS=false; CLI_EVAL_K=false; CLI_MAX_TURNS=false
CLI_ADAPTIVE_BUILD=false
SECURITY_PASS=false
ROLE_ASSIGN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage "$0"; exit 0;;
    --status)    STATUS_ONLY=true; shift;;
    --who)       WHO_ONLY=true; shift;;
    --dry-run)   DRYRUN=true; shift;;
    --plan)      PLAN="${2:?value required for $1}"; shift 2;;
    --verify)    VERIFY="${2:?value required for $1}"; shift 2;;
    --task)      TASK="${2:?value required for $1}"; shift 2;;
    --profile)   PROFILE="${2:?value required for $1}"; shift 2;;
    --auto-plan) AUTO_PLAN=true; shift;;
    --from-phase) FROM_PHASE="${2:?value required for $1}"; shift 2;;
    --to-phase)   TO_PHASE="${2:?value required for $1}"; shift 2;;
    --variants)  VARIANTS="${2:?value required for $1}"; CLI_VARIANTS=true; shift 2;;
    --eval-k)    EVAL_K="${2:?value required for $1}"; CLI_EVAL_K=true; shift 2
                 [[ "$EVAL_K" =~ ^[0-9]+$ ]] || fail "dual-run: --eval-k must be a positive integer, got '$EVAL_K'.";;
    --max-turns) MAX_TURNS="${2:?value required for $1}"; CLI_MAX_TURNS=true; shift 2;;
    --builder)   BUILDER="${2:?value required for $1}"; CLI_BUILDER=true; shift 2;;
    --assess-vendor) ASSESS_VENDOR="${2:?value required for $1}"; CLI_ASSESSOR=true; shift 2;;
    --model)     MODEL="${2:?value required for $1}"; shift 2;;
    --adaptive)  ADAPTIVE=true; CLI_ADAPTIVE_BUILD=true; shift;;
    --no-adaptive) ADAPTIVE=false; CLI_ADAPTIVE_BUILD=true; shift;;
    --no-role-adaptive) ROLE_ADAPTIVE=false; shift;;
    --team-work) TEAM_WORK=true; shift;;
    --no-team-work) TEAM_WORK=false; shift;;
    --scout)     SCOUT=true; CLI_SCOUT=true; shift;;
    --fortify)   SKIP_FORTIFY=false; CLI_FORTIFY=true; shift;;
    --skip-fortify) SKIP_FORTIFY=true; CLI_FORTIFY=true; shift;;
    --skip-merge) SKIP_MERGE=true; shift;;
    --no-import-scan) IMPORT_SCAN=false; shift;;
    --no-test-guard)  TEST_GUARD=false; shift;;
    --into)      INTO="${2:?value required for $1}"; shift 2;;
    --poc)       POC_BRANCH="${2:?value required for $1}"; shift 2;;
    *) fail "dual-run: unknown arg '$1'";;
  esac
done

# --- adaptive who-does-what -------------------------------------------------
apply_role_assignment() {
  local review="${1:-}"
  local args=(--profile "$PROFILE" --json)
  [[ -n "$TASK" && -f "$PLAN" ]] || true
  [[ -n "$TASK" ]] && args+=(--task "$TASK")
  [[ -f "$PLAN" ]] && args+=(--plan "$PLAN")
  [[ -n "$review" && -f "$review" ]] && args+=(--review "$review")
  # Pass CLI vendor pins into the router so moat logic sees them
  [[ "$CLI_BUILDER" == true ]] && args+=(--builder "$BUILDER")
  [[ "$CLI_ASSESSOR" == true ]] && args+=(--assessor "$ASSESS_VENDOR")

  ROLE_ASSIGN="$_HERE/.dual-agent/role-assignment.json"
  mkdir -p "$_HERE/.dual-agent"
  if [[ "$ROLE_ADAPTIVE" != true ]]; then
    # Static baseline assignment (no signal routing)
    cat >"$ROLE_ASSIGN" <<EOF
{"profile":"static","functions":{"architect":"claude","builder":"$BUILDER","assessor":"$ASSESS_VENDOR","guards":"gate","arbiter":"gate","hardener":$([[ "$SKIP_FORTIFY" == true ]] && echo null || echo '"claude"'),"security":null,"scout":null,"rebutter":"$BUILDER"},"flags":{"scout":$SCOUT,"fortify":$([[ "$SKIP_FORTIFY" == true ]] && echo false || echo true),"security_pass":false,"adaptive_build":$ADAPTIVE,"skip_fortify":$SKIP_FORTIFY},"params":{"variants":$VARIANTS,"eval_k":$EVAL_K,"max_turns":$MAX_TURNS,"builder":"$BUILDER","assess_vendor":"$ASSESS_VENDOR"},"reasons":["role-adaptive disabled (--no-role-adaptive)"],"who_matrix":[]}
EOF
    return 0
  fi
  "$_HERE/lib/role-router.sh" route "${args[@]}" --out "$ROLE_ASSIGN" >/dev/null \
    || fail "role-router failed — cannot assign who-does-what."

  # Apply params unless CLI overrode them
  local p_builder p_assess p_fortify p_scout p_sec p_vars p_eval p_turns p_abuild p_profile
  p_builder="$(json_field "$ROLE_ASSIGN" functions.builder)"
  p_assess="$(json_field "$ROLE_ASSIGN" functions.assessor)"
  p_fortify="$(json_field "$ROLE_ASSIGN" flags.fortify)"
  p_scout="$(json_field "$ROLE_ASSIGN" flags.scout)"
  p_sec="$(json_field "$ROLE_ASSIGN" flags.security_pass)"
  p_vars="$(json_field "$ROLE_ASSIGN" params.variants)"
  p_eval="$(json_field "$ROLE_ASSIGN" params.eval_k)"
  p_turns="$(json_field "$ROLE_ASSIGN" params.max_turns)"
  p_abuild="$(json_field "$ROLE_ASSIGN" flags.adaptive_build)"
  p_profile="$(json_field "$ROLE_ASSIGN" profile)"

  [[ "$CLI_BUILDER" != true && -n "$p_builder" ]] && BUILDER="$p_builder"
  [[ "$CLI_ASSESSOR" != true && -n "$p_assess" ]] && ASSESS_VENDOR="$p_assess"
  if [[ "$CLI_FORTIFY" != true && -n "$p_fortify" ]]; then
    [[ "$p_fortify" == "true" ]] && SKIP_FORTIFY=false || SKIP_FORTIFY=true
  fi
  if [[ "$CLI_SCOUT" != true && -n "$p_scout" ]]; then
    [[ "$p_scout" == "true" ]] && SCOUT=true || SCOUT=false
  fi
  [[ "$p_sec" == "true" ]] && SECURITY_PASS=true || SECURITY_PASS=false
  [[ "$CLI_VARIANTS" != true && -n "$p_vars" ]] && VARIANTS="$p_vars"
  [[ "$CLI_EVAL_K" != true && -n "$p_eval" ]] && EVAL_K="$p_eval"
  [[ "$CLI_MAX_TURNS" != true && -n "$p_turns" ]] && MAX_TURNS="$p_turns"
  [[ "$CLI_ADAPTIVE_BUILD" != true && -n "$p_abuild" ]] && {
    [[ "$p_abuild" == "true" ]] && ADAPTIVE=true || ADAPTIVE=false
  }
  PROFILE_RESOLVED="${p_profile:-$PROFILE}"
}

show_who_matrix() {
  [[ -f "${ROLE_ASSIGN:-}" ]] || return 0
  info "── who-does-what (adaptive) ──"
  python3 - "$ROLE_ASSIGN" <<'PY'
import json,sys
a=json.load(open(sys.argv[1], encoding="utf-8"))
print(f"  profile : {a.get('profile')} — {a.get('profile_label','')}")
for row in a.get("who_matrix") or []:
    agent = row.get("agent") or "—"
    print(f"  {row.get('phase','?'):6}  {row.get('function','?'):10}  {str(agent):8}  {row.get('does','')}")
print("  reasons:")
for r in (a.get("reasons") or [])[:8]:
    print(f"    • {r}")
mid=a.get("mid_run") or {}
if mid.get("applied"):
    print(f"  mid-run : {json.dumps(mid, ensure_ascii=False)}")
PY
}

if [[ "$STATUS_ONLY" == true ]]; then
  coordination_validate_config
  coordination_status
  apply_role_assignment
  show_who_matrix
  exit 0
fi

if [[ "$WHO_ONLY" == true ]]; then
  apply_role_assignment
  "$_HERE/lib/role-router.sh" explain "$ROLE_ASSIGN"
  exit 0
fi

# Phase order validation — W = team Work (Claude+Grok+Codex all code)
_phase_rank() {
  case "$1" in
    C) echo 0;; W) echo 1;; R) echo 2;; G) echo 3;; A) echo 4;; F) echo 5;; T) echo 6;; done) echo 7;;
    *) return 1;;
  esac
}
_from_r="$(_phase_rank "$FROM_PHASE")" || fail "dual-run: bad --from-phase '$FROM_PHASE' (C|W|R|G|A|F|T)."
_to_r="$(_phase_rank "$TO_PHASE")"     || fail "dual-run: bad --to-phase '$TO_PHASE' (C|W|R|G|A|F|T)."
[[ "$_from_r" -le "$_to_r" ]] || fail "dual-run: --from-phase must be ≤ --to-phase."

should_run_phase() {
  local p="$1" pr fr tr
  pr="$(_phase_rank "$p")" || return 1
  fr="$(_phase_rank "$FROM_PHASE")"
  tr="$(_phase_rank "$TO_PHASE")"
  [[ "$pr" -ge "$fr" && "$pr" -le "$tr" ]]
}

coordination_validate_config
apply_role_assignment

info "=== Dual-Agent / dual-run (adaptive Claude ↔ Grok) ==="
log "config   : $(coordination_config_path)"
log "roles    : $( [[ -f "$_HERE/config/roles.json" ]] && echo "$_HERE/config/roles.json" || echo roles.json )"
log "profile  : ${PROFILE_RESOLVED:-$PROFILE}  (role-adaptive=$ROLE_ADAPTIVE)"
log "plan     : $PLAN"
log "verify   : ${VERIFY:-"(none — merge will require --force path or skip)"}"
log "phases   : $FROM_PHASE → $TO_PHASE  (team-work=$([[ "$TEAM_WORK" == true ]] && echo ON || echo off), fortify=$([[ "$SKIP_FORTIFY" == true ]] && echo skip || echo on), security=$([[ "$SECURITY_PASS" == true ]] && echo on || echo off), merge=$([[ "$SKIP_MERGE" == true ]] && echo skip || echo on))"
log "who      : architect+worker=claude  workers=claude,grok,codex  lead_builder=$BUILDER  assessor=$ASSESS_VENDOR  guards=gate  arbiter=gate"
log "params   : eval_k=$EVAL_K  variants=$VARIANTS  adaptive_build=$ADAPTIVE  scout=$SCOUT  max_turns=$MAX_TURNS"
log "branches : base=$BASE_BRANCH poc=$POC_BRANCH harden=$HARDEN_BRANCH into=$INTO"
[[ -n "$TASK" ]] && log "task     : $TASK"
show_who_matrix

if [[ "$DRYRUN" == true ]]; then
  warn "DryRun — phase plan only, no vendor calls, no lock."
  for p in C W R G A F T; do
    if should_run_phase "$p"; then
      agent="?"
      case "$p" in
        C) agent="claude (architect)";;
        W) agent="$([[ "$TEAM_WORK" == true ]] && echo "claude+grok+codex (ALL code)" || echo "skip --no-team-work")";;
        R) agent="$([[ "$TEAM_WORK" == true ]] && echo "skip if W done / optional single-builder" || echo "$BUILDER")";;
        A) agent="$ASSESS_VENDOR";;
        F) agent="$([[ "$SKIP_FORTIFY" == true ]] && echo skip || echo claude)";;
        G|T) agent="gate";;
      esac
      if [[ "$p" == "W" && "$TEAM_WORK" != true ]]; then
        log "  skip  W (Team-Work) — --no-team-work"
      elif [[ "$p" == "R" && "$TEAM_WORK" == true ]]; then
        log "  skip  R (single Render) — team-work W replaces mono-builder (use --no-team-work for old path)"
      elif [[ "$p" == "F" && "$SKIP_FORTIFY" == true ]]; then
        log "  skip  F (Fortify) — fortify off (profile/flag)"
      elif [[ "$p" == "T" && "$SKIP_MERGE" == true ]]; then
        log "  skip  T (Test-Merge) — --skip-merge"
      else
        ok "  run   $p  agent=$agent"
      fi
    else
      log "  out   $p (outside $FROM_PHASE..$TO_PHASE)"
    fi
  done
  if [[ "$TEAM_WORK" == true ]] && plan_is_filled 2>/dev/null; then
    info "── team-work dry preview ──"
    "$_HERE/lib/team-dispatch.sh" run --plan "$PLAN" ${TASK:+--task "$TASK"} --dry-run \
      --out "$_HERE/.dual-agent/tmp/WORK-dry.json" 2>&1 | tail -20 || true
  fi
  exit 0
fi

# --- exclusive lock + state (anti overlap) ---------------------------------
RUN_ID="run-$(utc_stamp)-$$"
coordination_lock_acquire "$RUN_ID"
trap 'coordination_lock_release' EXIT INT TERM

# Resume: if state exists and --from-phase was set, keep run_id; else init.
if [[ -f "$(coordination_state_path)" && "$FROM_PHASE" != "C" ]]; then
  info "Resuming existing run-state (from-phase=$FROM_PHASE)."
else
  coordination_state_init "$RUN_ID" "$TASK"
fi

# --- helpers ---------------------------------------------------------------
advance() {
  local phase="$1" note="${2:-}"
  local next baton agent
  next="$(coordination_next_phase "$phase")"
  # Adaptive baton: hand to the function-holder for the NEXT phase, not a
  # hard-coded vendor name (builder may be grok OR codex; assessor may vary).
  case "$phase" in
    C) agent="claude";          baton="$([[ "$TEAM_WORK" == true ]] && echo team || echo "$BUILDER")"
       next="$([[ "$TEAM_WORK" == true ]] && echo W || echo R)" ;;
    W) agent="team";            baton="gate"; next="G" ;;  # team-work replaces mono R by default
    R) agent="$BUILDER";        baton="gate" ;;
    G) agent="gate";            baton="$ASSESS_VENDOR" ;;
    A) agent="$ASSESS_VENDOR";  baton="$([[ "$SKIP_FORTIFY" == true ]] && echo gate || echo claude)" ;;
    F) agent="claude";          baton="gate" ;;
    T) agent="gate";            baton="done"; next="done" ;;
    *) agent="$(coordination_phase_agent "$phase")"
       baton="$(coordination_baton_after "$phase")" ;;
  esac
  # Pass explicit next baton/phase so HANDOFF header matches run-state (no split-brain).
  coordination_handoff_append "$agent" "$phase" \
    "- $note"$'\n'"- phase complete."$'\n'"- adaptive: builder=$BUILDER assessor=$ASSESS_VENDOR profile=${PROFILE_RESOLVED:-$PROFILE} team-work=$TEAM_WORK" \
    "$baton" "$next"
  coordination_state_set_phase "$next" "$baton" "completed_$phase"
  ok "phase $phase done → next=$next baton=$baton (agent was $agent)"
}

plan_is_filled() {
  [[ -f "$PLAN" ]] || return 1
  local t
  t="$(tr -d '\r' <"$PLAN")"
  [[ -n "${t// }" ]] || return 1
  # template placeholders still present?
  if grep -qE '<Feature-Name>|<Was soll gebaut' <<<"$t"; then
    return 1
  fi
  return 0
}

# ============================================================================
# C — Contract (Claude)
# ============================================================================
if should_run_phase C; then
  info "\n── C · Contract (Claude) ──"
  coordination_require_baton claude
  # Allow init baton claude; assert phase C if fresh
  cur_phase="$(coordination_state_get phase)"
  if [[ "$cur_phase" != "C" && "$FROM_PHASE" == "C" ]]; then
    coordination_state_set_phase C claude "reset_to_C"
  fi

  if [[ "$AUTO_PLAN" == true ]]; then
    [[ -n "$TASK" ]] || fail "dual-run --auto-plan requires --task."
    command -v claude >/dev/null 2>&1 || fail "claude CLI not in PATH (needed for --auto-plan)."
    tmpl="$_HERE/PLAN.template.md"
    [[ -f "$tmpl" ]] || fail "PLAN.template.md missing."
    promptfile="$_HERE/.dual-agent/tmp/autoplan-$(utc_stamp).txt"
    mkdir -p "$_HERE/.dual-agent/tmp"
    cat >"$promptfile" <<EOF
You are the ARCHITECT in a dual-agent workflow (Claude + Grok). Fill a complete PLAN.md
from the task below. Use the template structure exactly. No code — contract only.
Be precise on Interface-Contract and binary acceptance criteria. List Out of Scope.
Output ONLY the finished markdown document, no fences, no preamble.

=== TASK ===
$TASK

=== TEMPLATE ===
$(cat "$tmpl")
EOF
    info "Claude drafting PLAN.md from --task …"
    # claude-call emits adapter-contract JSON on stdout (exit_code/text/json_log).
    ap_json="$("$_HERE/lib/claude-call.sh" --prompt-file "$promptfile" \
      --disallowed-tools "Bash,Write,Edit,WebFetch,WebSearch" \
      --tag dual-run-autoplan \
      ${MODEL:+--model "$MODEL"})" \
      || fail "claude-call failed during --auto-plan."
    ap_exit="$(printf '%s' "$ap_json" | json_field_stdin exit_code)"
    [[ "$ap_exit" == 0 ]] || fail "claude-call --auto-plan exit_code=$ap_exit."
    printf '%s' "$ap_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("text",""))' >"$PLAN"
    [[ -s "$PLAN" ]] || fail "auto-plan produced empty PLAN.md."
  fi

  plan_is_filled || fail "Contract missing/unfilled: $PLAN — Claude must fill PLAN.md (or pass --auto-plan --task)."
  # Commit contract if dirty so Render sees it
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain -- "$PLAN" 2>/dev/null || true)" ]]; then
      git add -- "$PLAN"
      git commit -q -m "contract: dual-run $RUN_ID [no-push]" || warn "contract commit skipped (nothing to commit?)."
    fi
  fi
  advance C "Contract ready: $PLAN — next team work (all three code)"
fi

# ============================================================================
# W — Team Work: Claude + Grok + Codex ALL execute packages
# ============================================================================
if should_run_phase W && [[ "$TEAM_WORK" == true ]]; then
  info "\n── W · Team Work (Claude + Grok + Codex — everyone codes) ──"
  if [[ "$(coordination_state_get baton)" != "team" ]]; then
    coordination_state_set_phase W team "enter_W"
  fi

  WORK_FILE="$_HERE/ledger/WORK.json"
  "$_HERE/lib/team-dispatch.sh" run --plan "$PLAN" ${TASK:+--task "$TASK"} --out "$WORK_FILE" \
    || fail "team-dispatch failed — not all workers completed packages."

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git branch -f "$POC_BRANCH" HEAD >/dev/null 2>&1 \
      || git branch "$POC_BRANCH" HEAD >/dev/null 2>&1 \
      || warn "could not update $POC_BRANCH pointer."
  fi
  TEAM_WORK_DONE=true
  "$_HERE/lib/team-dispatch.sh" status "$WORK_FILE" || true
  advance W "Team packages done (ledger/WORK.json) — Claude+Grok+Codex all worked"
fi

# ============================================================================
# R — mono-Render (only if team-work off)
# ============================================================================
if should_run_phase R && [[ "$TEAM_WORK_DONE" != true ]]; then
  info "\n── R · Render (mono-builder=$BUILDER$([[ "$SCOUT" == true ]] && echo ', scout=on')) ──"
  cur_baton="$(coordination_state_get baton)"
  if [[ "$cur_baton" != "$BUILDER" ]]; then
    coordination_state_set_phase R "$BUILDER" "enter_R_builder=$BUILDER"
  fi
  coordination_require_baton "$BUILDER"

  build_args=(--plan "$PLAN" --variants "$VARIANTS" --branch "$POC_BRANCH" --into "$INTO"
              --max-turns "$MAX_TURNS" --builder "$BUILDER")
  [[ "$ADAPTIVE" == true ]] && build_args+=(--adaptive)
  [[ -n "$VERIFY" ]] && build_args+=(--verify "$VERIFY")
  [[ "$SCOUT" == true ]] && build_args+=(--scout)
  [[ -n "$MODEL" ]] && build_args+=(--model "$MODEL")

  "$_HERE/dual-build.sh" "${build_args[@]}" || fail "dual-build failed — Render RED."
  advance R "POC on $POC_BRANCH via dual-build (builder=$BUILDER scout=$SCOUT)"
elif should_run_phase R && [[ "$TEAM_WORK_DONE" == true ]]; then
  info "\n── R · mono-Render SKIPPED (team-work W produced $POC_BRANCH) ──"
fi

# ============================================================================
# G — Guards (deterministic, zero tokens)
# ============================================================================
if should_run_phase G; then
  info "\n── G · Guards (import-scan + test-guard) ──"
  # gate may hold baton
  cur_baton="$(coordination_state_get baton)"
  if [[ "$cur_baton" != "gate" ]]; then
    coordination_state_set_phase G gate "enter_G"
  fi

  if [[ "$IMPORT_SCAN" == true ]]; then
    scan_args=(--poc "$POC_BRANCH" --base "$BASE_BRANCH" --plan "$PLAN")
    [[ "$IMPORT_PROV" == true ]] && scan_args+=(--check-provenance)
    "$_HERE/lib/import-scan.sh" "${scan_args[@]}" || fail "import-scan BLOCKED — invented/off-contract deps."
    ok "import-scan clean."
  else
    warn "import-scan skipped (--no-import-scan)."
  fi

  if [[ "$TEST_GUARD" == true ]]; then
    tg_args=(--poc "$POC_BRANCH" --base "$BASE_BRANCH")
    # Team-work: Claude-owned test packages in WORK.json are allowed (architect pins tests).
    # Grok/Codex test edits remain blocked (invariant 7).
    if [[ "$TEAM_WORK" == true && -f "$_HERE/ledger/WORK.json" ]]; then
      tg_args+=(--allow-from-work "$_HERE/ledger/WORK.json")
    fi
    "$_HERE/lib/test-guard.sh" "${tg_args[@]}" \
      || fail "test-guard BLOCKED — builder touched tests (invariant 7)."
    ok "test-guard clean (builder did not edit tests; team Claude tests allowed if WORK.json)."
  else
    warn "test-guard skipped (--no-test-guard)."
  fi

  # Ownership audit: builder must not touch Claude/harness surfaces (anti-overlap).
  if git rev-parse --verify "$POC_BRANCH" >/dev/null 2>&1; then
    mapfile -t poc_files < <(git diff --name-only "$BASE_BRANCH...$POC_BRANCH" 2>/dev/null || true)
    if [[ ${#poc_files[@]} -gt 0 ]]; then
      coordination_check_builder_paths "${poc_files[@]}"
    fi
  fi

  advance G "Guards passed (import-scan=$IMPORT_SCAN test-guard=$TEST_GUARD)"
fi

# ============================================================================
# A — Assess (Claude bounded review + one Grok rebuttal)
# ============================================================================
if should_run_phase A; then
  info "\n── A · Assess (assessor=$ASSESS_VENDOR, rebutter=$BUILDER, 1 rebuttal cap) ──"
  cur_baton="$(coordination_state_get baton)"
  if [[ "$cur_baton" != "$ASSESS_VENDOR" ]]; then
    coordination_state_set_phase A "$ASSESS_VENDOR" "enter_A_assessor=$ASSESS_VENDOR"
  fi
  coordination_require_baton "$ASSESS_VENDOR"

  review_args=(--plan "$PLAN" --poc "$POC_BRANCH" --base "$BASE_BRANCH"
               --assess-vendor "$ASSESS_VENDOR" --rebutter "$BUILDER")
  [[ -n "$MODEL" ]] && review_args+=(--model "$MODEL")
  "$_HERE/dual-review.sh" "${review_args[@]}" || fail "dual-review failed."

  # Mid-run adaptive re-route from REVIEW ledger (high issues → fortify+security).
  if [[ "$ROLE_ADAPTIVE" == true && -f "$_HERE/ledger/REVIEW.json" ]]; then
    local_skip_before="$SKIP_FORTIFY"
    apply_role_assignment "$_HERE/ledger/REVIEW.json"
    if [[ "$local_skip_before" == true && "$SKIP_FORTIFY" == false ]]; then
      warn "mid-run adaptive: REVIEW elevated severity → Fortify FORCED on."
    fi
    if [[ "$SECURITY_PASS" == true ]]; then
      info "mid-run adaptive: security pass armed (hardener will include security lens)."
    fi
    show_who_matrix
  fi
  advance A "Bounded cross-review → ledger/REVIEW.* (assessor=$ASSESS_VENDOR)"
fi

# ============================================================================
# F — Fortify (Claude hardens onto feat/harden)
# ============================================================================
if should_run_phase F; then
  if [[ "$SKIP_FORTIFY" == true ]]; then
    warn "── F · Fortify SKIPPED (profile/flag; use --fortify or risk signals to enable) ──"
    # Move baton to gate for merge-from-poc path
    coordination_state_set_phase T gate "skip_F"
    coordination_handoff_append claude F "- Fortify skipped (profile=${PROFILE_RESOLVED:-$PROFILE}); merge candidate remains $POC_BRANCH."
  else
    info "\n── F · Fortify (hardener=claude → $HARDEN_BRANCH$([[ "$SECURITY_PASS" == true ]] && echo ', security=on')) ──"
    cur_baton="$(coordination_state_get baton)"
    if [[ "$cur_baton" != "claude" && "$cur_baton" != "gate" ]]; then
      coordination_state_set_phase F claude "enter_F"
    fi
    # After A with fortify on, baton is claude; allow gate→claude handoff
    if [[ "$(coordination_state_get baton)" != "claude" ]]; then
      coordination_state_set_phase F claude "force_F_baton"
    fi
    coordination_require_baton claude
    command -v claude >/dev/null 2>&1 || fail "claude CLI not in PATH (needed for --fortify)."

    # Branch harden from poc
    git branch -D "$HARDEN_BRANCH" >/dev/null 2>&1 || true
    git branch "$HARDEN_BRANCH" "$POC_BRANCH" >/dev/null 2>&1 \
      || fail "could not create $HARDEN_BRANCH from $POC_BRANCH."

    top="$(git rev-parse --show-toplevel)"
    wt="$(dirname "$top")/wt-${HARDEN_BRANCH//[\/:]/-}"
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
    git worktree add "$wt" "$HARDEN_BRANCH" >/dev/null 2>&1 || fail "worktree add for fortify failed."

    plan_text="$(tr -d '\r' <"$PLAN")"
    review_snip=""
    [[ -f "$_HERE/ledger/REVIEW.md" ]] && review_snip="$(head -c 8000 "$_HERE/ledger/REVIEW.md")"
    fprompt="$_HERE/.dual-agent/tmp/fortify-$(utc_stamp).txt"
    sec_block=""
    if [[ "$SECURITY_PASS" == true ]]; then
      sec_block="
SECURITY PASS (required by adaptive profile): produce a short threat model for changed
surfaces, sweep for secrets/auth/injection, fix concrete findings. Do not claim clean
without checking."
    fi
    cat >"$fprompt" <<EOF
You are the HARDENER in a dual-agent workflow. The BUILDER already produced a POC on this
branch. Harden it: add/fix tests, error handling, security, docs — without changing the
contract. Do NOT invent dependencies outside PLAN. Commit your work.
$sec_block

=== CONTRACT ===
$plan_text

=== REVIEW NOTES (if any) ===
$review_snip
EOF
    # Claude operates in the harden worktree cwd (claude-call has no --cwd flag).
    # Absolute prompt path so the wrapper finds it after cd.
    fprompt_abs="$(cd "$(dirname "$fprompt")" && pwd)/$(basename "$fprompt")"
    (
      cd "$wt" || exit 1
      "$_HERE/lib/claude-call.sh" --prompt-file "$fprompt_abs" \
        --tag dual-run-fortify \
        ${MODEL:+--model "$MODEL"}
    ) || { git worktree remove --force "$wt" >/dev/null 2>&1 || true; fail "fortify claude-call failed."; }

    # Capture any uncommitted harden work
    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null || true)" ]]; then
      git -C "$wt" add -A
      git -C "$wt" commit -q -m "fortify: dual-run $RUN_ID [no-push]" || true
    fi
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
    advance F "Hardened on $HARDEN_BRANCH"
  fi
fi

# ============================================================================
# T — Test + No-Cut merge
# ============================================================================
if should_run_phase T && [[ "$SKIP_MERGE" != true ]]; then
  info "\n── T · Test-Merge (eval pass^k, No-Cut) ──"
  cur_baton="$(coordination_state_get baton)"
  if [[ "$cur_baton" != "gate" && "$cur_baton" != "done" ]]; then
    # after skip F we set gate; after full F baton is gate
    coordination_state_set_phase T gate "enter_T"
  fi

  MERGE_FROM="$POC_BRANCH"
  if [[ "$SKIP_FORTIFY" != true ]] && git rev-parse --verify "$HARDEN_BRANCH" >/dev/null 2>&1; then
    MERGE_FROM="$HARDEN_BRANCH"
  fi

  [[ -n "$VERIFY" ]] || fail "dual-run: --verify is required for merge (invariant 4). Pass --skip-merge to stop before T."

  merge_args=(--from "$MERGE_FROM" --into "$INTO" --verify "$VERIFY" --eval-k "$EVAL_K")
  [[ "$TEST_GUARD" == true ]] && merge_args+=(--test-guard)

  "$_HERE/dual-merge.sh" "${merge_args[@]}" || fail "dual-merge BLOCKED — no merge (invariant 3/4/7)."
  coordination_state_set_phase done done "merged"
  coordination_handoff_append gate T "- MERGED $MERGE_FROM → $INTO (eval_k=$EVAL_K)."$'\n'"- BATON -> done"
  ok "\nALL PHASES COMPLETE — $MERGE_FROM → $INTO (No-Cut + pass^k)."
elif should_run_phase T && [[ "$SKIP_MERGE" == true ]]; then
  warn "── T · Merge SKIPPED (--skip-merge) ──"
  coordination_state_set_phase T gate "skip_T"
  ok "Stopped before merge. Candidate branch: $([[ "$SKIP_FORTIFY" == true ]] && echo "$POC_BRANCH" || echo "$HARDEN_BRANCH")"
fi

info "\n=== dual-run finished ==="
coordination_status
# lock released by EXIT trap
