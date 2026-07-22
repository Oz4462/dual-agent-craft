#!/usr/bin/env bash
# import-scan.sh — deterministic invented-package / off-contract-import guard.
#
# The best-documented coding-agent hallucination is the INVENTED PACKAGE:
# ~19.7% of LLM-recommended packages do not exist (arXiv:2406.10279), weaponised
# as "slopsquatting". This gate extracts every import added in a diff and
# FAIL-CLOSED checks each against (a) the real public registry (PyPI/npm 404 =
# does not exist) and (b) the PLAN allow-list (anything else = off-contract).
# ZERO model calls -- nothing in the loop can itself hallucinate.
#
# Writes ledger/IMPORT-SCAN.json. Exit 0 = clean/warn, exit 2 = BLOCKED.
#
# Testability: set IMPORT_SCAN_REGISTRY_BASE=file:///path (a dir with
# <pkg>.status files each containing an HTTP code) OR provide --diff-text to
# scan a literal diff -> the whole suite runs offline & deterministically.
#
# Usage:
#   lib/import-scan.sh --poc feat/poc --base main [--allow "requests,numpy"]
#                      [--ecosystem auto|python|npm] [--diff-text "<diff>"]
#                      [--check-provenance] [--suspect-age-days 30] [--block-suspect]
#                      [--out FILE]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

POC="feat/poc"; BASE="main"; DIFF_TEXT=""; ALLOW=""; ECO="auto"; PLAN=""
CHECK_PROV=false; SUSPECT_AGE=30; BLOCK_SUSPECT=false; OUTFILE=""; TIMEOUT=12
while [[ $# -gt 0 ]]; do
  case "$1" in
    --poc)            POC="${2:?value required for $1}"; shift 2;;
    --base)           BASE="${2:?value required for $1}"; shift 2;;
    --diff-text)      DIFF_TEXT="${2:?value required for $1}"; shift 2;;
    --allow)          ALLOW="${2:?value required for $1}"; shift 2;;
    --plan)           PLAN="${2:?value required for $1}"; shift 2;;
    --ecosystem)      ECO="${2:?value required for $1}"; shift 2;;
    --check-provenance) CHECK_PROV=true; shift;;
    --suspect-age-days) SUSPECT_AGE="${2:?value required for $1}"; shift 2;;
    --block-suspect)  BLOCK_SUSPECT=true; shift;;
    --timeout)        TIMEOUT="${2:?value required for $1}"; shift 2;;
    --out)            OUTFILE="${2:?value required for $1}"; shift 2;;
    *) fail "import-scan: unknown arg '$1'";;
  esac
done

# Python / Node standard-library names: present in the language, NOT on any
# registry -> must never be flagged as "invented". `__future__` is a python
# pseudo-module (the PowerShell version wrongly 404'd it) so it is listed here.
PY_STD="__future__ os sys re json math time datetime random collections itertools functools typing \
pathlib subprocess threading asyncio logging io csv sqlite3 hashlib base64 urllib http socket struct \
enum dataclasses abc contextlib argparse shutil tempfile glob copy traceback warnings inspect unittest \
decimal fractions statistics string textwrap operator heapq bisect queue signal platform ctypes gc \
weakref types secrets uuid zlib gzip tarfile zipfile xml html pickle"
NODE_STD="fs path http https os util events stream crypto child_process url querystring assert buffer \
net dns zlib readline cluster tls process timers string_decoder perf_hooks worker_threads async_hooks v8 vm"

# --- Get the diff ----------------------------------------------------------
if [[ -z "$DIFF_TEXT" ]]; then
  DIFF_TEXT="$(git diff "$BASE...$POC" 2>/dev/null)"
  if [[ -z "${DIFF_TEXT// }" ]]; then
    fail_code 2 "leerer Diff ($BASE...$POC) - nichts zu scannen."
  fi
fi

# --- Extract top-level imported package names (added lines only) -----------
# Emits "name<TAB>kind" lines; python handles the parsing precisely (relative
# imports skipped, scoped npm packages kept whole).
mapfile -t PKG_LINES < <(DIFF_TEXT="$DIFF_TEXT" python3 - "$ECO" <<'PY'
import sys, re, os
eco = sys.argv[1]
diff = os.environ["DIFF_TEXT"]
pkgs = {}
for raw in diff.splitlines():
    if raw.startswith(('---', '+++')):
        continue
    # Added lines (git diff '+') OR raw hand-fed lines (no leading space/-/@).
    if raw.startswith('+'):
        line = raw[1:]
    elif raw and raw[0] not in ' -@':
        line = raw
    else:
        continue
    if eco in ('auto', 'python'):
        m = re.match(r'\s*import\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        if m: pkgs.setdefault(m.group(1), 'python')
        # `from X[.sub] import ...` -> top-level package; NOT relative `from .`.
        # Dotted form MUST be captured (audit finding: `from fakepkg.sub import x`
        # previously bypassed the scan entirely because '.' broke the match).
        m = re.match(r'\s*from\s+([A-Za-z_][A-Za-z0-9_.]*)\s+import', line)
        if m: pkgs.setdefault(m.group(1).split('.')[0], 'python')
    if eco in ('auto', 'npm'):
        m = re.search(r'''(?:import\s.*\sfrom|require\()\s*['"]([^'"]+)['"]''', line)
        if m:
            p = m.group(1)
            if not p.startswith(('.', '/')):
                sm = re.match(r'(@[^/]+/[^/]+)', p)
                p = sm.group(1) if sm else p.split('/')[0]
                pkgs.setdefault(p, 'npm')
for name, kind in pkgs.items():
    print(f"{name}\t{kind}")
PY
)

# --- Manifest supply-chain pass (audit P1) ---------------------------------
# A registry-name scan can't see deps pulled straight from git/urls/files.
# Track the current +++ file; in a dependency manifest, flag any ADDED line
# using a non-registry source scheme. Deterministic, zero tokens.
mapfile -t SUPPLY_LINES < <(DIFF_TEXT="$DIFF_TEXT" python3 - <<'PY'
import os, re
diff = os.environ["DIFF_TEXT"]
cur = ""
manifest = re.compile(r'(requirements[^/]*\.txt|pyproject\.toml|package\.json|Pipfile|setup\.py|setup\.cfg)$')
scheme = re.compile(r'(git\+[a-z]+://|git@|(^|["\s:=])https?://|(^|["\s])file:|["\s]github:|["\s]gitlab:|["\s]bitbucket:)', re.I)
for raw in diff.splitlines():
    if raw.startswith('+++'):
        m = re.match(r'\+\+\+ b/(.*)', raw); cur = m.group(1) if m else ""
        continue
    if raw.startswith('---') or raw.startswith('@@'):
        continue
    added = raw[1:] if raw.startswith('+') else (raw if raw and raw[0] not in ' -' else None)
    if added is None or not cur or not manifest.search(cur):
        continue
    if scheme.search(added):
        frag = added.strip()[:80].replace('\t', ' ')
        print(f"{cur}\t{frag}")
PY
)

# --plan: derive the allow-list from PLAN's "Erlaubte Dependencies:" line when no
# explicit --allow was given (audit P1: the NEXT hint used to print a placeholder
# the operator hand-filled). "stdlib only" -> empty allow-list but the off-contract
# check stays ARMED (via PLAN_ARMED) instead of the silent-disable an unset ALLOW triggers.
PLAN_ARMED=false
if [[ -z "$ALLOW" && -n "$PLAN" && -f "$PLAN" ]]; then
  PLAN_ARMED=true
  # Heredoc (not -c '...'): the extraction needs quotes AND a backtick, both of
  # which break an inline single-quoted -c inside $(...). Env var + heredoc is safe.
  ALLOW="$(PLANFILE="$PLAN" python3 <<'PY'
import os, re
txt = open(os.environ["PLANFILE"], encoding="utf-8", errors="replace").read()
m = re.search(r"Erlaubte Dependencies:\s*(.+)", txt)
if not m:
    print(""); raise SystemExit
val = m.group(1).strip()
if re.fullmatch(r"(?i)stdlib[\s-]*only\.?", val):
    print(""); raise SystemExit
strip_chars = chr(96) + "\"'\t "   # backtick + quotes + tab + space
parts = [p.strip(strip_chars) for p in re.split(r"[,\s]+", val) if p.strip(strip_chars)]
print(",".join(parts))
PY
)"
fi

# Loud, once: with no allow-list AND no --plan the off-contract half of the gate
# cannot fire (registry-404 check still runs). Silent-disable was an audit finding.
[[ -z "$ALLOW" && "$PLAN_ARMED" == false ]] && warn "import-scan: no --allow/--plan given -> off-contract check DISABLED (registry-only mode). Pass --allow or --plan for the full gate."

# --- Registry check (real or stubbed for tests) ----------------------------
# Prints the HTTP status for a package, honouring IMPORT_SCAN_REGISTRY_BASE.
registry_status() {
  local pkg="$1" kind="$2"
  if [[ -n "${IMPORT_SCAN_REGISTRY_BASE:-}" ]]; then
    local base="${IMPORT_SCAN_REGISTRY_BASE#file://}"
    # Defense in depth: constrain the name before it becomes a filesystem path
    # (npm regex admits nearly any char; keep traversal chars out of the stub path).
    local safe="${pkg//[^A-Za-z0-9._@-]/_}"; safe="${safe//../_}"
    if [[ -f "$base/$safe.status" ]]; then cat "$base/$safe.status"; else echo "404"; fi
    return 0
  fi
  local url
  if [[ "$kind" == npm ]]; then url="https://registry.npmjs.org/$pkg"; else url="https://pypi.org/pypi/$pkg/json"; fi
  http_status "$url" "$TIMEOUT"
}

# Package age in days (slopsquat tier); empty if unknown. Stub-aware: a
# <pkg>.age file under the registry base overrides the network.
package_age_days() {
  local pkg="$1" kind="$2"
  if [[ -n "${IMPORT_SCAN_REGISTRY_BASE:-}" ]]; then
    local base="${IMPORT_SCAN_REGISTRY_BASE#file://}"
    local safe="${pkg//[^A-Za-z0-9._@-]/_}"; safe="${safe//../_}"
    [[ -f "$base/$safe.age" ]] && cat "$base/$safe.age"
    return 0
  fi
  local url body
  if [[ "$kind" == npm ]]; then url="https://registry.npmjs.org/$pkg"; else url="https://pypi.org/pypi/$pkg/json"; fi
  body="$(http_get_json "$url" "$TIMEOUT")"
  [[ -z "$body" ]] && return 0
  BODY="$body" python3 - "$kind" <<'PY'
import sys, json, datetime, os
kind = sys.argv[1]
try: j = json.loads(os.environ["BODY"])
except Exception: sys.exit(0)
now = datetime.datetime.now(datetime.timezone.utc)
def days(dt): return (now - dt).total_seconds()/86400
try:
    if kind == "npm":
        created = j.get("time", {}).get("created")
        if created:
            print(round(days(datetime.datetime.fromisoformat(created.replace("Z","+00:00"))), 1))
    else:
        times = []
        for rel in j.get("releases", {}).values():
            for f in rel:
                if f.get("upload_time_iso_8601"):
                    times.append(datetime.datetime.fromisoformat(f["upload_time_iso_8601"].replace("Z","+00:00")))
                elif f.get("upload_time"):
                    times.append(datetime.datetime.fromisoformat(f["upload_time"]).replace(tzinfo=datetime.timezone.utc))
        if times:
            print(round(days(min(times)), 1))
except Exception:
    pass
PY
}

in_list() { local needle="$1"; shift; for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

IFS=',' read -ra ALLOW_ARR <<<"$ALLOW"
# Trim surrounding whitespace on each entry (audit P2): "requests, numpy" must
# match "numpy", not " numpy" -> otherwise a legit dep is a false OFF-CONTRACT block.
for i in "${!ALLOW_ARR[@]}"; do
  a="${ALLOW_ARR[$i]#"${ALLOW_ARR[$i]%%[![:space:]]*}"}"   # ltrim
  ALLOW_ARR[$i]="${a%"${a##*[![:space:]]}"}"                # rtrim
done

invented=(); off_contract=(); okpkgs=(); unknown=(); suspect=()
scanned=0
for pl in "${PKG_LINES[@]}"; do
  [[ -z "$pl" ]] && continue
  pkg="${pl%%$'\t'*}"; kind="${pl##*$'\t'}"
  scanned=$((scanned+1))
  # stdlib?
  if { [[ "$kind" == python ]] && in_list "$pkg" $PY_STD; } || { [[ "$kind" == npm ]] && in_list "$pkg" $NODE_STD; }; then
    okpkgs+=("$pkg:$kind:stdlib"); continue
  fi
  in_allow=false
  # armed (allow given or --plan): membership decides. unarmed (no list): allow all.
  if [[ -z "$ALLOW" && "$PLAN_ARMED" == false ]]; then in_allow=true
  elif in_list "$pkg" "${ALLOW_ARR[@]}"; then in_allow=true; fi
  status="$(registry_status "$pkg" "$kind")"
  if [[ "$status" == "404" ]]; then invented+=("$pkg:$kind:registry-404"); continue; fi
  if [[ -z "$status" ]]; then unknown+=("$pkg:$kind:registry-unreachable"); continue; fi
  if [[ "$in_allow" == false ]]; then off_contract+=("$pkg:$kind:not-in-PLAN-allowlist"); continue; fi
  if [[ "$CHECK_PROV" == true ]]; then
    age="$(package_age_days "$pkg" "$kind")"
    if [[ -n "$age" ]] && awk -v a="$age" -v s="$SUSPECT_AGE" 'BEGIN{exit !(a<s)}'; then
      suspect+=("$pkg:$kind:registered ${age}d ago (slopsquat-suspect)"); continue
    fi
  fi
  okpkgs+=("$pkg:$kind:registry-ok+allowed")
done

blocked=false
{ [[ ${#invented[@]} -gt 0 ]] || [[ ${#off_contract[@]} -gt 0 ]]; } && blocked=true
{ [[ "$BLOCK_SUSPECT" == true ]] && [[ ${#suspect[@]} -gt 0 ]]; } && blocked=true
[[ ${#SUPPLY_LINES[@]} -gt 0 ]] && blocked=true   # non-registry manifest source = fail-closed

verdict="PASS"
if [[ "$blocked" == true ]]; then verdict="BLOCK"
elif [[ ${#suspect[@]} -gt 0 ]]; then verdict="WARN-slopsquat"
elif [[ ${#unknown[@]} -gt 0 ]]; then verdict="WARN-unreachable"; fi

[[ -z "$OUTFILE" ]] && { ledger="$(repo_root)/ledger"; mkdir -p "$ledger"; OUTFILE="$ledger/IMPORT-SCAN.json"; }
# Serialise "pkg:kind:why" arrays to JSON.
arr_json() { local out="[]"; for e in "$@"; do out=$(python3 - "$out" "$e" <<'PY'
import sys, json
arr = json.loads(sys.argv[1]); p,k,w = sys.argv[2].split(":",2)
arr.append({"pkg":p,"kind":k,"why":w}); print(json.dumps(arr))
PY
); done; printf '%s' "$out"; }

# supply-chain findings as JSON (file<TAB>fragment lines)
supply_json="$(python3 - <<'PY' "${SUPPLY_LINES[@]:-}"
import sys, json
out=[]
for e in sys.argv[1:]:
    if not e: continue
    f,_,frag = e.partition("\t")
    out.append({"file":f,"source":frag})
print(json.dumps(out))
PY
)"
python3 - "$OUTFILE" "$BASE" "$POC" "$scanned" "$verdict" "$(iso_now)" \
  "$(arr_json "${invented[@]}")" "$(arr_json "${off_contract[@]}")" \
  "$(arr_json "${suspect[@]}")" "$(arr_json "${unknown[@]}")" "$(arr_json "${okpkgs[@]}")" "$supply_json" <<'PY'
import sys, json
out, base, poc, scanned, verdict, stamp, inv, off, sus, unk, ok, supply = sys.argv[1:13]
obj = {"base":base,"poc":poc,"scanned":int(scanned),
  "invented":json.loads(inv),"off_contract":json.loads(off),"suspect":json.loads(sus),
  "unknown":json.loads(unk),"ok":json.loads(ok),"supply_chain":json.loads(supply),
  "verdict":verdict,"stamp":stamp}
open(out,"w",encoding="utf-8").write(json.dumps(obj, indent=2))
PY

if [[ "$blocked" == true ]]; then col="$C_RED"
elif [[ ${#suspect[@]} -gt 0 || ${#unknown[@]} -gt 0 ]]; then col="$C_YELLOW"
else col="$C_GREEN"; fi
printf '%simport-scan: %s scanned | invented=%s off-contract=%s suspect=%s unknown=%s ok=%s -> %s%s\n' \
  "$col" "$scanned" "${#invented[@]}" "${#off_contract[@]}" "${#suspect[@]}" "${#unknown[@]}" "${#okpkgs[@]}" "$verdict" "$C_RESET"
for i in "${invented[@]}";     do printf '%s  INVENTED:     %s%s\n' "$C_RED" "${i%%:*}" "$C_RESET"; done
for o in "${off_contract[@]}"; do printf '%s  OFF-CONTRACT: %s%s\n' "$C_RED" "${o%%:*}" "$C_RESET"; done
for s in "${suspect[@]}";      do printf '%s  SLOPSQUAT?:   %s%s\n' "$C_YELLOW" "$s" "$C_RESET"; done
for sc in "${SUPPLY_LINES[@]:-}"; do [[ -n "$sc" ]] && printf '%s  SUPPLY-CHAIN: %s%s\n' "$C_RED" "${sc//$'\t'/ -> }" "$C_RESET"; done

[[ "$blocked" == true ]] && exit 2 || exit 0
