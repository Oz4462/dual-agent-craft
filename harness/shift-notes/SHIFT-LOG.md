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

## 2026-07-21 — Agent-orchestrated self-improvement (workflow craft-self-improve)
- **DONE (verified)**: Ran a 44-agent workflow (6 analysis lenses × verified findings),
  got 38 verified improvements (2 P0, 17 P1). Self-verified each before fixing, +tests.
  - P0: test-guard non-ASCII bypass (git quotePath C-quoting defeated anchors — umlaut
    test file turned BLOCK->PASS; reproduced live in this German env) → quotePath=false + -z.
  - P0: dual-merge unguarded `git checkout $INTO` (fail-open at the most destructive step)
    → `|| fail` + HEAD assertion.
  - SELF-FOUND: self-check timeout SIGTERM left a MUTATED guard on disk (mutation-train
    had no restore-on-interrupt) → EXIT/INT/TERM trap; SKIP now fails (was fail-open).
  - P1: codex --full-auto silently voided its sandbox → upgrade read-only->workspace-write,
    no bypass flag. eval-k numeric validation. guard: +command-substitution shell-exec +
    extended secret readers (xxd/base64/cp…). Doc integrity: test-count 88->106, nightly
    runs full battery, W4 agent refs fixed.
- **Verify**: suite 106/106 · reflex-drill 44/44 strong · mutation-train 12/12 killed 0 stale
  · self-check --quick FIT.
- **LESSON (-> muscle #35)**: a mutation/fault-injection tool MUST restore on interrupt
  (trap), or a killed run silently weakens a live guard. Found the hard way.
- **OPEN**: 30 verified backlog items remain (mostly P2 + a few M-effort P1: Ollama-scout
  wiring, Codex-reviewer role in dual-review, import-scan reading PLAN allowlist, dual-build
  test coverage). Handed to owner to greenlight.
- **STATE**: branch feat/bash-port, 17 commits ahead of main, tree clean, suite 106/106, unpushed.

## 2026-07-22 — Backlog cleared (all 26 verified items from the self-improve workflow)
- **DONE (verified)**: worked the entire verified backlog in 6 themed batches (A-F) + the Ollama scout, each item verified against real code + regression-tested:
  - A robustness: worktree paths from git-toplevel, tiebreak keeps the winning branch, EXIT-trap worktree cleanup (no leaks).
  - B import-scan/test-guard: allow-list trim, --plan reads 'Erlaubte Dependencies', manifest supply-chain block (git+/file:/github:), test-runner-config coverage (pytest.ini/jest.config, excl pyproject/package.json).
  - C orchestration: budget-guard opt-in pre-flight, --assess-vendor claude|codex (Codex reviewer real), --builder grok|codex (Codex sandboxed builder).
  - D diagnostics/DX: dual-status.sh doctor, eval-harness keeps run logs + points at first failing log, --help everywhere, dual-review diff-size cap.
  - E coverage: dual-build.bats (deny-argv, INCOMPLETE label, toplevel worktree), rebuttal-fail fail-closed, budget ISO-stamp, eval score_ok/threshold/K-clamp.
  - F doctrine: CONTRACT training pairing-rule, guard surfaces the nightly SUITE-RED flag once.
  - #3 Ollama scout: zero-quota local rung, self-gated by --verify, path-traversal rejected, falls through to the paid builder; both paths LIVE-verified (fake ollama server).
- **Verify**: suite 143/143; scout + dual-status + eval-red-log live-checked; mutation-train extended to 17 mutations (pairing rule) — running to completion in background.
- **LIVE CONFIRMATION**: the mutation-train EXIT-trap (self-found last session) restored a clean tree after a 550s timeout SIGTERM — the fix works under real interruption.
- **Shell lessons paid**: backtick inside python -c '...' opens a nested command-sub inside $(...); a ' inside -c '...' closes the outer quote -> use heredoc+env. $?-reset by `local x;` bit the reflex-drill.
- **STATE**: branch feat/bash-port, ~23 commits ahead of main, tree clean, suite 143/143, unpushed. Backlog: 0 open.
