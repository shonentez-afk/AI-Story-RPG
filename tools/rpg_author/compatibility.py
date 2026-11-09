"""Read-only compatibility guard. Never rewrite the application's contract."""
from __future__ import annotations

import hashlib
import re

from . import VERSION
from .common import ROOT, canonical, digest, read_bytes, read_json, require


def check_contract() -> dict:
    """Pin actual upstream BYTES, including the standalone Dart authoring API.

    E6f locks used SHA-256. E6g locks Git's content-addressed blob OIDs so
    the same pinned byte identities can be verified through GitHub's API and
    through the local checkout. Never bless changes by trusting a filename or
    a version string. Existing E6d/E6f checkpoint IDs remain distinct.
    """
    lock = read_json(ROOT / "tools/rpg_author/compatibility.json")
    fmt = lock.get("format", "rpg_author_compatibility_v1")
    algorithm = lock.get("digest_algorithm", "sha256")
    require(fmt in ("rpg_author_compatibility_v1", "rpg_author_compatibility_v2")
            and algorithm in ("sha256", "git_blob_sha1")
            and (fmt != "rpg_author_compatibility_v2"
                 or algorithm == "git_blob_sha1")
            and (fmt != "rpg_author_compatibility_v2"
                 or type(lock.get("application_baseline")) is str)
            and type(lock.get("files")) is dict
            and bool(lock["files"]),
            "invalid_compatibility_lock", "Unrecognized upstream compatibility lock")

    mismatches = []
    for name, expected in lock["files"].items():
        valid = (type(name) is str and
                 bool(re.fullmatch(r"[a-zA-Z0-9_./-]+", name)) and
                 ".." not in name.split("/") and not name.startswith("/"))
        require(valid, "invalid_compatibility_lock", "Invalid pinned path")
        path = ROOT / name
        if not path.is_file():
            mismatches.append(name)
            continue
        raw = read_bytes(path)
        actual = (hashlib.sha1(
            b"blob " + str(len(raw)).encode("ascii") + bytes((0,)) + raw
        ).hexdigest() if algorithm == "git_blob_sha1" else digest(raw))
        if actual != expected:
            mismatches.append(name)

    require(not mismatches, "contract_drift",
            "Review upstream changes before continuing: " + ", ".join(mismatches))
    return lock


def toolchain_id() -> str:
    check_contract()
    files = sorted((ROOT / "tools/rpg_author").glob("*.py"))
    files += sorted((ROOT / "schemas/rpg_author").glob("*.json"))
    files += [ROOT / "tools/rpg_author/compatibility.json"]
    return digest(canonical({str(p.relative_to(ROOT)): digest(read_bytes(p)) for p in files}))


def doctor() -> dict:
    lock = check_contract()
    # Real synthetic Python writer/reader + E6d sidecar probe. This is not
    # a claim that complete NPC book authoring or device E2E is ready.
    from .npc_compatibility_probe import check_npc_extension, check_npc_social_v5
    npc_probe = check_npc_extension()
    social_probe = check_npc_social_v5()
    return {"tool_version": VERSION, "toolchain_sha256": toolchain_id(),
            "optional_npc_knowledge_contract": npc_probe,
            "optional_npc_social_v5_contract": social_probe,
            "npc_reviewed_authoring_supported": True,
            "npc_auto_authoring_ready": False,
            "application_baseline": lock["application_baseline"],
            "source_adapter": "python_port_with_standalone_story_authoring_dart_parity",
            "native_authoring_package": "packages/story_authoring",
            "rich_v4_export_status": "explicit_native_dart_build_extended; E6g v3-reviewed StoryPlan bounds",
            "native_v4_requires": "Dart SDK plus resolved story_authoring package configuration",
            "native_v4_build_command": "build-extended --project PROJECT --enrichment JSON --output GAME.bworld",
            "native_v4_verify_command": "verify-extended --input GAME.bworld --attribution GAME.attribution.json",
            "requires_model_api": False, "application_modified": False,
            "supported_input_formats": ["txt", "fb2"],
            "candidate_modes": ["PROTAGONIST", "ALTER_FATE", "CLASSIC"],
            "external_ai_bworld_export": "supported_rich_v3",
            "default_package_version": 3,
            "build_command": "build --project PROJECT --enrichment JSON --output GAME.bworld",
            "verify_command": "verify --input GAME.bworld --attribution GAME.attribution.json",
            "next_step": "Analyze the full source, validate the story, supply rich enrichment and optional explicitly reviewed NPC overlay, then build/verify rich v3"}
