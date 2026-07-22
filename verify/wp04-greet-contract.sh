#!/usr/bin/env bash
# WP04 verify gate: run the greet contract tests (stdlib unittest only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m unittest tests.test_greet_contract -v
