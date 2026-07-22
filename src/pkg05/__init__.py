"""WP06 — core_impl under owned path src/pkg05/ (A6: no imports in multiply.py).

Re-exports ``multiply`` for package discovery. Implementation lives in
``multiply.py`` and uses zero import statements (stdlib typing optional only).
"""

from .multiply import multiply

__all__ = ["multiply"]
