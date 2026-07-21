# Agent Teams — Claude Code + Grok orchestration

> How the vendors form a team, who may write where, and how to see them work.

## Roster (role → vendor → why)
| Role | Vendor | Adapter | Why this vendor |
|---|---|---|---|
| Architect / Reviewer | Claude Code | `lib/claude-call.sh` | deepest review, drives the loop |
| Builder | Grok | `lib/grok-call.sh` | fast POCs, best-of-n variants |
| Sandboxed 2nd reviewer / builder | Codex | `lib/codex-call.sh` | REAL `-s` Linux sandbox, 3rd-vendor diversity |
| Scout (exploration only) | Ollama local | `lib/local-call.sh` | $0, zero quota — never merge-gating |

Cross-vendor moat: reviewer ≠ builder vendor, ALWAYS. `lib/decorrelation.sh` warns when they converge.

## Two orchestration surfaces
1. **Cross-vendor CRAFT loop** (between CLIs): `dual-build.sh` → guards → `dual-review.sh` → `dual-merge.sh`. The eval decides. This is the production path.
2. **In-session Claude teams** (inside one Claude Code session): custom agents via `--agents "$(cat harness/teams/agents.json)"` — planner/builder/reviewer/security subagents, each in FRESH context (prompts/subagent-fresh.md discipline). Independent subtasks launch in parallel; one writer per file-space still applies.

## Team display mode
Run orchestrating sessions with **`--forward-subagent-text`** — subagent output and thinking stream into the transcript live, so you SEE the team working instead of a spinner. For long builds, pair with the split cockpit `./dual-view.sh` (left: Claude, right: Grok live log).

## Coordination invariants (inherited from PROTOCOL.md)
Baton in HANDOFF.md · one writer per file-space · No-Cut merges only · eval decides, never consensus · bounded review (1 rebuttal) · builder never edits tests (test-guard enforced).
