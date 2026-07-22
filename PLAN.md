# PLAN — hello-live-spike

## 1. Problem
Build a tiny Python hello module for a live system smoke test of dual-agent team-work.

## 2. Stack / Constraints
- Sprache/Framework: Python 3
- Erlaubte Dependencies: stdlib only
- Verbote: no network, no secrets

## 3. Interface-Contract
function greet(name: str) -> str

## 4. Akzeptanzkriterien (verifizierbar, binär)
- [ ] greet returns a non-empty string containing the name
- [ ] empty name fails closed with a clear error
- [ ] pure stdlib, no third-party deps

## 5. Test-Liste
- happy path greet("Ada")
- empty name rejected

## 6. Out of Scope
UI, network, persistence, CLI packaging beyond a simple module
