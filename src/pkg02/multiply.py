"""WP03 — pure stdlib multiply(a, b); covers zero-product cases.

Null cases (acceptance A3): multiply(0, 5) == 0, multiply(7, 0) == 0.
stdlib only; no I/O; no side effects; no third-party imports.
"""


def multiply(a, b):
    """Return the arithmetic product a * b.

    Accepts int or float only (bool is rejected). int*int yields int;
    otherwise float (standard Python ``*`` semantics). Raises TypeError
    with a clear message when either argument is not a real number type.

    Zero cases: multiply(0, 5) == 0, multiply(7, 0) == 0, multiply(0, 0) == 0.
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
