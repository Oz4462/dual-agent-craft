---
name: project-brief
description: Turn a vague ask into a 1-page executable brief — problem, constraints, interface contract, acceptance criteria, out-of-scope — before any code.
---
# Projekt-Brief

## When
Any task >1 hour, any multi-agent build, anything the user described in one sentence.

## The 1-pager (PLAN.template.md is the long form)
1. **Problem** — 2-3 sentences, no solutioneering.
2. **Constraints** — stack, allowed dependencies, forbidden ops, budget/time.
3. **Interface contract** — exact signatures/endpoints/CLI flags. Precise enough that a builder can't guess and a reviewer can name drift.
4. **Acceptance criteria** — binary, each expressible as a runnable test/command.
5. **Test list** — happy path, edge, fail-closed case minimum.
6. **Out of scope** — explicit, prevents scope creep by the builder.

## Rules
- The brief is THE shared truth: builder builds against it, reviewer reviews against it, the eval gates against its acceptance list.
- Underspecified after honest effort → 2-4 targeted questions to the owner, then freeze. Never build on guessed requirements.
- Changes mid-build = brief edit FIRST (versioned), then code. Silent contract drift is a review finding.
