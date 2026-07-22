# Security & privacy audit

**Last audit:** 2026-07-22 (after CI green on `main`)  
**Scope:** all **git-tracked** files + full git history (`git rev-list --all`)  
**Result:** **PASS** — no Claude / Grok / Codex / OpenAI / GitHub / AWS / private-key material found.

## What we look for

| Class | Examples |
|---|---|
| API keys | `sk-…`, `sk-ant-…`, `xai-…`, `AIza…`, `AKIA…` |
| Tokens | `ghp_…`, `github_pat_…`, JWT, `Bearer …`, Slack `xox…` |
| Key material | `BEGIN PRIVATE KEY`, `.pem` contents |
| Auth assignments | `api_key=…`, `password=…`, `access_token=…` (with long values) |
| Vendor auth stores | `.claude/credentials`, `.codex/auth`, session dumps |

## Findings

| Check | Result |
|---|---|
| Tracked files (111) secret patterns | **0 hits** |
| Full history (66 commits) hard-secret patterns | **0 hits** |
| Sensitive filenames (`.env`, `*.pem`, `*token*`) tracked | **none** |
| `.mcp.json` | keyless only (`npx` / `uvx` public packages) |
| `ledger/*` runtime | **gitignored** (only `ledger/.gitkeep` tracked) |
| `.dual-agent/logs|tmp|locks` | **gitignored** |
| Auth / secret file globs | ignored via `.gitignore` |

### Public metadata (not secrets)

- Git author emails on commits (`noreply` + personal) are normal git history — not credentials.
- Docs mention the words “secret”, “token”, “password” only as **policy text** (e.g. “never commit API keys”).

### Local untracked (machine-only, not on GitHub)

These may exist on a developer machine but are **not** in the remote repo:

- `ledger/*.json`, `ledger/SPEND.jsonl` (spend is cost telemetry, not API keys)
- `.dual-agent/logs/*`, `.dual-agent/tmp/*`
- CLI OAuth state under the user’s home (`~/.claude`, `~/.codex`, Grok app data) — **outside this repo**

## Design: how auth works (no keys in-repo)

| Vendor | Auth model |
|---|---|
| Claude Code | Local CLI subscription / OAuth — not stored in this tree |
| Grok CLI | Local CLI subscription / OAuth — not stored in this tree |
| Codex | Local CLI OAuth/API via user env — not stored in this tree |
| Ollama | Local HTTP, no cloud key |

The harness is built for **zero API keys in config**. Do not add keys to `config/`, `.mcp.json`, or scripts.

## How to re-run the audit

```bash
# quick: tracked tree + history hard patterns
python3 scripts/secret-audit.py

# optional: install gitleaks for CI-style scan
# gitleaks detect --source . --no-git=false
```

## If something ever leaks

1. **Rotate** the credential immediately (Claude / xAI / OpenAI / GitHub).  
2. Remove from git history (`git filter-repo` / BFG) — force-push only with team agreement.  
3. Add a regression pattern to `scripts/secret-audit.py` and `.gitignore`.

## Contact

Report security issues privately to the repo owner — do not open a public issue with live secrets.
