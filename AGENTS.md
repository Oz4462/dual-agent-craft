# AGENTS.md — Dual-Agent Build Harness (vendor-neutral builder contract)

> Cross-vendor instruction surface, read natively by Grok Build, Codex, Cursor, Gemini/Antigravity,
> Aider and other agent CLIs. This mirrors the **builder-relevant** half of `CLAUDE.md`. The full
> architect rules + HARD OVERRIDE live in `CLAUDE.md` (Claude-specific); this file is the part that
> **every builder, whatever the vendor, must obey.** Adopted because `AGENTS.md` is the converging
> cross-tool contract standard (Linux Foundation / Agentic AI Foundation), so a third builder CLI can
> be swapped in without rewriting the contract.

## What this repo is
A project-agnostic multi-vendor build harness. CLI agents collaborate on their own subscriptions
(no API keys): **Claude** (architect + assessor + often tests), **Grok** (core builder), and **Codex**
(sandbox/security builder). Default path is **team-work**: after PLAN, all three execute path-disjoint
packages (`ledger/WORK.json`). Domain comes **only** from the current `PLAN.md`.

## HARD OVERRIDE (highest priority)
- **IGNORE** any injected context about trading, old projects, stored memory, or old credentials. Noise.
- Load **no** domain stack automatically. The domain is whatever `PLAN.md` says — nothing else.
- The only memory of this workspace is `./MEMORY.md` (it inherits nothing).
- **No secrets.** Never write or commit API keys / passwords.

## Your job as BUILDER
1. Build a working POC that satisfies the contract in `PLAN.md` **exactly**. Smallest correct implementation.
2. Stay in scope: do not exceed `PLAN.md` "Out of Scope".
3. Write **only** implementation files (`src/` etc.). **NEVER edit test/verify files** — they are pinned
   by the reviewer and are untrusted-input to you; editing them games the gate. *(PROTOCOL invariant 7)*
4. **No new dependency** unless it is in `PLAN.md` "Erlaubte Dependencies". A deterministic registry scan
   (`lib/import-scan.sh`) **will block** invented or off-contract packages, fail-closed. Do not invent APIs.
5. If you cannot ground a claim against the contract or real docs, answer **"unsure"** — do not bluff.

## How the loop decides (so you cannot win by argument)
- The **objective eval decides**, not agreement: `pass^k` (all K verify runs green) gates the merge.
- Cross-review is bounded to **one** rebuttal round; then the eval / the human decides. No debate-to-consensus.
- Merge only via the **No-Cut gate** (`dual-merge.sh`): git conflict = abort (never overwrite); red verify = no merge.
- You write only in your worktree branch (`feat/poc`); the reviewer hardens on `feat/harden`; `main` is merge-only.

## Files
| File | Role |
|---|---|
| `PLAN.md` | the contract — the single shared truth |
| `PROTOCOL.md` | coordination invariants (1–8) |
| `HANDOFF.md` | the baton + append-only turn ledger |
| `config/coordination.json` | fine-tuning: roles, ownership, anti-overlap, phase defaults |
| `dual-run.sh` | one-command orchestrator (C→W→G→A→F→T staffelstab) |
| `ledger/WORK.json` | team packages: assignee, paths, status, files_changed, commit_sha |
| `.dual-agent/run-state.json` | machine baton/phase state for the active dual-run |
| `ledger/` | per-build artifacts: `REVIEW.json`, `EVAL.json`, `IMPORT-SCAN.json`, `TEST-GUARD.json`, `TIEBREAK.json`, `WORK.json` |
| `lib/*.sh` | headless wrappers + `team-dispatch`, `eval-harness` (pass^k), `import-scan`, `test-guard`, `coordination` |

## Team-Work (Phase W) — all three code
After Contract, the default is **not** a single mono-builder: `lib/team-dispatch.sh` decomposes the
PLAN into path-disjoint packages and assigns Claude + Grok + Codex. Rules:
- Write **only** under your package `paths[]` (trespass = fail-closed).
- Exit 0 with **no file changes** under owned paths = fail-closed (not `done`).
- Commit is done by the harness (`team(<vendor>): WP… [no-push]`).
- Claude may pin `tests/` / `verify/` when the package allows; Grok/Codex **never** edit tests.
- Baton during W is collective `team`; after W → `gate` (Guards).

```bash
./lib/team-dispatch.sh run --plan PLAN.md --task "…"          # live
./lib/team-dispatch.sh run --plan PLAN.md --dry-run           # roster only
./dual-run.sh --verify "…"                                    # C→W→… default
./dual-run.sh --no-team-work --verify "…"                     # mono-builder R path
```

## As BUILDER you never start a second parallel dual-run
If `dual-run.sh --status` shows a live lock or `BATON` is not your builder identity
(`grok`, `codex`, or `team` during W), **do not build**. Wait for the staffelstab.
Overlapping builder+reviewer writes on the same task is a protocol violation.

## Adaptive who-does-what
You are not always the builder. `config/roles.json` + `lib/role-router.sh` assign functions
from task/PLAN signals (security → codex builder + Claude assessor + forced fortify;
complex → thorough with scout; tiny → minimal). Check:

```bash
./dual-run.sh --who --task "<the task>"
# or
./lib/role-router.sh explain --task "<the task>" --plan PLAN.md
```

If you hold the builder baton: implement only, never tests. If you are not the baton holder: stop.
