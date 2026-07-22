"""WP04 core_impl — pure stdlib multiply(a, b); no forbidden I/O APIs (A4).

PLAN.md §4 A4: the public surface must not reference network clients,
URL stacks, process spawning, or environment access. This package is
stdlib-only arithmetic with no imports and no side effects.

Contract (PLAN.md §3):
  multiply(a: int | float, b: int | float) -> int | float
  - returns arithmetic product a * b
  - TypeError on non-numeric args (str, None, list, bool, …)
  - no side effects, no I/O, no global state, no non-typing imports

Owned by WP04 under src/pkg03/. Root multiply.py is wired by INTEGRATE.
"""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product of a and b.

    Accepts int or float only (bool is rejected even though it subclasses
    int). int*int yields int; otherwise float (standard Python ``*``
    semantics). Non-numeric arguments raise TypeError.
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
