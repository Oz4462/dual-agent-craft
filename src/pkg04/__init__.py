"""WP05 — core_impl: pure multiply with no network/process APIs (A5).

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` — no network, no process spawn,
no environment access, no non-typing imports.
"""

from .multiply import multiply

__all__ = ["multiply"]
