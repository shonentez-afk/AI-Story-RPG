"""One source-locked ChatGPT Skill -> existing native NPC v3/v4 contracts.

The SKILL writes literary dossiers and source assertion IDs. This adapter
derives immutable character IDs and quote hashes, then the pinned rich writer
and Dart importer validate all gameplay. No new NPC simulation or model API.
"""
from __future__ import annotations

from copy import deepcopy

from tools.bookworld import private_rich_bookworld as rich

from .common import (
    canonical, digest, fields, identifier, require, string,
)
from .npc_review import FORMAT as NPC_FORMAT
from .validate import assertion_registry

DOSSIERS_FORMAT = "rpg_author_skill_npc_dossiers_v1"
REVIEW_FORMAT = "rpg_author_skill_npc_review_v1"

_LIST_FIELDS = {
    "knowledge_grants": {
        "scene_id", "choice_id", "actor_id", "fact_id", "assertion_id",
    },
    "witnesses": {
        "scene_id", "actor_id", "mode", "assertion_id",
    },
    "rules": {
        "memory_id", "scene_id", "choice_id", "observer_id", "kind",
        "related_actor_id", "relationship_delta", "max_triggers",
        "assertion_id",
    },
    "choice_gates": {
        "scene_id", "choice_id", "actor_id", "required_memory_id",
        "minimum_trust_to_player", "assertion_id",
    },
    "item_grants": {
        "scene_id", "choice_id", "item_id", "assertion_id",
    },
    "item_transfers": {
        "scene_id", "choice_id", "item_id", "from_actor_id",
        "to_actor_id", "assertion_id",
    },
    "life_transitions": {
        "scene_id", "choice_id", "actor_id", "next_state", "assertion_id",
    },
}


def _evidence(scene_id: str, assertion_id: str, scenes: dict,
              registry: dict, *, must_be_narrated: bool = False,
              origins: dict | None = None) -> tuple[str, str]:
    identifier(scene_id, "NPC witnessed source scene")
    identifier(assertion_id, "NPC exact source assertion")
    require(scene_id in scenes and
            scenes[scene_id]["origin"] == "SOURCE_PASSAGE" and
            assertion_id in scenes[scene_id]["assertion_ids"] and
            assertion_id in registry,
            "skill_npc_source_invalid",
            "NPC claim must cite a real passage in its original scene")
    claim = registry[assertion_id]["assertion"]
    require(not must_be_narrated or claim["kind"] == "NARRATED",
            "skill_npc_hearsay",
            "First-person NPC presence/identity cannot be based on hearsay")
    sha = digest(claim["quote"].encode("utf-8"))
    if origins is not None:
        origin = origins.get(scene_id)
        require(origin is not None and origin["origin"] == "SOURCE_PASSAGE"
                and any(ref["quote_sha256"] == sha
                        and ref["visible_after_chapter"] <=
                        origin["chapter_index"]
                        for ref in origin["source_refs"]),
                "skill_npc_source_invalid",
                "NPC social evidence does not match the locked native source")
    return sha, claim["quote"]


def prepare_npc_dossiers(response: dict, index: dict, story: dict,
                         analyses: list[dict]) -> dict:
    """Compute permanent character_id from original book and witnessed name."""
    fields(response, {"characters", "absence_reason"}, "skill NPC cast")
    characters = response["characters"]
    require(type(characters) is list and len(characters) <= 15,
            "skill_npc_cast_invalid", "At most 15 source-grounded NPCs")
    scenes = {row["id"]: row for row in story["scenes"]}
    registry = assertion_registry(analyses, index)
    cast, seen = [], set()
    for record in characters:
        fields(record, {"ref", "name", "description",
                        "source_scene_id", "assertion_id"}, "source NPC dossier")
        ref = record["ref"]
        identifier(ref, "stable NPC reference")
        require(ref not in seen, "skill_npc_duplicate",
                "Character reference must remain unique for the same book")
        seen.add(ref)
        string(record["name"], "NPC displayed name", 120)
        string(record["description"], "NPC source-aware dossier", 1200)
        quote_sha, quote = _evidence(
            record["source_scene_id"], record["assertion_id"],
            scenes, registry, must_be_narrated=True)
        require(record["name"].casefold() in quote.casefold(),
                "skill_npc_identity_unproven",
                "NPC displayed name must occur in the attested source quote")
        actor = "npc_" + digest(canonical({
            "source_fingerprint": index["source_fingerprint"],
            "npc_ref": ref,
            "identity_assertion": record["assertion_id"],
        }))[:32]
        cast.append({
            "ref": ref, "character_id": actor,
            "name": record["name"], "description": record["description"],
            "source_scene_id": record["source_scene_id"],
            "identity_assertion_id": record["assertion_id"],
            "identity_quote_sha256": quote_sha,
        })
    reason = response["absence_reason"]
    require((not cast and type(reason) is str and
             len(reason.strip()) >= 20) or
            (bool(cast) and reason is None),
            "skill_npc_absence_unreviewed",
            "Empty NPC cast needs a written literary reason; nonempty cast needs null")
    return {
        "format": DOSSIERS_FORMAT,
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "characters": sorted(cast, key=lambda row: row["character_id"]),
        "absence_reason": reason,
        "canon_identity_verified_by_ai": False,
        "private_source_only": True,
    }



def verify_source_dossiers(dossiers: dict, index: dict, story: dict,
                           analyses: list[dict]) -> dict:
    """Fail closed on tampered private checkpoints and unknown identities."""
    fields(dossiers, {
        "format", "source_fingerprint", "story_sha256", "characters",
        "absence_reason", "canon_identity_verified_by_ai",
        "private_source_only",
    }, "saved NPC dossier checkpoint")
    require(dossiers["format"] == DOSSIERS_FORMAT and
            dossiers["source_fingerprint"] == index["source_fingerprint"] and
            dossiers["story_sha256"] == digest(canonical(story)) and
            dossiers["canon_identity_verified_by_ai"] is False and
            dossiers["private_source_only"] is True,
            "skill_npc_dossiers_stale",
            "Saved NPC cast is not bound to this book and StoryPlan")
    raw = {
        "characters": [{
            "ref": c["ref"], "name": c["name"],
            "description": c["description"],
            "source_scene_id": c["source_scene_id"],
            "assertion_id": c["identity_assertion_id"],
        } for c in dossiers["characters"]],
        "absence_reason": dossiers["absence_reason"],
    }
    checked = prepare_npc_dossiers(raw, index, story, analyses)
    require(canonical(checked) == canonical(dossiers),
            "skill_npc_dossiers_stale",
            "Saved NPC IDs/evidence do not match their original source")
    return checked


def prepare_npc_review(response: dict, dossiers: dict, index: dict,
                       story: dict, analyses: list[dict], enrichment: dict,
                       blueprint: dict, provenance: dict,
                       *, user_confirmed: bool) -> dict:
    """Convert ID/quote suggestions into native v3 review, fail-closed.

    The Skill cannot supply arbitrary source_quote_sha256, choose an
    unrecognized actor, or record a witnessed event from another scene.
    """
    require(dossiers["format"] == DOSSIERS_FORMAT and
            dossiers["source_fingerprint"] == index["source_fingerprint"] and
            dossiers["story_sha256"] == digest(canonical(story)) and
            bool(dossiers["characters"]),
            "skill_npc_dossiers_stale",
            "A source-locked nonempty cast is required for an NPC review")
    fields(response, {"format", *list(_LIST_FIELDS), "dialogue_knowledge"},
           "skill NPC social authoring")
    require(response["format"] == REVIEW_FORMAT,
            "skill_npc_review_wrong_format",
            "Use the exact NPC Skill response contract")
    actors = {row["character_id"] for row in dossiers["characters"]}
    require(len(actors) == len(dossiers["characters"]),
            "skill_npc_duplicate", "NPC actor IDs cannot collide")
    scenes = {row["id"]: row for row in story["scenes"]}
    originals = {r["scene_id"]: r for r in provenance["scene_origins"]}
    registry = assertion_registry(analyses, index)
    compiled = {row["id"]: row for row in blueprint["scenes"]}
    choice_ids = {
        (sid, row["id"])
        for sid, scene in compiled.items()
        for row in scene["choices"]
    }
    output = {}
    for section, allowed in _LIST_FIELDS.items():
        entries = response[section]
        require(type(entries) is list and len(entries) <= 128,
                "skill_npc_review_invalid", "Native NPC section out of bounds")
        converted = []
        for record in entries:
            fields(record, allowed, "skill NPC " + section)
            scene_id, assertion_id = record["scene_id"], record["assertion_id"]
            q, _ = _evidence(
                scene_id, assertion_id, scenes, registry, origins=originals,
                must_be_narrated=section not in ("witnesses",))
            if "choice_id" in record:
                require((scene_id, record["choice_id"]) in choice_ids,
                        "skill_npc_action_invalid",
                        "NPC evidence references no original compiled action")
            for idfield in ("actor_id", "observer_id", "to_actor_id",
                            "from_actor_id", "related_actor_id"):
                if idfield in record:
                    ident = record[idfield]
                    require(ident == "player" or ident in actors,
                            "skill_npc_actor_unknown",
                            "NPC event cannot mention an unreviewed character ID")
            if section in ("knowledge_grants", "witnesses", "rules",
                           "choice_gates", "life_transitions"):
                actor = record.get("actor_id", record.get("observer_id"))
                require(actor in actors, "skill_npc_actor_unknown",
                        "NPC social observer must be a reviewed NPC")
            if section == "witnesses":
                require(record["mode"] in ("present", "reported") and
                        (record["mode"] != "present" or
                         registry[assertion_id]["assertion"]["kind"] ==
                         "NARRATED"),
                        "skill_npc_hearsay",
                        "A present NPC needs firsthand source evidence")
            new_record = {k: deepcopy(v) for k, v in record.items()
                          if k != "assertion_id"}
            new_record["source_quote_sha256"] = q
            converted.append(new_record)
        output[section] = converted
    require(bool(output["witnesses"]) and bool(output["rules"]),
            "skill_npc_social_missing",
            "NPC cast must have witnessed behavior and an event-sourced memory")
    guards = response["dialogue_knowledge"]
    require(type(guards) is dict and len(guards) <= len(scenes),
            "skill_npc_dialogue_invalid",
            "Base dialogue speaker review must be explicit")
    dialogues = {}
    for sid, turns in guards.items():
        require(sid in compiled and type(turns) is list,
                "skill_npc_dialogue_invalid",
                "NPC dialogues must reference actual original scenes")
        verified = []
        for turn in turns:
            require(type(turn) is dict, "skill_npc_dialogue_invalid",
                    "Speaker review must be structured")
            actor = turn.get("actor_id")
            require(actor == "player" or actor in actors,
                    "skill_npc_actor_unknown", "Speaker must have a verified character ID")
            signed = {k: deepcopy(v) for k, v in turn.items()
                      if k not in ("source_scene_id", "assertion_id")}
            if "assertion_id" in turn:
                source_scene = turn.get("source_scene_id", sid)
                quote_sha, _ = _evidence(
                    source_scene, turn["assertion_id"], scenes, registry,
                    origins=originals)
                signed["source_quote_sha256"] = quote_sha
            require("source_quote_sha256" not in turn,
                    "skill_npc_source_invalid",
                    "Never accept an unverified supplied dialogue quote SHA")
            verified.append(signed)
        dialogues[sid] = verified
    scope = {
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": index["source_fingerprint"],
        "user_confirmed": user_confirmed,
        "literary_canon_verified": False,
    }
    return {
        "format": NPC_FORMAT,
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "enrichment_sha256": digest(canonical(enrichment)),
        "actors": sorted(actors),
        "npc_knowledge": {
            "format": rich.NPC_GRANTS_FORMAT, **scope,
            "grants": output["knowledge_grants"],
        },
        "npc_social": {
            "format": rich.NPC_SOCIAL_LIFE_FORMAT, **scope,
            "witnesses": output["witnesses"],
            "rules": output["rules"],
            "choice_gates": output["choice_gates"],
            "item_grants": output["item_grants"],
            "item_transfers": output["item_transfers"],
            "life_transitions": output["life_transitions"],
        },
        "dialogue_knowledge": dialogues,
    }


def prepare_npc_v4_extension(response: dict, index: dict, story: dict,
                             enrichment: dict, base_blueprint: dict,
                             base_provenance: dict, *,
                             npc_present: bool, user_confirmed: bool) -> dict:
    """Choose v4 acts v1/v2/v3 by which source reviews Skill actually wrote."""
    from .v4_acts import FORMAT as ACTS_V1
    from .v4_npc_acts import FORMAT as ACTS_V2, REVIEW_FORMAT as ACT_REVIEW
    from .v4_npc_scene_items import (
        FORMAT as ACTS_V3, REVIEW_FORMAT as SCENE_REVIEW,
    )
    fields(response, {
        "acts", "initial_state", "npc_actor_review", "npc_scene_review",
    } if "npc_actor_review" in response or "npc_scene_review" in response
           else {"acts", "initial_state"}, "skill reviewed v4 authoring")
    has_actor = "npc_actor_review" in response
    has_scene = "npc_scene_review" in response
    require((not has_scene or has_actor) and (not has_actor or npc_present),
            "skill_npc_extension_invalid",
            "NPC-dependent act requires a reviewed base NPC identity")
    require(not npc_present or has_actor,
            "skill_npc_extension_incomplete",
            "Source-reviewed NPC cast requires across-act memory review")
    value = {
        "format": ACTS_V3 if has_scene else ACTS_V2 if has_actor else ACTS_V1,
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "enrichment_sha256": digest(canonical(enrichment)),
        "base_blueprint_sha256": digest(canonical(base_blueprint)),
        "editorial_review": {
            "user_confirmed": user_confirmed,
            "transition_causality_reviewed": user_confirmed,
            "character_continuity_reviewed": user_confirmed,
            "literary_canon_verified": False,
        },
        "acts": response["acts"],
        "initial_state": response["initial_state"],
    }
    if has_actor:
        row = response["npc_actor_review"]
        fields(row, {
            "knowledge_grants", "witnesses", "memories", "choice_gates",
            "life_transitions",
        }, "NPC across-act source review")
        require("npc_knowledge" in base_provenance and
                "npc_social" in base_provenance,
                "skill_npc_base_missing", "Native NPC base provenance is required")
        value["npc_actor_review"] = {
            "format": ACT_REVIEW,
            "source_fingerprint": index["source_fingerprint"],
            "base_npc_knowledge_sha256":
                digest(canonical(base_provenance["npc_knowledge"])),
            "base_npc_social_sha256":
                digest(canonical(base_provenance["npc_social"])),
            "user_confirmed": user_confirmed,
            "literary_canon_verified": False,
            **deepcopy(row),
        }
    if has_scene:
        scene = response["npc_scene_review"]
        fields(scene, {"dialogues", "item_grants", "item_transfers"},
               "signed NPC dialogue and item ownership review")
        value["npc_scene_review"] = {
            "format": SCENE_REVIEW,
            "source_fingerprint": index["source_fingerprint"],
            "base_npc_act_review_sha256":
                digest(canonical(value["npc_actor_review"])),
            "user_confirmed": user_confirmed,
            "literary_canon_verified": False,
            **deepcopy(scene),
        }
    return value
