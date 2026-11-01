"""Executable negative security/regression contracts for .bworld v1."""
import copy
import hashlib
import io
import json
import sqlite3
import unittest
import zipfile
from pathlib import Path

from tools.bookworld.bookworld import (
    BookworldError,
    EXPECTED,
    ZIP_TIME,
    _manifest,
    build,
    canonical,
    create_database,
    decode_object,
    digest,
    verify,
)

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "shared_schemas" / "fixtures" / "manor_world_m17.json"


def source():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def parts(archive):
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        return {name: z.read(name) for name in EXPECTED}


def repack(parts_by_name, names=EXPECTED):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED) as z:
        for name in names:
            z.writestr(name, parts_by_name[name])
    return out.getvalue()


def resign(bp, raw_sqlite):
    raw_blueprint = canonical(bp)
    files = {
        "scenario/blueprint.json": raw_blueprint,
        "world.sqlite": raw_sqlite,
    }
    files["manifest.json"] = canonical(_manifest(
        bp, raw_sqlite, raw_blueprint))
    return repack(files)


class BookworldArchiveTests(unittest.TestCase):
    def setUp(self):
        self.bp = source()
        self.archive = build(self.bp)

    def test_build_verify_contract_and_real_sqlite(self):
        report = verify(self.archive)
        self.assertEqual(report["scene_count"], 8)
        self.assertEqual(report["bookworld_id"], self.bp["book_id"])
        self.assertEqual(report["choice_count"], 15)
        self.assertEqual(report["format_version"], 1)
        data = parts(self.archive)
        db = sqlite3.connect(":memory:")
        try:
            db.deserialize(data["world.sqlite"])
            self.assertEqual(
                db.execute("SELECT COUNT(*) FROM scenes").fetchone()[0], 8)
            self.assertEqual(
                db.execute("SELECT COUNT(*) FROM choices").fetchone()[0], 15)
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(),
                             ("ok",))
        finally:
            db.close()

    def test_build_is_reproducible_bytes_and_has_no_source_text(self):
        self.assertEqual(build(self.bp), build(self.bp))
        self.assertEqual(len(parts(self.archive)), 3)
        self.assertNotIn(b"source/text", self.archive)
        self.assertNotIn(b".py", b" ".join(
            name.encode() for name in parts(self.archive)))
        self.assertEqual(
            digest(self.archive), hashlib.sha256(self.archive).hexdigest())

    def test_corrupt_archive_is_rejected(self):
        bad = bytearray(self.archive)
        bad[len(bad) // 2] ^= 0x3f
        with self.assertRaises(BookworldError):
            verify(bytes(bad))
        with self.assertRaises(BookworldError):
            verify(b"")
        with self.assertRaises(BookworldError):
            verify(b"X" * (12 * 1024 * 1024 + 1))

    def test_missing_duplicate_and_traversal_entries_rejected(self):
        data = parts(self.archive)
        for name in [
            "../world.sqlite", "/world.sqlite", "C:/world.sqlite",
            r"..\world.sqlite", "world/../world.sqlite",
        ]:
            renamed = dict(data)
            renamed[name] = renamed.pop("world.sqlite")
            with self.subTest(path=name), self.assertRaises(BookworldError):
                verify(repack(renamed, names=(
                    "manifest.json", "scenario/blueprint.json", name,
                )))
        with self.assertRaises(BookworldError):
            verify(repack(data, names=(
                "manifest.json", "scenario/blueprint.json",
                "world.sqlite", "world.sqlite",
            )))
        with self.assertRaises(BookworldError):
            verify(repack(data, names=(
                "manifest.json", "world.sqlite",
            )))

    def test_nested_zip_and_extra_archive_entry_rejected(self):
        p = parts(self.archive)
        p["source/full_text.txt"] = b"unsafe inclusion"
        with self.assertRaises(BookworldError):
            verify(repack(p, names=(*EXPECTED, "source/full_text.txt")))

    def test_unsupported_compression_is_rejected(self):
        p = parts(self.archive)
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
            for name in EXPECTED:
                z.writestr(name, p[name])
        with self.assertRaises(BookworldError):
            verify(out.getvalue())

    def test_manifest_digest_rejects_repacked_blueprint_change(self):
        data = parts(self.archive)
        new = copy.deepcopy(self.bp)
        new["title"] = "Подмена заголовка без манифеста"
        data["scenario/blueprint.json"] = canonical(new)
        with self.assertRaises(BookworldError):
            verify(repack(data))

    def test_manifest_version_and_false_ai_mode_rejected(self):
        p = parts(self.archive)
        manifest = decode_object(p["manifest.json"], "manifest")
        manifest["format_version"] = 2
        p["manifest.json"] = canonical(manifest)
        with self.assertRaises(BookworldError):
            verify(repack(p))
        changed = source()
        changed["supported_modes"]["interactions"] = ["AI_FREEFORM"]
        with self.assertRaises(BookworldError):
            build(changed)

    def test_sqlite_wrong_scene_even_after_all_hashes_recomputed_rejected(self):
        p = parts(self.archive)
        db = sqlite3.connect(":memory:")
        try:
            db.deserialize(p["world.sqlite"])
            db.execute("UPDATE scenes SET body='ПОДМЕНА' WHERE scene_id='gate'")
            db.commit()
            corrupt = db.serialize()
        finally:
            db.close()
        with self.assertRaises(BookworldError):
            verify(resign(self.bp, corrupt))

    def test_sqlite_unknown_trigger_rejected_even_with_valid_hash(self):
        p = parts(self.archive)
        db = sqlite3.connect(":memory:")
        try:
            db.deserialize(p["world.sqlite"])
            db.executescript(
                "CREATE TRIGGER evil AFTER INSERT ON scenes "
                "BEGIN DELETE FROM world_meta; END;")
            db.commit()
            corrupt = db.serialize()
        finally:
            db.close()
        with self.assertRaises(BookworldError):
            verify(resign(self.bp, corrupt))

    def test_sqlite_invalid_header_and_missing_metadata_rejected(self):
        with self.assertRaises(BookworldError):
            verify(resign(self.bp, b"Not a real SQLite database"))
        p = parts(self.archive)
        db = sqlite3.connect(":memory:")
        try:
            db.deserialize(p["world.sqlite"])
            db.execute("DELETE FROM world_meta WHERE key='schema_version'")
            db.commit()
            corrupt = db.serialize()
        finally:
            db.close()
        with self.assertRaises(BookworldError):
            verify(resign(self.bp, corrupt))

    def test_blueprint_missing_scene_and_duplicate_choice_rejected(self):
        changed = source()
        changed["scenes"].pop(0)
        with self.assertRaises(BookworldError):
            build(changed)
        changed = source()
        changed["scenes"][1]["choices"][0]["id"] = "inspect_gate"
        with self.assertRaises(BookworldError):
            build(changed)


if __name__ == "__main__":
    unittest.main()
