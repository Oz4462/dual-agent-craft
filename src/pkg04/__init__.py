"""WP05 — core_impl: pure stdlib multiply(a, b) with no forbidden imports.

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` (stdlib only, zero non-typing imports).
"""

from .multiply import multiply

__all__ = ["multiply"]
