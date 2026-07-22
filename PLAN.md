# PLAN — Pure-Stdlib Multiply

> Claude füllt das aus. Grok baut strikt dagegen. Kein Code in diesem File.
> Dieser Build kennt KEINEN Kontext ausser dem, was hier steht.

## 1. Problem
Baue eine minimale, reine Python-Funktion `multiply(a, b)`, die das Produkt zweier Zahlen zurückgibt. Dazu gehören Unit-Tests, die mindestens den Happy Path (2·3 = 6) und den Null-Fall abdecken. Kein weiterer Funktionsumfang.

## 2. Stack / Constraints
- Sprache/Framework: Python 3.10+ (getestet gegen die im Workspace installierte `python3`-Version)
- Erlaubte Dependencies: stdlib only (Tests mit `unittest` aus der stdlib)
- Verbote: keine Third-Party-Packages, keine Netzwerkzugriffe (kein `socket`, `urllib`, `http`, `requests`), keine Secrets/Env-Var-Zugriffe, keine Datei-I/O, keine globalen Installs, kein `print` in der Bibliotheksfunktion

## 3. Interface-Contract (die einzige Wahrheit, die beide teilen)

```
# Datei: multiply.py (Repo-Root)
# function multiply(a: int | float, b: int | float) -> int | float
#   - a, b: Zahlen (int oder float; bool zählt NICHT als gültige Zahl)
#   - returns: das arithmetische Produkt a * b
#     - int * int  -> int
#     - sonst      -> float (Standard-Python-Semantik von `*`)
#   - raises: TypeError mit aussagekräftiger Message, wenn a oder b
#     kein int/float ist (inkl. bool, None, str, list, ...) — fail-closed,
#     KEINE implizite Konvertierung (kein `int(a)`, kein Duck-Typing)
#   - keine Seiteneffekte: kein I/O, kein Logging, kein globaler Zustand
#
# Datei: tests/test_multiply.py
#   - unittest.TestCase-basierte Tests gegen `from multiply import multiply`
#   - lauffähig via: python3 -m unittest tests.test_multiply -v
#     (tests/__init__.py anlegen, falls für den Import nötig)
```

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] `python3 -m unittest tests.test_multiply -v` läuft mit Exit-Code 0 und ≥ 4 Tests
- [ ] Ein Test belegt `multiply(2, 3) == 6`
- [ ] Tests belegen den Null-Fall: `multiply(0, 5) == 0` und `multiply(7, 0) == 0`
- [ ] Ein Test belegt, dass `multiply("2", 3)` und `multiply(True, 3)` jeweils `TypeError` auslösen
- [ ] `multiply.py` enthält keinerlei `import`-Statements ausser optional `typing`-Konstrukten; `grep -E "socket|urllib|http|requests|subprocess|os\.environ" multiply.py tests/test_multiply.py` liefert keinen Treffer
- [ ] Nur die Dateien `multiply.py`, `tests/test_multiply.py` (und ggf. `tests/__init__.py`) werden angelegt/geändert

## 5. Test-Liste (Claude härtet diese in Schritt F)
- Happy path: `multiply(2, 3) == 6`
- Null-Fälle: `multiply(0, 5) == 0`, `multiply(7, 0) == 0`, `multiply(0, 0) == 0`
- Negative Zahlen: `multiply(-2, 3) == -6`
- Float: `multiply(2.5, 4) == 10.0` (Rückgabetyp float)
- Fehlerfall / fail-closed: `TypeError` für `str`, `None`, `list`, `bool` als Argument (beide Positionen)

## 6. Out of Scope
- Keine CLI, kein `argparse`, kein `__main__`-Entrypoint
- Keine Unterstützung für `Decimal`, `Fraction`, `complex` oder NumPy-Typen
- Kein Overflow-Handling jenseits von Python-int-Semantik (beliebige Präzision ist ok)
- Keine Logging-, Config- oder Package-Struktur (`setup.py`/`pyproject.toml`)
- Keine Performance-Optimierung, kein Caching
- Keine weiteren mathematischen Operationen (add, divide, ...)

