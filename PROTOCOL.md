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
   **Deterministisch erzwungen** durch `lib/test-guard.sh` (Diff-Scan, fail-closed, zero tokens) —
   via `dual-merge.sh --test-guard` oder standalone.
8. **Subjektives Patt → Mikro-Probe, nicht Endlos-Debatte.** Defended + nicht-eval-entscheidbare
   Issues löst `dual-tiebreak.sh` (Wahl c): Grok baut BEIDE Varianten isoliert, der Eval misst den
   Sieger. Der gemessene Gewinner zählt, keine Meinung, kein Dauermediator-Mensch. **Implementiert**
   (`ledger/TIEBREAK.json`; Ranking: pass^k, dann passes, dann Wall-Clock).

## Rollen-Aufteilung (wer macht was) — adaptiv

**Baseline (Standard-Profil)** — gilt, wenn nichts spezielles am Task/PLAN hängt:

| Phase | Function | Default-Agent | Worktree/Branch | Output |
|---|---|---|---|---|
| C — Contract | architect | **Claude** | `main` (nur PLAN.md) | `PLAN.md` |
| R-pre | scout (optional) | **Ollama** | — | $0 first pass, never merge-gating |
| R — Render | builder | **Grok** (oder **Codex** wenn sandbox/security) | `feat/poc` | POC |
| G — Guards | guards | **Gate** (deterministisch) | — | import-scan, test-guard, ownership |
| A — Assess | assessor | **Claude** (≠ builder-vendor) | read-only | `ledger/REVIEW.*` |
| A2 | rebutter | = builder | — | genau 1 Rebuttal |
| F — Fortify | hardener | **Claude** (wenn Profil/ fortify) | `feat/harden` | Tests, Harden |
| F+ | security | **Claude** (wenn risk high) | `feat/harden` | Threat/Security |
| T — Test | arbiter | **Gate / Eval** | merge | `pass^k` only |

### Phase W — Team Work (alle drei arbeiten)

Nach dem PLAN delegiert der Architect **nicht nur**: Claude, Grok und Codex bekommen
**path-disjunkte Work Packages** (`ledger/WORK.json` via `lib/team-dispatch.sh`) und **jeder codet**.

| Worker | Typische Pakete |
|---|---|
| **Claude** | Tests/Verify + mind. 1 Impl/Security-Paket (Architect + Worker) |
| **Grok** | Core happy-path Impl |
| **Codex** | Edge/risky I/O / sandbox-nahe Impl |

```bash
./lib/team-dispatch.sh run --plan PLAN.md --task "…"          # live
./lib/team-dispatch.sh run --plan PLAN.md --dry-run           # roster only
./dual-run.sh --verify "…"                                    # C→W→G→A→… (default)
./dual-run.sh --no-team-work --verify "…"                     # alter Mono-Builder-Pfad
```

**Adaptiv (erweitert):** `config/roles.json` + `lib/role-router.sh` wählen Profil und Agents aus
Task/PLAN-Signalen und mid-run REVIEW:

| Profil | Wann (Signale) | builder | fortify | scout | security |
|---|---|---|---|---|---|
| `minimal` | tiny/spike, low risk | grok | off | off | off |
| `standard` | default | grok | off | off | off |
| `thorough` | distributed/migration/complex | grok | on | on | on |
| `security` | auth/secret/payment/token | **codex** | on | off | on |
| `sandbox` | shell/filesystem/network risk | **codex** | on | off | on |

```bash
./dual-run.sh --who --task "add OAuth payment"     # show matrix
./lib/role-router.sh profiles
./lib/role-router.sh explain --task "…"
```

Hard invariants (nie adaptiv überschreibbar): assessor-vendor ≠ builder-vendor · arbiter=gate ·
builder ediert keine Tests · max 1 Rebuttal · scout nie merge-gating.

Grok und Claude editieren **nie gleichzeitig dieselbe Datei**: Baton + exclusive dual-run lock.

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

**Empfohlen (bash, ein Kommando):** `./dual-run.sh --verify "<test-cmd>"`  
orchestriert C→R→G→A→[F]→T mit exclusive lock + BATON. Fine-tuning:
`config/coordination.json` (Rollen, Ownership-Globs, Defaults, anti_overlap).
Maschinenzustand: `.dual-agent/run-state.json`. Menschliches Ledger: `HANDOFF.md`.

```
1. Claude:  PLAN.md schreiben + committen, BATON -> team (Phase W)
2. Team  :  team-dispatch (Claude+Grok+Codex path-disjunkt), BATON -> gate
   (alt: --no-team-work → Grok/Codex mono dual-build.sh auf feat/poc)
3. Gate :   import-scan + test-guard (team-aware) + ownership (deterministisch)
4. Claude:  dual-review.sh (Assess + 1 Rebuttal via builder-vendor), optional Fortify
5. Gate :   dual-merge.sh --verify ... --eval-k K --test-guard
6. Alle:    SUGGESTIONS in HANDOFF.md -> naechster PLAN.md
```

**HANDOFF-Wahrheit:** `BATON`/`PHASE` im Header = nächster Holder (run-state), nicht der Static-Config-Default.
Nach C mit Team-Work: `BATON: team`, `PHASE: W`.

Anti-Overlap (strukturell, nicht nur Prompt):
- **Exclusive dual-run lock** — zweites `./dual-run.sh` blockt, solange eines live ist.
- **BATON** — Agent darf nur handeln, wenn er den Stab hält (`run-state` + `HANDOFF.md`).
- **Eine Phase gleichzeitig** — phase machine in `lib/coordination.sh`.
- **Ownership** — Grok-never-list (tests/, PLAN harness surfaces, dual-*.sh, …);
  orchestration files (HANDOFF, .dual-agent, ledger) sind exempt.

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

Bausteine (verifiziert 2026-06-17, Windows): `grok-call` + `claude-call` (saubere headless-Hüllen,
stdout/stderr OS-getrennt), `eval-harness` (pass@k / pass^k), `dual-review` (bounded review),
`dual-merge --eval-k` (graded Gate).

## Linux/bash-Port (v3, 2026-07-21)

Die Harness ist jetzt **bash-first** (Linux/macOS); die verifizierte Windows-PS-5.1-Variante liegt
unverändert in `powershell/`. Neu gegenüber v2:

- `dual-tiebreak.sh` — Invariante 8 **implementiert** (war zuvor nur referenziert).
- `lib/test-guard.sh` — Invariante 7 **deterministisch erzwungen** (war zuvor nur Prompt-Text).
- `lib/codex-call.sh` — dritter Vendor (OpenAI Codex, `codex exec`): echte `-s`-Sandbox auf Linux,
  sauberes Resultat via `-o` last-message. Adapter-Contract identisch (`ADAPTERS.md`).
- `import-scan`-Fixes: `__future__`/relative Imports nie mehr als "invented" geflaggt;
  Registry via `IMPORT_SCAN_REGISTRY_BASE` stubbar (offline-deterministische Tests).
- **49 bats-Tests** (`tests/run.sh`) decken alle deterministischen Module + die 3
  No-Cut-Invarianten + die Adapter-Contracts (gestubbte CLIs, keine billed calls) ab; CI via
  GitHub Actions.
