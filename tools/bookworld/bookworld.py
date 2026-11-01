"""Deterministic, offline .bworld v1 builder and fail-closed verifier.

Compiler runs in Python *separately*; Flutter runtime never invokes Python.
The first format version intentionally permits exactly three ZIP_STORED files.
No archive extraction, network request, executable code or embedded source text.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import sqlite3
import stat
import sys
import zipfile
from pathlib import Path

FORMAT = "ai_story_bookworld"
VERSION = 1
EXPECTED = ("manifest.json", "scenario/blueprint.json", "world.sqlite")
MAX_ARCHIVE_BYTES = 12 * 1024 * 1024
MAX_ENTRY_BYTES = 8 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 16 * 1024 * 1024
ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
SQLITE_MAGIC = b"SQLite format 3\x00"
APPLICATION_ID = 0x42574F52
ZIP_TIME = (2020, 1, 1, 0, 0, 0)
MANDATORY_MANIFEST = {
    "format", "format_version", "bookworld_id", "source_fingerprint",
    "title", "author", "languages", "engine_min_version",
    "scenario_format", "scenario_format_version", "content_capabilities",
    "build_status", "hashes", "sizes", "build_tool", "model_provenance",
    "rights_status", "blueprint_sha256",
}
ALLOWED_SQL_TABLES = {
    "world_meta", "scenes", "choices", "actors", "items", "canon_facts",
    "source_refs", "event_dependencies", "templates",
}


class BookworldError(ValueError):
    pass


def fail(message: str) -> None:
    raise BookworldError(message)


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def decode_object(raw: bytes, where: str) -> dict:
    try:
        # Duplicate JSON keys must not silently overwrite values.
        def unique_pairs(pairs):
            out = {}
            for key, value in pairs:
                if key in out:
                    fail(f"{where}: duplicate JSON key {key}")
                out[key] = value
            return out
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_pairs)
    except (UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{where}: invalid JSON: {exc}")
    if not isinstance(result, dict):
        fail(f"{where}: expected object")
    return result


def validate_blueprint(bp: dict) -> None:
    """M1.7.3 only accepts original-demo CLASSIC blueprints.

    This is an independent boundary validator. Dart story_core performs
    full DSL, reachability and gameplay-rule checks after importing.
    """
    required = {
        "format", "schema_version", "book_id", "title", "entry_scene_id",
        "rights_status", "source_fingerprint", "supported_modes",
        "items", "facts", "actors", "initial_state", "scenes",
    }
    if set(bp) != required or bp["format"] != "ai_story_blueprint_v1" or \
            type(bp["schema_version"]) is not int or bp["schema_version"] != 1 or \
            bp["rights_status"] != "original_demo" or \
            bp["source_fingerprint"] is not None:
        fail("Unsupported or incomplete blueprint")
    if not isinstance(bp["book_id"], str) or not ID_RE.fullmatch(bp["book_id"]):
        fail("Invalid book_id")
    if not isinstance(bp["title"], str) or not 0 < len(bp["title"]) <= 256:
        fail("Invalid title")
    if bp["supported_modes"] != {
        "roles": ["PROTAGONIST"], "plots": ["CANON"], "interactions": ["CLASSIC"]
    }:
        fail("Unsupported blueprint mode")
    if not isinstance(bp["scenes"], list) or not 1 <= len(bp["scenes"]) <= 5000:
        fail("Invalid scene list")
    scene_ids = set()
    choice_ids = set()
    terminal = 0
    for scene in bp["scenes"]:
        if not isinstance(scene, dict) or set(scene) != {
            "id", "text", "terminal", "choices"
        } or not isinstance(scene["id"], str) or \
                not ID_RE.fullmatch(scene["id"]) or \
                scene["id"] in scene_ids or \
                not isinstance(scene["text"], str) or \
                len(scene["text"]) > 50000 or \
                type(scene["terminal"]) is not bool or \
                not isinstance(scene["choices"], list):
            fail("Malformed or duplicate scene")
        scene_ids.add(scene["id"])
        terminal += int(scene["terminal"])
        if scene["terminal"] and scene["choices"] or \
                not scene["terminal"] and not scene["choices"] or \
                len(scene["choices"]) > 100:
            fail("Inconsistent terminal scene")
        for choice in scene["choices"]:
            if not isinstance(choice, dict) or set(choice) != {
                "id", "label", "next_scene_id", "conditions", "effects"
            } or not isinstance(choice["id"], str) or \
                    not ID_RE.fullmatch(choice["id"]) or \
                    choice["id"] in choice_ids or \
                    not isinstance(choice["label"], str) or \
                    not 0 < len(choice["label"]) <= 600 or \
                    not isinstance(choice["conditions"], list) or \
                    not isinstance(choice["effects"], list):
                fail("Malformed or duplicate choice")
            choice_ids.add(choice["id"])
    if not terminal or bp["entry_scene_id"] not in scene_ids:
        fail("Missing entry or terminal scene")
    for scene in bp["scenes"]:
        for choice in scene["choices"]:
            if choice["next_scene_id"] not in scene_ids:
                fail("Dangling choice destination")


SCHEMA = """
CREATE TABLE world_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE scenes(
 scene_id TEXT PRIMARY KEY, body TEXT NOT NULL,
 terminal INTEGER NOT NULL CHECK(terminal IN (0,1)));
CREATE TABLE choices(
 choice_id TEXT PRIMARY KEY, scene_id TEXT NOT NULL
 REFERENCES scenes(scene_id), sort_order INTEGER NOT NULL,
 label TEXT NOT NULL, next_scene_id TEXT NOT NULL REFERENCES scenes(scene_id),
 conditions_json TEXT NOT NULL, effects_json TEXT NOT NULL,
 UNIQUE(scene_id,sort_order));
CREATE TABLE actors(actor_id TEXT PRIMARY KEY);
CREATE TABLE items(item_id TEXT PRIMARY KEY);
CREATE TABLE canon_facts(fact_id TEXT PRIMARY KEY);
CREATE TABLE source_refs(
 ref_id TEXT PRIMARY KEY,
 scene_id TEXT NOT NULL REFERENCES scenes(scene_id),
 chapter_id TEXT NOT NULL, start_offset INTEGER NOT NULL,
 end_offset INTEGER NOT NULL);
CREATE TABLE event_dependencies(
 choice_id TEXT NOT NULL REFERENCES choices(choice_id),
 dependency_id TEXT NOT NULL, PRIMARY KEY(choice_id,dependency_id));
CREATE TABLE templates(template_id TEXT PRIMARY KEY, template TEXT NOT NULL);
"""


def create_database(bp: dict) -> bytes:
    db = sqlite3.connect(":memory:")
    try:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute(f"PRAGMA application_id={APPLICATION_ID}")
        db.execute("PRAGMA user_version=1")
        db.executescript(SCHEMA)
        meta = {
            "schema_version": "1",
            "bookworld_id": bp["book_id"],
            "blueprint_sha256": digest(canonical(bp)),
            "initial_state_json": canonical(bp["initial_state"]).decode("utf-8"),
        }
        db.executemany("INSERT INTO world_meta VALUES(?, ?)", sorted(meta.items()))
        db.executemany("INSERT INTO scenes VALUES(?, ?, ?)",
                       [(s["id"], s["text"], int(s["terminal"])) for s in bp["scenes"]])
        rows = [
            (c["id"], s["id"], index, c["label"], c["next_scene_id"],
             canonical(c["conditions"]).decode("utf-8"),
             canonical(c["effects"]).decode("utf-8"))
            for s in bp["scenes"] for index, c in enumerate(s["choices"])
        ]
        db.executemany("INSERT INTO choices VALUES(?, ?, ?, ?, ?, ?, ?)", rows)
        for table, field, column in [
            ("actors", "actors", "actor_id"),
            ("items", "items", "item_id"),
            ("canon_facts", "facts", "fact_id"),
        ]:
            ids = bp[field]
            if not isinstance(ids, list) or len(ids) != len(set(ids)) or \
                    any(not isinstance(v, str) or not ID_RE.fullmatch(v) for v in ids):
                fail("Invalid catalog")
            db.executemany(f"INSERT INTO {table}({column}) VALUES(?)",
                           [(v,) for v in ids])
        db.commit()
        data = db.serialize()
        if len(data) > MAX_ENTRY_BYTES:
            fail("SQLite exceeds package size limit")
        return data
    finally:
        db.close()


def _manifest(bp: dict, sqlite_bytes: bytes, blueprint_bytes: bytes) -> dict:
    hashes = {
        "scenario/blueprint.json": digest(blueprint_bytes),
        "world.sqlite": digest(sqlite_bytes),
    }
    return {
        "format": FORMAT, "format_version": VERSION,
        "bookworld_id": bp["book_id"],
        "source_fingerprint": None,
        "title": bp["title"], "author": "AI Story RPG",
        "languages": ["ru"],
        "engine_min_version": "0.1.0",
        "scenario_format": "ai_story_blueprint_v1",
        "scenario_format_version": 1,
        "content_capabilities": bp["supported_modes"],
        "build_status": "original_demo_verified",
        "rights_status": "original_demo",
        "build_tool": {"name": "ai_story_offline_bookworld", "version": "1.0"},
        "model_provenance": {"provider": "none", "model_id": None},
        "hashes": hashes,
        "sizes": {
            "scenario/blueprint.json": len(blueprint_bytes),
            "world.sqlite": len(sqlite_bytes),
        },
        "blueprint_sha256": digest(blueprint_bytes),
    }


def build(blueprint: dict) -> bytes:
    validate_blueprint(blueprint)
    scenario = canonical(blueprint)
    sqlite_bytes = create_database(blueprint)
    manifest = canonical(_manifest(blueprint, sqlite_bytes, scenario))
    streams = {
        "manifest.json": manifest,
        "scenario/blueprint.json": scenario,
        "world.sqlite": sqlite_bytes,
    }
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED,
                         allowZip64=False) as target:
        for name in EXPECTED:
            info = zipfile.ZipInfo(name, date_time=ZIP_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o600) << 16
            target.writestr(info, streams[name])
    archive = out.getvalue()
    if len(archive) > MAX_ARCHIVE_BYTES:
        fail("Archive exceeds size limit")
    verify(archive)
    return archive


def _validate_manifest(manifest: dict, blueprint: dict,
                       files: dict[str, bytes]) -> None:
    if set(manifest) != MANDATORY_MANIFEST or \
            manifest["format"] != FORMAT or \
            type(manifest["format_version"]) is not int or \
            manifest["format_version"] != VERSION or \
            manifest["bookworld_id"] != blueprint["book_id"] or \
            manifest["title"] != blueprint["title"] or \
            manifest["source_fingerprint"] is not None or \
            manifest["rights_status"] != "original_demo" or \
            manifest["build_status"] != "original_demo_verified" or \
            manifest["languages"] != ["ru"] or \
            manifest["engine_min_version"] != "0.1.0" or \
            manifest["scenario_format"] != "ai_story_blueprint_v1" or \
            manifest["scenario_format_version"] != 1 or \
            manifest["content_capabilities"] != blueprint["supported_modes"] or \
            manifest["build_tool"] != {"name": "ai_story_offline_bookworld",
                                       "version": "1.0"} or \
            manifest["model_provenance"] != {"provider": "none", "model_id": None}:
        fail("Unsupported/incompatible/forged manifest")
    expected_paths = {"scenario/blueprint.json", "world.sqlite"}
    if not isinstance(manifest["hashes"], dict) or \
            set(manifest["hashes"]) != expected_paths or \
            not isinstance(manifest["sizes"], dict) or \
            set(manifest["sizes"]) != expected_paths:
        fail("Invalid manifest digest catalog")
    for path in sorted(expected_paths):
        expected = manifest["hashes"][path]
        declared_size = manifest["sizes"][path]
        if not isinstance(expected, str) or not SHA_RE.fullmatch(expected) or \
                type(declared_size) is not int or declared_size != len(files[path]) or \
                expected != digest(files[path]):
            fail(f"Size/digest mismatch: {path}")
    if manifest["blueprint_sha256"] != digest(canonical(blueprint)) or \
            files["scenario/blueprint.json"] != canonical(blueprint):
        fail("Noncanonical or altered blueprint")


def _check_sqlite(blob: bytes, bp: dict) -> None:
    if not blob.startswith(SQLITE_MAGIC) or len(blob) > MAX_ENTRY_BYTES:
        fail("Not a valid SQLite database header")
    db = sqlite3.connect(":memory:")
    try:
        db.deserialize(blob)
        db.execute("PRAGMA query_only=ON")
        db.execute("PRAGMA trusted_schema=OFF")
        db.execute("PRAGMA foreign_keys=ON")
        if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            fail("SQLite integrity_check failed")
        if db.execute("PRAGMA foreign_key_check").fetchall():
            fail("SQLite foreign_key_check failed")
        if db.execute("PRAGMA application_id").fetchone()[0] != APPLICATION_ID or \
                db.execute("PRAGMA user_version").fetchone()[0] != 1:
            fail("Invalid SQLite format version")
        objects = db.execute(
            "SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
        ).fetchall()
        if set(objects) != {("table", name) for name in ALLOWED_SQL_TABLES}:
            fail("Unexpected database objects or missing tables")
        meta = dict(db.execute("SELECT key, value FROM world_meta"))
        if meta != {
            "schema_version": "1",
            "bookworld_id": bp["book_id"],
            "blueprint_sha256": digest(canonical(bp)),
            "initial_state_json": canonical(bp["initial_state"]).decode("utf-8"),
        }:
            fail("World metadata does not match blueprint")
        scene_rows = db.execute(
            "SELECT scene_id, body, terminal FROM scenes ORDER BY rowid"
        ).fetchall()
        wanted_scenes = [
            (s["id"], s["text"], int(s["terminal"])) for s in bp["scenes"]
        ]
        if scene_rows != wanted_scenes:
            fail("World SQLite scenes disagree with blueprint")
        choice_rows = db.execute(
            """SELECT choice_id, scene_id, sort_order, label, next_scene_id,
                      conditions_json, effects_json FROM choices ORDER BY rowid"""
        ).fetchall()
        wanted_choices = [
            (c["id"], s["id"], index, c["label"], c["next_scene_id"],
             canonical(c["conditions"]).decode("utf-8"),
             canonical(c["effects"]).decode("utf-8"))
            for s in bp["scenes"] for index, c in enumerate(s["choices"])
        ]
        if choice_rows != wanted_choices:
            fail("World SQLite choices disagree with blueprint")
        for table, field, column in [
            ("actors", "actors", "actor_id"),
            ("items", "items", "item_id"),
            ("canon_facts", "facts", "fact_id"),
        ]:
            rows = [row[0] for row in db.execute(f"SELECT {column} FROM {table}")]
            if rows != bp[field]:
                fail(f"World SQLite {table} catalog mismatch")
        for table in ("source_refs", "event_dependencies", "templates"):
            if db.execute(f"SELECT count(*) FROM {table}").fetchone()[0] != 0:
                fail(f"Unverified {table} rows in demo format")
    except sqlite3.DatabaseError as exc:
        fail(f"SQLite rejected database: {exc}")
    finally:
        db.close()


def verify(data: bytes) -> dict:
    if not isinstance(data, bytes) or len(data) > MAX_ARCHIVE_BYTES or \
            len(data) < 100:
        fail("Invalid archive length")
    try:
        with zipfile.ZipFile(io.BytesIO(data), "r", allowZip64=False) as z:
            if z.comment:
                fail("ZIP comments are not supported")
            entries = z.infolist()
            if len(entries) != len(EXPECTED):
                fail("Unexpected ZIP entries")
            names = [info.filename for info in entries]
            if names != list(EXPECTED) or len(names) != len(set(names)):
                fail("Unsafe, missing, duplicate or unordered ZIP paths")
            total = 0
            for info in entries:
                path = info.filename
                if not path.isascii() or "\\" in path or ".." in path or \
                        path.startswith("/") or ":" in path:
                    fail("Unsafe ZIP path")
                mode = info.external_attr >> 16
                if info.is_dir() or stat.S_IFMT(mode) == stat.S_IFLNK or \
                        info.flag_bits & 0x1 or \
                        info.compress_type != zipfile.ZIP_STORED or \
                        info.file_size > MAX_ENTRY_BYTES or \
                        info.compress_size != info.file_size:
                    fail("Unsupported, encrypted or oversized ZIP entry")
                total += info.file_size
            if total > MAX_UNCOMPRESSED_BYTES:
                fail("Uncompressed ZIP limit")
            files = {name: z.read(name) for name in EXPECTED}
    except (zipfile.BadZipFile, zipfile.LargeZipFile, RuntimeError,
            EOFError, OverflowError, OSError) as exc:
        fail(f"Corrupted ZIP: {exc}")
    bp = decode_object(files["scenario/blueprint.json"], "blueprint")
    validate_blueprint(bp)
    manifest = decode_object(files["manifest.json"], "manifest")
    _validate_manifest(manifest, bp, files)
    _check_sqlite(files["world.sqlite"], bp)
    return {
        "bookworld_id": manifest["bookworld_id"],
        "blueprint_sha256": manifest["blueprint_sha256"],
        "scene_count": len(bp["scenes"]),
        "choice_count": sum(len(s["choices"]) for s in bp["scenes"]),
        "archive_sha256": digest(data),
        "format_version": VERSION,
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Offline .bworld v1 compiler/verifier")
    sub = p.add_subparsers(dest="command", required=True)
    make = sub.add_parser("build")
    make.add_argument("--blueprint", type=Path, required=True)
    make.add_argument("--output", type=Path, required=True)
    check = sub.add_parser("verify")
    check.add_argument("--input", type=Path, required=True)
    args = p.parse_args()
    if args.command == "build":
        blueprint = decode_object(args.blueprint.read_bytes(), "blueprint")
        archive = build(blueprint)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(archive)
        print(json.dumps(verify(archive), ensure_ascii=False, sort_keys=True))
    else:
        print(json.dumps(verify(args.input.read_bytes()),
                         ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (BookworldError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
