---
name: jest-browser
description: Testing pyramid for web work — Jest/Vitest units first, then real-browser E2E (Playwright) for the flows that pay rent; anti-flake discipline throughout.
---
# Jest + Browser

## Pyramid
1. **Unit (Jest/Vitest)**: pure logic, hooks, transforms. AAA structure, behavior-named tests, no snapshot dumps as assertions.
2. **Component (Testing Library)**: query by role/label (what users see), not test-ids first. One behavior per test.
3. **E2E (Playwright)**: only critical user flows (auth, checkout, the money path). Screenshot key breakpoints when visual.

## Anti-flake rules
- Deterministic waits (`await expect(locator).toBeVisible()`), NEVER `sleep`/timeout assertions.
- One `pass^k` idea applies here too: a test that fails 1/20 runs is red, quarantine it with a ticket — don't retry-until-green.
- Isolated state per test (fresh fixtures, no order dependence). Verify by running the file alone AND shuffled.
- Mock at the boundary (network), not the middle (your own modules), or the test proves nothing.

## Gate
- New feature = new tests FIRST (red→green→refactor).
- Coverage target 80% on changed code; visual-heavy components may substitute visual regression, never nothing.
- CI runs the suite headless; local repro command documented in the PR.
