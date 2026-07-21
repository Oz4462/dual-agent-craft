---
name: loop-runner
description: Run bounded autonomous loops — declared done-condition, hard caps, per-cycle logging, no-progress abort — via harness/bin/loop-runner.sh.
---
# The Loop Runner

## Contract (Reflex R10)
No autonomous loop starts without ALL of:
1. **Done-condition** — a COMMAND whose exit 0 means finished (not a vibe).
2. **Hard caps** — max iterations AND max wall-clock seconds.
3. **Cycle command** — the one step repeated each round.
4. **Log** — one JSONL line per cycle (stamp, cycle, exit, done?).

## Usage
```bash
harness/bin/loop-runner.sh \
  --cycle "./dual-build.sh --adaptive --variants 3 --verify 'pytest -q'" \
  --done  "python3 -m pytest -q" \
  --max-cycles 6 --max-seconds 1800
```

## Semantics
- Loop ends on: done-condition green (SUCCESS) · cap hit (CAPPED, exit 1) ·
  2 consecutive cycles with identical failure signature (STALLED, exit 1 — a
  loop that isn't learning is burning quota).
- Every cycle appends to `.dual-agent/logs/LOOP-LOG.jsonl`; the final line
  records the outcome verdict — auditable afterwards.
- CAPPED/STALLED hand back to the human with the last failure verbatim. The
  runner never silently extends its own caps.
