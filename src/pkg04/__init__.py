"""WP05 — core_impl: pure multiply with no non-typing imports (A5).

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` — zero import statements there
(optional typing constructs only; this package uses none).
"""

from .multiply import multiply

__all__ = ["multiply"]
