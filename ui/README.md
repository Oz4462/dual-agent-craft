# Dual-Craft Team-Cockpit (Chat-UI)

Lokale **Task-Chat-Oberfläche** für den Dual-Agent-Harness.
Aufgaben in Alltagssprache eintippen; der Server leitet sie über `dual-run.sh`
an das Team (Claude · Grok · Codex) — mit Live-Status, Pipeline und Logs.

## Start

```bash
# aus dem Repo-Root
./dual-chat.sh                     # http://127.0.0.1:8787/  (öffnet Browser)
./dual-chat.sh --daemon --no-open  # Hintergrund, ohne Browser
./dual-chat.sh --status            # läuft er?
./dual-chat.sh --stop              # beenden
```

Wichtig: die Seite über **http://127.0.0.1:8787/** öffnen, **nicht** per `file://`.

## Was bedeutet was? (Transparenz)

| Aktion | Wirkung |
|---|---|
| **Vorschau** | Nur Rollen-Zuweisung (Who-Matrix). Es startet **kein** Lauf, nichts wird gespeichert. |
| **Dry-Run** | Lauf ohne echte Schreibzugriffe — Pakete werden nur `dry-ok` markiert, **kein Code**. |
| **Starten** (echt) | Worker schreiben Dateien; der Harness committet lokal (`[no-push]`). |
| **Merge überspringen** (Default) | Ergebnis bleibt auf dem Arbeits-Branch — `main` wird **nicht** verändert. |

Nach jedem echten Team-Lauf zeigt das Cockpit einen **Persistenz-Check**:
er vergleicht `ledger/WORK.json` mit der git-Realität und **warnt**, wenn ein
Paket „done" ist, aber weder ein team-Commit noch geänderte Dateien existieren
(Worker-CLI mit Exit 0, aber ohne Writes).

## Funktionen

- Chat-first-Cockpit: Chat · Vorlagen · Who-Matrix · Arbeitspakete · Live-Log (SSE)
- Modus-Chips in der Mission-Leiste: echt / Dry-Run · Merge / kein main-Merge · Team / Solo
- Profile: `auto` / `minimal` / `standard` / `thorough` / `security` / `sandbox`
- Optionen (progressive disclosure): Auto-Plan, Team-Arbeit, Merge überspringen, Dry-Run, Härten, Verify
- Lauf stoppen (SIGTERM), Verlauf unter `.dual-agent/chat/history.jsonl`

## Sicherheit

- Bindet standardmäßig **127.0.0.1** (nur lokal; `DUAL_CHAT_ALLOW_REMOTE=1` nur, wenn du weißt warum)
- **Keine API-Keys** in der UI — nutzt die lokalen CLI-Logins
- Kein Datei-Browser-API, Path-Traversal-Schutz für Statics

## API (lokal)

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/api/health` | Liveness |
| GET | `/api/status` | git, Sperre, Ledger, CLIs, aktiver Lauf (inkl. Modus) |
| GET | `/api/who?task=` | adaptive Rollen-Zuweisung |
| GET | `/api/persistence` | Persistenz-Check (WORK.json vs. git) |
| GET | `/api/history` | Chat-Verlauf |
| POST | `/api/chat` | Nachricht + optionaler Lauf (`preview_only`, `dry_run`, …) |
| POST | `/api/runs` | Lauf starten |
| GET | `/api/runs/{id}/stream` | SSE-Live-Log |
| POST | `/api/runs/{id}/cancel` | SIGTERM |

## Tests

```bash
python3 tests/chat_ui_test.py
```
