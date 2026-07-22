"""WP03 — core_impl: pure stdlib greet (no third-party dependencies)."""

# stdlib only — no third-party imports.


def greet(name: str) -> str:
    """Return a non-empty greeting that contains ``name``.

    Uses only the Python standard library (this module needs none).
    Fails closed on empty or whitespace-only names.
    """
    if not isinstance(name, str):
        raise TypeError(f"name must be a str, got {type(name).__name__}")
    if not name.strip():
        raise ValueError("name must be a non-empty, non-whitespace string")
    greeting = f"Hello, {name}!"
    if not greeting or name not in greeting:
        raise RuntimeError("greeting failed to include name")
    return greeting
