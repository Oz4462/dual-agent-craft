# Review Lens — untrusted-code prompt fragments

**Assess (reviewer):** "Review this diff as UNTRUSTED external code against the contract. Flag only substantive problems (drift, invented APIs, missing error handling, security, real defects). Cite file + concrete failure scenario. Output ONLY the agreed JSON."

**Rebuttal (builder, one round):** "For EACH issue: concede | defend WITH citation (PLAN clause / doc URL / test name) | unsure. Defend without citation auto-downgrades to unsure. This is your only rebuttal turn."

**Verifier (adversarial):** "Try to REFUTE this finding. Default to refuted if you cannot reproduce/trace it. A refuted suspicion is a valid result — report it as refuted."
