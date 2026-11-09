"""Reviewed rich gameplay overlay for a validated external authoring project.

No unconstrained LLM JSON is allowed to reach the native importer. The story
must already have exact source citations and pass the E1 state simulator; the
overlay only adds typed, checked gameplay effects and Russian presentation.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import zipfile

from tools.bookworld import private_rich_bookworld as rich
from tools.rpg_author.common import (AuthoringError, atomic_write, canonical,
                                     digest, fields, identifier, outside_repository,
                                     parse_json, read_bytes, read_json, require, string)
from tools.rpg_author.compatibility import check_contract
from tools.rpg_author.legacy_package import _provenance
from tools.rpg_author.project import load_project
from tools.rpg_author.validate import candidate_blueprint, validate_story

FORMAT = "rpg_author_rich_enrichment_v1"
MODEL_ID = "gpt-6"


def _named(value: dict, where: str, maximum: int):
    require(type(value) is dict, "invalid_catalog", where + ": expected an object")
    for key, entry in value.items():
        identifier(key, where + " key")
        require(type(entry) is str, "invalid_catalog", where + ": non-string label")
        string(entry, where + " label", maximum)


def _enrich(blueprint, story, index, enrichment, *, npc_review=None):
    fields(enrichment, {"format", "source_fingerprint", "story_sha256",
                        "hero", "stats", "items", "facts",
                        "scene_names", "choices"}, "rich enrichment")
    require(enrichment["format"] == FORMAT and
            enrichment["source_fingerprint"] == index["source_fingerprint"] and
            enrichment["story_sha256"] == digest(canonical(story)),
            "wrong_enrichment", "Overlay belongs to another edition or story revision")
    hero = enrichment["hero"]
    fields(hero, {"name", "description"}, "hero")
    string(hero["name"], "hero name", 120)
    string(hero["description"], "hero description", 1200)
    stats = enrichment["stats"]
    items = enrichment["items"]
    facts = enrichment["facts"]
    require(type(stats) is dict and len(stats) <= 8 and
            type(items) is dict and len(items) <= 32 and
            type(facts) is dict and len(facts) <= 64,
            "invalid_catalog", "Expected bounded stats/items/facts catalogs")
    stats_value = {}
    stat_names = {}
    for key, entry in stats.items():
        identifier(key, "stat")
        fields(entry, {"name", "initial"}, "stat")
        string(entry["name"], "stat name", 100)
        require(type(entry["initial"]) is int and 0 <= entry["initial"] <= 1000,
                "invalid_stat", "Initial stat outside supported bounds")
        stats_value[key] = entry["initial"]
        stat_names[key] = entry["name"]
    item_names, item_descriptions = {}, {}
    for key, entry in items.items():
        identifier(key, "item")
        fields(entry, {"name", "description"}, "item")
        string(entry["name"], "item name", 100)
        string(entry["description"], "item description", 400)
        item_names[key] = entry["name"]
        item_descriptions[key] = entry["description"]
    _named(facts, "fact", 180)
    _named(enrichment["scene_names"], "scene", 120)
    scene_ids = {s["id"] for s in story["scenes"]}
    require(set(enrichment["scene_names"]) == scene_ids,
            "missing_scene_name", "Every scene needs a real readable title")
    choice_ids = {c["id"] for s in story["scenes"] for c in s["choices"]}
    custom = enrichment["choices"]
    require(type(custom) is dict and set(custom) <= choice_ids,
            "unknown_choice", "Overlay refers to nonexistent story choice")
    for cid, data in custom.items():
        fields(data, {"conditions", "effects"}, "choice overlay")
        require(type(data["conditions"]) is list and
                type(data["effects"]) is list and
                len(data["conditions"]) <= 16 and len(data["effects"]) <= 16,
                "invalid_overlay", "Too many custom gameplay rules")
    # Candidate was previously source checked, including all flag-only rules.
    # Copy-on-write; no mutation of the stored checkpoint or source citations.
    result = json.loads(canonical(blueprint))
    identity = {"story": story, "overlay": enrichment}
    if npc_review is not None:
        from .npc_review import validate_review
        actors = validate_review(npc_review, story, index, enrichment)
        identity["npc_review"] = npc_review
        result["actors"] = ["player", *actors]
        result["initial_state"]["knowledge"] = {a: [] for a in result["actors"]}
    result["book_id"] = "rich_" + index["source_fingerprint"][:12] + "_" + \
        digest(canonical(identity))[:12]
    result["items"] = sorted(items)
    result["facts"] = sorted(facts)
    result["initial_state"]["stats"] = stats_value
    for scene in result["scenes"]:
        for choice in scene["choices"]:
            extra = custom.get(choice["id"], {"conditions": [], "effects": []})
            choice["conditions"] = choice["conditions"] + list(extra["conditions"])
            choice["effects"] = choice["effects"] + list(extra["effects"])
    presentation = {
        "hero": hero,
        "item_names": item_names,
        "item_descriptions": item_descriptions,
        "stat_names": stat_names,
        "fact_names": facts,
        "scene_names": enrichment["scene_names"],
    }
    rich._blueprint(result)
    # NPC speaker/social checks must run only after the signed provenance
    # review has been attached; player-only v3 keeps the original validation.
    if npc_review is None:
        rich._presentation(presentation, result)
    return result, presentation


def compile_rich_from_project(root: Path, enrichment: dict,
                              *, model_id: str | None = None,
                              npc_review: dict | None = None):
    check_contract()
    _, state, index, analyses, story = load_project(root)
    require(story is not None, "story_missing", "Reviewed story not yet supplied")
    report = validate_story(story, index, analyses)
    require(report["source_citations_verified"] and report["engine_blueprint_valid"],
            "unvalidated_story", "Story failed original source checks")
    require(model_id in (None, MODEL_ID), "unverified_model",
            "Only explicitly declared gpt-6 is supported")
    from tools.bookworld.bookworld import BookworldError
    try:
        blueprint, presentation = _enrich(candidate_blueprint(story, index),
                                          story, index, enrichment, npc_review=npc_review)
        provenance = _provenance(story, index, analyses, blueprint)
        provenance["format"] = rich.PROVENANCE_FORMAT
        provenance["presentation"] = presentation
        if npc_review is not None:
            from .npc_review import add_review
            add_review(blueprint, presentation, provenance, npc_review)
        provenance["model_provenance"] = {
            "provider": "openai",
            "model_id": model_id,
            "model_id_status": "user_declared" if model_id else "not_attested",
            "tool": "ChatGPT", "method": "external",
        }
        raw = rich.build(blueprint, provenance, index)
        verified = rich.verify(raw)
    except (BookworldError, KeyError, TypeError) as error:
        raise AuthoringError("rich_compile_rejected", str(error)) from error
    require(verified["source_fingerprint"] == index["source_fingerprint"],
            "mismatch", "Compiled world belongs to another source edition")
    return raw, canonical(_attribution(raw, digest(canonical(blueprint)), provenance))


def _attribution(archive: bytes, blueprint_sha256: str, provenance: dict,
                 *, format_version: int = 3) -> dict:
    """Disclose only verified archive data; neither hashes nor labels attest a model."""
    require(format_version in (3, 4), "invalid_format_version",
            "Attribution is available only for private rich v3/v4")
    return {
        "format": "ai_story_external_attribution_v2",
        "bookworld_sha256": digest(archive),
        "source_fingerprint": provenance["source_fingerprint"],
        "blueprint_sha256": blueprint_sha256,
        "scenario_generation": dict(provenance["model_provenance"]),
        "bookworld_packaging": {
            "method": "local_compiler",
            "build_tool": ("ai_story_private_extended_bookworld"
                           if format_version == 4 else "ai_story_private_rich_bookworld"),
            "version": "4.0" if format_version == 4 else "3.0",
            "authorship_also_in_package": True,
        },
        "rights_status": "private_use_only",
        "publication_authorized": False,
        "semantic_review_completed": False,
        "device_playtest_completed": False,
    }


def build_rich(root: Path, enrichment_path: Path, output: Path,
               *, model_id: str | None = None,
               npc_review_path: Path | None = None):
    output = outside_repository(output)
    root = outside_repository(root)
    require(output != root and root not in output.parents, "output_in_project",
            "Build outside the checkpoint directory")
    require(output.suffix.lower() == ".bworld", "invalid_output",
            "Expected a .bworld output")
    sidecar = output.with_suffix(".attribution.json")
    require(not output.exists() and not sidecar.exists(), "output_exists",
            "Refusing to overwrite package or authorship disclosure")
    raw, disclosure = compile_rich_from_project(
        root, read_json(enrichment_path), model_id=model_id,
        npc_review=(read_json(outside_repository(npc_review_path))
                    if npc_review_path is not None else None))
    # Write disclosure first so a successful output always has attribution.
    atomic_write(sidecar, disclosure)
    try:
        atomic_write(output, raw)
    except BaseException:
        sidecar.unlink(missing_ok=True)
        raise
    return {
        "status": "private_rich_v3_built",
        "package": str(output), "attribution": str(sidecar),
        "archive_sha256": digest(raw),
        "rich_state": True, "private_only": True,
        "authorship_recorded_inside_archive": True,
        "device_playtest_completed": False,
    }


def verify_rich_bundle(package: Path, attribution: Path):
    from tools.bookworld.bookworld import BookworldError
    check_contract()
    archive = read_bytes(package, 12 * 1024 * 1024)
    sidecar = read_json(attribution)
    try:
        inspected = rich.verify(archive)
    except BookworldError as error:
        raise AuthoringError("rich_package_invalid", str(error)) from error
    # Open only after the real v3 verifier has validated ZIP/JSON/SQLite,
    # including equality of manifest and source model_provenance.
    with zipfile.ZipFile(io.BytesIO(archive)) as contents:
        blueprint_sha256 = digest(contents.read("scenario/blueprint.json"))
        provenance = parse_json(contents.read("source/provenance.json"))
    expected = _attribution(archive, blueprint_sha256, provenance)
    # Canonical comparison also rejects extra/missing fields and bool/int
    # substitutions (False == 0 in ordinary Python object equality).
    require(type(sidecar) is dict and canonical(sidecar) == canonical(expected),
            "attribution_mismatch", "Attribution fields must match this verified archive exactly")
    return {"status": "rich_bundle_structurally_verified",
            "archive_sha256": inspected["archive_sha256"],
            "authorship_inside_archive": True,
            "attribution_matches_archive": True,
            "authorship_cryptographically_attested": False,
            "semantic_review_completed": False,
            "device_playtest_completed": False}
