# Reflexes — stimulus → response (fires before reasoning)

> Instant, non-negotiable reactions. If the stimulus matches, the response
> happens FIRST; analysis comes after. Enforced where possible by
> `operations/hooks/guard-bad-calls.sh` (deterministic), practiced everywhere else.

| # | Stimulus | Reflex |
|---|---|---|
| R1 | About to run `rm -rf`, `git push --force`, `chmod -R 777`, `curl \| bash` | STOP → is it deny-listed? worktree-scoped? confirmed? |
| R2 | A test fails | Reproduce in isolation BEFORE blaming the last change |
| R3 | A guard/hook blocks a call | Treat as feedback: change approach, never retry verbatim |
| R4 | About to write "done/fertig/fixed" | Run the verify command NOW; paste the green output or don't say it |
| R5 | Model reply needs parsing | Real parser + explicit failure path; garbage ⇒ BLOCK, never default-empty |
| R6 | Touching auth/secrets/deps/hooks/permissions | Run `audit-threats` skill before commit |
| R7 | An operation needs data from a pipe into python | env var, never a second stdin owner |
| R8 | Starting a session | Read last `shift-notes/SHIFT-LOG.md` entry first |
| R9 | Ending a session | Clean-exit checklist + append shift note |
| R10 | About to loop autonomously | Done-condition + hard caps declared first (`bin/loop-runner.sh`) |
| R11 | Secret/API key appears in any output | Halt, never echo/commit it, rotate if exposed |
| R12 | Uncommitted work + about to branch/worktree | Commit WIP to a wip branch first (base must be a commit) |
| R13 | "It works on the happy path" | Feed it the failure path before shipping (empty, missing, garbage, non-zero) |
| R14 | Two agents disagree | Route to the eval (pass^k), never to more debate rounds |
| R15 | New dependency wanted | import-scan mindset: does it exist, is it allowed, how old is it? |
