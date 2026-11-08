"""E6g native-v4 adapter safety checks; no Dart SDK or real books needed here.

Actual compiler/importer and SQLite parity are exercised by run_dart_parity.py.
"""
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools.rpg_author import native_v4_bridge as v4
from tools.rpg_author.cli import parser
from tools.rpg_author.common import AuthoringError
from tools.rpg_author import project
from tests.rpg_author.fixtures import TEXT
from tests.rpg_author.fixtures_rich import enrichment


class NativeV4BridgeTests(unittest.TestCase):
    def test_cli_v4_requires_explicit_opt_in(self):
        default = parser().parse_args([
            "build", "--project", "p", "--enrichment", "e", "--output", "v3.bworld"])
        extended = parser().parse_args([
            "build-extended", "--project", "p", "--enrichment", "e", "--output",
            "v4.bworld"])
        verify = parser().parse_args([
            "verify-extended", "--input", "v4.bworld",
            "--attribution", "v4.attribution.json"])
        self.assertEqual(default.command, "build")
        self.assertEqual(extended.command, "build-extended")
        self.assertEqual(verify.command, "verify-extended")

    def test_native_receives_only_original_basename_from_private_cwd(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "package_config.json"
            config.write_text("{}", encoding="utf-8")
            book = root / "my_story.txt"
            review = root / "review.json"
            result = root / "ready.bworld"
            fake = SimpleNamespace(returncode=0, stdout=json.dumps({
                "format_version": 4,
                "result": "PRIVATE_EXTENDED_V4_VERIFIED",
            }), stderr="")
            with patch.object(v4, "_PACKAGE_CONFIG", config), \
                 patch.object(v4, "_AUTHOR_PACKAGE_CONFIG", root / "absent_config"), \
                 patch.object(v4.shutil, "which", return_value="dart"), \
                 patch.object(v4.subprocess, "run", return_value=fake) as launched:
                actual = v4._native("build-extended", book, review, result)
            self.assertEqual(actual["format_version"], 4)
            command = launched.call_args.args[0]
            self.assertEqual(command[-4:], [
                "build-extended", "my_story.txt", "review.json", "ready.bworld"])
            self.assertEqual(launched.call_args.kwargs["cwd"], root)
            self.assertTrue(command[1].startswith("--packages="))
            self.assertNotIn(str(root), command[-3:])

    def test_native_refuses_mixed_paths_before_running(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "package_config.json"
            config.write_text("{}", encoding="utf-8")
            with patch.object(v4, "_PACKAGE_CONFIG", config), \
                 patch.object(v4, "_AUTHOR_PACKAGE_CONFIG", root / "absent_config"), \
                 patch.object(v4.shutil, "which", return_value="dart"):
                with self.assertRaises(AuthoringError) as err:
                    v4._native("build-extended",
                               root / "book.txt",
                               root / "other" / "review.json",
                               root / "game.bworld")
            self.assertEqual(err.exception.code, "invalid_native_paths")

    def test_v4_refuses_custom_chunking_until_native_supports_it(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "book.txt"
            source.write_text(TEXT, encoding="utf-8")
            private = root / "project"
            project.init_project(private, source, chunk_size=256)
            with self.assertRaises(AuthoringError) as err:
                v4.compile_extended_from_project(private, enrichment())
            self.assertEqual(err.exception.code, "native_chunk_size_mismatch")

    def test_v3_cannot_be_misreported_as_native_v4(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("manifest.json", '{"format_version":3}')
            archive.writestr("scenario/blueprint.json", '{}')
            archive.writestr("source/provenance.json", '{}')
            archive.writestr("world.sqlite", b"not a database")
        with self.assertRaises(AuthoringError) as err:
            v4._inspect_v4(data.getvalue())
        self.assertEqual(err.exception.code, "invalid_extended_archive")


if __name__ == "__main__":
    unittest.main()
