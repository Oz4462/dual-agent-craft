# PLAN — Pure-Stdlib Multiply

> Claude füllt das aus. Grok baut strikt dagegen. Kein Code in diesem File.
> Dieser Build kennt KEINEN Kontext ausser dem, was hier steht.

## 1. Problem
Es soll eine minimale, reine Python-Funktion `multiply(a, b)` gebaut werden, die das Produkt zweier Zahlen zurückgibt. Dazu gehören Unit-Tests, die mindestens den Happy Path (2·3=6) und Null-Fälle abdecken. Kein weiterer Funktionsumfang.

## 2. Stack / Constraints
- Sprache/Framework: Python 3.10+ (getestet gegen die vorhandene System-Python-3-Installation), Tests mit `unittest` aus der stdlib
- Erlaubte Dependencies: stdlib only (`unittest`; optional `typing`-Konstrukte)
- Verbote: keine Netzwerkzugriffe, keine Subprozesse, keine Secrets, keine globalen Installs, keine Third-Party-Packages (kein pytest), kein Zugriff auf `os.environ`, keine Dateisystem-Schreibzugriffe zur Laufzeit

## 3. Interface-Contract (die einzige Wahrheit, die beide teilen)
Dateien (relativ zur Build-Wurzel):
- `multiply.py` — enthält ausschliesslich die Funktion `multiply` (plus optional Docstring/Type-Hints)
- `tests/test_multiply.py` — `unittest`-Testfälle gegen `multiply.py`

```
# multiply.py
# function multiply(a: int | float, b: int | float) -> int | float
#   - a, b: numerische Werte (int oder float); keine Typkonvertierung von Strings
#   - returns: das arithmetische Produkt a * b
#   - raises: TypeError bei nicht-numerischen Argumenten (z.B. str, None, list) —
#     das native TypeError des *-Operators genügt; kein eigenes Exception-Handling nötig
#   - keine Seiteneffekte, kein I/O, kein globaler Zustand

# tests/test_multiply.py
# class TestMultiply(unittest.TestCase) mit Testmethoden gemäss Abschnitt 5
# Ausführbar via: python3 -m unittest discover -s tests
```

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] `python3 -c "from multiply import multiply; assert multiply(2, 3) == 6"` läuft ohne Fehler durch
- [ ] `python3 -c "from multiply import multiply; assert multiply(0, 5) == 0 and multiply(5, 0) == 0"` läuft ohne Fehler durch
- [ ] `python3 -m unittest discover -s tests` beendet sich mit Exit-Code 0 und mindestens 3 ausgeführten Tests
- [ ] `grep -E "socket|urllib|http|requests|subprocess|os\.environ" multiply.py tests/test_multiply.py` liefert keinen Treffer (Exit-Code 1)
- [ ] `multiply.py` enthält keine `import`-Statements ausser optional `typing`-Konstrukten

## 5. Test-Liste (Claude härtet diese in Schritt F)
- Happy path: `multiply(2, 3) == 6`
- Null-Fälle: `multiply(0, 5) == 0`, `multiply(5, 0) == 0`, `multiply(0, 0) == 0`
- Negative Zahlen: `multiply(-2, 3) == -6`, `multiply(-2, -3) == 6`
- Float: `multiply(2.5, 4) == 10.0` (exakte Binärwerte, kein Rundungs-Epsilon nötig)
- Fehlerfall / Fail-closed: `multiply("2", 3)` und `multiply(None, 3)` lösen `TypeError` aus (via `assertRaises`)

## 6. Out of Scope
- Keine CLI, kein `argparse`, kein `__main__`-Block
- Keine Eingabe-Parsing- oder String-zu-Zahl-Konvertierung
- Keine Unterstützung für `Decimal`, `Fraction`, `complex` oder NumPy-Typen (werden weder getestet noch explizit abgelehnt)
- Kein Logging, keine Konfiguration, keine Packaging-Artefakte (`pyproject.toml`, `setup.py`)
- Keine Performance-Optimierung, keine Overflow-Behandlung (Python-int ist beliebig gross)
- Keine weiteren Module oder Hilfsfunktionen über `multiply` hinaus

