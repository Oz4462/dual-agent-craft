#!/usr/bin/env bash
# nightly-suite.sh — bounded nightly verification; red leaves a flag file the next session sees.
set -uo pipefail; export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
flag=".dual-agent/SUITE-RED.flag"; mkdir -p .dual-agent
fails=0
for f in *.sh lib/*.sh harness/bin/*.sh harness/operations/hooks/*.sh; do bash -n "$f" || fails=$((fails+1)); done
tests/run.sh || fails=$((fails+1))
if [[ $fails -gt 0 ]]; then
  printf '{"stamp":"%s","suite":"RED","fails":%s}\n' "$(date -u +%Y%m%d-%H%M%S)" "$fails" | tee "$flag"
  exit 1
fi
rm -f "$flag"; echo "nightly: green"
