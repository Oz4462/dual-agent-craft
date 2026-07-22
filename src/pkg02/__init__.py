"""WP03 — core_impl for PLAN acceptance A3 (unittest discover ≥3 tests).

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` (stdlib only, no side effects).
"""

from .multiply import multiply

__all__ = ["multiply"]
