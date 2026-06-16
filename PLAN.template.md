# PLAN — <Feature-Name>

> Claude füllt das aus. Grok baut strikt dagegen. Kein Code in diesem File.
> Dieser Build kennt KEINEN Kontext ausser dem, was hier steht.

## 1. Problem
<Was soll gebaut werden, in 2-3 Sätzen. Kein Bezug zu alten Projekten.>

## 2. Stack / Constraints
- Sprache/Framework: <z.B. Python 3.12 / TypeScript / Rust>
- Erlaubte Dependencies: <Liste oder "stdlib only">
- Verbote: <z.B. keine Netzwerkzugriffe, keine Secrets, keine globalen Installs>

## 3. Interface-Contract (die einzige Wahrheit, die beide teilen)
<Exakte Signaturen / Endpunkte / CLI-Flags / Datenformate. So präzise, dass
Grok nicht raten muss und Claude beim Review jede Abweichung als Drift erkennt.>

```
# Beispiel:
# function parse(input: str) -> Result
#   - input: ...
#   - returns: ...
#   - raises: ...
```

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] <Kriterium 1 — als Test/Befehl ausdrückbar>
- [ ] <Kriterium 2>
- [ ] <Kriterium 3>

## 5. Test-Liste (Claude härtet diese in Schritt F)
- <Happy path>
- <Edge case>
- <Fehlerfall / Fail-closed>

## 6. Out of Scope
<Was bewusst NICHT gebaut wird — verhindert Grok-Scope-Creep.>
