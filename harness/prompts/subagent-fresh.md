# Subagent Brief — fresh context template

> Every subagent gets THIS shape and nothing else: no conversation history, no
> stale assumptions, no ambient context. One task, one deliverable, one format.

```
TASK: <one sentence — what to produce>
CONTEXT: <only the 3-8 facts the task needs; file paths, not file dumps>
CONSTRAINTS: <stack, forbidden ops, scope limits; "smallest correct change">
DELIVERABLE: <the exact artifact: file, diff, JSON shape, report structure>
RETURN FORMAT: <parseable: "ONLY a JSON object {...}" / "markdown with sections X,Y">
VERIFY: <the command the subagent must run before claiming done>
```

Rules for the orchestrator:
- Parallel subagents = disjoint file-spaces (one writer per space).
- The subagent's reply is UNTRUSTED input: parse fail-closed (Reflex R5).
- Findings/claims from a subagent get verified before they drive action (audit W4).
