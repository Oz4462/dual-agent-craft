# PLAN — VerdiScan Verdict Stage (scan → product → warn)

> Claude füllt das aus. Grok baut strikt dagegen. Kein Code in diesem File.
> Dieser Build kennt KEINEN Kontext ausser dem, was hier steht.

## 1. Problem

VerdiScan verwandelt einen untrusted Barcode-Scan in ein Produkt-Urteil (scan → product → warn). Die Scan-Stufe existiert bereits in diesem Workspace (`src/pkg00/barcode.py`, `normalize_barcode` — gegeben, wird nicht angefasst). Dieser Build ergänzt die Verdict-Stufe: kanonischen Code gegen einen In-Memory-Produktkatalog auflösen und ein fail-closed Urteil `ok` / `warn` / `unknown` / `invalid` mit maschinenlesbaren Gründen liefern. (Hinweis fürs Protokoll: Remote-Repo und lokaler Checkout `/home/genesis/verdiscan` sind aus dieser Session permission-blockiert; dieser Contract baut deshalb ausschliesslich auf der im Workspace vorhandenen pkg00-Primitive auf — nichts über Remote-Code wird geraten.)

## 2. Stack / Constraints

- Sprache/Framework: Python 3.12, reine Library (kein Framework)
- Erlaubte Dependencies: stdlib only; zusätzlich genau ein interner Import: `pkg00.barcode.normalize_barcode` (gegeben, read-only)
- Verbote:
  - kein Netzwerk, kein File-I/O, keine Secrets, kein globaler mutabler Zustand
  - Builder schreibt **ausschliesslich** unter `src/pkg06/` (neu; pkg00–pkg05, `src/app.py`, `tests/`, `verify/` sind fremdes Eigentum und tabu)
  - kein `print`, kein Logging, kein stiller `except`

## 3. Interface-Contract (die einzige Wahrheit, die beide teilen)

Neue Dateien: `src/pkg06/__init__.py` (re-exportiert `evaluate_scan`, `ScanVerdict`) und `src/pkg06/verdict.py`.

```
# GEGEBEN (existiert bereits, nur importieren, niemals ändern):
# from pkg00.barcode import normalize_barcode
#   normalize_barcode(raw: str) -> str | None
#     - trimmt Whitespace; akzeptiert nur reine Ziffern-Strings der Länge 8/12/13
#       mit gültiger GS1-Prüfziffer; UPC-A (12) -> EAN-13 mit führender Null
#     - ungültig -> None; raw kein str -> TypeError

# ZU BAUEN in src/pkg06/verdict.py:

# @dataclass(frozen=True)
# class ScanVerdict:
#     status: str                # exakt einer von: "ok" | "warn" | "unknown" | "invalid"
#     code: str | None           # kanonischer EAN-13/EAN-8; None genau bei status "invalid"
#     reasons: tuple[str, ...]   # sortiert, dedupliziert, normalisiert; leer ausser bei "warn"

# def evaluate_scan(
#     raw: str,
#     catalog: Mapping[str, Mapping[str, object]],
#     flagged_tags: Iterable[str],
# ) -> ScanVerdict

# Eingabe-Gates (fail-closed, Reihenfolge verbindlich):
#   1. raw kein str          -> TypeError (propagiert aus normalize_barcode, nicht fangen)
#   2. catalog keine collections.abc.Mapping                    -> TypeError
#   3. flagged_tags nicht iterierbar ODER enthält Nicht-str     -> TypeError
#      (beliebiges Iterable erlaubt — list/set/tuple/Generator; wird genau einmal konsumiert)

# Ablauf:
#   4. code = normalize_barcode(raw)
#      code is None                -> ScanVerdict("invalid", None, ())
#   5. code not in catalog         -> ScanVerdict("unknown", code, ())
#      (Lookup ist exakter String-Match auf kanonischen Code; Katalog-Keys MÜSSEN
#       kanonisch sein — ein 12-stelliger UPC-A-Key matcht nie)
#   6. record = catalog[code]
#      record keine Mapping                                   -> ValueError (Message enthält code)
#      tags = record.get("tags", ()); muss Iterable von str sein;
#      ein blanker str als tags-Wert gilt als malformed        -> ValueError (Message enthält code)
#      alle anderen record-Keys (z.B. "name") werden ignoriert
#   7. Normalisierung beidseitig: tag.strip().casefold();
#      leere Strings nach Normalisierung werden beidseitig ignoriert
#   8. matched = sortierte, deduplizierte Schnittmenge(normalisierte tags, normalisierte flagged_tags)
#      matched nicht leer -> ScanVerdict("warn", code, tuple(matched))
#      sonst              -> ScanVerdict("ok",   code, ())

# Garantien: pure Funktion — deterministisch, mutiert weder catalog noch flagged_tags,
# kein I/O. ScanVerdict ist frozen (Attribut-Zuweisung -> dataclasses.FrozenInstanceError).
```

## 4. Akzeptanzkriterien (verifizierbar, binär)

Alle Kommandos aus dem Repo-Root, `src/` auf dem `sys.path` (Konvention wie `tests/test_app_surface.py`).

- [ ] Import: `python3 -c "import sys; sys.path.insert(0,'src'); from pkg06 import evaluate_scan, ScanVerdict"` → Exit 0
- [ ] Invalid: `evaluate_scan("1234567", {}, ())` → `ScanVerdict("invalid", None, ())` (ebenso für falsche Prüfziffer und Nicht-Ziffern)
- [ ] Unknown: `evaluate_scan("4006381333931", {}, ())` → `ScanVerdict("unknown", "4006381333931", ())`
- [ ] Ok: `evaluate_scan("4006381333931", {"4006381333931": {"name": "x", "tags": ["vegan"]}}, ["gluten"])` → `status == "ok"`, `reasons == ()`
- [ ] Warn + Kanonisierung + Case/Whitespace-Insensitivität: `evaluate_scan("  036000291452 ", {"0036000291452": {"tags": ["Gluten", "soy"]}}, {"GLUTEN ", "soy"})` → `ScanVerdict("warn", "0036000291452", ("gluten", "soy"))`
- [ ] TypeError: `evaluate_scan(None, {}, ())`, `evaluate_scan("96385074", [], ())` und `evaluate_scan("96385074", {}, [5])` werfen jeweils `TypeError`
- [ ] ValueError: `evaluate_scan("96385074", {"96385074": {"tags": "gluten"}}, ())` und `evaluate_scan("96385074", {"96385074": 7}, ())` werfen jeweils `ValueError`, Message enthält `96385074`
- [ ] Immutabilität: Attribut-Zuweisung auf einem `ScanVerdict` wirft `dataclasses.FrozenInstanceError`
- [ ] Purity-Guard: `grep -RInE "socket|urllib|http|requests|subprocess|open\(" src/pkg06/` → leer
- [ ] Ownership: Builder-Diff berührt ausschliesslich `src/pkg06/`

## 5. Test-Liste (Claude härtet diese in Schritt F)

- Happy path `ok`: Produkt im Katalog, keine Tag-Schnittmenge
- `warn` mit mehreren Treffern → Gründe sortiert + dedupliziert (`["Soy","soy ","Gluten"]` ∩ `["SOY","gluten"]` → `("gluten","soy")`)
- `unknown`: gültiger Code, leerer Katalog / Code nicht enthalten
- `invalid`-Varianten: falsche Prüfziffer, Länge 7/11/14, Nicht-Ziffern, Leerstring
- Whitespace-Trim + UPC-A→EAN-13-Kanonisierung vor dem Lookup (12-stelliger Katalog-Key matcht nie)
- Leere Tags nach Normalisierung (`""`, `"  "`) erzeugen nie einen Match
- TypeError: raw non-str (None, int, bytes, list); catalog non-Mapping; flagged_tags non-iterable und mit Nicht-str-Element
- ValueError fail-closed: record keine Mapping; `tags` als blanker str; `tags`-Liste mit Nicht-str-Element — nie stilles `ok` auf Garbage
- Purity: identischer Aufruf zweimal → gleiche Ergebnisse; catalog nach Aufruf unverändert
- Frozen-Dataclass: Mutationsversuch wirft

## 6. Out of Scope

- Kein Netzwerk-Produkt-Lookup (kein OpenFoodFacts, kein Zugriff auf das VerdiScan-Backend/-Repo)
- Kein Laden des Katalogs von Platte/DB — der Aufrufer übergibt die Mapping; keine Persistenz
- Kein CLI, keine UI, kein HTTP-Endpoint
- Keine Änderungen an pkg00–pkg05, `src/app.py`, `tests/`, `verify/` durch den Builder; Integration in die App-Surface (`src/app.py`-Re-Export + Pin-Tests) erfolgt erst in Schritt F/Integrate durch Claude
- Keine neuen Barcode-Symbologien (nur was pkg00 akzeptiert: EAN-8, UPC-A, EAN-13); keine GTIN-14/ITF-14
- Keine Severity-Stufen, kein Scoring, keine Lokalisierung der Gründe
- Keine Wiederherstellung des Zugriffs auf `/home/genesis/verdiscan` (separates Harness-Thema, nicht Teil dieses Builds)

