import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("build", Path(__file__).resolve().parents[1] / "scripts/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class InputTests(unittest.TestCase):
    def test_rejects_wrong_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "archive.zip"
            path.write_bytes(b"wrong release")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                build.verify_input(path, build.CONFIG["sha256"])

    def test_rejects_archive_traversal_and_symlinks(self):
        for name, mode in [("../outside", 0), ("/outside", 0), ("link", 0o120777)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "archive.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    info = zipfile.ZipInfo(name)
                    info.external_attr = mode << 16
                    archive.writestr(info, "outside")
                with self.assertRaisesRegex(ValueError, "Unsafe ZIP"):
                    build.extract_zip(path, Path(temporary) / "extracted")


if __name__ == "__main__":
    unittest.main()
