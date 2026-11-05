"""Read-only compatibility guard. Never rewrite the application's contract."""
from __future__ import annotations

from . import VERSION
from .common import ROOT, AuthoringError, canonical, digest, read_bytes, read_json, require


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
    return {"tool_version": VERSION, "toolchain_sha256": toolchain_id(),
            "application_baseline": lock["application_baseline"],
            "source_adapter": "python_port_not_yet_dart_parity_certified",
            "requires_model_api": False, "application_modified": False,
            "supported_input_formats": ["txt", "fb2"],
            "candidate_modes": ["PROTAGONIST", "ALTER_FATE", "CLASSIC"],
            "external_ai_bworld_export": "blocked_by_existing_provenance_contract",
            "next_step": "Analyze the book and export a validated authoring candidate"}


def block_unsupported_export():
    check_contract()
    raise AuthoringError(
        "external_ai_provenance_unsupported",
        "The unchanged v2 importer only accepts provider=none/model_id=null. "
        "External AI authorship must not be erased. Use export for the candidate; "
        "a separately reviewed application-format change is required for .bworld.")
