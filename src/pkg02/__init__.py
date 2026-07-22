"""WP03 — core_impl: pure stdlib multiply(a, b); zero-product cases.

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` (stdlib only, no side effects).
"""

from .multiply import multiply

__all__ = ["multiply"]
