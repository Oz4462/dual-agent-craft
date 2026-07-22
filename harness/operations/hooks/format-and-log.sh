#!/usr/bin/env bash
# format-and-log.sh — PostToolUse hook (Write|Edit): best-effort format + tool log.
#
# 1. Formats the edited file with whatever project-local formatter exists
#    (shfmt / black / prettier) — best effort, NEVER fails the hook.
# 2. Appends one JSONL line to .dual-agent/logs/TOOL-LOG.jsonl — the flight
#    recorder for "what did the agent actually touch this session".
#
# stdin: {"tool_name":"Write","tool_input":{"file_path":"..."}}
# Test hook: HARNESS_HOOK_INPUT overrides stdin.
set -uo pipefail
export LC_ALL=C

payload="${HARNESS_HOOK_INPUT:-$(cat)}"
proj="${CLAUDE_PROJECT_DIR:-$(pwd)}"

file="$(PAYLOAD="$payload" python3 -c '
import os, json
try:
    j = json.loads(os.environ["PAYLOAD"])
    print((j.get("tool_input") or {}).get("file_path") or "")
except Exception:
    pass
')"
[[ -z "$file" || ! -f "$file" ]] && exit 0

# --- best-effort format (project-local tools only, never a hard failure) ----
case "$file" in
  *.sh)   command -v shfmt >/dev/null 2>&1 && shfmt -w "$file" >/dev/null 2>&1 || true ;;
  *.py)   command -v black >/dev/null 2>&1 && black -q "$file" >/dev/null 2>&1 || true ;;
  *.js|*.ts|*.jsx|*.tsx|*.json|*.css|*.md)
          [[ -x "$proj/node_modules/.bin/prettier" ]] && "$proj/node_modules/.bin/prettier" --write "$file" >/dev/null 2>&1 || true ;;
esac

# --- flight-recorder line ---------------------------------------------------
logdir="$proj/.dual-agent/logs"; mkdir -p "$logdir"
FILE="$file" python3 -c '
import os, json, datetime
rec = {"stamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S"),
       "event": "edit", "file": os.environ["FILE"]}
print(json.dumps(rec))
' >> "$logdir/TOOL-LOG.jsonl" 2>/dev/null || true

exit 0
