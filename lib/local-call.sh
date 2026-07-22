#!/usr/bin/env bash
# local-call.sh — zero-quota local Ollama wrapper (scout builder).
#
# Runs a prompt against a local Ollama model (localhost:11434) for $0 and ZERO
# subscription quota. Use it as an extra best-of-n variant source or for
# mechanical/scout passes -- NEVER for the merge-gating ASSESS (that must stay
# frontier; the cross-vendor moat needs a strong reviewer). Quality-safe because
# every local output is downstream-gated by pass^k / a JSON-schema check.
#
# Prints the adapter contract JSON: {exit_code, text, json_log, stdout_log}.
# Honest BLOCKED (exit 1) if Ollama is unreachable.
#
# Usage:
#   lib/local-call.sh --prompt-file <path> [--model qwen2.5:7b] [--temperature 0.2]
#     [--json] [--endpoint URL] [--timeout 120] [--tag local]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

PROMPT_FILE=""; MODEL="qwen2.5:7b"; TEMP="0.2"; JSONFMT=false
ENDPOINT="http://localhost:11434/api/chat"; TIMEOUT=120; TAG="local"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) PROMPT_FILE="${2:?value required for $1}"; shift 2;;
    --model)       MODEL="${2:?value required for $1}"; shift 2;;
    --temperature) TEMP="${2:?value required for $1}"; shift 2;;
    --json)        JSONFMT=true; shift;;
    --endpoint)    ENDPOINT="${2:?value required for $1}"; shift 2;;
    --timeout)     TIMEOUT="${2:?value required for $1}"; shift 2;;
    --tag)         TAG="${2:?value required for $1}"; shift 2;;
    *) fail "local-call: unknown arg '$1'";;
  esac
done
[[ -f "$PROMPT_FILE" ]] || { warn "BLOCKED: prompt file missing: $PROMPT_FILE"; exit 1; }

logdir="$(repo_root)/.dual-agent/logs"; mkdir -p "$logdir"
stamp="$(utc_stamp_ms)"
outfile="$logdir/$TAG-$stamp.out.json"

# Build the request body with python (safe JSON escaping of the prompt).
body="$(PROMPT_FILE="$PROMPT_FILE" MODEL="$MODEL" TEMP="$TEMP" JSONFMT="$JSONFMT" python3 <<'PY'
import os, json
prompt = open(os.environ["PROMPT_FILE"], encoding="utf-8").read().lstrip("﻿").strip()
body = {"model": os.environ["MODEL"], "stream": False,
        "messages": [{"role": "user", "content": prompt}],
        "options": {"temperature": float(os.environ["TEMP"])}}
if os.environ["JSONFMT"] == "true": body["format"] = "json"
print(json.dumps(body))
PY
)"

# Capture body AND http status (audit finding: `curl -s` without -f treats an
# HTTP error body — e.g. {"error":"model not found"} — as a successful reply).
http_out="$(curl -s --max-time "$TIMEOUT" -w $'\n%{http_code}' \
             -H 'Content-Type: application/json' -d "$body" "$ENDPOINT" 2>/dev/null)" || http_out=""
status="${http_out##*$'\n'}"
resp="${http_out%$'\n'*}"
if [[ -z "$http_out" || -z "$resp" ]]; then
  warn "BLOCKED: Ollama unreachable/failed at $ENDPOINT. Run 'ollama serve' + pull model '$MODEL'."
  emit_result 1 /dev/null /dev/null "$outfile"; exit 1
fi
printf '%s' "$resp" >"$outfile"
if [[ "$status" != 2* ]]; then
  warn "BLOCKED: Ollama returned HTTP $status: $(head -c 200 "$outfile")"
  emit_result 1 /dev/null "$outfile" "$outfile"; exit 1
fi

# Ollama /api/chat shape: {message:{content:...}}. A response that parses but
# lacks message.content is a FAILURE (fail-closed), not an empty success.
textfile="$(mktemp)"
if ! RESP="$resp" python3 - >"$textfile" <<'PY'
import os, json, sys
try:
    j = json.loads(os.environ["RESP"])
    c = j.get("message", {}).get("content")
    if not isinstance(c, str):
        sys.exit(1)
    print(c, end="")
except SystemExit:
    raise
except Exception:
    sys.exit(1)
PY
then
  warn "BLOCKED: Ollama reply had no message.content (malformed/unexpected shape) — see $outfile"
  emit_result 1 /dev/null "$outfile" "$outfile"; rm -f "$textfile"; exit 1
fi
emit_result 0 "$textfile" "$outfile" "$outfile"
rm -f "$textfile"
exit 0
