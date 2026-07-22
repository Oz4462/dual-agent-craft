# HANDOFF — <Feature>  (append-only Staffelstab-Ledger)

> Kopie nach HANDOFF.md pro Feature. Jeder Turn hängt unten an, nichts wird gelöscht.

BATON: team        # wer gerade handeln darf: claude | grok | codex | team | gate | done
PHASE: W             # C | W | R | G | A | F | T | done
CONTRACT: PLAN.md
VERIFY_CMD: <z.B. pytest -q   oder   npm test>

---

## Turn-Log (neueste unten)

### [<timestamp>] claude — C (Contract)
- Contract geschrieben. Akzeptanzkriterien: <n>.
- BATON -> team  (next phase W)   # default team-work; sonst BATON -> grok/codex (R)

### [<timestamp>] team — W (Team-Work)
- WORK.json: Claude + Grok + Codex path-disjunkte Packages.
- Commits: team(<worker>): WP… [no-push]
- BATON -> gate  (next phase G)

### [<timestamp>] gate — G (Guards)
- import-scan + test-guard (team-aware) + ownership.
- BATON -> claude  (Assess)

### [<timestamp>] claude — A (Assess) + optional F (Fortify)
- Review: <Drift? erfundene APIs?>
- Rebutter = builder-vendor (grok|codex), max 1 Runde.
- BATON -> gate

### [<timestamp>] gate — T (Test + Merge)
- Verify pass^k: <grün/rot>. Merge: <ja/nein>.
- BATON -> done

### [2026-07-22T16:27:39Z] claude — C
- Contract ready: PLAN.md — next team work (all three code)
- phase complete.
- adaptive: builder=codex assessor=claude profile=security team-work=true
- BATON -> team  (next phase W)

### [2026-07-22T17:27:41Z] claude — C
- Contract ready: PLAN.md — next team work (all three code)
- phase complete.
- adaptive: builder=grok assessor=claude profile=minimal team-work=true
- BATON -> team  (next phase W)

### [2026-07-22T17:39:03Z] team — W
- Team packages done (ledger/WORK.json) — Claude+Grok+Codex all worked
- phase complete.
- adaptive: builder=grok assessor=claude profile=minimal team-work=true
- BATON -> gate  (next phase G)

### [2026-07-22T17:50:00Z] claude — C
- Contract ready: PLAN.md — next team work (all three code)
- phase complete.
- adaptive: builder=codex assessor=claude profile=minimal team-work=true
- BATON -> team  (next phase W)
