#!/usr/bin/env bash
# grok-call.sh — clean wrapper for ONE headless Grok invocation.
#
# Preserves the three guarantees the PowerShell version fought for:
#   1. stdout (the JSON result) and stderr (auth/MCP noise) are separated at the
#      OS level (real fds, not a fragile stream-merge) -> the HuggingFace /
#      AuthorizationRequired spam can NEVER leak into the parsed result.
#   2. Raw process bytes are captured (grok emits UTF-8); no re-encoding step.
#   3. --output-format json is parsed; callers get .text via json_extract_text.
#
# Prints the adapter contract as ONE JSON object on stdout (see emit_result):
#   {exit_code, text, json_log, stdout_log}   (+ writes *.out.json / *.err.log)
#
# Usage:
#   lib/grok-call.sh --prompt-file <abs> [--cwd DIR] [--max-turns 40]
#     [--best-of-n 1] [--model M] [--sandbox S] [--always-approve]
#     [--check] [--deny 'Bash(rm -rf *)' --deny ...] [--tag grok] [--dry-run]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

PROMPT_FILE=""; CWD="$(pwd)"; MAX_TURNS=40; BEST_OF_N=1; MODEL=""; SANDBOX=""
ALWAYS_APPROVE=false; CHECK=false; TAG="grok"; DRYRUN=false; DENY=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file)    PROMPT_FILE="$2"; shift 2;;
    --cwd)            CWD="$2"; shift 2;;
    --max-turns)      MAX_TURNS="$2"; shift 2;;
    --best-of-n)      BEST_OF_N="$2"; shift 2;;
    --model)          MODEL="$2"; shift 2;;
    --sandbox)        SANDBOX="$2"; shift 2;;
    --always-approve) ALWAYS_APPROVE=true; shift;;
    --check)          CHECK=true; shift;;
    --deny)           DENY+=("$2"); shift 2;;
    --tag)            TAG="$2"; shift 2;;
    --dry-run)        DRYRUN=true; shift;;
    *) fail "grok-call: unknown arg '$1'";;
  esac
done
command -v grok >/dev/null 2>&1 || { warn "BLOCKED: grok CLI not in PATH."; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { warn "BLOCKED: prompt file missing: $PROMPT_FILE"; exit 1; }

logdir="$(repo_root)/.dual-agent/logs"; mkdir -p "$logdir"
stamp="$(utc_stamp_ms)"
outfile="$logdir/$TAG-$stamp.out.json"
errfile="$logdir/$TAG-$stamp.err.log"

# Build args as an array (quoting-safe, unlike the PS string concat).
args=(--prompt-file "$PROMPT_FILE" --cwd "$CWD" --output-format json --max-turns "$MAX_TURNS")
[[ "$BEST_OF_N" -gt 1 ]] && args+=(--best-of-n "$BEST_OF_N")
[[ "$ALWAYS_APPROVE" == true ]] && args+=(--always-approve)
[[ "$CHECK" == true ]] && args+=(--check)
[[ -n "$MODEL" ]] && args+=(--model "$MODEL")
[[ -n "$SANDBOX" ]] && args+=(--sandbox "$SANDBOX")
for d in "${DENY[@]:-}"; do [[ -n "$d" ]] && args+=(--deny "$d"); done  # deny overrides approve

if [[ "$DRYRUN" == true ]]; then
  warn "grok-call DryRun -- grok ${args[*]}"
  echo "$outfile" >/dev/null
  emit_result 0 /dev/null /dev/null "$outfile"; exit 0
fi

# OS-level fd separation: result -> $outfile, noise -> $errfile.
grok "${args[@]}" >"$outfile" 2>"$errfile"
exit_code=$?

# Extract the agent text; honest noise self-check must stay in stderr.
textfile="$(mktemp)"; json_extract_text "$outfile" >"$textfile"
if grep -qiE 'AuthorizationRequired|Transport channel closed|huggingface\.co|www_authenticate' "$outfile" 2>/dev/null; then
  warn "grok-call: noise detected in RESULT (unexpected -> inspect $outfile)."
fi
emit_result "$exit_code" "$textfile" "$outfile" "$outfile"
rm -f "$textfile"
exit "$exit_code"
