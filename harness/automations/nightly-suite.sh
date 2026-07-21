#!/usr/bin/env bash
# nightly-suite.sh — bounded nightly verification; red leaves a flag file the next session sees.
set -uo pipefail; export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
flag=".dual-agent/SUITE-RED.flag"; mkdir -p .dual-agent
# Full fitness battery (syntax + configs + suite + reflex-drill + mutation-train),
# not just 2 of 4 checks (audit P2). self-check exits nonzero if any stage fails.
fails=0
harness/bin/self-check.sh || fails=$((fails+1))
if [[ $fails -gt 0 ]]; then
  printf '{"stamp":"%s","suite":"RED","fails":%s}\n' "$(date -u +%Y%m%d-%H%M%S)" "$fails" | tee "$flag"
  exit 1
fi
rm -f "$flag"; echo "nightly: green"
