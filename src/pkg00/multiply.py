"""WP01 core_impl — pure stdlib multiply(a, b).

PLAN.md §3 Interface-Contract:
  multiply(a: int | float, b: int | float) -> int | float
  - returns arithmetic product a * b
  - TypeError on non-numeric args (str, None, list, …)
    Note: str * int is valid Python (string repeat), so we reject non-numbers
    explicitly rather than relying only on the * operator.
  - no side effects, no I/O, no imports
  - no string conversion, no global state

Owned by package WP01 under src/pkg00/. Root multiply.py is wired by INTEGRATE.
"""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product of a and b.

    Accepts int or float only (bool is rejected even though it subclasses int).
    Non-numeric arguments raise TypeError.
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
