# Shift Log — append-only cross-session memory

> Newest at the bottom. Every session APPENDS (template: TEMPLATE.md); clean-exit
> hook adds a skeleton automatically. Read the last entry BEFORE starting work (Reflex R8).

## 2026-07-21 — Brain-based training + controlled regression on CRAFT
- **DONE (verified)**: Trained the harness like a nervous system, two phases.
  - Phase 1 (neuro-drill on the reflex layer): 22 adversarial stimuli vs
    `guard-bad-calls`. Found 2 weak reflexes — `rm -r -f /` (split flags) and
    `rm --recursive --force /` (long form) slipped the old spelling-bound regex.
    Rewrote to detect recursive+force by CAPABILITY (any order/spelling) + a
    protected-path list; no false positives (scoped deletes still allowed).
    Locked with +6 regression tests. (commit 1aa48d5)
  - Phase 2 (controlled regressive self-improvement = mutation testing):
    injected 12 deliberate fail-closed faults across import-scan, eval-harness,
    test-guard, dual-merge, dual-review, guard, budget-guard, claude-call,
    loop-runner. **12/12 killed, 0 survived** — no test gaps. Made repeatable as
    `harness/bin/mutation-train.sh` (refuses dirty tree, reverts via checkout,
    exits nonzero on any survivor). (commit after)
- **Verify evidence**: `tests/run.sh` -> 94/94 green · `bash -n` sweep clean ·
  3 JSON configs valid · `mutation-train.sh` -> killed=12 survived=0 exit 0.
- **LESSON (-> muscle memory #34)**: guard by capability, not by spelling — an
  adversary reorders/renames flags; a fixed-string regex is a weak reflex.
- **STATE**: branch feat/bash-port, 11 commits ahead of main, tree clean,
  suite 94/94. Unpushed (owner rule). Session spend high (~$52).
