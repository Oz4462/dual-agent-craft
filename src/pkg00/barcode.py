"""WP01 core_impl — barcode normalize/validate (pure stdlib).

Ground truth (PLAN.md is BLOCKED for this dual-run — no §3 interface was written):
  Ported from local VerdiScan checkout:
  /home/genesis/verdiscan/backend/src/lib/barcode.ts

Task signal: continue VerdiScan (scan → product → warn). The barcode normalizer
is the pure domain primitive at the start of that loop: untrusted scan input →
canonical EAN-13 / EAN-8 or reject.

Contract (mirrors barcode.ts):
  normalize_barcode(raw: str) -> str | None
    - trim whitespace
    - accept only all-digit strings of length 8, 12, or 13
    - require GS1 check digit
    - UPC-A (12) → EAN-13 with leading zero
    - invalid → None (fail-closed; no partial / coerced results)
  has_valid_checksum(code: str) -> bool
    - GS1: from the right (excluding check digit), weights alternate 3, 1

Constraints: stdlib only, no I/O, no network, no secrets, no imports.
Owned path: src/pkg00/ only.
"""

_VALID_LENGTHS = frozenset({8, 12, 13})


def has_valid_checksum(code: str) -> bool:
    """Return True if ``code`` has a valid GS1 check digit.

    ``code`` must already be an all-digit string of length 8/12/13.
    Weights from the right (excluding check digit): 3, 1, 3, 1, …
    """
    if type(code) is not str or not code.isdigit():
        return False
    if len(code) not in _VALID_LENGTHS:
        return False
    digits = [int(ch) for ch in code]
    check = digits.pop()
    # reverse remaining body so index 0 is the rightmost body digit (weight 3)
    total = 0
    for i, d in enumerate(reversed(digits)):
        total += d * (3 if i % 2 == 0 else 1)
    return (10 - (total % 10)) % 10 == check


def normalize_barcode(raw: str) -> str | None:
    """Normalize a raw barcode string or return None if invalid.

    Accepts EAN-8, UPC-A (12), and EAN-13. UPC-A is returned as EAN-13
    with a leading zero. Non-str inputs raise TypeError (fail-closed).
    """
    if type(raw) is not str:
        raise TypeError(
            f"normalize_barcode() raw must be str, not {type(raw).__name__}"
        )
    code = raw.strip()
    if not code.isdigit() or len(code) not in _VALID_LENGTHS:
        return None
    if not has_valid_checksum(code):
        return None
    if len(code) == 12:
        return f"0{code}"
    return code
