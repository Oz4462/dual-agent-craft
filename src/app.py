"""WP03 integrate — PLAN surface consolidating WP01/WP02 (src/pkg00, src/pkg01).

Public API of this dual-run, re-exported from the path-disjoint packages:

  normalize_barcode(raw: str) -> str | None   (WP01, src/pkg00/barcode.py)
      Untrusted scan input -> canonical EAN-13/EAN-8, or None (fail-closed).
  has_valid_checksum(code: str) -> bool       (WP01, src/pkg00/barcode.py)
      GS1 check-digit validation for all-digit strings of length 8/12/13.
  multiply(a: int | float, b: int | float) -> int | float
      (WP02, src/pkg01/multiply.py) Fail-closed product: exact int/float
      only, bool rejected, TypeError on anything else.

The active PLAN.md holds a BLOCKED report (no §3 interface was contracted
for the VerdiScan run), so this surface consolidates what WP01/WP02
actually shipped: WP01's barcode primitives as the run's core surface and
WP02's hardened multiply as the carried-over previous contract.

Import convention: the test harness puts ``src/`` on ``sys.path`` and
imports top-level modules (``import app``). The fallback below keeps the
module importable when only the repo root is on the path.
"""

try:
    from pkg00.barcode import has_valid_checksum, normalize_barcode
    from pkg01.multiply import multiply
except ModuleNotFoundError:  # pragma: no cover - direct import without src/ on path
    import pathlib
    import sys

    _SRC_DIR = str(pathlib.Path(__file__).resolve().parent)
    if _SRC_DIR not in sys.path:
        sys.path.insert(0, _SRC_DIR)
    from pkg00.barcode import has_valid_checksum, normalize_barcode
    from pkg01.multiply import multiply

__all__ = [
    "normalize_barcode",
    "has_valid_checksum",
    "multiply",
]
