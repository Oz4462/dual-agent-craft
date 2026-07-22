#!/usr/bin/env bash
# common.sh — shared helpers for the dual-agent bash harness.
#
# Sourced by every lib/*.sh and dual-*.sh. Centralises what the PowerShell
# modules re-implemented inline: coloured logging, JSON extraction (via python3,
# so there is NO jq dependency), and HTTP status probing (curl).
#
# Design notes carried from the PowerShell port:
#   - Paths are native '/' everywhere -> the whole class of Windows backslash /
#     $env:TEMP / `wt` bugs simply cannot occur here.
#   - Result-text extraction probes vendor JSON keys in the SAME order as
#     ADAPTERS.md: result, response, output, text, content, message.
#   - Never let a failed sub-call kill the whole script silently; callers check
#     explicit return codes (the bash analogue of the PS "$LASTEXITCODE" rule).

# Guard against double-sourcing.
[[ -n "${_DUAL_COMMON_SOURCED:-}" ]] && return 0
_DUAL_COMMON_SOURCED=1

# Locale-neutral numerics: the harness parses/formats JSON floats (4.75, not
# 4,75). Under a comma-decimal locale (de_DE etc.) `printf %.2f` and awk reject
# dotted numbers. Force C numerics so every module is byte-identical regardless
# of the host locale. (Verify commands run in subshells inherit this -- standard
# and safe for CI.)
export LC_ALL=C

# --- Platform / bash version -----------------------------------------------
# Linux: bash 5.x (distro default). macOS: system /bin/bash is 3.2 — use
# Homebrew bash (`brew install bash`). Windows: Git Bash or WSL (see PLATFORM.md).
# Bash 4+ is required for mapfile/associative arrays used by the harness.
if [[ -z "${DUAL_SKIP_BASH_CHECK:-}" ]] && (( BASH_VERSINFO[0] < 4 )); then
  printf 'BLOCKED: bash 4+ required (found %s). macOS: brew install bash && re-run with that bash.\n' \
    "${BASH_VERSION:-unknown}" >&2
  return 2 2>/dev/null || exit 2
fi

# dual_os: linux | darwin | windows | unknown  (uname-based; Git Bash reports MINGW*)
dual_os() {
  case "$(uname -s 2>/dev/null)" in
    Linux*)  echo linux ;;
    Darwin*) echo darwin ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) echo windows ;;
    *) echo unknown ;;
  esac
}

# --- Colours (respect NO_COLOR and non-tty) --------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_DIM=''; C_RESET=''
fi

# %b so "\n" in messages renders as a newline (log "\nDone" etc.).
log()  { printf '%b\n' "$*"; }
info() { printf '%s%b%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '%s%b%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s%b%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
# fail: print "BLOCKED: msg" in red and exit with the given code (default 1).
fail() { printf '%sBLOCKED: %b%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit "${_FAIL_CODE:-1}"; }
fail_code() { _FAIL_CODE="$1"; shift; fail "$@"; }

# --- Repo / paths ----------------------------------------------------------
# repo_root: the dual-agent harness root (parent of lib/). Works regardless of cwd.
repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

# usage <script-path>: print the header "# Usage:" block through the arg-parse
# start, comment markers stripped. `-h|--help` handlers call this and exit 0
# (audit P2: asking for help used to print a red BLOCKED unknown-arg error).
usage() {
  sed -n '/^# Usage:/,/^set -uo/p' "$1" | sed 's/^# \?//; $d'
}

# --- Portable time / file helpers (GNU Linux vs BSD macOS vs Git Bash) -----
# Prefer python3 for ms stamps — %3N is GNU-date only and breaks on macOS.
utc_stamp() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S"))'
  else
    date -u +"%Y%m%d-%H%M%S"
  fi
}
utc_stamp_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'from datetime import datetime,timezone; d=datetime.now(timezone.utc); print(d.strftime("%Y%m%d-%H%M%S-")+f"{d.microsecond//1000:03d}")'
  else
    # last resort: whole seconds + 000
    printf '%s-000\n' "$(date -u +"%Y%m%d-%H%M%S")"
  fi
}
iso_now() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))'
  else
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

# sed_i <expr> <file>  — in-place edit, GNU (Linux) and BSD (macOS) compatible.
sed_i() {
  local expr="$1" file="$2"
  [[ -f "$file" ]] || { warn "sed_i: missing file $file"; return 1; }
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    # BSD sed requires a (possibly empty) backup-suffix argument
    sed -i '' "$expr" "$file"
  fi
}

# file_size_bytes <path> — GNU stat -c%s vs BSD stat -f%z vs wc fallback.
file_size_bytes() {
  local f="$1"
  if stat -c%s "$f" >/dev/null 2>&1; then
    stat -c%s "$f"
  elif stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    wc -c <"$f" | tr -d '[:space:]'
  fi
}

# --- JSON (python3, no jq) -------------------------------------------------
# json_extract_text <file>: probe the common vendor result keys in order and
# print the first present string value; if none match, print the raw file.
# Mirrors the PowerShell wrappers' extraction contract exactly.
json_extract_text() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, json
path = sys.argv[1]
try:
    raw = open(path, encoding="utf-8").read()
except OSError:
    print(""); sys.exit(0)
def load(s):
    try: return json.loads(s)
    except Exception: return None
obj = load(raw)
if obj is None:
    # fall back to the last non-empty line (trailing-object shape, e.g. JSONL)
    for line in reversed([l for l in raw.splitlines() if l.strip()]):
        obj = load(line)
        if obj is not None: break
if isinstance(obj, dict):
    for k in ("result","response","output","text","content","message"):
        v = obj.get(k)
        if isinstance(v, str):
            print(v); sys.exit(0)
        if isinstance(v, dict) and isinstance(v.get("content"), str):
            print(v["content"]); sys.exit(0)
# no known key -> raw payload verbatim
print(raw, end="")
PY
}

# json_field <file> <dotted.path>: print a scalar field or empty. e.g.
#   json_field out.json is_error   ; json_field out.json total_cost_usd
json_field() {
  local file="$1" path="$2"
  python3 - "$file" "$path" <<'PY'
import sys, json
path, dotted = sys.argv[1], sys.argv[2]
try:
    obj = json.load(open(path, encoding="utf-8"))
except Exception:
    # try last JSONL line
    obj = None
    try:
        for line in reversed([l for l in open(path, encoding="utf-8").read().splitlines() if l.strip()]):
            try: obj = json.loads(line); break
            except Exception: continue
    except Exception:
        obj = None
if obj is None:
    sys.exit(0)
cur = obj
for part in dotted.split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(0)
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is not None:
    print(cur)
PY
}

# json_field_stdin <dotted.path>: like json_field but reads the JSON from STDIN.
# NOTE: json_field's program arrives via a stdin-heredoc, so `json_field
# /dev/stdin` can NEVER see piped data (the heredoc owns fd0 — it only appeared
# to work depending on bash's heredoc pipe-vs-tmpfile choice). This variant uses
# `python3 -c` so the caller's pipe stays on stdin. Use it for `cmd | ... key`.
json_field_stdin() {
  python3 -c '
import sys, json
dotted = sys.argv[1]
raw = sys.stdin.read()
try:
    obj = json.loads(raw)
except Exception:
    obj = None
    for line in reversed([l for l in raw.splitlines() if l.strip()]):
        try:
            obj = json.loads(line); break
        except Exception:
            continue
if obj is None:
    sys.exit(0)
cur = obj
for part in dotted.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(0)
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is not None:
    print(cur)
' "$1"
}

# json_valid <file>: exit 0 if the file parses as a JSON object/array.
json_valid() {
  python3 -c 'import sys,json; json.load(open(sys.argv[1],encoding="utf-8"))' "$1" 2>/dev/null
}

# emit_result <exit> <text_file> <json_file> <stdout_log>: print the adapter
# contract as ONE JSON object on stdout. Callers parse it with json_field.
# This is the bash stand-in for PowerShell's [PSCustomObject] return.
emit_result() {
  local exit_code="$1" text_file="$2" json_file="$3" stdout_log="$4"
  python3 - "$exit_code" "$text_file" "$json_file" "$stdout_log" <<'PY'
import sys, json
exit_code, text_file, json_file, stdout_log = sys.argv[1:5]
def rd(p):
    try: return open(p, encoding="utf-8").read()
    except OSError: return ""
print(json.dumps({
    "exit_code": int(exit_code),
    "text": rd(text_file),
    "json_log": json_file,
    "stdout_log": stdout_log,
}))
PY
}

# --- HTTP (curl) -----------------------------------------------------------
# http_status <url> [timeout_sec]: print the HTTP status code, or nothing on a
# network/connection error (so a caller can tell 404 from unreachable, exactly
# like the PowerShell Invoke-WebRequest try/catch distinguished them).
http_status() {
  local url="$1" timeout="${2:-12}" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null) || return 0
  # curl prints 000 when it never got an HTTP response (DNS/conn failure).
  [[ "$code" == "000" ]] && return 0
  printf '%s' "$code"
}

# http_get_json <url> [timeout_sec]: print the body on 2xx, empty otherwise.
http_get_json() {
  local url="$1" timeout="${2:-12}"
  curl -s --max-time "$timeout" -f "$url" 2>/dev/null || true
}
