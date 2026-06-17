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
6. **Der Eval entscheidet, nicht Konsens.** Merge-Freigabe und Streitschlichtung kommen vom
   objektiven Eval (`pass^k` — alle K Läufe grün), nie von gegenseitiger Zustimmung. Cross-Review
   ist auf **eine** Rebuttal-Runde gedeckelt (kein Rhetorik-Loop), danach entscheidet der Test.
   (Research-Grund: „debate-until-consensus" erzeugt sykophantischen Falsch-Konsens; der Eval ist
   der einzige Schiedsrichter, den kein Agent per Argument überschreiben kann.)
7. **Grok editiert NIE Tests/Verify.** In `feat/poc` schreibt Grok nur Implementierung (`src/` o.ä.),
   niemals Test-/Verify-Dateien. Sonst gamed der Builder das Gate (Tests lockern statt Code fixen).
   Tests sind für Grok untrusted-input; Claude pinnt `verify/acceptance` vor dem Build.
8. **Subjektives Patt → Mikro-Probe, nicht Endlos-Debatte.** Defended + nicht-eval-entscheidbare
   Issues löst `dual-tiebreak.ps1` (Wahl c): Grok baut BEIDE Varianten isoliert, der Eval misst den
   Sieger. Der gemessene Gewinner zählt, keine Meinung, kein Dauermediator-Mensch.

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

## Bounded Cross-Review + Eval-Schiedsrichter (v2, 2026-06-17)

CRAFT-Schritt **A** ist jetzt eine **bounded cross-review** (`dual-review.ps1`), KEIN
„debate-until-consensus". Zwei verschiedene Vendoren (Claude != Grok) brechen korrelierte
Fehler + self-preference bias; der **Eval** ist die Wahrheit, nicht die Einigung:

    A1 Assess    Claude reviewt Groks Diff als untrusted code  -> issues[]   (JSON)
    A2 Rebuttal  Grok antwortet EINMAL: concede | defend+Beleg -> rebuttals[] (JSON)  [HARTER CAP]
    A3 Klassif.  conceded            -> Grok fixt im naechsten Build
                 defended+decidable  -> der Eval (pass^k) entscheidet, kein weiterer Streit
                 defended+subjektiv  -> Tie -> dual-tiebreak.ps1 (Mikro-Probe + Eval, Wahl c)
    T  Gate      dual-merge.ps1 -EvalK K   (Merge nur bei pass^k == 1)

Bausteine (verifiziert 2026-06-17): `lib\grok-call.ps1` + `lib\claude-call.ps1` (saubere
headless-Hüllen, stdout/stderr OS-getrennt), `lib\eval-harness.ps1` (pass@k / pass^k),
`dual-review.ps1` (bounded review), `dual-merge.ps1 -EvalK` (graded Gate). Offen: `dual-tiebreak.ps1`
(Wahl c) + Security-Pass (`--sandbox`, Hook-Matcher `Bash|PowerShell`) + erster echter End-to-End-Build.
