# MEMORY — Dual-Agent Workspace (frisch, isoliert)

> NEUE Memory. Erbt **nichts** aus globaler/alter Memory. Kein ASYA, kein Trading,
> keine alten Projekte. Nur Fakten zu DIESEM Workspace. Bei Widerspruch zu altem
> Kontext: alter Kontext ist Rauschen.

## Projekt
- **Dual-Agent Build-Harness** (Claude Code = Architect/Reviewer, Grok Build = Builder).
- Ort: `C:\Users\Ozan\Desktop\dual-agent`. Lokales git-Repo, nie gepusht.
- Zweck: project-agnostisch Software bauen — Contract (Claude) -> POC (Grok) -> Härtung (Claude).

## Verifizierte Fakten (selbst getestet 2026-06-16)
- `grok -p` / `--prompt-file` laufen auf dem **Grok-Abo (OAuth)**, KEIN xAI-API-Key noetig
  (Beweis: `GROK_OK` / `PROMPTFILE_OK` zurueckgekommen).
- Grok-CLI v0.2.51, `C:\Users\Ozan\.grok\bin\grok.exe`. Flags: `--worktree`, `--best-of-n`,
  `--check`, `--output-format json|plain|streaming-json`, `--always-approve`, `--prompt-file`.
- **No-Cut-Gate (`dual-merge.ps1`) empirisch bewiesen** (3/3): disjunkt->Merge,
  Kollision->Abbruch ohne Overwrite, Verify-rot->Block.
- PS-5.1-Lektion: nie `$?` nach nativem git; `$ErrorActionPreference="Continue"` +
  `$LASTEXITCODE` pruefen (sonst terminiert git-stderr faelschlich).
- **grok `--worktree` greift HEADLESS NICHT** (Grok baut sonst im Main-Tree). Fix: worktree
  selbst anlegen (`git worktree add -b feat/poc <pfad> main`) + Grok mit `--cwd <pfad>` hineinschicken.
- **End-to-End-Loop real bewiesen 2026-06-16:** Contract->Grok-Render(isoliert)->Assess->No-Cut-Gate
  ->Merge. Grok lieferte korrekten Code + unaufgefordert `SUGGESTIONS`. Default-Branch hier ist `main`
  (umbenannt von `master`).

- **Shared MCP verdrahtet (`.mcp.json`, keyless):** playwright (`npx @playwright/mcp`) + fetch
  (`uvx mcp-server-fetch`). Grok liest es (`grok inspect` -> `source: mcpJson`), beide Server starten
  real. Nutzung braucht Grok-Projekt-Trust + CC-`.mcp.json`-Approval (Discovery != Ausfuehrung).
- **`--best-of-n 3` real bewiesen:** Grok fuhr ein 3-Kandidaten-Turnier (isolierte `bon/candidate-*`
  Worktrees, je anderer Algo), waehlte Gewinner per Vergleichstabelle, landete ihn auf `feat/poc`;
  eigene Temp-Worktrees selbst aufgeraeumt (verifiziert).
- **Split-Screen-Cockpit:** `dual-view.ps1` (Windows Terminal, links Claude / rechts Grok-Live-Log
  via `watch-grok.ps1`, das `.dual-agent/logs/grok-*.log` live tailt). `wt` vorhanden, tmux nicht.

- **WIP-Basis-Fix (verifiziert):** `dual-build.ps1` committet uncommittete Arbeit vor dem Render
  automatisch (auf `main` -> neuer `feat/wip-<stamp>`, kein Push, `main` bleibt sauber), `feat/poc`
  branched von HEAD -> Grok sieht tracked+untracked WIP. Test: worktree=WIP-CHANGE+untracked, main=base.

## Protokoll (Kurz)
CRAFT-Loop: Contract -> Render(Grok) -> Assess -> Fortify -> Test. Regeln in `PROTOCOL.md`,
Staffelstab in `HANDOFF.md`. Invarianten: ein Schreiber pro Datei-Raum, getrennte worktrees,
Merge nur via `dual-merge.ps1`, kein falsches "fertig", kein Alt-Kontext.

## Ultimate-Redesign (Entscheid 2026-06-17)
5-Stimmen-Studie (4 Claude-Agenten + Grok) + ECC-Vergleich (Affaan Mustafa, Anthropic-Hackathon-
Gewinner, Repo "Everything Claude Code"). **Kern-Entscheid (Owner bestaetigt):** NICHT
"debate-until-consensus" (research-belegt schaedlich: sykophantische Konformitaet bis ~85%, 2-3x Token)
— sondern **Eval entscheidet (pass^k) + bounded cross-review (1-2 Runden, Kommentarliste)**.
Cross-Vendor-Diversitaet (Claude != Grok) ist der Moat (MoA / PoLL / self-preference-bias belegt).
Amnesie bleibt (kein auto-injected Cross-Build-Memory; Poisoning-Risiko). Nur human-kuratierte Lessons.
Verifizierte neue Bausteine (2026-06-17):
- `lib\grok-call.ps1`: EINE saubere headless-Grok-Huelle. Fix des verifizierten Bugs — stdout(json) und
  stderr(noise) OS-getrennt via Start-Process-Redirects (alter `*>&1|Where`-Filter scheiterte still; Logs
  waren UTF-16LE). Bewiesen: PONG-Lauf, ExitCode 0, NoiseInResult=False.
- Echtes Grok-JSON-Shape: `{text, stopReason, sessionId, requestId, thought}` -> `sessionId` ermoeglicht
  spaeter Multi-Turn via `--resume`. Modelle: nur `grok-build` + `grok-composer-2.5-fast`.
- `lib\eval-harness.ps1`: pass@k / pass^k Scorer. Bewiesen: always-green pass^k=1; flaky 4/8 -> pass@k=1
  pass^k=0 (graded faengt Flake, das binaere Gate durchliesse).
- `dual-build.ps1` nutzt jetzt `lib\grok-call.ps1` (kaputter Inline-Filter entfernt).
- `dual-merge.ps1 -EvalK K`: graded Gate, Merge nur bei pass^k==1 (Default K=1 = altes Verhalten).

## Offen
- `--best-of-n 3` lief frueher als Turnier (s.o. "verifizierte Fakten"), ABER unter dem NEUEN
  `lib\grok-call.ps1` (stdout-json-Capture) noch NICHT verifiziert: liefert N>1 EIN finales JSON oder N?
  -> erster echter Render gegen eine reale PLAN.md muss das zeigen (Phase-1-Acceptance). [loest den frueheren
  MEMORY-Selbstwiderspruch Z.30 vs Z.46 auf: N=3 lief, aber nicht unter dem neuen Capture-Pfad.]
- Naechste Module: `claude-call.ps1` + `dual-review.ps1` (bounded cross-review), `PROTOCOL.md` v2
  (Invarianten 6-8: Eval entscheidet; Grok editiert NIE Tests/Verify, nur `src/`; bounded review),
  Grok-Idee "Vendor-Blind Adversarial Verify", Security (`--sandbox` + Hook-matcher `Bash|PowerShell`),
  voller Merge-Gate-Smoke (blockt empty-branch + rot).
- Hook-Edits (`.no-recap`-Opt-out) liegen im Live-Install `~/.claude`, noch nicht in
  canonical Source `Desktop\CLAUDE_WORKFLOW` gesynct (Drift).

## Zyklus 2-3: Subagents + Forecasting (2026-06-17)
Agents/Subagents-Sweep (4 Claude + Grok) + Forecasting-Sweep (4 Claude + Grok), Anti-Drift/
Halluzination als Pflichtdimension. Konvergenz: unsere Architektur = publiziertes SOTA-Muster
(SLEAN arXiv:2510.10010 "independent -> cross-critique -> arbitration, providers never communicate").
Gebaut + verifiziert (2026-06-17):
- `lib\import-scan.ps1`: deterministischer invented-package Gate (PyPI/npm 404 + PLAN-allowlist,
  fail-closed, ZERO tokens). Verifiziert gegen echte Registries: fake PyPI+npm -> exit 2, stdlib +
  echte Packages durchgelassen, off-contract geblockt (T1-T3 alle gruen).
- `dual-review.ps1`: Abstention-Schema (verdict concede|defend|unsure; defend OHNE citation ->
  auto-downgrade unsure). Anti-Halluzination: Builder gibt zu statt zu bluffen (R-Tuning).
- `AGENTS.md`: vendor-neutraler Builder-Kontrakt. Verifiziert: `grok inspect` listet ihn
  (fileType agents_md) -> cross-vendor lesbar (Codex/Cursor/Gemini/Grok-Standard, Linux Foundation).
Roadmap offen (Forecasting build-now): slopsquat-provenance-tier in import-scan (404 verfehlt
REGISTRIERTE fake-names -> age/popularity via Sonatype MCP); cross-vendor decorrelation-log
(messen ob Claude!=Grok noch verschieden scheitern); OTel-GenAI-Spans; Grok-microVM-sandbox
(Windows: `--sandbox` nur macOS -> kompensieren mit `--deny`/worktree); vendor-adapter-contract dok.
Token-relevant (-> Zyklus 3): **headless-credit-budget-guard** (`claude -p` zieht seit 15.6.2026 aus
SEPARATEM non-rolling pool $20/$100/$200, bei Erschoepfung "requests stop"); Ollama-scout
(`lib\local-call.ps1`, :11434) fuer billige best-of-n Varianten; prompt-caching (stabiler PLAN.md
prefix, -90% cached input); cheap-mode N1/K3 vs standard N3/K5.

## Kontaminations-Hinweis (Root-Cause gefixt 2026-06-16)
- `.no-recap`-Marker hier aktiv -> globale Hooks `session_start.py` (kein Recap injizieren)
  + `session_finalizer.py` (kein `last_session.md` schreiben) ueberspringen dieses Projekt.
  Verifiziert: amnesisch hier, normale Projekte unveraendert. Hook-Backups `.bak-20260616`.
- `mcps/<server>/tools/*.json` = Harness-Tool-Search-Cache (KEIN Hook), per `.gitignore`
  draussen. Falls auf Disk: harmlos, kein Bestandteil dieses Workspace.
