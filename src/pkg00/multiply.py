"""WP01 — multiply module under package path (stdlib only).

Re-export of the package-level multiply for import compatibility.
No third-party imports; no I/O; no side effects.
"""


def multiply(a, b):
    """Return the arithmetic product a * b.

    Accepts int or float only (bool is rejected). int*int yields int;
    otherwise float (standard Python ``*`` semantics). Raises TypeError
    with a clear message when either argument is not a real number type.
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
