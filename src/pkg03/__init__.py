"""WP04 — core_impl for PLAN acceptance A4 (no forbidden I/O patterns).

Exports ``multiply`` for package discovery (same pattern as sibling packages).
Implementation lives in ``multiply.py`` (stdlib only, no side effects,
no network/process/environment APIs).
"""

from .multiply import multiply

__all__ = ["multiply"]
