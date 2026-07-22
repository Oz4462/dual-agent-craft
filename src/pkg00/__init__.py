"""WP01 core_impl package (src/pkg00/).

Primary surface for this dual-run (VerdiScan task, PLAN.md blocked):
  normalize_barcode, has_valid_checksum  — from barcode.py

Compatibility surface (previous multiply contract still tested in-repo):
  multiply  — from multiply.py
"""

from .barcode import has_valid_checksum, normalize_barcode
from .multiply import multiply

__all__ = [
    "normalize_barcode",
    "has_valid_checksum",
    "multiply",
]
