# Dual-Agent Workflow — Claude Code + Grok Build

Sauberer, **project-agnostischer** Build-Harness. Zwei CLI-Agenten arbeiten zusammen,
jeder auf seinem eigenen Abo — **kein xAI-API-Key, kein Cloud-Tool, kein Memory aus alten Projekten.**

## Rollen

| Agent | Rolle | Stärken |
|---|---|---|
| **Claude Code** | Architect / Reviewer / Hardener | Plan, Contract, kritischer Review, Tests, Security |
| **Grok Build**  | Builder / Explorer | Tempo, kreative POCs, `--best-of-n` Varianten, Subagents |

## CRAFT-Loop

```
C  Contract   Claude schreibt PLAN.md (aus PLAN.template.md) — kein Code
R  Render     dual-build.ps1 -> Grok baut N POC-Varianten im worktree feat/poc
A  Assess     Claude reviewt Groks Diff als untrusted code (Drift? erfundene APIs?)
F  Fortify    Claude härtet: Refactor + Tests + Error-Handling + Doku + Security
T  Test       Akzeptanzkriterien laufen -> Merge nur bei grün
```

## Setup (einmalig)

```powershell
cd $env:USERPROFILE\Desktop\dual-agent
git init; git add -A; git commit -m "init dual-agent harness"
```

## Pro Feature

```powershell
# 1) C — Claude füllt PLAN.md aus dem Template, committen:
Copy-Item PLAN.template.md PLAN.md
#    ... Claude schreibt Contract + Akzeptanzkriterien rein ...
git add PLAN.md; git commit -m "contract: <feature>"

# 2) R — Grok baut 3 Varianten in isoliertem worktree:
.\dual-build.ps1 -Variants 3

# 3) A+F — Claude reviewt + härtet den feat/poc-Branch (Script gibt die Befehle aus)
```

## Modi

- **Automatisiert (Stufe 2):** `dual-build.ps1` ruft `grok -p` als Subprozess. Verifiziert
  lauffähig auf dem Abo (Headless-Antwort kam zurück, kein API-Key).
- **Manuell (Stufe 1):** Zwei Terminals nebeneinander. Grok-Terminal liest PLAN.md selbst.
  Immer als Fallback nutzbar.

## Auth (wichtig)

Funktioniert über dein Grok-**Abo** (OAuth). Falls `grok -p` mal `AuthorizationRequired`
zeigt: einmal `grok login` ausführen. Ein `xAI-API-Key` ist **nicht** nötig.

## Gemeinsame MCP-Tools (Playwright + Fetch)

`.mcp.json` definiert zwei Tools, die **beide** Agenten lesen — **kein API-Key noetig**:
- **playwright** (`npx @playwright/mcp`): Browser steuern, Screenshots, UI-Smoke -> echte Akzeptanz-Evidenz im Verify-Schritt.
- **fetch** (`uvx mcp-server-fetch`): URL -> Text, "research before code".

Verifiziert: Grok entdeckt beide via `grok inspect` (`source: mcpJson`, exakter Pfad);
beide Server-Befehle starten real. Prereqs: `node`/`npx` + `uv`/`uvx` im PATH (Erststart laedt Pakete einmalig).
- **Grok-Trust:** `grok inspect` zeigt `projectTrusted:false` -> Grok *entdeckt* die Server, *laedt* sie
  erst nach Projekt-Trust (einmal `grok` im Ordner starten + bestaetigen).
- **Claude Code:** fragt beim naechsten Start die Freigabe der `.mcp.json`-Server ab (Security-Approval).

## Troubleshooting

- **Error-Spam `AuthorizationRequired ... huggingface.co/.../mcp`:** ein kaputter MCP-Server
  in Groks Config, nicht dein Login. Output kommt trotzdem. Aufräumen: `grok mcp` (Server entfernen).
  Für sauberes Parsen nutzt das Script ohnehin `--output-format json`.
- **`grok exit != 0`:** Refusal oder Tool-Fehler — `.dual-agent/logs/grok-*.log` lesen.
- **Worktree nicht gefunden:** `git worktree list` prüfen; ggf. `git worktree prune`.

## Grenzen / ehrlich

- Die globalen Claude-Code-Hooks (Recap/Klassifizierung) feuern weiter und injizieren ggf.
  alten Kontext. Die lokale `CLAUDE.md` weist Claude an, das zu **ignorieren** — abstellen
  liesse sich das nur per Edit an der globalen Config (hier bewusst nicht angefasst).
- `--always-approve` lässt Grok im worktree autonom Tools ausführen. Akzeptabel, weil isoliert;
  für mehr Härte `--sandbox <profile>` ergänzen.
- **Erster echter Render-Lauf** (`dual-build.ps1` ruft Grok): Pfad-/Arg-Assembly + POC-Auto-Commit
  sind getestet, aber Groks Verhalten unter `--worktree`+`--best-of-n` (committet es selbst? Anzahl
  Varianten-Commits?) erst am echten Lauf bestaetigen.
- **git-Identitaet noetig:** `dual-merge` + POC-Auto-Commit machen Commits. Ohne globale Identitaet
  vorher `git config user.name/.email` setzen (in diesem Workspace lokal bereits gesetzt).
- **`feat/poc`-Wiederverwendung:** existiert Branch/worktree schon, schlaegt `--worktree feat/poc`
  fehl -> vorher `git worktree remove` + Branch loeschen, oder anderen `-Branch` waehlen.
- **Verify im frischen worktree:** laeuft in einem detached worktree ohne `node_modules`/venv/Build-
  Artefakte -> der Verify-Befehl muss self-contained sein (ggf. Install einschliessen).
- **Merge-Gate** wechselt dich nach Erfolg auf `$Into` (main); ggf. danach Branch zurueckwechseln.
- **Worktree-Pfade mit Leerzeichen** werden nicht robust geparst (dieser Workspace-Pfad: ok).
