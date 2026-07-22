---
name: readmes-apis
description: Documentation that stays true — READMEs written from verified behavior, API docs generated from the source of truth, drift caught by the suite.
---
# READMEs + APIs

## README rules
- **Document what you ran, not what you believe.** Every quickstart command was executed before it was written; paste-tested top to bottom.
- Structure: what it is (1 line) → why it's different (3 bullets) → quickstart → components table → honest limitations.
- **Honest limitations section is mandatory** — undocumented gaps are lies with a delay timer.
- Badges reflect measured reality (test count, platforms) and get updated in the same commit that changes the reality.

## API docs
- Source of truth is code (signatures, schemas, --help). Generate or hand-mirror FROM it, never parallel-maintain.
- Every endpoint/function doc: signature, one realistic example, failure modes (what raises/returns on bad input).
- Version and date every breaking change; changelog entry in the same PR.

## Drift control
- Doc examples that can run ARE tests (doctest/bats snippet) — wire the cheap ones into the suite.
- Grep-check on release: flags/paths mentioned in docs exist in code (`--help` diff vs README).
- Stale reference found = fix in the SAME session (Muscle #33: record while it hurts).
