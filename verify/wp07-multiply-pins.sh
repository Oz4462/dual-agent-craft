#!/usr/bin/env bash
# WP07 verify gate: run the multiply contract tests (stdlib unittest only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m unittest tests.test_multiply -v
