"""WP03 — core_impl: zero-product cases for multiply(a, b).

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` (stdlib only, no side effects).
"""

from .multiply import multiply

__all__ = ["multiply"]
