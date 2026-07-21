---
name: safe-rewrites
description: Behavior-preserving rewrites and refactors — pin behavior with tests before touching structure, migrate in reversible slices, never big-bang.
---
# Safe Rewrites

## Iron rules
1. **Pin first**: green tests around CURRENT behavior (including its warts) before changing structure. No pins = no rewrite.
2. **Slices, not big-bang**: each slice ≤1 review-able diff, independently revertable, suite green after each.
3. **Strangler pattern** for live systems: new path grows beside old, traffic shifts behind a flag, old path dies LAST.
4. **No behavior changes smuggled in.** Found a bug mid-rewrite? Separate commit, separate test, flagged in the PR.
5. **Preserve the Windows/legacy variant** when porting (parallel dir), don't destroy verified prior work.

## Procedure
1. Characterization tests (golden outputs for the ugly parts).
2. Map seams; cut at module boundaries, not mid-function.
3. Rewrite slice → suite green → commit → next slice.
4. Final: diff the OBSERVABLE behavior (CLI output, API responses) old vs new; byte-diff where feasible.
5. Deprecate old path with a dated removal note, not a silent delete.

## Abort criteria
Pins can't be written (untestable code) → STOP, extract-and-test first. Slice touches >20 files → slice is too big.
