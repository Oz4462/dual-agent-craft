#!/usr/bin/env bash
# tests/run.sh — bootstrap bats (system or vendored) and run the whole suite.
#
# Deterministic + offline: every test stubs registries/CLIs; no billed calls,
# no network needed once bats is present.
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BATS="$(command -v bats || true)"
if [[ -z "$BATS" ]]; then
  VENDOR="$_HERE/vendor/bats-core"
  if [[ ! -x "$VENDOR/bin/bats" ]]; then
    echo "bats not found -> vendoring bats-core (shallow clone, one-time) ..."
    git clone --depth 1 https://github.com/bats-core/bats-core.git "$VENDOR" \
      || { echo "FAIL: no system bats and clone failed. Install bats (apt install bats) and retry."; exit 1; }
  fi
  BATS="$VENDOR/bin/bats"
fi

echo "bats: $BATS"
exec "$BATS" "$_HERE"/*.bats "$@"
