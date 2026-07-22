"""WP06 — pure stdlib multiply(a, b); zero non-typing imports (A6).

Acceptance A6: this file must not contain any ``import`` statements
except optional ``typing`` constructs. Implementation is pure Python
with exact type checks; no third-party packages, no I/O, no side effects.
"""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product a * b.

    Accepts int or float only (bool is rejected even though it subclasses
    int). int*int yields int; otherwise float (standard Python ``*``
    semantics). Raises TypeError when either argument is not exactly
    int or float — fail-closed, no implicit conversion, no duck-typing
    via ``__mul__``.
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
