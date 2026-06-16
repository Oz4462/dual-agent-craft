# PLAN — roman_to_int

## 1. Problem
Eine dependency-freie Python-Funktion, die eine roemische Zahl in einen Integer wandelt.

## 2. Stack / Constraints
- Python 3, nur stdlib. Keine externen Packages, kein Netzwerk, keine Secrets.

## 3. Interface-Contract (verbindlich)
- Datei MUSS `roman.py` heissen.
- Funktion: `def roman_to_int(s: str) -> int`
  - akzeptiert Grossbuchstaben I V X L C D M
  - subtraktive Notation korrekt (IV=4, IX=9, XL=40, XC=90, CD=400, CM=900)
  - leerer String -> 0
- Die Datei MUSS einen `if __name__ == "__main__":`-Block enthalten, der mit `assert`
  prueft und bei Erfolg `print("OK")` ausgibt, sonst Exit-Code != 0:
  - `roman_to_int("III") == 3`
  - `roman_to_int("IV") == 4`
  - `roman_to_int("IX") == 9`
  - `roman_to_int("LVIII") == 58`
  - `roman_to_int("MCMXCIV") == 1994`
  - `roman_to_int("") == 0`

## 4. Akzeptanzkriterien (binaer)
- [ ] `py -3 roman.py` laeuft, gibt `OK`, Exit-Code 0.

## 5. Test-Liste
- Einfach (III), subtraktiv (IV, IX), gemischt (LVIII, MCMXCIV), leer.

## 6. Out of Scope
- Keine Validierung ungueltiger Eingaben (z.B. "IIII"), kein int->roman.
