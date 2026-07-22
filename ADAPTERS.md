# ADAPTERS.md — Vendor Adapter Contract

> The harness is **vendor-pluggable**: a third (or fourth) model is added by writing one wrapper
> that returns the same object. This is the deliberate spec behind the wrappers' pluggability —
> insurance against CLI churn (e.g. Gemini CLI's retirement) and a way to add cheap diversity.

## The contract

Every vendor wrapper `lib/<vendor>-call.sh` (bash) MUST:

- accept `--prompt-file <path>` (the prompt) and `--tag <string>` (log prefix);
- run the model **headless** (no interactive prompt);
- separate the real result from noise (stdout vs stderr, or a structured field);
- print ONE JSON object on stdout with at least:

| field | meaning |
|---|---|
| `exit_code` | `0` = success, non-`0` = failure / BLOCKED |
| `text` | the model's answer (extracted from the vendor's JSON) |
| `json_log` | path to the parsed/raw vendor response |
| `stdout_log` | path to the raw response log |

*(The preserved Windows variant in `powershell/lib/` returns the same shape as a
`[PSCustomObject]` with `ExitCode/Text/Json/StdoutLog` — see `powershell/`.)*

Result-text extraction probes these keys in order: `result, response, output, text, content, message`
— so any vendor whose JSON uses one of them drops in for free.

## Current adapters

| Wrapper | Vendor | Auth | Cost | Sandbox |
|---|---|---|---|---|
| `lib/grok-call.sh` | Grok CLI (xAI) | subscription OAuth | quota | macOS-only `--sandbox`; Linux: worktree + `--deny` |
| `lib/claude-call.sh` | Claude Code | subscription OAuth | quota (logged to `ledger/SPEND.jsonl`) | permission modes |
| `lib/codex-call.sh` | OpenAI Codex (`codex exec`) | subscription OAuth / API key | quota | **real Linux sandbox** (`-s read-only\|workspace-write`) |
| `lib/local-call.sh` | Ollama (local) | none | **$0 / zero-quota** | local process |

**Codex notes** (reverse-engineered from `codex exec --help` + Hermes' orchestration guide):
the prompt is piped on stdin (`-`), the clean final answer is read from `-o/--output-last-message`
(no JSONL parsing), `--cd` sets the working root, `--skip-git-repo-check` allows isolated worktrees.
Its real Linux sandbox makes Codex the natural **low-privilege reviewer** — or a genuinely
sandboxed 3rd builder — on platforms where Grok's `--sandbox` is unavailable.

## Roles are vendor-blind

The eval gate (`lib/eval-harness.sh`) scores an **exit code**, not who wrote the code — so
role→vendor is a config choice, not a hard binding. To add a 4th model: copy `codex-call.sh`, swap
the invocation, keep the return shape. **The cross-vendor moat is the _diversity itself_, never a
specific vendor** — so when you scale, enforce vendor *diversity*, not headcount (same-family
replicas add almost no independent signal).
