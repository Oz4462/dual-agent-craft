# Coordination Protocol — "No-Cut" Dual-Agent (Claude + Grok)

> Das eigene Herzstück: zwei Agenten, die sich **strukturell nie schneiden können**,
> die Arbeit klar aufteilen und sich **gegenseitig verbessern**. Sequentieller
> Staffelstab + getrennte worktrees + Merge-Gate, das bei Konflikt abbricht.

## Invarianten (dürfen NIE verletzt werden)

1. **Ein Schreiber pro Datei-Raum.** Grok schreibt nur in worktree `feat/poc`,
   Claude nur in `feat/harden`. `main` ist reine Merge-Zone — dort schreibt niemand direkt.
2. **Staffelstab (Baton).** Es handelt immer nur **ein** Agent. Wer dran ist, steht in
   `HANDOFF.md` (Feld `BATON`). Kein Agent startet, ohne den Baton zu halten.
3. **Kein stilles Überschreiben.** Zusammenführung nur via `dual-merge.ps1`. Bei git-Konflikt
   wird abgebrochen (`merge --abort`), nie automatisch aufgelöst.
4. **Kein falsches "fertig".** Merge in `main` nur, wenn die Akzeptanz-Kriterien (Verify-Command)
   grün sind. Rot = Block, kein Merge.
5. **Kein Alt-Kontext.** Jeder Build kennt nur seine `PLAN.md`. Kein Memory, keine Secrets.

## Rollen-Aufteilung (wer macht was)

| Phase | Agent | Worktree/Branch | Output |
|---|---|---|---|
| C — Contract | **Claude** | `main` (nur PLAN.md) | `PLAN.md` (Contract + Akzeptanz) |
| R — Render   | **Grok**   | `feat/poc`  | POC-Varianten (`--best-of-n`), beste gewinnt |
| A — Assess   | **Claude** | liest `feat/poc` read-only | Review-Report im Ledger |
| F — Fortify  | **Claude** | `feat/harden` (gebrancht von `feat/poc`) | Tests, Error-Handling, Doku, Security |
| T — Test     | **Gate**   | `dual-merge.ps1` | Merge `feat/harden` → `main` nur bei grün |

Grok und Claude editieren **nie gleichzeitig dieselbe Datei**: Grok ist fertig (Baton zurück),
bevor Claude `feat/harden` aus `feat/poc` branched.

## Gegenseitige Verbesserung (der Compounding-Kanal)

Jeder Agent beendet seinen Turn mit einem Vorschlags-Block im `HANDOFF.md`:

- **Grok → Architect:** "Im Contract war X unterspezifiziert / Y wäre einfacher / Z ist ein Risiko."
- **Claude → Builder:** "Pattern P nächstes Mal direkt nutzen / Anti-Pattern Q vermeiden."

Diese Vorschläge fließen in den nächsten `PLAN.md` ein → das System wird mit jedem Build besser.

## Konflikt-Fall (wenn doch mal Überlappung droht)

`dual-merge.ps1` meldet **vor** dem Merge, welche Dateien beide Seiten angefasst haben
(Ownership-Report). Bei echtem Zeilen-Konflikt: Merge bricht ab, Mensch entscheidet.
Niemals "der Letzte gewinnt".

## Ablauf (eine Runde)

```
1. Claude:  PLAN.md schreiben + committen, BATON -> grok
2. Grok :   dual-build.ps1            (baut feat/poc), BATON -> claude
3. Claude:  Review feat/poc, dann feat/harden bauen
4. Gate :   dual-merge.ps1 -Verify "<test-cmd>"   (feat/harden -> main bei grün)
5. Beide:   SUGGESTIONS in HANDOFF.md -> naechster PLAN.md
```
