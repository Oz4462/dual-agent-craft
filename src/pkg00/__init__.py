def greet(name: str) -> str:
    """Return a greeting that includes the supplied name."""
    if not name:
        raise ValueError("name must be non-empty")
    return f"Hello, {name}!"
