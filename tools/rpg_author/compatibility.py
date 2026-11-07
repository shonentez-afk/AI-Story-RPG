"""Read-only compatibility guard. Never rewrite the application's contract."""
from __future__ import annotations

from . import VERSION
from .common import ROOT, canonical, digest, read_bytes, read_json, require


def check_contract() -> dict:
    lock = read_json(ROOT / "tools/rpg_author/compatibility.json")
    mismatches = [name for name, expected in lock["files"].items()
                  if not (ROOT / name).is_file()
                  or digest(read_bytes(ROOT / name)) != expected]
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
            "npc_auto_authoring_ready": False,
            "application_baseline": lock["application_baseline"],
            "source_adapter": "python_port_with_dart_parity_tests",
            "requires_model_api": False, "application_modified": False,
            "supported_input_formats": ["txt", "fb2"],
            "candidate_modes": ["PROTAGONIST", "ALTER_FATE", "CLASSIC"],
            "external_ai_bworld_export": "supported_rich_v3",
            "default_package_version": 3,
            "build_command": "build --project PROJECT --enrichment JSON --output GAME.bworld",
            "verify_command": "verify --input GAME.bworld --attribution GAME.attribution.json",
            "next_step": "Analyze the source, validate the story, then provide rich enrichment and build v3"}
