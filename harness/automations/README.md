# Automations

Templates for recurring runs (cron / CI / Claude Code scheduled sessions). Each automation is bounded (caps), logged (JSONL), and fail-closed (red = loud, never silent).

| Template | Cadence | What it does |
|---|---|---|
| `nightly-suite.sh` | nightly | full bats suite + `bash -n` sweep; nonzero exit = red flag file for the next session |
| `weekly-decorrelation.sh` | weekly | decorrelation trend from ledger; warns if the vendors are converging |
| `spend-report.sh` | weekly | sums SPEND.jsonl by tag/model; appends to ledger/SPEND-REPORT.md |

Wire-up (user cron, example):
```cron
15 3 * * *  cd ~/dual-agent-craft && harness/automations/nightly-suite.sh >> .dual-agent/logs/cron.log 2>&1
```
