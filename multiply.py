"""WP06 integrate — PLAN.md contract surface: pure stdlib multiply(a, b).

Consolidated from the path-disjoint packages src/pkg00..pkg04 (WP01-WP05),
which all converged on the same fail-closed implementation. This root
module is the public API the tests import (PLAN.md §3).

Contract:
  multiply(a: int | float, b: int | float) -> int | float
  - bool is rejected (fail-closed; bool is an int subclass)
  - int * int -> int; otherwise float (standard Python ``*`` semantics)
  - TypeError on non-number inputs; no implicit conversion, no
    duck-typing via ``__mul__``
  - pure and deterministic: no I/O, no side effects, no imports
"""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product a * b.

    Accepts int or float only; bool is rejected even though it subclasses
    int. int*int yields int; otherwise float (standard Python ``*``
    semantics). Raises TypeError with a clear message when either argument
    is not exactly int or float (str, bool, None, list, ...).
    """
    if type(a) is not int and type(a) is not float:
        raise TypeError(
            f"multiply() a must be int or float, not {type(a).__name__}"
        )
    if type(b) is not int and type(b) is not float:
        raise TypeError(
            f"multiply() b must be int or float, not {type(b).__name__}"
        )
    return a * b
