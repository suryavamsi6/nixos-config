import importlib.util
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "patch_serpantinum",
    Path(__file__).parents[1] / "scripts" / "patch_serpantinum.py",
)
patcher = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(patcher)


class PatcherUnitTests(unittest.TestCase):
    def test_replace_once_rejects_missing_and_duplicate_anchors(self):
        with self.assertRaisesRegex(RuntimeError, "found 0"):
            patcher.replace_once("hello", "missing", "new", "fixture")
        with self.assertRaisesRegex(RuntimeError, "found 2"):
            patcher.replace_once("xx", "x", "new", "fixture")

    def test_replace_once_changes_exact_anchor(self):
        self.assertEqual(
            patcher.replace_once("before old after", "old", "new", "fixture"),
            "before new after",
        )

    def test_wrong_version_fails_before_reading_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "version.txt").write_text("9.9.9\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsupported Serpantinum version"):
                patcher.apply(root, "2.1.0", "expected-revision")

    def test_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "version.txt").write_text("2.1.0\n", encoding="utf-8")
            relative = next(iter(patcher.PATCHERS))
            path = root / relative
            path.parent.mkdir(parents=True)
            path.write_text("unrecognized source\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsupported .* sha256"):
                patcher.apply(root, "2.1.0", "expected-revision")


if __name__ == "__main__":
    unittest.main()
