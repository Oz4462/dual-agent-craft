# PLAN — multiply (Pure-stdlib Python)

> Claude füllt das aus. Grok baut strikt dagegen. Kein Code in diesem File.
> Dieser Build kennt KEINEN Kontext ausser dem, was hier steht.

## 1. Problem
Es soll eine minimale, reine Python-Funktion `multiply(a, b)` gebaut werden, die das Produkt zweier Zahlen zurückgibt. Dazu gehören Unit-Tests, die mindestens den Happy Path (`2 * 3 = 6`) und die Null-Fälle abdecken. Keine weitere Funktionalität.

## 2. Stack / Constraints
- Sprache/Framework: Python 3.12, Tests mit stdlib `unittest` (Ausführung via `python -m unittest` oder `pytest`, falls lokal vorhanden — der Testcode selbst importiert nur stdlib)
- Erlaubte Dependencies: stdlib only (in `multiply.py` selbst: keinerlei Imports ausser optional `typing`)
- Verbote:
  - Keine Netzwerkzugriffe (kein `socket`, `urllib`, `http`, `requests`)
  - Keine Prozess-/System-Aufrufe (kein `subprocess`, kein `os.environ`-Zugriff)
  - Keine Secrets, keine Dateisystem-Schreibzugriffe zur Laufzeit
  - Keine globalen Installs, kein `pip install`
  - Keine zusätzlichen Dateien ausser den unter Abschnitt 3 genannten

## 3. Interface-Contract (die einzige Wahrheit, die beide teilen)
Dateien (exakt diese, keine weiteren):
- `multiply.py` — Implementierung
- `tests/test_multiply.py` — Unit-Tests
- optional `tests/__init__.py` (leer), falls für die Test-Discovery nötig

```
# multiply.py
# function multiply(a: int | float, b: int | float) -> int | float
#   - a, b: Zahlen vom Typ int oder float. bool gilt NICHT als Zahl
#     (obwohl bool eine int-Subklasse ist) und wird abgelehnt.
#   - returns: das Produkt a * b. Typ folgt Python-Semantik
#     (int * int -> int, sonst float).
#   - raises: TypeError, wenn a oder b kein int/float ist
#     (z.B. str, None, bool, list). Fail-closed: keine implizite
#     Konvertierung, kein Duck-Typing über __mul__.
#   - Nebenwirkungen: keine (pur, deterministisch, kein I/O).
```

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] `python -m unittest discover -s tests -v` läuft grün (Exit-Code 0)
- [ ] Ein Test belegt `multiply(2, 3) == 6`
- [ ] Tests belegen die Null-Fälle: `multiply(0, 5) == 0`, `multiply(7, 0) == 0`, `multiply(0, 0) == 0`
- [ ] Ein Test belegt, dass `multiply("2", 3)` und `multiply(True, 3)` jeweils `TypeError` auslösen
- [ ] `grep -E "socket|urllib|http|requests|subprocess|os\.environ" multiply.py tests/test_multiply.py` liefert keinen Treffer (Exit-Code 1)
- [ ] `multiply.py` enthält keine `import`-Statements ausser optional `typing`-Konstrukten
- [ ] Nur die Dateien `multiply.py`, `tests/test_multiply.py` (und ggf. `tests/__init__.py`) werden angelegt/geändert

## 5. Test-Liste (Claude härtet diese in Schritt F)
- Happy path: `multiply(2, 3) == 6`
- Null-Fälle: `multiply(0, 5) == 0`, `multiply(7, 0) == 0`, `multiply(0, 0) == 0`
- Negative Zahlen: `multiply(-2, 3) == -6`, `multiply(-2, -3) == 6`
- Float: `multiply(2.5, 4) == 10.0` (Ergebnistyp float)
- Fehlerfall / Fail-closed: `multiply("2", 3)`, `multiply(None, 1)`, `multiply(True, 3)` → `TypeError`
- Kommutativität stichprobenartig: `multiply(3, 7) == multiply(7, 3)`

## 6. Out of Scope
- Keine CLI, kein `argparse`, kein `__main__`-Block
- Keine weiteren mathematischen Operationen (add, divide, power etc.)
- Keine Unterstützung für `complex`, `Decimal`, `Fraction`, NumPy-Typen oder beliebige `__mul__`-Objekte
- Kein Logging, keine Konfiguration, keine Umgebungsvariablen
- Kein Packaging (`pyproject.toml`, `setup.py`), keine CI-Konfiguration
- Keine Performance-Optimierung, keine Doku ausser Docstring in der Funktion

