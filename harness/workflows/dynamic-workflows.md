# Dynamic Workflows

> Composable multi-step flows. Pick the smallest workflow that fits; escalate only on evidence. Every workflow ends with a verify step and a shift-note line.

## W1 — feature (default)
brief (project-brief) → CRAFT build (`dual-build.sh --adaptive`) → guards (import-scan + test-guard) → bounded review → pass^k merge (`--eval-k 5 --test-guard`).

## W2 — bugfix
reproduce in isolation (Reflex R2) → pin with failing regression test → smallest fix to green → suite → merge. The repro test ships with the fix.

## W3 — refactor
safe-rewrites skill: pin behavior → slices → suite green per slice → behavior diff old vs new.

## W4 — audit
parallel fresh-context reviewers — the `reviewer` + `security` agents from teams/agents.json, each given a distinct lens (correctness / silent-failure / security) → self-verify EVERY finding → fix confirmed only → regression test per fix (`AUDIT-FIX:` naming).

## W5 — autonomous iteration
loop-runner with declared done-condition + caps. STALLED/CAPPED hands back to human — never self-extend.

## W6 — data task
pandas-sql skill gates: dtype pinning, merge validation, row-count reconciliation → conclusions only after the sanity gate.

## Escalation matrix
| Signal | Escalate to |
|---|---|
| brief unclear after honest effort | questions to owner, freeze brief |
| guard blocks twice | stop, explain intent, ask |
| review finds security surface | insert W4 before merge |
| flaky verify (pass@k=1, pass^k=0) | quarantine + ticket, no merge |
