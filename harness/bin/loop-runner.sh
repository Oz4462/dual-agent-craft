#!/usr/bin/env bash
# loop-runner.sh — bounded autonomous loop with declared done-condition + caps.
#
# Contract (harness/skills/loop-runner/SKILL.md, Reflex R10): no loop without a
# checkable done-condition AND hard caps. Ends on:
#   SUCCESS  — done-condition exits 0
#   CAPPED   — max-cycles or max-seconds reached          (exit 1)
#   STALLED  — 2 consecutive cycles, identical failure     (exit 1)
# Logs one JSONL line per cycle to .dual-agent/logs/LOOP-LOG.jsonl.
#
# Usage:
#   harness/bin/loop-runner.sh --cycle "<cmd>" --done "<cmd>" \
#     [--max-cycles 6] [--max-seconds 1800] [--log FILE]
set -uo pipefail
export LC_ALL=C

CYCLE=""; DONE=""; MAX_CYCLES=6; MAX_SECONDS=1800; LOGFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycle)       CYCLE="${2:?value required for $1}"; shift 2;;
    --done)        DONE="${2:?value required for $1}"; shift 2;;
    --max-cycles)  MAX_CYCLES="${2:?value required for $1}"; shift 2;;
    --max-seconds) MAX_SECONDS="${2:?value required for $1}"; shift 2;;
    --log)         LOGFILE="${2:?value required for $1}"; shift 2;;
    *) echo "loop-runner: unknown arg '$1'" >&2; exit 1;;
  esac
done
[[ -n "$CYCLE" && -n "$DONE" ]] || { echo "BLOCKED: --cycle AND --done are required (no loop without a done-condition)." >&2; exit 1; }
[[ "$MAX_CYCLES" -ge 1 && "$MAX_SECONDS" -ge 1 ]] 2>/dev/null || { echo "BLOCKED: caps must be positive integers." >&2; exit 1; }
[[ -z "$LOGFILE" ]] && { mkdir -p .dual-agent/logs; LOGFILE=".dual-agent/logs/LOOP-LOG.jsonl"; }
mkdir -p "$(dirname "$LOGFILE")"

jlog() { # jlog <cycle> <event> <exit> <extra-json-fragment>
  printf '{"stamp":"%s","cycle":%s,"event":"%s","exit":%s%s}\n' \
    "$(date -u +%Y%m%d-%H%M%S)" "$1" "$2" "$3" "${4:+,$4}" >> "$LOGFILE"
}

start=$(date +%s)
prev_sig=""
stall=0

# Already done? Then don't burn a cycle.
if eval "$DONE" >/dev/null 2>&1; then
  jlog 0 "success" 0 '"note":"done-condition green before first cycle"'
  echo "loop-runner: SUCCESS (already done, 0 cycles)"; exit 0
fi

for (( c=1; c<=MAX_CYCLES; c++ )); do
  now=$(date +%s)
  if (( now - start >= MAX_SECONDS )); then
    jlog "$c" "capped" 1 '"cap":"max-seconds"'
    echo "loop-runner: CAPPED (max-seconds $MAX_SECONDS) after $((c-1)) cycles — handing back." >&2
    exit 1
  fi

  cycle_out="$(eval "$CYCLE" 2>&1)"; cycle_exit=$?
  # failure signature: exit code + last output line -> detects a loop that isn't learning
  sig="$cycle_exit:$(printf '%s' "$cycle_out" | tail -1 | head -c 200)"
  jlog "$c" "cycle" "$cycle_exit"

  if eval "$DONE" >/dev/null 2>&1; then
    jlog "$c" "success" 0
    echo "loop-runner: SUCCESS after $c cycle(s)."
    exit 0
  fi

  if [[ "$cycle_exit" -ne 0 && "$sig" == "$prev_sig" ]]; then
    stall=$((stall+1))
  else
    stall=0
  fi
  prev_sig="$sig"

  if (( stall >= 1 )); then   # 2 consecutive identical failures total
    jlog "$c" "stalled" 1 '"note":"identical failure twice - loop is not learning"'
    { echo "loop-runner: STALLED (identical failure two cycles in a row) — handing back. Last output:";
      printf '%s\n' "$cycle_out" | tail -5; } >&2
    exit 1
  fi
done

jlog "$MAX_CYCLES" "capped" 1 '"cap":"max-cycles"'
echo "loop-runner: CAPPED (max-cycles $MAX_CYCLES) — done-condition still red, handing back." >&2
exit 1
