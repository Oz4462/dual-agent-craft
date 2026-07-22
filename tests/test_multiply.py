"""WP07 — pin PLAN.md acceptance criteria as real tests.

Contract (PLAN.md §3-§5):
- multiply(a: int | float, b: int | float) -> int | float
- happy path: multiply(2, 3) == 6
- null cases: multiply(0, 5) == 0, multiply(7, 0) == 0, multiply(0, 0) == 0
- negative numbers: multiply(-2, 3) == -6

Pure stdlib (unittest), no third-party deps, no I/O beyond imports. The
contract is checked against the root-level multiply.py (once integrated)
plus every multiply-providing package under src/ so no variant can drift.
"""

import importlib
import pathlib
import sys
import unittest

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT_DIR / "src"


def _multiply_implementations():
    """Discover all callables named multiply: root multiply.py + src packages."""
    implementations = []

    if (ROOT_DIR / "multiply.py").is_file():
        if str(ROOT_DIR) not in sys.path:
            sys.path.insert(0, str(ROOT_DIR))
        module = importlib.import_module("multiply")
        if callable(getattr(module, "multiply", None)):
            implementations.append(("multiply", module.multiply))

    if SRC_DIR.is_dir():
        if str(SRC_DIR) not in sys.path:
            sys.path.insert(0, str(SRC_DIR))
        for entry in sorted(SRC_DIR.iterdir()):
            if not (entry.is_dir() and (entry / "__init__.py").is_file()):
                continue
            module = importlib.import_module(entry.name)
            if callable(getattr(module, "multiply", None)):
                implementations.append((entry.name, module.multiply))

    return implementations


class MultiplyContractTest(unittest.TestCase):
    def setUp(self):
        self.implementations = _multiply_implementations()

    def test_at_least_one_multiply_implementation_exists(self):
        # Fail closed: an empty workspace must not pass the contract silently.
        self.assertTrue(
            self.implementations,
            f"no root multiply.py and no package under {SRC_DIR} "
            "exports a callable multiply()",
        )

    def test_happy_path_two_times_three_is_six(self):
        for name, multiply in self.implementations:
            with self.subTest(implementation=name):
                result = multiply(2, 3)
                self.assertEqual(result, 6)
                self.assertIsInstance(result, int)
                self.assertNotIsInstance(result, bool)

    def test_null_case_zero_times_five_is_zero(self):
        for name, multiply in self.implementations:
            with self.subTest(implementation=name):
                self.assertEqual(multiply(0, 5), 0)

    def test_null_case_seven_times_zero_is_zero(self):
        for name, multiply in self.implementations:
            with self.subTest(implementation=name):
                self.assertEqual(multiply(7, 0), 0)

    def test_null_case_zero_times_zero_is_zero(self):
        for name, multiply in self.implementations:
            with self.subTest(implementation=name):
                self.assertEqual(multiply(0, 0), 0)

    def test_negative_times_positive_is_negative(self):
        for name, multiply in self.implementations:
            with self.subTest(implementation=name):
                self.assertEqual(multiply(-2, 3), -6)


if __name__ == "__main__":
    unittest.main()
