# HANDOFF — <Feature>  (append-only Staffelstab-Ledger)

> Kopie nach HANDOFF.md pro Feature. Jeder Turn hängt unten an, nichts wird gelöscht.

BATON: claude        # wer gerade handeln darf: claude | grok | gate | done
PHASE: C             # C | R | A | F | T
CONTRACT: PLAN.md
VERIFY_CMD: <z.B. pytest -q   oder   npm test>

---

## Turn-Log (neueste unten)

### [<timestamp>] claude — C (Contract)
- Contract geschrieben. Akzeptanzkriterien: <n>.
- BATON -> grok

### [<timestamp>] grok — R (Render)
- Variante gewählt: <kurz>. Dateien: <liste>.
- SUGGESTIONS FOR ARCHITECT:
  - <Vorschlag 1>
- BATON -> claude

### [<timestamp>] claude — A+F (Assess + Fortify)
- Review: <Drift? erfundene APIs? ok?>
- Gehärtet: Tests <n>, Error-Handling, Doku.
- SUGGESTIONS FOR BUILDER:
  - <Vorschlag 1>
- BATON -> gate

### [<timestamp>] gate — T (Test + Merge)
- Verify: <grün/rot>. Merge feat/harden -> main: <ja/nein>.
- BATON -> done
