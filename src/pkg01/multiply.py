"""WP02 package-local multiply implementation.

Fail-closed edge-case behavior:
- accept only exact ``int`` and ``float`` values
- reject ``bool`` even though it is an ``int`` subclass
- do not coerce strings, decimals, arrays, or custom objects
"""


def _require_number(name: str, value: int | float) -> None:
    if type(value) is not int and type(value) is not float:
        raise TypeError(
            f"multiply() {name} must be int or float, not {type(value).__name__}"
        )


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product of two exact int or float values."""
    _require_number("a", a)
    _require_number("b", b)
    return a * b
