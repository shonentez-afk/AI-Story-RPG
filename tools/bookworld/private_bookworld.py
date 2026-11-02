"""M2d private-only .bworld v2 compiler and adversarial verifier.

This standalone offline tool consumes already editorially reviewed, typed
blueprint/provenance JSON, not a raw book or an AI response. Integrity checks
prove archive consistency, NOT authorship, copyright, source quotation truth,
or permission to publish. original_demo v1 remains handled only by bookworld.py.
"""
from __future__ import annotations

import argparse
import io
import json
import re
import stat
import struct
import sys
import zipfile
from pathlib import Path

from tools.bookworld import bookworld as legacy

PATHS = ("manifest.json", "scenario/blueprint.json",
         "source/provenance.json", "world.sqlite")
PAYLOAD = set(PATHS[1:])
SHA = re.compile(r"^[0-9a-f]{64}$")
SHA_ID = re.compile(r"^[0-9a-f]{32}$")
M2_ID = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
MAX_SCENES = 192
MAX_STATES = 2500


def fail(message: str):
    raise legacy.BookworldError(message)


def _is_int(value: object) -> bool:
    return type(value) is int


def _keys(value: object, keys: set[str], where: str):
    if type(value) is not dict or set(value) != keys:
        fail(f"{where}: invalid fields")


def _sha(value: object) -> bool:
    return isinstance(value, str) and bool(SHA.fullmatch(value))


def _id32(value: object) -> bool:
    return isinstance(value, str) and bool(SHA_ID.fullmatch(value))


def _valid_provenance(prov: dict, bp: dict):
    _keys(prov, {
        "format", "bookworld_id", "source_fingerprint", "source_title",
        "source_author", "source_chapters_total", "source_chapters_indexed",
        "semantic_catalog_sha256", "intermediate_draft_sha256",
        "rights_status", "publication_authorized", "model_provenance",
        "scene_origins",
    }, "provenance")
    if prov["format"] != "ai_story_private_provenance_v1" or \
            prov["bookworld_id"] != bp["book_id"] or \
            prov["source_fingerprint"] != bp["source_fingerprint"] or \
            not isinstance(prov["source_title"], str) or \
            not 0 < len(prov["source_title"].strip()) <= 256 or \
            not isinstance(prov["source_author"], str) or \
            len(prov["source_author"]) > 256 or \
            not _sha(prov["semantic_catalog_sha256"]) or \
            not _sha(prov["intermediate_draft_sha256"]) or \
            prov["rights_status"] != "private_use_only" or \
            prov["publication_authorized"] is not False or \
            prov["model_provenance"] != {
                "provider": "none", "model_id": None,
            }:
        fail("Provenance source, rights or provider are invalid")
    total = prov["source_chapters_total"]
    indexed = prov["source_chapters_indexed"]
    if not _is_int(total) or not _is_int(indexed) or \
            total < 1 or total > 10000 or indexed < 1 or indexed > total:
        fail("Invalid chapter coverage")
    origins = prov["scene_origins"]
    if type(origins) is not list or len(origins) != len(bp["scenes"]):
        fail("Missing scene provenance")
    source_count = alternate_count = 0
    for scene, record in zip(bp["scenes"], origins):
        _keys(record, {"scene_id", "chapter_index", "origin",
                       "assertion_ids", "source_refs"}, "scene origin")
        chapter = record["chapter_index"]
        claims = record["assertion_ids"]
        refs = record["source_refs"]
        if record["scene_id"] != scene["id"] or not _is_int(chapter) or \
                chapter < 0 or chapter >= total or \
                record["origin"] not in ("SOURCE_PASSAGE",
                                         "EXPLICIT_ADAPTATION") or \
                type(claims) is not list or len(claims) > 24 or \
                len(claims) != len(set(claims)) or \
                any(not _id32(value) for value in claims) or \
                type(refs) is not list or len(refs) > 72:
            fail("Invalid scene origin or claims")
        if record["origin"] == "SOURCE_PASSAGE":
            source_count += 1
            if not claims or not refs:
                fail("Source scene has no evidence")
        else:
            alternate_count += 1
        seen = set()
        for ref in refs:
            _keys(ref, {
                "id", "chunk_id", "chapter_id", "chapter_index",
                "block_index", "start_utf16", "end_utf16",
                "quote_sha256", "visible_after_chapter",
            }, "source ref")
            i = ref["chapter_index"]
            v = ref["visible_after_chapter"]
            start = ref["start_utf16"]
            end = ref["end_utf16"]
            if not _id32(ref["id"]) or ref["id"] in seen or \
                    not isinstance(ref["chunk_id"], str) or \
                    not 0 < len(ref["chunk_id"]) <= 120 or \
                    not isinstance(ref["chapter_id"], str) or \
                    not 0 < len(ref["chapter_id"]) <= 120 or \
                    not _is_int(i) or i < 0 or i >= total or i > chapter or \
                    not _is_int(ref["block_index"]) or \
                    ref["block_index"] < 0 or \
                    not _is_int(v) or v < i or v > chapter or \
                    not _is_int(start) or not _is_int(end) or \
                    start < 0 or end <= start or end - start > 180 or \
                    not _sha(ref["quote_sha256"]):
                fail("Unverified citation range or future spoiler")
            seen.add(ref["id"])
    if not source_count or not alternate_count:
        fail("No source scene or alternate path")


def _valid_blueprint(bp: dict):
    _keys(bp, {
        "format", "schema_version", "book_id", "title", "entry_scene_id",
        "rights_status", "source_fingerprint", "supported_modes", "items",
        "facts", "actors", "initial_state", "scenes",
    }, "private blueprint")
    if bp["format"] != "ai_story_blueprint_v1" or \
            bp["schema_version"] != 1 or \
            bp["rights_status"] != "private_adaptation" or \
            not _sha(bp["source_fingerprint"]) or \
            not isinstance(bp["book_id"], str) or \
            not M2_ID.fullmatch(bp["book_id"]) or \
            not isinstance(bp["title"], str) or \
            not 0 < len(bp["title"].strip()) <= 256 or \
            bp["supported_modes"] != {
                "roles": ["PROTAGONIST"], "plots": ["ALTER_FATE"],
                "interactions": ["CLASSIC"],
            } or bp["items"] != [] or bp["facts"] != [] or \
            bp["actors"] != ["player"]:
        fail("Private-only blueprint contract violated")
    state = bp["initial_state"]
    _keys(state, {
        "scene_id", "revision", "tick", "stats",
        "inventory", "flags", "knowledge",
    }, "private initial state")
    flags = state["flags"]
    if state["revision"] != 0 or state["tick"] != 0 or \
            state["stats"] != {} or state["inventory"] != [] or \
            state["knowledge"] != {"player": []} or \
            type(flags) is not dict or len(flags) > 32 or \
            any(not isinstance(k, str) or not M2_ID.fullmatch(k) or
                type(v) is not bool for k, v in flags.items()) or \
            state["scene_id"] != bp["entry_scene_id"]:
        fail("Invalid initial state")
    scenes = bp["scenes"]
    if type(scenes) is not list or not 3 <= len(scenes) <= MAX_SCENES:
        fail("No private causal scenes")
    ids = set()
    choice_ids = set()
    for scene in scenes:
        _keys(scene, {"id", "text", "terminal", "choices"}, "scene")
        if not isinstance(scene["id"], str) or \
                not M2_ID.fullmatch(scene["id"]) or scene["id"] in ids or \
                not isinstance(scene["text"], str) or \
                not 0 < len(scene["text"].strip()) <= 6000 or \
                type(scene["terminal"]) is not bool or \
                type(scene["choices"]) is not list or \
                len(scene["choices"]) > 16 or \
                scene["terminal"] == bool(scene["choices"]):
            fail("Invalid private scene")
        ids.add(scene["id"])
        for choice in scene["choices"]:
            _keys(choice, {
                "id", "label", "next_scene_id", "conditions", "effects",
            }, "choice")
            if not isinstance(choice["id"], str) or \
                    not M2_ID.fullmatch(choice["id"]) or \
                    choice["id"] in choice_ids or \
                    not isinstance(choice["next_scene_id"], str) or \
                    not M2_ID.fullmatch(choice["next_scene_id"]) or \
                    not isinstance(choice["label"], str) or \
                    not 0 < len(choice["label"].strip()) <= 300 or \
                    type(choice["conditions"]) is not list or \
                    type(choice["effects"]) is not list or \
                    len(choice["conditions"]) > 32 or \
                    len(choice["effects"]) > 32:
                fail("Invalid private choice")
            choice_ids.add(choice["id"])
            for rule in choice["conditions"]:
                _keys(rule, {"op", "id", "value"}, "condition")
                if rule["op"] != "flag_is" or \
                        rule["id"] not in flags or type(rule["value"]) is not bool:
                    fail("Unsafe condition")
            for rule in choice["effects"]:
                _keys(rule, {"op", "id", "value"}, "effect")
                if rule["op"] != "set_flag" or \
                        rule["id"] not in flags or type(rule["value"]) is not bool:
                    fail("Unsafe effect")
    if bp["entry_scene_id"] not in ids or \
            any(c["next_scene_id"] not in ids for scene in scenes
                for c in scene["choices"]):
        fail("Missing entry or destination")
    _validate_causality(bp)


def _validate_causality(bp: dict):
    scenes = {scene["id"]: scene for scene in bp["scenes"]}
    initial = tuple(sorted(k for k, v in bp["initial_state"]["flags"].items()
                           if v))
    start = (bp["entry_scene_id"], initial)
    queue = [start]
    seen = {start}
    visited_scenes = set()
    parents: dict[tuple, set[tuple]] = {}
    terminal_states = set()
    endings = set()
    for scene_id, active in queue:
        if len(queue) > MAX_STATES:
            fail("Too many states")
        scene = scenes[scene_id]
        visited_scenes.add(scene_id)
        if scene["terminal"]:
            terminal_states.add((scene_id, active))
            endings.add(scene_id)
            continue
        available = 0
        for choice in scene["choices"]:
            if any((rule["id"] in active) != rule["value"]
                   for rule in choice["conditions"]):
                continue
            available += 1
            next_active = set(active)
            for effect in choice["effects"]:
                if effect["value"]:
                    next_active.add(effect["id"])
                else:
                    next_active.discard(effect["id"])
            dest = (choice["next_scene_id"], tuple(sorted(next_active)))
            parents.setdefault(dest, set()).add((scene_id, active))
            if dest not in seen:
                seen.add(dest)
                queue.append(dest)
        if not available:
            fail("Playable dead end")
    if len(endings) < 2 or len(visited_scenes) != len(scenes):
        fail("Unreachable scenes or missing alternative ending")
    can_escape = set(terminal_states)
    to_check = list(terminal_states)
    while to_check:
        state = to_check.pop()
        for previous in parents.get(state, ()):
            if previous not in can_escape:
                can_escape.add(previous)
                to_check.append(previous)
    if len(can_escape) != len(seen):
        fail("Cycle without ending")


def verify_source_index(bp: dict, prov: dict, source_index: dict):
    """Check every provenance slice against actual index text before build.

    The portable ZIP deliberately omits source text. Later re-import verifies
    only the bound hashes; authoring MUST receive the trusted local index.
    """
    if not isinstance(source_index, dict) or \
            source_index.get("source_fingerprint") != bp["source_fingerprint"] or \
            source_index.get("chapter_count") != prov["source_chapters_total"] or \
            source_index.get("indexed_chapter_count") != \
                prov["source_chapters_indexed"] or \
            not _is_int(source_index.get("text_total_utf16")) or \
            source_index.get("text_indexed_utf16") != \
                source_index.get("text_total_utf16"):
        fail("Source edition and 100% text indexing must be verified")
    chunks = source_index.get("chunks")
    if not isinstance(chunks, list) or not 0 < len(chunks) <= 30000:
        fail("Invalid source chunk registry")
    by_id = {}
    for entry in chunks:
        if not isinstance(entry, dict):
            fail("Malformed source chunk")
        required = {
            "id", "chapter_index", "chapter_id", "block_index",
            "start_utf16", "end_utf16", "text", "sha256_text",
        }
        if not required.issubset(entry):
            fail("Incomplete source chunk")
        chunk_id = entry["id"]
        content = entry["text"]
        if not isinstance(chunk_id, str) or chunk_id in by_id or \
                not isinstance(content, str) or not _sha(entry["sha256_text"]) or \
                legacy.digest(content.encode("utf-8")) != entry["sha256_text"]:
            fail("Source chunk hash does not match text")
        units = content.encode("utf-16-le", errors="surrogatepass")
        if not _is_int(entry["start_utf16"]) or \
                not _is_int(entry["end_utf16"]) or \
                entry["end_utf16"] - entry["start_utf16"] != len(units) // 2:
            fail("Wrong UTF-16 chunk boundaries")
        by_id[chunk_id] = entry
    for scene in prov["scene_origins"]:
        for proof in scene["source_refs"]:
            chunk = by_id.get(proof["chunk_id"])
            if chunk is None or \
                    chunk["chapter_id"] != proof["chapter_id"] or \
                    chunk["chapter_index"] != proof["chapter_index"] or \
                    chunk["block_index"] != proof["block_index"] or \
                    proof["start_utf16"] < chunk["start_utf16"] or \
                    proof["end_utf16"] > chunk["end_utf16"]:
                fail("A cited passage is not in the original source chunk")
            u16 = chunk["text"].encode("utf-16-le", errors="surrogatepass")
            a = 2 * (proof["start_utf16"] - chunk["start_utf16"])
            b = 2 * (proof["end_utf16"] - chunk["start_utf16"])
            try:
                exact = u16[a:b].decode("utf-16-le", errors="strict")
            except UnicodeError:
                fail("Citation splits a Unicode surrogate pair")
            if not exact.strip() or \
                    legacy.digest(exact.encode("utf-8")) != \
                    proof["quote_sha256"]:
                fail("Forged or changed exact source quotation")


def _manifest(bp: dict, prov: dict, payloads: dict[str, bytes]) -> dict:
    return {
        "format": "ai_story_bookworld", "format_version": 2,
        "bookworld_id": bp["book_id"],
        "source_fingerprint": bp["source_fingerprint"],
        "title": bp["title"],
        "author": prov["source_author"],
        "languages": ["ru"], "engine_min_version": "0.1.0",
        "scenario_format": "ai_story_blueprint_v1",
        "scenario_format_version": 1,
        "content_capabilities": bp["supported_modes"],
        "build_status": "private_classic_structural",
        "rights_status": "private_use_only",
        "build_tool": {"name": "ai_story_private_bookworld", "version": "2.0"},
        "model_provenance": {"provider": "none", "model_id": None},
        "hashes": {path: legacy.digest(payloads[path]) for path in PAYLOAD},
        "sizes": {path: len(payloads[path]) for path in PAYLOAD},
        "blueprint_sha256": legacy.digest(payloads["scenario/blueprint.json"]),
    }


def build(blueprint: dict, provenance: dict, source_index: dict) -> bytes:
    _valid_blueprint(blueprint)
    _valid_provenance(provenance, blueprint)
    verify_source_index(blueprint, provenance, source_index)
    payloads = {
        "scenario/blueprint.json": legacy.canonical(blueprint),
        "source/provenance.json": legacy.canonical(provenance),
        "world.sqlite": legacy.create_database(blueprint),
    }
    files = {"manifest.json": legacy.canonical(
        _manifest(blueprint, provenance, payloads)), **payloads}
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED,
                         allowZip64=False) as target:
        for path in PATHS:
            info = zipfile.ZipInfo(path, date_time=legacy.ZIP_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o600) << 16
            target.writestr(info, files[path])
    result = out.getvalue()
    if len(result) > legacy.MAX_ARCHIVE_BYTES:
        fail("Oversized private .bworld")
    verify(result)
    return result


def _safe_entries(archive: bytes) -> dict[str, bytes]:
    if not isinstance(archive, bytes) or \
            len(archive) > legacy.MAX_ARCHIVE_BYTES or len(archive) < 100:
        fail("Invalid v2 archive length")
    # V2 has no ZIP comment, prefix, suffix or data descriptors. This is an
    # independent check in addition to the Dart ZIP local/central parser.
    if archive[-22:-18] != b"PK\x05\x06":
        fail("ZIP must end with an exact EOCD record")
    end = struct.unpack_from("<IHHHHIIH", archive, len(archive) - 22)
    if end[1] or end[2] or end[3] != 4 or end[4] != 4 or end[7]:
        fail("Invalid v2 ZIP EOCD")
    if end[6] + end[5] != len(archive) - 22:
        fail("ZIP central directory is not contiguous")
    try:
        with zipfile.ZipFile(io.BytesIO(archive), "r",
                             allowZip64=False) as z:
            entries = z.infolist()
            if [i.filename for i in entries] != list(PATHS) or z.comment:
                fail("Unexpected ordered private ZIP entries")
            files = {}
            total = 0
            next_offset = 0
            for item in entries:
                if item.header_offset != next_offset or item.flag_bits or \
                        item.compress_type != zipfile.ZIP_STORED or \
                        item.extra or item.comment or \
                        item.file_size != item.compress_size or \
                        item.file_size > legacy.MAX_ENTRY_BYTES or \
                        item.is_dir() or \
                        stat.S_IFMT(item.external_attr >> 16) == stat.S_IFLNK:
                    fail("Unsafe private ZIP entry")
                if not item.filename.isascii() or ".." in item.filename or \
                        "\\" in item.filename or ":" in item.filename:
                    fail("Unsafe entry path")
                local = struct.unpack_from("<IHHHHHIIIHH", archive,
                                           item.header_offset)
                if local[0] != 0x04034b50 or local[2] or local[3] or \
                        local[6] != item.CRC or local[7] != item.file_size or \
                        local[8] != item.file_size or \
                        local[9] != len(item.filename.encode('ascii')) or \
                        local[10]:
                    fail("Local/central ZIP mismatch")
                next_offset += 30 + len(item.filename.encode("ascii")) + \
                    item.file_size
                files[item.filename] = z.read(item.filename)
                total += item.file_size
            if total > legacy.MAX_UNCOMPRESSED_BYTES or \
                    next_offset != end[6]:
                fail("Unexpected private ZIP payload")
            return files
    except (zipfile.BadZipFile, zipfile.LargeZipFile, OSError,
            RuntimeError, EOFError, OverflowError, struct.error) as exc:
        fail(f"Corrupt v2 ZIP: {exc}")


def verify(archive: bytes) -> dict:
    files = _safe_entries(archive)
    bp = legacy.decode_object(files["scenario/blueprint.json"], "blueprint")
    prov = legacy.decode_object(files["source/provenance.json"], "provenance")
    manifest = legacy.decode_object(files["manifest.json"], "manifest")
    if files["scenario/blueprint.json"] != legacy.canonical(bp) or \
            files["source/provenance.json"] != legacy.canonical(prov) or \
            files["manifest.json"] != legacy.canonical(manifest):
        fail("Noncanonical or duplicated JSON")
    _valid_blueprint(bp)
    _valid_provenance(prov, bp)
    expected = _manifest(bp, prov, {
        name: files[name] for name in PAYLOAD
    })
    if manifest != expected:
        fail("Invalid source/rights/manifest hash binding")
    legacy._check_sqlite(files["world.sqlite"], bp)
    return {
        "bookworld_id": bp["book_id"],
        "source_fingerprint": bp["source_fingerprint"],
        "scene_count": len(bp["scenes"]),
        "archive_sha256": legacy.digest(archive),
        "private_only": True,
        "publication_authorized": False,
        "format_version": 2,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Strict offline PRIVATE .bworld v2 build/verify")
    cmd = parser.add_subparsers(dest="command", required=True)
    make = cmd.add_parser("build")
    make.add_argument("--blueprint", type=Path, required=True)
    make.add_argument("--provenance", type=Path, required=True)
    make.add_argument("--index", type=Path, required=True)
    make.add_argument("--output", type=Path, required=True)
    check = cmd.add_parser("verify")
    check.add_argument("--input", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "build":
        bp = legacy.decode_object(args.blueprint.read_bytes(), "blueprint")
        prov = legacy.decode_object(args.provenance.read_bytes(), "provenance")
        index = legacy.decode_object(args.index.read_bytes(), "source_index")
        raw = build(bp, prov, index)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(raw)
        print(json.dumps(verify(raw), ensure_ascii=False, sort_keys=True))
    else:
        print(json.dumps(verify(args.input.read_bytes()),
                         ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (legacy.BookworldError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
