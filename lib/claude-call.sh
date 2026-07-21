#!/usr/bin/env bash
# claude-call.sh — clean wrapper for ONE headless Claude invocation.
#
# The Claude-side twin of grok-call.sh so the bounded cross-review runs Claude
# headless symmetrically to Grok. The prompt is fed on STDIN so long multi-line
# review prompts with quotes/markdown survive intact (no arg-quoting hell).
#
# --exclude-dynamic-system-prompt-sections moves per-machine sections (cwd/env/
# memory paths) into the first user message so the ~100k system prefix becomes
# cache-shareable ACROSS worktrees (Claude's cache is per-directory; our
# worktree isolation defeats it by default). Quality-neutral.
#
# Cost telemetry: appends {stamp,tag,model,cost_usd} to ledger/SPEND.jsonl --
# the deterministic basis for budget-guard.sh.
#
# Prints the adapter contract JSON: {exit_code, text, json_log, stdout_log}.
# Additionally exits non-zero if the response's is_error flag is true.
#
# Usage:
#   lib/claude-call.sh --prompt-file <abs> [--model M] [--system-prompt S]
#     [--max-budget-usd N] [--tag claude]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

PROMPT_FILE=""; MODEL=""; SYSTEM_PROMPT=""; MAX_BUDGET="0"; TAG="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file)    PROMPT_FILE="$2"; shift 2;;
    --model)          MODEL="$2"; shift 2;;
    --system-prompt)  SYSTEM_PROMPT="$2"; shift 2;;
    --max-budget-usd) MAX_BUDGET="$2"; shift 2;;
    --tag)            TAG="$2"; shift 2;;
    *) fail "claude-call: unknown arg '$1'";;
  esac
done
command -v claude >/dev/null 2>&1 || { warn "BLOCKED: claude CLI not in PATH."; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { warn "BLOCKED: prompt file missing: $PROMPT_FILE"; exit 1; }

logdir="$(repo_root)/.dual-agent/logs"; mkdir -p "$logdir"
stamp="$(utc_stamp_ms)"
outfile="$logdir/$TAG-$stamp.out.json"
errfile="$logdir/$TAG-$stamp.err.log"

args=(-p --output-format json --exclude-dynamic-system-prompt-sections)
[[ -n "$MODEL" ]] && args+=(--model "$MODEL")
[[ -n "$SYSTEM_PROMPT" ]] && args+=(--append-system-prompt "$SYSTEM_PROMPT")
awk -v b="$MAX_BUDGET" 'BEGIN{exit !(b>0)}' && args+=(--max-budget-usd "$MAX_BUDGET")

# Prompt on stdin; stdout -> result file, stderr -> err log.
claude "${args[@]}" <"$PROMPT_FILE" >"$outfile" 2>"$errfile"
exit_code=$?

textfile="$(mktemp)"; json_extract_text "$outfile" >"$textfile"
is_error="$(json_field "$outfile" is_error)"
cost="$(json_field "$outfile" total_cost_usd)"

# Cost telemetry -> SPEND.jsonl (feeds budget-guard).
if [[ -n "$cost" ]]; then
  ledger="$(repo_root)/ledger"; mkdir -p "$ledger"
  python3 - "$ledger/SPEND.jsonl" "$stamp" "$TAG" "$MODEL" "$cost" <<'PY'
import sys, json
out, stamp, tag, model, cost = sys.argv[1:6]
open(out,"a",encoding="utf-8").write(json.dumps({"stamp":stamp,"tag":tag,"model":model,"cost_usd":float(cost)})+"\n")
PY
fi

emit_result "$exit_code" "$textfile" "$outfile" "$outfile"
rm -f "$textfile"
[[ "$is_error" == "true" ]] && exit 1
exit "$exit_code"
