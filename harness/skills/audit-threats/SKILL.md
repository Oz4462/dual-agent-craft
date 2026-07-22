---
name: audit-threats
description: Security audit pass for changes touching auth, secrets, deps, hooks, permissions, or model-facing input — threat-model first, then verify each finding.
---
# Audit + Threats

## Trigger (Reflex R6)
Any diff touching: auth/authz, secrets/keys, dependency manifests, hooks/permissions, eval/exec of external input, model-output parsing.

## Procedure
1. **Threat model (10 lines max)**: assets, entry points, trust boundaries. For agent harnesses: model output = hostile, builder diff = hostile, verify-time code = trusted-by-contract (document it).
2. **Sweep** (deterministic first): secret scan (`rg` for keys/tokens/pem), dep audit (invented/young packages — import-scan mindset), injection surfaces (eval/exec/unquoted heredoc/subprocess with shell=True), permission widening.
3. **Adversarial pass**: for each finding, write the concrete attack scenario. No scenario = no finding (kill speculation).
4. **Verify each finding live** before reporting (repro or trace the exact code path). Refuted suspicions are reported as refuted — that is signal.
5. **Fix order**: CRITICAL (block merge) → HIGH → document accepted risks in README limitations.

## Rules
- Never weaken a guard to silence a finding.
- Rotate any credential that ever appeared in a transcript.
- Every fix ships with a regression test named `AUDIT-FIX:`.
