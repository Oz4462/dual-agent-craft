"""WP05 core_impl — pure stdlib multiply(a, b); zero third-party deps (A5).

PLAN.md §4 A5: this module must not contain any ``import`` / ``from``
statements except optional ``typing`` constructs. Implementation uses only
language primitives (PEP 604 ``int | float`` on Python 3.10+; no typing module).

Contract (PLAN.md §3):
  multiply(a: int | float, b: int | float) -> int | float
  - returns arithmetic product a * b
  - TypeError on non-numeric args (str, None, list, bool, …)
  - no side effects, no I/O, no global state

Owned by WP05 under src/pkg04/. Root multiply.py is wired by INTEGRATE.
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
