"""WP04 — pin PLAN.md acceptance criteria as real tests.

Contract (PLAN.md §3-§5):
- greet(name: str) -> str
- happy path: greet("Ada") returns a non-empty string containing the name
- empty name fails closed with a clear error

Pure stdlib (unittest), no third-party deps. The contract is checked against
every greet-providing package under src/ so no integrated variant can drift.
"""

import importlib
import pathlib
import sys
import unittest

SRC_DIR = pathlib.Path(__file__).resolve().parent.parent / "src"


def _greet_packages():
    """Discover all src packages that export a callable greet()."""
    if str(SRC_DIR) not in sys.path:
        sys.path.insert(0, str(SRC_DIR))
    packages = []
    for entry in sorted(SRC_DIR.iterdir()):
        if not (entry.is_dir() and (entry / "__init__.py").is_file()):
            continue
        module = importlib.import_module(entry.name)
        if callable(getattr(module, "greet", None)):
            packages.append((entry.name, module.greet))
    return packages


class GreetContractTest(unittest.TestCase):
    def setUp(self):
        self.packages = _greet_packages()

    def test_at_least_one_greet_implementation_exists(self):
        # Fail closed: an empty src/ must not pass the contract silently.
        self.assertTrue(
            self.packages,
            f"no package under {SRC_DIR} exports a callable greet()",
        )

    def test_happy_path_greet_ada_returns_nonempty_string_with_name(self):
        for name, greet in self.packages:
            with self.subTest(package=name):
                result = greet("Ada")
                self.assertIsInstance(result, str)
                self.assertTrue(result, "greet('Ada') returned an empty string")
                self.assertIn("Ada", result)

    def test_empty_name_fails_closed_with_clear_error(self):
        for name, greet in self.packages:
            with self.subTest(package=name):
                with self.assertRaises(ValueError) as ctx:
                    greet("")
                self.assertTrue(
                    str(ctx.exception).strip(),
                    "empty-name rejection must carry a clear error message",
                )


if __name__ == "__main__":
    unittest.main()
