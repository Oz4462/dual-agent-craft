"""WP01 core_impl — pure stdlib multiply(a, b).

Contract (PLAN.md §3):
  multiply(a: int | float, b: int | float) -> int | float
  - bool is rejected (fail-closed; bool is an int subclass)
  - int * int -> int; otherwise float (Python * semantics)
  - TypeError on non-number inputs; no duck-typing via __mul__
  - no I/O, no side effects, no imports beyond optional typing
"""


def multiply(a, b):
    """Return the product a * b for int/float operands only.

    Raises TypeError if either argument is not exactly int or float
    (bool, str, None, list, and other types are rejected).
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
