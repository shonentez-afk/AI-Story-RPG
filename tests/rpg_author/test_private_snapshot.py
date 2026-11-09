"""Private ChatGPT Skill session handoff: authentic immutable checkpoint roundtrips.

Only an original synthetic text is used; no user book or answers enter CI.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError
from tools.rpg_author.private_snapshot import (
    snapshot_private, restore_private_snapshot, verify_private_snapshot,
)


class PrivateSessionSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.book = self.base / "book.txt"
        self.book.write_text("Лодочник рассказал о верёвке и мосте.\n"
                             "В долине бушевала река.\n"
                             "На берегу герои нашли выход.", encoding="utf-8")
        self.project = self.base / "original-project"
        project.init_project(self.project, self.book)
        self.workdir = self.base / "original-private-skill"
        (self.workdir / "skill-responses" / "requests").mkdir(parents=True)
        (self.workdir / "skill-responses" / "requests" /
         "analysis_c00000.request.json").write_text(
             '{"stage":"analysis","private_source":"Книга остаётся локальной"}',
             encoding="utf-8")
        (self.workdir / "skill-responses" /
         "analysis_c00000.json").write_text('{"summary":"Был мост"}',
                                             encoding="utf-8")
        (self.workdir / "npc_dossiers.json").write_text(
            '{"characters":[{"name":"Лодочник"}]}', encoding="utf-8")
        self.archive = self.base / "session.zip"
        self.outproject = self.base / "recovered-project"
        self.outwork = self.base / "recovered-skill"

    def create(self, *, game=False):
        if game:
            self.game = self.base / "tested.bworld"
            self.game.write_bytes(b"SYNTHETIC-BOOKWORLD-FIXTURE")
            self.game.with_suffix(".attribution.json").write_text(
                '{"privately_verified":false}', encoding="utf-8")
            return snapshot_private(self.project, self.workdir, self.archive,
                                    game_path=self.game)
        return snapshot_private(self.project, self.workdir, self.archive)

    def test_verified_deterministic_snapshot_and_restore_without_book_file(self):
        result = self.create()
        self.assertTrue(result["contains_private_book_and_answers"])
        self.assertFalse(result["user_ready"])
        self.assertEqual(verify_private_snapshot(self.archive)["sha256"],
                         result["sha256"])
        second = self.base / "second.zip"
        snapshot_private(self.project, self.workdir, second)
        self.assertEqual(self.archive.read_bytes(), second.read_bytes())
        self.book.unlink()
        restored = restore_private_snapshot(
            self.archive, self.outproject, self.outwork)
        self.assertTrue(restored["resume_without_reanalyzing_book"])
        self.assertEqual(project.status(self.project)["source_fingerprint"],
                         project.status(self.outproject)["source_fingerprint"])
        for suffix in ("npc_dossiers.json",
                       "skill-responses/analysis_c00000.json",
                       "skill-responses/requests/analysis_c00000.request.json"):
            self.assertEqual((self.workdir / suffix).read_bytes(),
                             (self.outwork / suffix).read_bytes())

    def test_compiled_game_and_sidecar_are_hash_bound_but_not_certified(self):
        self.create(game=True)
        with self.assertRaises(AuthoringError) as err:
            restore_private_snapshot(self.archive, self.outproject,
                                     self.outwork)
        self.assertEqual(err.exception.code, "snapshot_game_destination_mismatch")
        target = self.base / "recovered-game.bworld"
        r = restore_private_snapshot(self.archive, self.outproject,
                                     self.outwork, game_path=target)
        self.assertFalse(r["user_ready"])
        self.assertEqual(target.read_bytes(), self.game.read_bytes())
        self.assertEqual(target.with_suffix(".attribution.json").read_bytes(),
                         self.game.with_suffix(".attribution.json").read_bytes())

    def test_tampered_bytes_and_zip_slip_fail_without_writing(self):
        self.create()
        raw = self.archive.read_bytes()
        self.archive.write_bytes(raw + b"extraneous suffix")
        with self.assertRaises(AuthoringError) as err:
            verify_private_snapshot(self.archive)
        self.assertEqual(err.exception.code, "snapshot_noncanonical")
        self.assertFalse(self.outproject.exists())
        self.archive.write_bytes(raw)
        with zipfile.ZipFile(io.BytesIO(raw)) as source:
            members = [(info.filename, source.read(info)) for info
                       in source.infolist()]
        damaged = io.BytesIO()
        with zipfile.ZipFile(damaged, "w") as output:
            for name, data in members:
                output.writestr(name, b"wrong" if
                                name == "project/project.json" else data)
        self.archive.write_bytes(damaged.getvalue())
        with self.assertRaises(AuthoringError):
            verify_private_snapshot(self.archive)
        self.assertFalse(self.outwork.exists())

    def test_symlinks_and_live_writer_lock_are_refused(self):
        unsafe = self.base / "secret"
        unsafe.write_text("private", encoding="utf-8")
        try:
            (self.workdir / "stolen.json").symlink_to(unsafe)
        except OSError:
            self.skipTest("Symlinks unavailable on this runner")
        with self.assertRaises(AuthoringError) as err:
            self.create()
        self.assertEqual(err.exception.code, "snapshot_symlink")
        (self.workdir / "stolen.json").unlink()
        (self.project / ".write-lock").write_text("123", encoding="utf-8")
        with self.assertRaises(AuthoringError) as err:
            self.create()
        self.assertEqual(err.exception.code, "snapshot_project_busy")

    def test_existing_destination_and_changed_toolchain_fail_closed(self):
        self.create()
        self.outproject.mkdir()
        with self.assertRaises(AuthoringError) as err:
            restore_private_snapshot(self.archive, self.outproject,
                                     self.outwork)
        self.assertEqual(err.exception.code, "snapshot_restore_exists")
        self.outproject.rmdir()
        with patch("tools.rpg_author.private_snapshot.toolchain_id",
                   return_value="0" * 64):
            with self.assertRaises(AuthoringError) as err:
                restore_private_snapshot(self.archive, self.outproject,
                                         self.outwork)
        self.assertEqual(err.exception.code, "snapshot_toolchain_changed")
        self.assertFalse(self.outproject.exists())

    def test_unexpected_files_and_overlapping_destinations_are_refused(self):
        (self.project / "objects" / "not-a-digest.txt").write_text(
            "not a checkpoint", encoding="utf-8")
        with self.assertRaises(AuthoringError) as err:
            self.create()
        self.assertEqual(err.exception.code, "snapshot_unsafe_path")
        (self.project / "objects" / "not-a-digest.txt").unlink()
        with self.assertRaises(AuthoringError) as err:
            snapshot_private(self.project, self.workdir,
                             self.workdir / "unsafe.zip")
        self.assertEqual(err.exception.code, "snapshot_paths_overlap")


if __name__ == "__main__":
    unittest.main()
