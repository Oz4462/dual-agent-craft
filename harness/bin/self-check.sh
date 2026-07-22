#!/usr/bin/env bash
# self-check.sh — the harness's single fitness gate (closes the self-improvement loop).
#
# Runs the WHOLE battery and returns ONE verdict:
#   1. syntax   — bash -n over every shipped script
#   2. configs  — JSON validity (permissions / hooks / agents)
#   3. suite    — tests/run.sh (bats)
#   4. reflexes — reflex-drill.sh (guard-layer adversarial stimuli)
#   5. mutation — mutation-train.sh (logic-layer fault injection; needs clean tree)
#
# Exit 0 only if EVERY stage passes. This is what a recursively self-improving
# harness runs to measure its own fitness in one action. --quick skips mutation
# training (the slow stage) for a fast inner-loop check.
set -uo pipefail
export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

pass=(); fail=()
stage() { # stage <name> <cmd...>
  local name="$1"; shift
  printf '\n--- %s ---\n' "$name"
  if "$@"; then pass+=("$name"); else fail+=("$name"); fi
}

syntax_sweep() {
  local f=0
  for s in *.sh lib/*.sh tests/run.sh harness/*.sh harness/bin/*.sh \
           harness/operations/hooks/*.sh harness/automations/*.sh; do
    [[ -e "$s" ]] || continue
    bash -n "$s" || { echo "SYNTAX FAIL $s"; f=1; }
  done
  [[ $f -eq 0 ]] && echo "syntax: all clean"
  return $f
}
config_check() {
  local f=0
  for j in harness/operations/permissions.json harness/operations/hooks.json harness/teams/agents.json; do
    python3 -c "import json;json.load(open('$j'))" 2>/dev/null && echo "ok $j" || { echo "INVALID $j"; f=1; }
  done
  return $f
}

stage "1/5 syntax"   syntax_sweep
stage "2/5 configs"  config_check
stage "3/5 suite"    tests/run.sh
stage "4/5 reflexes" harness/bin/reflex-drill.sh

if [[ "$QUICK" == true ]]; then
  echo -e "\n--- 5/5 mutation --- (skipped: --quick)"
elif [[ -n "$(git status --porcelain)" ]]; then
  echo -e "\n--- 5/5 mutation ---"
  echo "SKIPPED: working tree dirty (mutation-train needs clean tree). Commit/stash then re-run."
  fail+=("5/5 mutation (skipped-dirty)")
else
  stage "5/5 mutation" harness/bin/mutation-train.sh
fi

printf '\n=== SELF-CHECK: %d passed, %d failed ===\n' "${#pass[@]}" "${#fail[@]}"
if [[ ${#fail[@]} -eq 0 ]]; then
  echo "FIT — every stage green. CRAFT is at its verified best."
  exit 0
else
  printf 'UNFIT — failed stage(s): %s\n' "${fail[*]}"
  exit 1
fi
