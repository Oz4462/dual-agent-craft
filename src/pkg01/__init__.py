"""WP02 — error handling: greet fails closed on empty or invalid names."""


def greet(name: str) -> str:
    """Return a greeting containing the name.

    Fails closed: rejects non-string, empty, and whitespace-only names
    with a clear error instead of producing a nameless greeting.
    """
    if not isinstance(name, str):
        raise TypeError(f"name must be a str, got {type(name).__name__}")
    if not name.strip():
        raise ValueError("name must be a non-empty, non-whitespace string")
    return f"Hello, {name}!"
