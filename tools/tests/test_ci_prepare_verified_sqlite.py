"""Offline security tests for verified, source-built CI SQLite."""
import hashlib
import io
import unittest
import zipfile

from tools.ci_prepare_verified_sqlite import (
    HOOKS, RELEASE, patch_ci_pubspec, verified_source,
)


def _fake_archive(source: bytes) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(f"sqlite-amalgamation-{RELEASE}/sqlite3.c", source)
    return buffer.getvalue()


class VerifiedSqliteCiTests(unittest.TestCase):
    def test_source_requires_exact_pinned_hash(self):
        source = b"/* test only */" + b"sqlite3_open " + b"x" * 3000
        archive = _fake_archive(source)
        digest = hashlib.sha3_256(archive).hexdigest()
        self.assertEqual(verified_source(archive, expected=digest), source)
        with self.assertRaisesRegex(ValueError, "SHA3-256 mismatch"):
            verified_source(archive, expected="f" * 64)

    def test_rejects_wrong_zip_member_and_too_small_source(self):
        small = _fake_archive(b"/* sqlite3_open */")
        with self.assertRaisesRegex(ValueError, "size"):
            verified_source(small, hashlib.sha3_256(small).hexdigest())
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("other.c", b"/* sqlite3_open */" + b"x" * 3000)
        raw = buf.getvalue()
        with self.assertRaisesRegex(ValueError, "missing"):
            verified_source(raw, hashlib.sha3_256(raw).hexdigest())

    def test_build_hook_does_not_disable_integrity_or_run_on_windows(self):
        base = "name: fixture\nversion: 0.1.0\n"
        result = patch_ci_pubspec(base)
        self.assertIn("source:\n        android: source\n        linux: source\n", result)
        self.assertIn("default: sqlite3", result)
        self.assertIn("../../artifacts/sqlite/sqlite3.c", result)
        self.assertEqual(result.count("hooks:"), 1)
        with self.assertRaisesRegex(ValueError, "existing package hooks"):
            patch_ci_pubspec(result)


if __name__ == "__main__":
    unittest.main()
