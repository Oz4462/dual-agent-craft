#!/usr/bin/env bash
# codex-call.sh — clean wrapper for ONE headless OpenAI Codex invocation.
#
# NEW third-vendor adapter, reverse-engineered from Hermes'
# autonomous-ai-agents/codex skill + the live `codex exec --help`. Matches the
# ADAPTERS.md contract so Codex drops into the loop as a real, DIFFERENT vendor
# (the cross-vendor moat is diversity itself, not a specific vendor).
#
# Why Codex is a strong add on Linux:
#   - `codex exec -s read-only|workspace-write|danger-full-access` is a REAL
#     local sandbox (Grok's --sandbox is macOS-only) -> the natural
#     low-privilege reviewer, or a genuinely-sandboxed extra builder.
#   - `-o/--output-last-message <FILE>` writes the clean final answer to a file,
#     so we get the result WITHOUT parsing the JSONL event stream.
#   - prompt on stdin via `-` (the same clean path as claude-call).
#
# Prints the adapter contract JSON: {exit_code, text, json_log, stdout_log}.
#
# Usage:
#   lib/codex-call.sh --prompt-file <abs> [--cwd DIR]
#     [--model M] [--sandbox read-only|workspace-write|danger-full-access]
#     [--full-auto] [--json] [--tag codex] [--dry-run]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

PROMPT_FILE=""; CWD="$(pwd)"; MODEL=""; SANDBOX="read-only"
FULL_AUTO=false; JSONL=false; TAG="codex"; DRYRUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) PROMPT_FILE="$2"; shift 2;;
    --cwd)         CWD="$2"; shift 2;;
    --model)       MODEL="$2"; shift 2;;
    --sandbox)     SANDBOX="$2"; shift 2;;
    --full-auto)   FULL_AUTO=true; shift;;
    --json)        JSONL=true; shift;;
    --tag)         TAG="$2"; shift 2;;
    --dry-run)     DRYRUN=true; shift;;
    *) fail "codex-call: unknown arg '$1'";;
  esac
done
command -v codex >/dev/null 2>&1 || { warn "BLOCKED: codex CLI not in PATH."; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { warn "BLOCKED: prompt file missing: $PROMPT_FILE"; exit 1; }

logdir="$(repo_root)/.dual-agent/logs"; mkdir -p "$logdir"
stamp="$(utc_stamp_ms)"
outfile="$logdir/$TAG-$stamp.out.log"      # raw stdout (JSONL if --json)
errfile="$logdir/$TAG-$stamp.err.log"
lastmsg="$logdir/$TAG-$stamp.last.txt"     # clean final answer (-o)

# `codex exec` runs non-interactively. -C sets the working root; --skip-git-repo-check
# lets us run in isolated worktrees without a fresh init. Prompt via stdin ('-').
args=(exec --cd "$CWD" --skip-git-repo-check -o "$lastmsg" -s "$SANDBOX" --color never)
[[ -n "$MODEL" ]] && args+=(-m "$MODEL")
[[ "$JSONL" == true ]] && args+=(--json)
# Full-auto for a sandboxed builder role: bypass approval prompts (still sandboxed
# unless the caller explicitly chose danger-full-access).
[[ "$FULL_AUTO" == true ]] && args+=(--dangerously-bypass-approvals-and-sandbox)
args+=(-)   # read prompt from stdin

if [[ "$DRYRUN" == true ]]; then
  warn "codex-call DryRun -- codex ${args[*]}"
  emit_result 0 /dev/null /dev/null "$outfile"; exit 0
fi

codex "${args[@]}" <"$PROMPT_FILE" >"$outfile" 2>"$errfile"
exit_code=$?

# Prefer the clean -o last-message; fall back to extracting from stdout.
textfile="$(mktemp)"
if [[ -s "$lastmsg" ]]; then cat "$lastmsg" >"$textfile"; else json_extract_text "$outfile" >"$textfile"; fi
emit_result "$exit_code" "$textfile" "$outfile" "$outfile"
rm -f "$textfile"
exit "$exit_code"
