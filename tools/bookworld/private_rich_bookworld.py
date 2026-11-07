"""Public private-rich-v3 compiler and independent Python verifier.

The existing source, dialogue, social, bounded-state, ZIP and SQLite validators
are retained unchanged in private_rich_validation_core. This entrypoint joins
TWO independently checked review domains: ordinary player/inventory effects
and exact source-reviewed NPC knowledge grants. There is no schema change,
monkeypatch, second simulation, or implied literary-canon approval.
"""
from __future__ import annotations

from copy import deepcopy
import io
import stat
import zipfile

from tools.bookworld import private_rich_validation_core as _core

legacy = _core.legacy
v2 = _core.v2

# Keep the existing module API, including explicitly imported private helpers.
# No function in the shared core is modified or dynamically rebound.
__all__ = [name for name in vars(_core) if not name.startswith("_")]


def __getattr__(name):
    return getattr(_core, name)


def __dir__():
    return sorted(set(globals()) | set(dir(_core)))


def _gameplay_review(review, bp, prov):
    """Check the strict union without allowing actor or fact substitution.

    The original ordinary-review validator still sees every ordinary effect.
    Its temporary coverage view excludes only NPC learn_fact tuples that have
    ALREADY passed the complete source/actor/choice/hash NPC validation.
    The REAL blueprint, source and archive bytes are never modified.
    """
    _core._npc_knowledge(prov, bp)
    npc_review = prov.get("npc_knowledge")
    checked = {
        (g["scene_id"], g["choice_id"], g["actor_id"], g["fact_id"])
        for g in npc_review["grants"]
    } if npc_review is not None else set()
    if not checked:
        return _core._gameplay_review(review, bp, prov)
    ordinary = deepcopy(bp)
    for scene in ordinary["scenes"]:
        for choice in scene["choices"]:
            choice["effects"] = [
                effect for effect in choice["effects"]
                if not (
                    effect["op"] == "learn_fact"
                    and effect.get("actor") != "player"
                    and (scene["id"], choice["id"], effect.get("actor"),
                         effect.get("id")) in checked
                )
            ]
    # This is effect-coverage checking, not an alternate world simulation.
    # _blueprint/_npc_knowledge/_npc_social validated the untouched world.
    _core._gameplay_review(review, ordinary, prov)


def _provenance(prov, bp):
    keys = {"format", "bookworld_id", "source_fingerprint", "source_title",
            "source_author", "source_chapters_total", "source_chapters_indexed",
            "semantic_catalog_sha256", "intermediate_draft_sha256",
            "rights_status", "publication_authorized", "model_provenance",
            "scene_origins", "presentation"}
    _core._keys({k: v for k, v in prov.items()
                 if k not in {"gameplay_review", "npc_knowledge", "npc_social"}},
                keys, "rich provenance")
    if prov["format"] != _core.PROVENANCE_FORMAT:
        _core.fail("Wrong rich provenance format")
    _core._model(prov["model_provenance"])
    _core._npc_social(prov, bp)
    _core._presentation(prov["presentation"], bp, prov.get("npc_social"),
                        prov["scene_origins"])
    _core._npc_knowledge(prov, bp)
    if "gameplay_review" in prov:
        _gameplay_review(prov["gameplay_review"], bp, prov)
    old = dict(prov)
    old.pop("gameplay_review", None)
    old.pop("npc_knowledge", None)
    old.pop("npc_social", None)
    old.pop("presentation")
    old["format"] = "ai_story_private_provenance_v1"
    old["model_provenance"] = {"provider": "none", "model_id": None}
    v2._valid_provenance(old, bp)
    return old


def build(blueprint: dict, provenance: dict, source_index: dict) -> bytes:
    _core._blueprint(blueprint)
    old = _provenance(provenance, blueprint)
    v2.verify_source_index(blueprint, old, source_index)
    payloads = {
        "scenario/blueprint.json": legacy.canonical(blueprint),
        "source/provenance.json": legacy.canonical(provenance),
        "world.sqlite": legacy.create_database(blueprint),
    }
    members = {"manifest.json": legacy.canonical(
        _core._manifest(blueprint, provenance, payloads)), **payloads}
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED,
                         allowZip64=False) as target:
        for path in _core.PATHS:
            zi = zipfile.ZipInfo(path, date_time=legacy.ZIP_TIME)
            zi.compress_type = zipfile.ZIP_STORED
            zi.create_system = 3
            zi.external_attr = (stat.S_IFREG | 0o600) << 16
            target.writestr(zi, members[path])
    result = out.getvalue()
    if len(result) > legacy.MAX_ARCHIVE_BYTES:
        _core.fail("Rich private archive exceeds size limit")
    verify(result)
    return result


def verify(archive: bytes) -> dict:
    files = v2._safe_entries(archive)
    bp = legacy.decode_object(files["scenario/blueprint.json"], "blueprint")
    prov = legacy.decode_object(files["source/provenance.json"], "provenance")
    manifest = legacy.decode_object(files["manifest.json"], "manifest")
    for path, obj in [("scenario/blueprint.json", bp),
                      ("source/provenance.json", prov), ("manifest.json", manifest)]:
        if files[path] != legacy.canonical(obj):
            _core.fail("Non-canonical v3 JSON")
    _core._blueprint(bp)
    _provenance(prov, bp)
    if manifest != _core._manifest(bp, prov, {
            name: files[name] for name in v2.PAYLOAD}):
        _core.fail("Manifest/provenance/rights/hash binding invalid")
    legacy._check_sqlite(files["world.sqlite"], bp)
    return {"bookworld_id": bp["book_id"],
            "source_fingerprint": bp["source_fingerprint"],
            "scene_count": len(bp["scenes"]),
            "archive_sha256": legacy.digest(archive),
            "private_only": True, "publication_authorized": False,
            "format_version": 3, "rich_gameplay": True}
