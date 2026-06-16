# PLAN — slugify

## 1. Problem
Eine kleine, dependency-freie Python-Funktion, die einen String in einen URL-Slug wandelt.

## 2. Stack / Constraints
- Sprache: Python 3 (nur stdlib, KEINE externen Packages)
- Keine Netzwerkzugriffe, keine Secrets.

## 3. Interface-Contract (verbindlich)
- Datei MUSS `slugify.py` heissen.
- Funktion: `def slugify(text: str) -> str`
  - lowercase
  - fuehrende/abschliessende Whitespaces strippen
  - Folgen von Nicht-alphanumerischen Zeichen -> ein einzelner Bindestrich `-`
  - keine fuehrenden/abschliessenden Bindestriche
  - Beispiel: `slugify("  Hello,  World! ")` == `"hello-world"`
- Die Datei MUSS einen `if __name__ == "__main__":`-Block enthalten, der mit
  `assert` die folgenden Faelle prueft und bei Erfolg `print("OK")` ausgibt,
  bei Fehler mit Exit-Code != 0 abbricht:
  - `slugify("Hello World") == "hello-world"`
  - `slugify("  A_B  c ") == "a-b-c"`
  - `slugify("äÄ!!ö") ` darf nicht crashen (nur: kein Exception)
  - `slugify("") == ""`

## 4. Akzeptanzkriterien (binaer)
- [ ] `py -3 slugify.py` laeuft, gibt `OK` aus, Exit-Code 0.

## 5. Test-Liste
- Happy path "Hello World"
- Mehrfach-Trenner "A_B  c"
- Leerstring
- Unicode darf nicht crashen

## 6. Out of Scope
- Keine Transliteration von Unicode (ä->ae o.ae.), nur kein Crash.
- Kein CLI-Argument-Parsing, keine Datei-IO.
