#!/usr/bin/env bash
# test-guard.sh — deterministic enforcement of PROTOCOL invariant 7.
#
# "Grok editiert NIE Tests/Verify." The builder writes only implementation; if it
# edits the test/verify files it games the gate (loosen the test instead of fixing
# the code). Until now this invariant was PROMPT-ONLY. This guard makes it
# deterministic: scan the builder's diff; if it touches any test/verify file,
# BLOCK. Zero model calls, zero tokens -- nothing here can hallucinate.
#
# Writes ledger/TEST-GUARD.json. Exit 0 = clean, exit 2 = BLOCKED (test edited).
#
# Testability: pass --diff-files "a\nb" to feed a literal newline-separated file
# list instead of computing it from git.
#
# Usage:
#   lib/test-guard.sh --poc feat/poc --base main [--extra-pattern '<regex>'] [--out FILE]
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_HERE/common.sh"

POC="feat/poc"; BASE="main"; DIFF_FILES=""; EXTRA=""; OUTFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --poc)           POC="${2:?value required for $1}"; shift 2;;
    --base)          BASE="${2:?value required for $1}"; shift 2;;
    --diff-files)    DIFF_FILES="${2:?value required for $1}"; shift 2;;
    --extra-pattern) EXTRA="${2:?value required for $1}"; shift 2;;
    --out)           OUTFILE="${2:?value required for $1}"; shift 2;;
    *) fail "test-guard: unknown arg '$1'";;
  esac
done

# Default patterns for what counts as a test/verify file (case-insensitive).
# Covers pytest, unittest, jest/vitest, go, rust, and a conventional verify/ dir.
# Test/verify FILES plus dedicated test-RUNNER config files that have no
# non-test purpose (audit P1: the builder could neuter the eval by loosening
# pytest.ini/jest.config without touching a single test file). pyproject.toml /
# package.json are deliberately EXCLUDED — they carry real impl config too.
PATTERN='(^|/)(tests?|__tests__|spec)/|(^|/)conftest\.py$|(^|/)verify/|_test\.(py|js|ts|go|rs)$|\.test\.(js|ts|jsx|tsx)$|\.spec\.(js|ts|jsx|tsx)$|(^|/)test_[^/]+\.py$|_spec\.rb$|(^|/)(pytest\.ini|tox\.ini|\.coveragerc)$|(^|/)(jest|vitest)\.config\.(js|ts|mjs|cjs)$|(^|/)\.mocharc(\..*)?$|(^|/)jest\.setup\.(js|ts)$'
[[ -n "$EXTRA" ]] && PATTERN="$PATTERN|$EXTRA"

files=()
if [[ -n "$DIFF_FILES" ]]; then
  # injected list (tests): newline-separated
  while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done <<<"$DIFF_FILES"
else
  # FAIL-CLOSED: a failing git diff (bad/missing branch) must BLOCK, never
  # silently produce an empty list that reads as "PASS" (audit finding).
  # core.quotePath=false + -z: NON-ASCII filenames (tests/prüfung.py) are NOT
  # C-quoted, so the leading/trailing '"' can't defeat the ^/$ pattern anchors —
  # an umlaut in a test filename must not turn BLOCK into PASS (P0 audit finding).
  if ! git rev-parse --verify "$BASE" >/dev/null 2>&1 || ! git rev-parse --verify "$POC" >/dev/null 2>&1; then
    fail_code 2 "test-guard: bad ref ($BASE...$POC) — cannot verify invariant 7 (fail-closed)."
  fi
  mapfile -d '' -t files < <(git -c core.quotePath=false diff --name-only -z "$BASE...$POC" 2>/dev/null)
fi

violations=()
for f in "${files[@]:-}"; do
  [[ -z "$f" ]] && continue
  if printf '%s' "$f" | grep -qiE "$PATTERN"; then violations+=("$f"); fi
done

[[ -z "$OUTFILE" ]] && { ledger="$(repo_root)/ledger"; mkdir -p "$ledger"; OUTFILE="$ledger/TEST-GUARD.json"; }
verdict="PASS"; [[ ${#violations[@]} -gt 0 ]] && verdict="BLOCK"
python3 - "$OUTFILE" "$BASE" "$POC" "$verdict" "$(iso_now)" "${violations[@]:-}" <<'PY'
import sys, json
out, base, poc, verdict, stamp = sys.argv[1:6]
viol = [v for v in sys.argv[6:] if v]
open(out,"w",encoding="utf-8").write(json.dumps(
  {"base":base,"poc":poc,"verdict":verdict,"violations":viol,"stamp":stamp}, indent=2))
PY

if [[ ${#violations[@]} -gt 0 ]]; then
  printf '%stest-guard: BLOCK -- builder touched test/verify files (invariant 7):%s\n' "$C_RED" "$C_RESET"
  for v in "${violations[@]}"; do printf '%s  ! %s%s\n' "$C_RED" "$v" "$C_RESET"; done
  exit 2
fi
ok "test-guard: PASS -- no test/verify files modified by the builder."
exit 0
