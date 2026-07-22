#!/usr/bin/env bats
# import-scan.sh — deterministic invented-package / off-contract guard.
# Registry fully stubbed via IMPORT_SCAN_REGISTRY_BASE -> offline + deterministic.

load helpers/common

setup()    { setup_scratch; make_registry; }
teardown() { teardown_scratch; }

scan() { run "$HARNESS_ROOT/lib/import-scan.sh" --out "$SCRATCH/scan.json" "$@"; }

@test "stdlib + real registered package pass" {
  echo 200 > "$REGISTRY/requests.status"
  scan --diff-text $'+import os\n+import requests' --ecosystem python
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
  [ "$(jfield "$SCRATCH/scan.json" scanned)" = "2" ]
}

@test "first-party in-repo package (src/) is not OFF-CONTRACT under stdlib-only PLAN" {
  # Live finding: from src.pkg00.multiply import … flagged top-level "src".
  make_repo "$SCRATCH/repo"
  mkdir -p "$SCRATCH/repo/src/pkg00"
  echo 'x=1' > "$SCRATCH/repo/src/pkg00/__init__.py"
  cat >"$SCRATCH/repo/PLAN.md" <<'EOF'
- Erlaubte Dependencies: stdlib only
EOF
  cd "$SCRATCH/repo"
  scan --diff-text $'+from src.pkg00.multiply import multiply\n+import os' \
    --ecosystem python --plan "$SCRATCH/repo/PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
  cd "$HARNESS_ROOT"
}

@test "importlib is stdlib — never OFF-CONTRACT under stdlib-only PLAN" {
  # Live finding: importlib missing from PY_STD + PLAN "stdlib only (…)" false off-contract.
  cat >"$SCRATCH/PLAN.md" <<'EOF'
## 2. Stack
- Erlaubte Dependencies: stdlib only (Tests mit unittest aus der stdlib)
EOF
  scan --diff-text $'+import importlib\n+from importlib import import_module\n+import unittest' \
    --ecosystem python --plan "$SCRATCH/PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
}

@test "stdlib-only PLAN still blocks third-party not on allowlist" {
  echo 200 > "$REGISTRY/requests.status"
  cat >"$SCRATCH/PLAN.md" <<'EOF'
- Erlaubte Dependencies: stdlib only (no network)
EOF
  scan --diff-text $'+import requests' --ecosystem python --plan "$SCRATCH/PLAN.md"
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" off_contract.0.pkg)" = "requests" ]
}

@test "invented package (registry 404) -> BLOCK exit 2" {
  scan --diff-text $'+import totallyinventedpkg' --ecosystem python
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "BLOCK" ]
  [ "$(jfield "$SCRATCH/scan.json" invented.0.pkg)" = "totallyinventedpkg" ]
}

@test "__future__ is stdlib, never flagged (bug fix vs PS version)" {
  scan --diff-text $'+from __future__ import annotations' --ecosystem python
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
}

@test "python relative imports are skipped (bug fix)" {
  scan --diff-text $'+from . import helper\n+from .sub import x' --ecosystem python
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" scanned)" = "0" ]
}

@test "registered but off-contract package -> BLOCK when allow-list set" {
  echo 200 > "$REGISTRY/requests.status"
  echo 200 > "$REGISTRY/numpy.status"
  scan --diff-text $'+import requests\n+import numpy' --ecosystem python --allow "numpy"
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" off_contract.0.pkg)" = "requests" ]
}

@test "npm scoped package extracted whole; relative js imports skipped" {
  echo 200 > "$REGISTRY/@scope\/pkg.status" 2>/dev/null || echo 200 > "$REGISTRY/@scope"$'\x2f'"pkg.status" 2>/dev/null || true
  # scoped-name status files are awkward on disk; missing file -> stub default 404 -> proves extraction shape
  scan --diff-text $'+import x from "@scope/pkg"\n+const y = require("./local")' --ecosystem npm
  [ "$(jfield "$SCRATCH/scan.json" scanned)" = "1" ]
}

@test "slopsquat: young package flagged suspect (warn), blocked with --block-suspect" {
  echo 200 > "$REGISTRY/newpkg.status"
  echo 3   > "$REGISTRY/newpkg.age"
  scan --diff-text $'+import newpkg' --ecosystem python --check-provenance --suspect-age-days 30
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "WARN-slopsquat" ]
  scan --diff-text $'+import newpkg' --ecosystem python --check-provenance --suspect-age-days 30 --block-suspect
  [ "$status" -eq 2 ]
}

@test "old package passes provenance check" {
  echo 200  > "$REGISTRY/oldpkg.status"
  echo 2000 > "$REGISTRY/oldpkg.age"
  scan --diff-text $'+import oldpkg' --ecosystem python --check-provenance
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
}

@test "only ADDED lines are scanned (removed imports ignored)" {
  scan --diff-text $'-import removedfakepkg\n+import os' --ecosystem python
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" scanned)" = "1" ]
}

@test "AUDIT-FIX: dotted 'from pkg.sub import x' is scanned (invented -> BLOCK)" {
  scan --diff-text $'+from totallyinventedpkg.sub import evil' --ecosystem python
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" invented.0.pkg)" = "totallyinventedpkg" ]
}

@test "AUDIT-FIX: dotted stdlib 'from concurrent.futures import x' passes" {
  scan --diff-text $'+from collections.abc import Mapping' --ecosystem python
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
}

@test "AUDIT-FIX: missing --allow prints a loud off-contract-disabled warning" {
  echo 200 > "$REGISTRY/requests.status"
  scan --diff-text $'+import requests' --ecosystem python
  [ "$status" -eq 0 ]
  [[ "$output" == *"off-contract check DISABLED"* ]]
}

@test "AUDIT-P2: allow-list entries are whitespace-trimmed ('requests, numpy')" {
  echo 200 > "$REGISTRY/requests.status"; echo 200 > "$REGISTRY/numpy.status"
  scan --diff-text $'+import requests\n+import numpy' --ecosystem python --allow "requests, numpy"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "PASS" ]
}

@test "AUDIT-P1: --plan reads the allow-list from PLAN (off-contract still fires)" {
  echo 200 > "$REGISTRY/requests.status"; echo 200 > "$REGISTRY/evilpkg.status"
  printf -- '- Erlaubte Dependencies: requests, numpy\n' > "$SCRATCH/PLAN.md"
  scan --diff-text $'+import requests\n+import evilpkg' --ecosystem python --plan "$SCRATCH/PLAN.md"
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" off_contract.0.pkg)" = "evilpkg" ]
}

@test "AUDIT-P1: --plan 'stdlib only' keeps off-contract ARMED (not disabled)" {
  echo 200 > "$REGISTRY/requests.status"
  printf -- '- Erlaubte Dependencies: stdlib only\n' > "$SCRATCH/PLAN.md"
  scan --diff-text $'+import requests' --ecosystem python --plan "$SCRATCH/PLAN.md"
  [ "$status" -eq 2 ]
}

@test "AUDIT-P1: supply-chain — git+ source in requirements.txt is BLOCKED" {
  scan --diff-text $'+++ b/requirements.txt\n+evil @ git+https://github.com/x/y' --ecosystem python
  [ "$status" -eq 2 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "BLOCK" ]
}

@test "AUDIT-P1: supply-chain — clean pinned requirement passes; a URL in SOURCE code is not flagged" {
  echo 200 > "$REGISTRY/requests.status"
  scan --diff-text $'+++ b/requirements.txt\n+requests==2.31.0' --ecosystem python
  [ "$status" -eq 0 ]
  scan --diff-text $'+++ b/src/app.py\n+URL = "https://api.example.com"' --ecosystem python
  [ "$status" -eq 0 ]
}

@test "AUDIT-P2: registry-unreachable -> WARN-unreachable exit 0 (unknown, not invented/off)" {
  : > "$REGISTRY/somepkg.status"   # empty status file => unreachable
  scan --diff-text $'+import somepkg' --ecosystem python --allow "somepkg"
  [ "$status" -eq 0 ]
  [ "$(jfield "$SCRATCH/scan.json" verdict)" = "WARN-unreachable" ]
  [ "$(jfield "$SCRATCH/scan.json" unknown.0.pkg)" = "somepkg" ]
}
