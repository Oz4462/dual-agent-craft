# ADAPTERS.md — Vendor Adapter Contract

> The harness is **vendor-pluggable**: a third (or fourth) model is added by writing one wrapper
> that returns the same object. This is the deliberate spec behind the wrappers' pluggability —
> insurance against CLI churn (e.g. Gemini CLI's retirement) and a way to add cheap diversity.

## The contract

Every vendor wrapper `lib/<vendor>-call.ps1` MUST:

- accept `-PromptFile <path>` (the prompt) and `-Tag <string>` (log prefix);
- run the model **headless** (no interactive prompt);
- separate the real result from noise (stdout vs stderr, or a structured field);
- return a `[PSCustomObject]` with at least:

| field | meaning |
|---|---|
| `ExitCode` | `0` = success, non-`0` = failure / BLOCKED |
| `Text` | the model's answer (extracted from the vendor's JSON) |
| `Json` | the parsed vendor response (or `$null`) |
| `StdoutLog` | path to the raw response log |

Result-text extraction probes these keys in order: `result, response, output, text, content, message`
— so any vendor whose JSON uses one of them drops in for free.

## Current adapters

| Wrapper | Vendor | Auth | Cost |
|---|---|---|---|
| `lib/grok-call.ps1` | Grok CLI (xAI) | subscription OAuth | quota |
| `lib/claude-call.ps1` | Claude Code | subscription OAuth | quota (logged to `ledger/SPEND.jsonl`) |
| `lib/local-call.ps1` | Ollama (local) | none | **$0 / zero-quota** |

## Roles are vendor-blind

The eval gate (`lib/eval-harness.ps1`) scores an **exit code**, not who wrote the code — so
role→vendor is a config choice, not a hard binding. To add a 4th model: copy `grok-call.ps1`, swap
the invocation, keep the return shape. **The cross-vendor moat is the _diversity itself_, never a
specific vendor** — so when you scale, enforce vendor *diversity*, not headcount (same-family
replicas add almost no independent signal).
