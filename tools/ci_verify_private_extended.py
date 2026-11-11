"""Independent structural cross-language check of Dart-created PRIVATE v4.

This verifies the ZIP envelope, source binding, SQLite row equality and new
versioned initial-state evidence for the 203-scene regression fixture.
The strict bounded causal *semantics* remain enforced by Dart's importer;
this is not a replacement for that independent engine validation or literary
CANON certification.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path


def verify(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if len(data) > 12 * 1024 * 1024:
        raise ValueError("Oversized BookWorld")
    names = [
        "manifest.json", "scenario/blueprint.json",
        "source/provenance.json", "world.sqlite",
    ]
    with zipfile.ZipFile(path) as zf:
        if zf.namelist() != names:
            raise ValueError("Wrong or reordered ZIP members")
        for info in zf.infolist():
            if info.compress_type != zipfile.ZIP_STORED or info.flag_bits:
                raise ValueError("Unexpected ZIP features")
        files = {name: zf.read(name) for name in names}
    manifest = json.loads(files[names[0]])
    bp = json.loads(files[names[1]])
    provenance = json.loads(files[names[2]])
    if (manifest["format"] != "ai_story_bookworld"
            or manifest["format_version"] != 4
            or manifest["build_status"] != "private_extended_structural"
            or manifest["build_tool"] != {
                "name": "ai_story_private_extended_bookworld", "version": "4.0"
            } or manifest["rights_status"] != "private_use_only"
            or bp["rights_status"] != "private_adaptation"
            or bp["source_fingerprint"] != provenance["source_fingerprint"]
            or bp["source_fingerprint"] != manifest["source_fingerprint"]
            or manifest["blueprint_sha256"] != hashlib.sha256(files[names[1]]).hexdigest()):
        raise ValueError("Unsupported v4 binding")
    for name in names[1:]:
        if (manifest["hashes"][name] != hashlib.sha256(files[name]).hexdigest()
                or manifest["sizes"][name] != len(files[name])):
            raise ValueError("SHA/size mismatch for " + name)
    scenes = bp["scenes"]
    origins = provenance["scene_origins"]
    if len(scenes) <= 192 or len(scenes) != len(origins):
        raise ValueError("The extended-book regression was truncated")
    if [x["id"] for x in scenes] != [x["scene_id"] for x in origins]:
        raise ValueError("Source/scene ordering corrupted")
    review = provenance.get("initial_state_review")
    state = bp["initial_state"]
    has_initial_data = bool(state["inventory"]) or bool(
        [fact for facts in state["knowledge"].values() for fact in facts]
    ) or state["tick"] > 0
    if has_initial_data:
        if (manifest.get("initial_state_review_format") != "ai_story_private_initial_state_review_v1"
                or not isinstance(review, dict)
                or review["user_confirmed"] is not True
                or review["literary_canon_verified"] is not False
                or review["source_fingerprint"] != bp["source_fingerprint"]
                or review["initial_tick"] != state["tick"]
                or {i["item_id"] for i in review["item_grants"]} != set(state["inventory"])
                or {(x["actor_id"], x["fact_id"]) for x in review["fact_grants"]}
                    != {(actor, fact) for actor, facts in state["knowledge"].items() for fact in facts}):
            raise ValueError("Initial state custody/knowledge review mismatch")
    elif review is not None or "initial_state_review_format" in manifest:
        raise ValueError("Extra initial review on empty authoring world")
    with tempfile.TemporaryDirectory(prefix="ai_story_v4_py_") as folder:
        db_path = Path(folder) / "world.sqlite"
        db_path.write_bytes(files["world.sqlite"])
        uri = db_path.resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(uri, uri=True) as db:
            if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("SQLite integrity check failed")
            sqlite_scenes = db.execute("SELECT scene_id FROM scenes ORDER BY rowid").fetchall()
            if [x[0] for x in sqlite_scenes] != [x["id"] for x in scenes]:
                raise ValueError("SQLite scenes differ from exact blueprint")
            meta = dict(db.execute("SELECT key,value FROM world_meta").fetchall())
            if meta["blueprint_sha256"] != manifest["blueprint_sha256"]:
                raise ValueError("SQLite blueprint hash differs")
            if json.loads(meta["initial_state_json"]) != state:
                raise ValueError("SQLite initial knowledge/inventory/time differs")
    return {
        "format_version": 4,
        "scenes": len(scenes),
        "source_fingerprint": bp["source_fingerprint"],
        "can_publish_publicly": False,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tools/ci_verify_private_extended.py path.bworld")
    print(json.dumps(verify(Path(sys.argv[1])), ensure_ascii=False))
