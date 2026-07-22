"""WP01 — core_impl: pure stdlib multiply(a, b).

Exports ``multiply`` for package discovery (same pattern as prior team packages).
Implementation lives in ``multiply.py`` (stdlib only, no side effects).
"""

from .multiply import multiply

__all__ = ["multiply"]
