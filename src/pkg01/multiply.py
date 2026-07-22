"""WP02 package-local multiply implementation."""


def multiply(a: int | float, b: int | float) -> int | float:
    """Return the arithmetic product of two int or float values."""
    if type(a) is not int and type(a) is not float:
        raise TypeError(f"multiply() a must be int or float, not {type(a).__name__}")
    if type(b) is not int and type(b) is not float:
        raise TypeError(f"multiply() b must be int or float, not {type(b).__name__}")
    return a * b
