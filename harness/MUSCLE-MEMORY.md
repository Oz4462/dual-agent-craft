# Muscle Memory — 36 earned lessons

> Instant recall before touching code. Each entry is one burned lesson: many were
> paid for in THIS repo (marked ⚡ = found live here), the rest in prior projects.
> Violating a known entry is a process failure, not bad luck.

## Bash (the ones that bit us)

1. ⚡ **Never two stdin owners.** `cmd | python3 - <<'PY'` and `json_field /dev/stdin`
   both lose the pipe — the heredoc owns fd0. Pass data via env var or `python3 -c`.
2. ⚡ **`local a="$1" b="…$a…"` is broken.** All words of one `local` expand BEFORE
   any assignment → `$a` unbound under `set -u`. Declare locals on separate lines.
3. ⚡ **Force `LC_ALL=C`** in anything that formats/parses numbers — comma-decimal
   locales (de_DE) break `printf %.2f` and awk on dotted floats.
4. ⚡ **`2>/dev/null || true` on a guard is a hole.** A failing `git diff` in a
   fail-closed gate must BLOCK, not return an empty "all clean" list.
5. ⚡ **`${arr[@]:-}` + `mapfile` + `set -u`:** empty input can yield one empty
   element; NUL-terminate (`mapfile -d ''`) when values may contain newlines.
6. **Arrays for args, never string concat.** Quoting survives spaces/globs only
   through `"${args[@]}"`.
7. ⚡ **`$?` survives entering a function** (checked empirically) — but ANY command
   in between, including `[[ ]]`, resets it. Capture immediately.
8. ⚡ **Missing flag values:** `VAR="${2:?value required for $1}"` — a clear message
   beats a raw `unbound variable` at line N.
9. **`set -uo pipefail` always; `set -e` never in orchestration** — native tools
   write to stderr and non-zero mid-pipeline; check `$?`/explicit rc instead.
10. **Heredocs don't re-expand model text.** `$(…)` inside an expanded variable is
    inert (verified) — the injection risk is prompt-level, not shell-level.

## Git

11. ⚡ **A worktree branches from a COMMIT, not the working tree.** Commit WIP
    first (on a wip branch — `main` stays clean) or the builder sees a stale base.
12. ⚡ **Detached HEAD reports `HEAD`** from `rev-parse --abbrev-ref` — guard it
    before committing or you strand work on an unnamed commit.
13. **Conflict = abort.** `git merge --abort` and hand it to a human; never
    auto-resolve, never "last writer wins".
14. **`git diff base...branch` needs both refs verified first** — a bad ref makes
    downstream logic run on empty output.
15. **Never rewrite pushed history on shared branches; force-push only your own
    feature branches, only with `--force-with-lease`.**
16. ⚡ **Junk strip before committing agent output:** `__pycache__`/`.pyc` nest —
    `find -name` recursively, not top-level globs.

## Orchestration / agents

17. ⚡ **Model failure ≠ clean result.** An unparseable/refusal reply must BLOCK;
    reserve "no issues" for an explicit, parsed empty list.
18. ⚡ **In-band errors beat exit codes.** `is_error:true` with process exit 0 is
    common — fold it into the contract exit code the caller actually reads.
19. ⚡ **Never `--always-approve` outside a disposable worktree + deny rules** —
    especially when the prompt embeds untrusted diff content.
20. ⚡ **A fabricated measurement is worse than no measurement.** Track
    measured/build-failed/eval-failed per candidate; both-failed = no verdict.
21. **Subagents get fresh context:** task brief only, one deliverable, declared
    return format. Inherited conversation state breeds drift.
22. ⚡ **Grok exits 1 on "max turns reached" with complete work** — read stderr to
    distinguish turn-cap from refusal before declaring failure.
23. **pass@1 lies.** Gate on pass^k (all K green); one green run is luck, not done.
24. **Separate stdout/stderr at the fd level** for every headless CLI — auth/MCP
    noise must be physically unable to reach the parsed result.

## Python / data

25. **Parse JSON with a real parser, extract with explicit keys** — regex-scraping
    model JSON breaks on the first fenced/prose-wrapped reply.
26. ⚡ **`from pkg.sub import x` is the common form** — any import scanner that
    only matches `from pkg import` silently misses most real imports.
27. **Wrap per-record conversions** (`float(...)`) in try/except inside loops —
    one corrupt line must not kill the whole computation (skip + count + warn).
28. **pandas: never mutate while iterating; prefer vectorized ops; `.loc` for
    writes** — chained assignment warnings are real bugs waiting.
29. **SQL: parameterized queries only; LIMIT every exploratory query; wrap
    multi-statement changes in a transaction.**

## Process

30. **Read the file before editing it; read the error before fixing it.** No
    edits from memory of what a file "should" contain.
31. ⚡ **Tests catch what review misses** — the tiebreak `local` bug survived
    2 reviews and died on the first test run. Untested code paths are unverified
    claims.
32. **Timestamps in artifacts, stable names in code.** Logs get `utc_stamp`;
    interfaces don't.
33. **Write the shift note while it hurts.** The lesson you don't record in the
    same session is the lesson you pay for twice.
34. ⚡ **Guard by capability, not by spelling.** An adversary reorders/renames
    flags (`rm -r -f` = `rm --recursive --force` = `rm -rf`); a fixed-string
    reflex is a weak reflex. Detect the capability, then scope the target.
35. ⚡ **A fault-injection tool must restore on interrupt.** mutation-train left a
    mutated guard on disk when a timeout killed it mid-run (no trap) — silently
    weakening a live reflex. Any tool that temporarily breaks the tree needs an
    EXIT/INT/TERM trap, and a no-op mutation (SKIP) must FAIL, not read as 'killed'.
36. ⚡ **Never `git add -A` while a mutation/fault-injection tool runs.** mutation-train
    temporarily mutates tracked files; a concurrent `git add -A` can COMMIT a
    mutation (a real Batch-B import-scan fix got reverted this way — caught only by
    the suite). Commit with EXPLICIT paths during any such window, or wait for it.
