---
name: triage-repo
description: Fast structured triage of an unknown or broken repo — what is it, does it build, what is red, what is the one highest-leverage fix.
---
# Triage + Repo

## Procedure (15 min cap)
1. **Identify**: README head, manifest (package.json/pyproject/Cargo/go.mod), entrypoints. One sentence: what does this ship?
2. **Vitals**: `git log --oneline -10`, branch state, last CI status, test runner present?
3. **Build**: run the canonical build/test ONCE, capture the FIRST error verbatim (not the last — cascades lie).
4. **Classify red**: env/setup vs dependency vs real code defect vs flaky. Reproduce in isolation before blaming code (Reflex R2).
5. **Map**: 5-bullet architecture sketch (data in → transform → out), largest 3 files, ownership hot spots (`git shortlog -sn | head`).
6. **Verdict**: one page — state, top 3 risks, ONE highest-leverage next action. No fix without a listed verify command.

## Outputs
`TRIAGE.md` in repo root (or ticket comment): state / risks / next action / verify cmd.

## Rules
- Fail-closed reporting: "could not verify" ≠ "works".
- Touch nothing on main; all probing in a scratch worktree.
