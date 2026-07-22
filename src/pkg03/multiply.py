"""WP04 — error_handling: pure stdlib multiply(a, b) with fail-closed type checks.

Acceptance A4: multiply("2", 3) and multiply(True, 3) each raise TypeError.
Exact type checks (``type(x) is int/float``) reject bool explicitly, since
``isinstance(True, int)`` is True and would silently pass. No implicit
conversion, no duck-typing, no I/O, no third-party imports.
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
