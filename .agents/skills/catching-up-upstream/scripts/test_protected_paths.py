#!/usr/bin/env python3
"""python3 -m unittest scripts/test_protected_paths.py"""

import tempfile
import unittest
from pathlib import Path

from protected_paths import EXCLUSIVE, REQUIRED_TESTS, missing_files, missing_tests


class ProtectedPathsTest(unittest.TestCase):
    def test_empty_tree_reports_all_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(missing_files(Path(tmp)), EXCLUSIVE)

    def test_missing_test_name_detected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel in EXCLUSIVE:
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('test "unrelated" {}\n', encoding="utf-8")
            absent = missing_tests(root)
            self.assertEqual(absent, REQUIRED_TESTS)

    def test_present_test_not_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            body = "\n".join(f'test "{name}" {{}}\n' for name in REQUIRED_TESTS)
            for rel in EXCLUSIVE:
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(body, encoding="utf-8")
            self.assertEqual(missing_tests(root), [])


if __name__ == "__main__":
    unittest.main()
