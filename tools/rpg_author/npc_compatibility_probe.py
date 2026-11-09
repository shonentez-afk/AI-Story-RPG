"""Fail-closed external E6 compatibility probe for optional rich-v3 NPC knowledge.

Runs against the *actual* Python BookWorld writer/verifier and the external
author's verify+attribution path, using only a synthetic public fixture. This
does not assert user approval, literary canonicity, or real device E2E.
Dart<->Python extension parity is separately tested by the native PR suite.
"""
from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import zipfile

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_rich_bookworld as rich

from .common import ROOT, canonical, digest, require

NPC_ID = "npc_" + "c" * 32
FACT_ID = "npc_secret"
NPC_FORMAT = "ai_story_npc_knowledge_grants_v1"


def _base():
    path = ROOT / "shared_schemas/fixtures/private_classic_sample.json"
    require(path.is_file(), "npc_contract_fixture_missing",
            "Missing known synthetic private classic source fixture")
    data = json.loads(path.read_text(encoding="utf-8"))
    bp, provenance, index = (
        data["blueprint"], data["provenance"], data["source_index"]
    )
    provenance["format"] = "ai_story_private_provenance_v2"
    provenance["model_provenance"] = {
        "provider": "none", "model_id": None,
        "model_id_status": "not_applicable",
        "tool": "none", "method": "local_fixture",
    }
    provenance["presentation"] = {
        "hero": {"name": "Игрок", "description": "Синтетический тест совместимости."},
        "item_names": {}, "item_descriptions": {},
        "stat_names": {}, "fact_names": {},
        "scene_names": {s["id"]: "Сцена " + str(n + 1)
                        for n, s in enumerate(bp["scenes"])},
    }
    return bp, provenance, index


def _reviewed_npc_world():
    bp, provenance, index = _base()
    require(bp["actors"] == ["player"] and not bp["facts"],
            "npc_contract_fixture_changed",
            "Base fixture has unexpected actors or facts")
    bp["actors"].append(NPC_ID)
    bp["facts"].append(FACT_ID)
    bp["initial_state"]["knowledge"][NPC_ID] = []
    entry = bp["scenes"][0]
    require(entry["id"] == "entry" and len(entry["choices"]) >= 2
            and entry["choices"][0]["id"] == "wait",
            "npc_contract_fixture_changed", "Missing tested NPC learning route")
    entry["choices"][0]["effects"].append({
        "op": "learn_fact", "id": FACT_ID, "actor": NPC_ID,
    })
    entry["choices"][1]["conditions"].append({
        "op": "knows_fact", "id": FACT_ID, "actor": NPC_ID,
    })
    provenance["presentation"]["fact_names"][FACT_ID] = "Секрет NPC"
    origins = provenance["scene_origins"]
    require(origins and origins[0]["origin"] == "SOURCE_PASSAGE"
            and origins[0]["source_refs"],
            "npc_contract_fixture_changed", "No eligible quoted source")
    quote = origins[0]["source_refs"][0]["quote_sha256"]
    provenance["npc_knowledge"] = {
        "format": NPC_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        # This flag is only in a SYNTHETIC TEST. Never infer consent in a
        # user-authored world or automatically fill the editor's review.
        "user_confirmed": True,
        "literary_canon_verified": False,
        "grants": [{
            "scene_id": entry["id"], "choice_id": "wait",
            "actor_id": NPC_ID, "fact_id": FACT_ID,
            "source_quote_sha256": quote,
        }],
    }
    entry["text"] = (
        "Встреча у ворот.\n"
        "Мария: «Мне известен секрет!»\n"
        "Игрок: «Я слушаю»."
    )
    signed = rich._exact_scene_dialogue(entry["text"])
    require(signed is not None and len(signed["turns"]) == 3,
            "npc_contract_fixture_changed", "Signed dialogue parser diverged")
    provenance["presentation"]["scene_dialogues"] = {"entry": signed}
    provenance["presentation"]["scene_dialogue_knowledge"] = {
        "entry": [
            {"turn_index": 1, "speaker": "Мария", "actor_id": NPC_ID,
             "required_fact_ids": [FACT_ID]},
            {"turn_index": 2, "speaker": "Игрок", "actor_id": "player",
             "required_fact_ids": []},
        ],
    }
    return bp, provenance, index


def _must_reject(name, bp, provenance, index):
    try:
        rich.build(bp, provenance, index)
    except legacy.BookworldError:
        return
    raise AssertionError("Native Python writer accepted unsafe NPC case: " + name)


def check_npc_extension() -> dict:
    """Check real optional extension, old-v3 acceptance and negative guards."""
    require(getattr(rich, "NPC_GRANTS_FORMAT", None) == NPC_FORMAT,
            "npc_contract_drift", "Expected versioned NPC grants extension")
    old_bp, old_prov, old_index = _base()
    old = rich.build(old_bp, old_prov, old_index)
    require(rich.verify(old)["format_version"] == 3,
            "legacy_rich_v3_rejected", "Player-only v3 stopped working")

    bp, provenance, index = _reviewed_npc_world()
    raw = rich.build(bp, provenance, index)
    report = rich.verify(raw)
    require(report["format_version"] == 3 and report["private_only"]
            and report["scene_count"] == 3 and raw == rich.build(bp, provenance, index),
            "npc_contract_incompatible", "Extended v3 is not deterministic")
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        entries = zipped.namelist()
        manifest = json.loads(zipped.read("manifest.json"))
        blueprint_bytes = zipped.read("scenario/blueprint.json")
        source = json.loads(zipped.read("source/provenance.json"))
    require(entries == list(rich.PATHS) and len(entries) == 4
            and manifest.get("npc_knowledge_format") == NPC_FORMAT
            and source["npc_knowledge"]["format"] == NPC_FORMAT,
            "npc_contract_incompatible", "Unexpected NPC v3 ZIP layout or marker")

    # Prove E6d's OWN archive+sidecar verifier accepts the optional extension.
    from .rich_package import _attribution, verify_rich_bundle
    with tempfile.TemporaryDirectory(prefix="rpg-author-npc-probe-") as temp:
        archive_path = Path(temp) / "synthetic_npc.bworld"
        sidecar_path = Path(temp) / "synthetic_npc.attribution.json"
        archive_path.write_bytes(raw)
        sidecar_path.write_bytes(canonical(_attribution(
            raw, digest(blueprint_bytes), source)))
        inspected = verify_rich_bundle(archive_path, sidecar_path)
    require(inspected["attribution_matches_archive"],
            "npc_contract_incompatible", "External sidecar verifier rejected NPC v3")

    cases = (
        "missing_review", "empty_grants", "forged_quote",
        "grant_to_player", "initial_secret", "missing_line_review",
        "unsigned_bypass", "wrong_speaker_identity", "unknown_required_fact",
    )
    for case in cases:
        changed_bp, changed_prov, changed_index = _reviewed_npc_world()
        if case == "missing_review":
            del changed_prov["npc_knowledge"]
        elif case == "empty_grants":
            changed_prov["npc_knowledge"]["grants"].clear()
        elif case == "forged_quote":
            changed_prov["npc_knowledge"]["grants"][0][
                "source_quote_sha256"] = "f" * 64
        elif case == "grant_to_player":
            changed_prov["npc_knowledge"]["grants"][0]["actor_id"] = "player"
        elif case == "initial_secret":
            changed_bp["initial_state"]["knowledge"][NPC_ID] = [FACT_ID]
        elif case == "missing_line_review":
            del changed_prov["presentation"]["scene_dialogue_knowledge"]
        elif case == "unsigned_bypass":
            del changed_prov["presentation"]["scene_dialogue_knowledge"]
            del changed_prov["presentation"]["scene_dialogues"]
        elif case == "wrong_speaker_identity":
            changed_prov["presentation"]["scene_dialogue_knowledge"]["entry"][
                0]["actor_id"] = "npc_" + "d" * 32
        elif case == "unknown_required_fact":
            changed_prov["presentation"]["scene_dialogue_knowledge"]["entry"][
                0]["required_fact_ids"] = ["unknown_secret"]
        _must_reject(case, changed_bp, changed_prov, changed_index)

    return {
        "status": "synthetic_python_writer_verifier_and_external_sidecar_pass",
        "format": NPC_FORMAT,
        "player_only_v3_accepted": True,
        "signed_npc_dialogue_reviewed": True,
        "negative_cases_rejected": len(cases),
        "real_user_consent_or_literary_canon_attested": False,
        "dart_device_e2e_tested_here": False,
    }


def check_npc_social_v5() -> dict:
    """Run true native v5 writer+reader+sidecar and fail-closed negative cases.

    These reviews are deliberately SYNTHETIC. Real authoring requires a
    separately supplied consented source-bound npc_review.json; this probe
    does not auto-approve witnesses, secret knowledge, inventory or death.
    """
    require(getattr(rich, "NPC_SOCIAL_LIFE_FORMAT", None) ==
            "ai_story_npc_social_witness_v5" and
            getattr(rich, "NPC_SOCIAL_AUTHOR_ITEM_FORMAT", None) ==
            "ai_story_npc_social_witness_v4" and
            getattr(rich, "NPC_SOCIAL_ITEM_FORMAT", None) ==
            "ai_story_npc_social_witness_v3" and
            getattr(rich, "NPC_SOCIAL_GATE_FORMAT", None) ==
            "ai_story_npc_social_witness_v2" and
            getattr(rich, "NPC_SOCIAL_FORMAT", None) ==
            "ai_story_npc_social_witness_v1",
            "npc_social_contract_drift", "Main lost a versioned NPC social v1-v5 contract")

    bp, prov, index = _reviewed_npc_world()
    quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    prov["npc_social"] = {
        "format": rich.NPC_SOCIAL_LIFE_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "user_confirmed": True,
        "literary_canon_verified": False,
        "witnesses": [{
            "scene_id": "entry", "actor_id": NPC_ID, "mode": "present",
            "source_quote_sha256": quote,
        }],
        "rules": [{
            "memory_id": "reviewed_wait",
            "scene_id": "entry", "choice_id": "wait",
            "observer_id": NPC_ID, "kind": "witnessed",
            "related_actor_id": "player", "relationship_delta": 1,
            "max_triggers": 1, "source_quote_sha256": quote,
        }],
        "choice_gates": [],
        "item_transfers": [],
        "item_grants": [],
        "life_transitions": [{
            "scene_id": "entry", "choice_id": "wait",
            "actor_id": NPC_ID, "next_state": "absent",
            "source_quote_sha256": quote,
        }],
    }
    raw = rich.build(bp, prov, index)
    checked = rich.verify(raw)
    require(checked["format_version"] == 3 and
            raw == rich.build(bp, prov, index),
            "npc_social_v5_incompatible",
            "Native v5 world is not deterministic or verifiable")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.namelist()
        manifest = json.loads(archive.read("manifest.json"))
        blueprint_bytes = archive.read("scenario/blueprint.json")
    require(entries == list(rich.PATHS) and len(entries) == 4 and
            manifest.get("npc_social_format") == rich.NPC_SOCIAL_LIFE_FORMAT,
            "npc_social_v5_incompatible", "Native rich-v3 v5 marker is inconsistent")
    from .rich_package import _attribution, verify_rich_bundle
    with tempfile.TemporaryDirectory(prefix="rpg-author-npc-v5-") as tmp:
        target = Path(tmp) / "synthetic.bworld"
        disclosure = Path(tmp) / "synthetic.attribution.json"
        target.write_bytes(raw)
        disclosure.write_bytes(canonical(_attribution(raw, digest(blueprint_bytes), prov)))
        result = verify_rich_bundle(target, disclosure)
    require(result["attribution_matches_archive"],
            "npc_social_v5_incompatible", "External v5 sidecar failed verification")

    cases = (
        "bad_life", "player_life", "missing_choice", "forged_source",
        "duplicate_transition", "missing_transition",
        "version_downgrade", "consent_revoked", "orphan_witness",
    )
    for case in cases:
        cb, cp, ci = deepcopy((bp, prov, index))
        social = cp["npc_social"]
        life = social["life_transitions"]
        if case == "bad_life":
            life[0]["next_state"] = "revived"
        elif case == "player_life":
            life[0]["actor_id"] = "player"
        elif case == "missing_choice":
            life[0]["choice_id"] = "phantom"
        elif case == "forged_source":
            life[0]["source_quote_sha256"] = "f" * 64
        elif case == "duplicate_transition":
            life.append(deepcopy(life[0]))
        elif case == "missing_transition":
            life.clear()
        elif case == "version_downgrade":
            social["format"] = rich.NPC_SOCIAL_AUTHOR_ITEM_FORMAT
        elif case == "consent_revoked":
            social["user_confirmed"] = False
        elif case == "orphan_witness":
            social["rules"].clear()
        _must_reject(case, cb, cp, ci)

    return {
        "status": "native_python_v5_writer_verifier_and_sidecar_pass",
        "format": rich.NPC_SOCIAL_LIFE_FORMAT,
        "old_v3_preserved": True,
        "negative_cases_rejected": len(cases),
        "source_reviewed_user_consent_attested": False,
        "device_e2e_tested_here": False,
    }
