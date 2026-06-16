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

## Protokoll (Kurz)
CRAFT-Loop: Contract -> Render(Grok) -> Assess -> Fortify -> Test. Regeln in `PROTOCOL.md`,
Staffelstab in `HANDOFF.md`. Invarianten: ein Schreiber pro Datei-Raum, getrennte worktrees,
Merge nur via `dual-merge.ps1`, kein falsches "fertig", kein Alt-Kontext.

## Offen
- `--best-of-n > 1` (mehrere Varianten parallel) noch nicht real getestet — nur N=1 lief.
- Hook-Edits (`.no-recap`-Opt-out) liegen im Live-Install `~/.claude`, noch nicht in
  canonical Source `Desktop\CLAUDE_WORKFLOW` gesynct (Drift).

## Kontaminations-Hinweis (Root-Cause gefixt 2026-06-16)
- `.no-recap`-Marker hier aktiv -> globale Hooks `session_start.py` (kein Recap injizieren)
  + `session_finalizer.py` (kein `last_session.md` schreiben) ueberspringen dieses Projekt.
  Verifiziert: amnesisch hier, normale Projekte unveraendert. Hook-Backups `.bak-20260616`.
- `mcps/<server>/tools/*.json` = Harness-Tool-Search-Cache (KEIN Hook), per `.gitignore`
  draussen. Falls auf Disk: harmlos, kein Bestandteil dieses Workspace.
