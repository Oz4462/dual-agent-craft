"""WP01 — leftover pure stdlib multiply (previous dual-run contract).

Kept so workspace discovery/tests that still look for ``multiply`` under
src/pkg* do not break while the active task is VerdiScan. Prefer
``normalize_barcode`` in barcode.py for this run's core surface.

Contract (historical PLAN Pure-Stdlib Multiply):
  multiply(a: int | float, b: int | float) -> int | float
  - bool rejected (fail-closed; bool subclasses int)
  - TypeError on non-int/non-float
  - no imports, no I/O, no side effects
"""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product of a and b (int/float only; no bool)."""
    if type(a) is not int and type(a) is not float:
        raise TypeError(
            f"multiply() a must be int or float, not {type(a).__name__}"
        )
    if type(b) is not int and type(b) is not float:
        raise TypeError(
            f"multiply() b must be int or float, not {type(b).__name__}"
        )
    return a * b
