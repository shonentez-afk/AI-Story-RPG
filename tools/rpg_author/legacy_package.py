"""Explicit, private legacy BookWorld v2 compatibility packaging.

The legacy v2 field model_provenance=none is a *packaging compatibility
constant*, NOT a declaration that no model helped author the game. External AI
authorship is preserved in a SHA-bound sidecar, never dropped from the project.
The app does not read or verify this sidecar; this is not a provenance signature.
"""
from __future__ import annotations

import json
from pathlib import Path

from .common import AuthoringError, atomic_write, canonical, digest, outside_repository, require
from .compatibility import check_contract
from .project import load_project
from .validate import assertion_registry, candidate_blueprint, validate_story

LEGACY_PROVENANCE = {"provider": "none", "model_id": None}
FORMAT = "ai_story_external_attribution_v1"


def _source_ref(scene: dict, assertion: dict, chunk: dict, source_fingerprint: str) -> dict:
    # Legacy provenance requires 32 lowercase hex IDs, while authoring assertion
    # IDs are human-readable. The stable mapping is SHA-derived and never guesses
    # a quote range. Hashing does not endorse the interpretation.
    key = canonical({"source_fingerprint": source_fingerprint,
                     "scene_id": scene["id"], "assertion_id": assertion["id"],
                     "chunk_id": chunk["id"]})
    return {
        "id": digest(b"ref:" + key)[:32],
        "chunk_id": chunk["id"],
        "chapter_id": chunk["chapter_id"],
        "chapter_index": chunk["chapter_index"],
        "block_index": chunk["block_index"],
        "start_utf16": assertion["start_utf16"],
        "end_utf16": assertion["end_utf16"],
        "quote_sha256": digest(assertion["quote"].encode("utf-8")),
        "visible_after_chapter": scene["chapter_index"],
    }


def _provenance(story: dict, index: dict, analyses: list[dict], blueprint: dict) -> dict:
    registry = assertion_registry(analyses, index)
    origins = []
    for scene in story["scenes"]:
        claims, refs = [], []
        for assertion_id in scene["assertion_ids"]:
            entry = registry[assertion_id]
            assertion, chunk = entry["assertion"], entry["chunk"]
            key = canonical({"source_fingerprint": index["source_fingerprint"],
                             "chunk_id": chunk["id"], "assertion_id": assertion_id})
            claims.append(digest(b"claim:" + key)[:32])
            refs.append(_source_ref(scene, assertion, chunk, index["source_fingerprint"]))
        require(len(claims) == len(set(claims)) and
                len({r["id"] for r in refs}) == len(refs),
                "collision", "Duplicate or colliding source identifiers")
        origins.append({
            "scene_id": scene["id"],
            "chapter_index": scene["chapter_index"],
            "origin": scene["origin"],
            "assertion_ids": claims,
            "source_refs": refs,
        })
    return {
        "format": "ai_story_private_provenance_v1",
        "bookworld_id": blueprint["book_id"],
        "source_fingerprint": index["source_fingerprint"],
        "source_title": index["title"],
        "source_author": index["author"],
        "source_chapters_total": index["chapter_count"],
        "source_chapters_indexed": index["indexed_chapter_count"],
        "semantic_catalog_sha256": digest(canonical(analyses)),
        "intermediate_draft_sha256": digest(canonical(story)),
        "rights_status": "private_use_only",
        "publication_authorized": False,
        "model_provenance": dict(LEGACY_PROVENANCE),
        "scene_origins": origins,
    }


def _attribution(archive: bytes, story: dict, index: dict, blueprint: dict,
                 project_authorship: dict, *, model_id: str | None) -> dict:
    # A model ID supplied to this CLI is a user declaration, not an attestation.
    require(model_id is None or model_id == "gpt-6",
            "unsupported_model_id", "This experiment accepts an explicit gpt-6 declaration only")
    return {
        "format": FORMAT,
        "bookworld_sha256": digest(archive),
        "source_fingerprint": index["source_fingerprint"],
        "blueprint_sha256": digest(canonical(blueprint)),
        "scenario_generation": {
            "provider": "openai",
            "model_id": model_id,
            "model_id_status": "user_declared" if model_id else "not_attested",
            "tool": "ChatGPT",
            "method": "external",
            "project_authorship": project_authorship,
        },
        "bookworld_packaging": {
            "method": "local_compiler",
            "build_tool": "ai_story_private_bookworld",
            "version": "2.0",
            "legacy_model_provenance": dict(LEGACY_PROVENANCE),
            "legacy_value_means_no_model_used": False,
        },
        "rights_status": "private_use_only",
        "publication_authorized": False,
        "sidecar_is_required_for_authorship_disclosure": True,
        "sidecar_is_verified_by_legacy_app": False,
    }


def compile_from_project(root: Path, *, model_id: str | None = None) -> tuple[bytes, bytes]:
    """Compile only a complete locally indexed, validated project; no raw LLM JSON."""
    check_contract()
    _, state, index, analyses, story = load_project(root)
    require(story is not None, "story_missing", "Submit a validated story first")
    review = validate_story(story, index, analyses)
    require(review.get("source_citations_verified") is True and
            review.get("engine_blueprint_valid") is True,
            "unvalidated", "The authoring candidate did not pass structural validation")
    blueprint = candidate_blueprint(story, index)
    provenance = _provenance(story, index, analyses, blueprint)
    from tools.bookworld import private_bookworld
    from tools.bookworld.bookworld import BookworldError
    try:
        archive = private_bookworld.build(blueprint, provenance, index)
        verified = private_bookworld.verify(archive)
    except (BookworldError, KeyError, TypeError, ValueError) as exc:
        raise AuthoringError("legacy_compilation_failed", str(exc)) from exc
    require(verified["source_fingerprint"] == index["source_fingerprint"] and
            verified["bookworld_id"] == blueprint["book_id"],
            "package_mismatch", "Built package references the wrong edition or world")
    metadata = _attribution(archive, story, index, blueprint, state["authorship"],
                            model_id=model_id)
    return archive, canonical(metadata)


def build_legacy(root: Path, output: Path, *, acknowledgement: bool = False,
                 model_id: str | None = None) -> dict:
    require(acknowledgement, "legacy_ack_required",
            "Explicitly acknowledge that the old v2 manifest says none, while AI "
            "authorship is disclosed only in the SHA-bound external sidecar")
    output = outside_repository(output)
    require(output.suffix.lower() == ".bworld", "invalid_output",
            "Output must be a private .bworld package")
    sidecar = output.with_suffix(".attribution.json")
    require(not output.exists() and not sidecar.exists(), "output_exists",
            "Neither the .bworld nor its attribution file may be overwritten")
    archive, metadata_bytes = compile_from_project(root, model_id=model_id)
    # Both outputs are fully validated before either is committed.
    # The sidecar is written first, so no playable archive is left without
    # disclosure if sidecar writing fails.
    atomic_write(sidecar, metadata_bytes)
    try:
        atomic_write(output, archive)
    except BaseException:
        sidecar.unlink(missing_ok=True)
        raise
    return {
        "status": "private_legacy_package_built",
        "package": str(output),
        "sidecar": str(sidecar),
        "archive_sha256": digest(archive),
        "sidecar_sha256": digest(metadata_bytes),
        "private_only": True,
        "legacy_model_provenance": LEGACY_PROVENANCE,
        "external_ai_authorship_is_disclosed_in_sidecar": True,
        "legacy_app_verifies_sidecar": False,
        "semantic_review_completed": False,
        "device_playtest_completed": False,
    }


def verify_bundle(package: Path, sidecar: Path) -> dict:
    from .common import read_bytes, read_json
    from tools.bookworld import private_bookworld
    from tools.bookworld.bookworld import BookworldError
    archive = read_bytes(package, 12 * 1024 * 1024)
    metadata = read_json(sidecar)
    try:
        verified = private_bookworld.verify(archive)
    except (BookworldError, KeyError, ValueError) as exc:
        raise AuthoringError("package_invalid", str(exc)) from exc
    require(metadata.get("format") == FORMAT and
            metadata.get("bookworld_sha256") == digest(archive) and
            metadata.get("source_fingerprint") == verified["source_fingerprint"],
            "attribution_mismatch", "Attribution does not match this exact archive")
    require(metadata.get("publication_authorized") is False and
            metadata.get("sidecar_is_verified_by_legacy_app") is False,
            "attribution_invalid", "Attribution safety declarations are missing")
    return {"status": "bundle_structurally_verified",
            "archive_sha256": verified["archive_sha256"],
            "source_fingerprint": verified["source_fingerprint"],
            "authorship_disclosure_present": True,
            "legacy_app_verifies_sidecar": False,
            "authorship_cryptographically_attested": False,
            "semantic_review_completed": False,
            "device_playtest_completed": False}
