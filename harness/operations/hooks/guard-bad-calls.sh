#!/usr/bin/env bash
# guard-bad-calls.sh — PreToolUse hook: deterministically block dangerous calls.
#
# Claude Code feeds the pending tool call as JSON on stdin:
#   {"tool_name":"Bash","tool_input":{"command":"..."}}
# Exit 0 = allow, exit 2 = BLOCK (stderr is shown to the model as feedback).
# Reflex R1/R11 made executable: nothing here reasons, it pattern-matches.
#
# Regexes live in variables: bash's tokenizer chokes on unquoted ;/| inside
# `[[ =~ ]]` words (muscle-memory class: shell parsing quirks bite guards first).
# Test hook: HARNESS_GUARD_INPUT='<json>' overrides stdin (bats).
set -uo pipefail
export LC_ALL=C

payload="${HARNESS_GUARD_INPUT:-$(cat)}"

read -r tool cmd < <(PAYLOAD="$payload" python3 -c '
import os, json
try:
    j = json.loads(os.environ["PAYLOAD"])
except Exception:
    raise SystemExit(1)   # print NOTHING -> read fails -> fail-closed block
tool = j.get("tool_name", "unknown")
ti = j.get("tool_input") or {}
cmd = ti.get("command") or ti.get("file_path") or ""
print(f"{tool}\t{cmd}".replace("\n", " "))
' | tr '\t' ' ') || { echo "guard-bad-calls: unparseable hook payload — blocking (fail-closed)" >&2; exit 2; }
cmd="${cmd:-}"

block() { echo "guard-bad-calls BLOCKED: $1 — $2" >&2; exit 2; }

# --- pattern table (ERE), checked in order ----------------------------------
sp='[[:space:]]'
re_rmrf="rm$sp+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)$sp+(/($sp|\$)|/\*|~|\\\$HOME|\.\.|\.git($sp|/|\$))"
re_dev="mkfs|dd$sp+[^|]*of=/dev/"
re_chmod="chmod$sp+(-R$sp+)?777"
re_fork=':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};'
re_fpush1="git$sp+push$sp+[^;|]*(--force|-f)($sp)[^;|]*(main|master)"
re_fpush2="git$sp+push$sp+[^;|]*(main|master)$sp[^;|]*(--force|-f)($sp|\$)"
re_reset="git$sp+reset$sp+--hard$sp+origin/"
re_pipe_sh="(curl|wget)$sp[^;|]*\|[[:space:]]*(ba|z|da)?sh"
re_secrets="(cat|less|head|tail)$sp[^;|]*(\.env($sp|\$|\.)|id_rsa|id_ed25519|\.pem($sp|\$)|auth\.json)"
re_skipperm="dangerously-skip-permissions"
re_secret_files='(^|/)(\.env|id_rsa|id_ed25519|[^/]*\.pem|auth\.json)$'

if [[ "$tool" == "Bash" ]]; then
  [[ "$cmd" =~ $re_rmrf ]]      && block "recursive force-delete of a protected path" "$cmd"
  [[ "$cmd" =~ $re_dev ]]       && block "raw device write" "$cmd"
  [[ "$cmd" =~ $re_chmod ]]     && block "world-writable chmod" "$cmd"
  [[ "$cmd" =~ $re_fork ]]      && block "fork bomb" "$cmd"
  [[ "$cmd" =~ $re_fpush1 ]]    && block "force-push to main/master" "$cmd"
  [[ "$cmd" =~ $re_fpush2 ]]    && block "force-push to main/master" "$cmd"
  [[ "$cmd" =~ $re_reset ]]     && block "hard reset onto remote (silent local-work loss)" "$cmd"
  [[ "$cmd" =~ $re_pipe_sh ]]   && block "pipe-to-shell install (use the vetted bootstrap instead)" "$cmd"
  [[ "$cmd" =~ $re_secrets ]]   && block "printing secret material to the transcript" "$cmd"
  [[ "$cmd" =~ $re_skipperm ]]  && block "attempt to bypass the permission system" "$cmd"
fi

if [[ "$tool" == "Write" || "$tool" == "Edit" ]]; then
  [[ "$cmd" =~ $re_secret_files ]] && block "writing secret-material files" "$cmd"
fi

exit 0
