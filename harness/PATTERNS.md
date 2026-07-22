# Patterns — proven shapes for this harness

> Reusable structures. Reach for a pattern before inventing a shape; extend this
> file when a new shape survives contact with reality twice.

## Orchestration patterns

- **CRAFT loop** — Contract → Render (builder, isolated worktree) → Assess
  (cross-vendor, untrusted lens) → Fortify → Test gate (pass^k). The default for
  any built feature.
- **Bounded cross-review** — 1 assess + 1 rebuttal, grounding gate
  (defend needs a citation), then the eval decides. Never debate-to-consensus.
- **Micro-probe tie-break** — subjective disagreement ⇒ build BOTH, measure,
  record honest per-candidate status (measured / build-failed / eval-failed).
- **Adapter contract** — every vendor wrapper emits `{exit_code, text, json_log,
  stdout_log}`; roles are vendor-blind, diversity is the moat.
- **Fresh-context subagent** — brief in, artifact out; declared return format;
  no shared mutable state between parallel agents (one writer per file-space).
- **Loop runner** — done-condition + max-iterations + max-seconds + per-cycle
  log line; loop ends on condition, cap, or two consecutive no-progress cycles.

## Guard patterns

- **Deterministic gate** — zero model calls inside a guard; the guard itself
  must be unable to hallucinate (import-scan, test-guard, eval-harness).
- **Fail-closed default** — error paths land in BLOCK; PASS requires positive
  evidence (parsed, counted, verified).
- **Honest status enum** — never encode "failed to measure" as a zero score;
  carry `status` beside the number.
- **Escape-hatch labeling** — overrides exist (`--force`) but print loudly and
  never become the default path.

## Code patterns

- **Small files, one job** — 200–400 lines typical; split at 800.
- **Env-var data passing** into embedded python (stdin belongs to the program).
- **Locale-pinned numerics** (`LC_ALL=C`) at the entry point of every module.
- **NUL-terminated lists** whenever values can contain whitespace/newlines.
- **Ledger files** — append-only JSONL with a stamp field; readers skip+count
  malformed lines, never crash on them.

## Testing patterns

- **Stub the expensive edge** — fake CLIs on PATH, stubbed registries via env
  hook; the suite runs offline, deterministic, $0.
- **Regression test per confirmed bug** — named `AUDIT-FIX:` so the suite
  documents the bug history.
- **Throwaway repos per test** (`git init -b main` in mktemp) — never mutate the
  harness repo from tests; restore any shared ledger you touch.
- **Vacuous-pass check** — a test that can't fail is a lie; make it fail once
  (break the code, watch red) before trusting green.
