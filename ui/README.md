# Dual-Craft Chat Cockpit

Professional local **task chat UI** for the dual-agent harness.  
Type tasks in plain language; the server routes them through `dual-run.sh` (Claude · Grok · Codex) with live status and logs.

## Start

```bash
# from repo root
./dual-chat.sh                 # http://127.0.0.1:8787/  (opens browser)
./dual-chat.sh --port 8790 --no-open
```

Windows (Git Bash / WSL):

```bash
bash ./dual-chat.sh
```

Or:

```powershell
# after Git Bash is installed
bash dual-chat.sh
```

## Features

- Multi-panel cockpit: chat · mission presets · who-matrix · team packages · live log
- Adaptive profile selector (`auto` / `minimal` / `standard` / `thorough` / `security` / `sandbox`)
- **Preview who** (role-router only) vs **Run task** (starts dual-run)
- Options: auto-plan, team-work, skip-merge, dry-run, fortify, verify command
- SSE live log stream, cancel running job
- History under `.dual-agent/chat/history.jsonl` (gitignored runtime)

## Security

- Binds **127.0.0.1** by default (set `DUAL_CHAT_ALLOW_REMOTE=1` only if you know why)
- No API keys in the UI — uses local CLI logins
- Does not expose raw filesystem browse APIs

## API (local)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | liveness |
| GET | `/api/status` | git, lock, ledger, CLIs, active run |
| GET | `/api/who?task=` | adaptive assignment |
| GET | `/api/history` | chat history |
| POST | `/api/chat` | message + optional run |
| POST | `/api/runs` | start run |
| GET | `/api/runs/{id}/stream` | SSE logs |
| POST | `/api/runs/{id}/cancel` | SIGTERM |

## Tests

```bash
python3 tests/chat_ui_test.py
```
