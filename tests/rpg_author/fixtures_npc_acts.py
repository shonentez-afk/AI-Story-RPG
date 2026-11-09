"""Original synthetic NPC cross-act source, never a user/private literary book.

A persistent Boatman character learns a sourced fact, forms an event-sourced
memory in act one, and checks that memory/trust in act two. Absent characters,
false rumors and invented future knowledge must never gain authority.
"""
from copy import deepcopy

from tools.bookworld import private_rich_bookworld as rich
from tools.rpg_author.common import canonical, digest
from tests.rpg_author import fixtures_acts as ordinary
from tools.rpg_author.v4_npc_acts import FORMAT, REVIEW_FORMAT

ACTOR = "npc_" + "d" * 32
NPC_FACT = "npc_current"


def _quote(aid: str) -> str:
    found = [
        assertion["quote"]
        for record in ordinary.analyses()
        for assertion in record["assertions"]
        if assertion["id"] == aid
    ]
    assert len(found) == 1, aid
    return digest(found[0].encode("utf-8"))


def reviewed_base():
    """A fully valid, separately approved v3 NPC source/knowledge/social v5."""
    plan = ordinary.story_plan()
    overlay = ordinary.rich_enrichment()
    overlay["facts"][NPC_FACT] = "Лодочник знает о течении."
    overlay["choices"]["call_help"]["effects"].append(
        {"op": "learn_fact", "id": NPC_FACT, "actor": ACTOR})
    warning = _quote("bridge_warning")
    review = {
        "format": "rpg_author_reviewed_npc_overlay_v1",
        "source_fingerprint": ordinary.index()["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "enrichment_sha256": digest(canonical(overlay)),
        "actors": [ACTOR],
        "npc_knowledge": {
            "format": rich.NPC_GRANTS_FORMAT,
            "review_scope": "user_declared_private_game_fiction",
            "source_fingerprint": ordinary.index()["source_fingerprint"],
            "user_confirmed": True, "literary_canon_verified": False,
            "grants": [{
                "scene_id": "river", "choice_id": "call_help",
                "actor_id": ACTOR, "fact_id": NPC_FACT,
                "source_quote_sha256": warning,
            }],
        },
        "npc_social": {
            "format": rich.NPC_SOCIAL_LIFE_FORMAT,
            "review_scope": "user_declared_private_game_fiction",
            "source_fingerprint": ordinary.index()["source_fingerprint"],
            "user_confirmed": True, "literary_canon_verified": False,
            "witnesses": [{
                "scene_id": "river", "actor_id": ACTOR,
                "mode": "present", "source_quote_sha256": warning,
            }],
            "rules": [{
                "memory_id": "call_for_help",
                "scene_id": "river", "choice_id": "call_help",
                "observer_id": ACTOR, "kind": "witnessed",
                "related_actor_id": "player", "relationship_delta": 0,
                "max_triggers": 1, "source_quote_sha256": warning,
            }],
            "choice_gates": [], "item_transfers": [], "item_grants": [],
            "life_transitions": [{
                "scene_id": "river", "choice_id": "call_help",
                "actor_id": ACTOR, "next_state": "absent",
                "source_quote_sha256": warning,
            }],
        },
        "dialogue_knowledge": {},
    }
    return overlay, review


def reviewed_npc_acts(blueprint, provenance, overlay=None):
    """Two editorially reviewed acts with real NPC grant and future trust gate."""
    overlay = overlay or reviewed_base()[0]
    result = deepcopy(ordinary.reviewed_acts(blueprint, overlay=overlay))
    result["format"] = FORMAT
    first = result["acts"][0]["scenes"][1]["choices"][0]
    first["effects"].append(
        {"op": "learn_fact", "id": NPC_FACT, "actor": ACTOR})
    first["effect_assertion_ids"].append("bridge_damage")
    second = result["acts"][1]["scenes"][0]["choices"][0]
    second["conditions"].append({
        "op": "knows_fact", "id": NPC_FACT, "actor": ACTOR})
    result["npc_actor_review"] = {
        "format": REVIEW_FORMAT,
        "source_fingerprint": ordinary.index()["source_fingerprint"],
        "base_npc_knowledge_sha256":
            digest(canonical(provenance["npc_knowledge"])),
        "base_npc_social_sha256": digest(canonical(provenance["npc_social"])),
        "user_confirmed": True, "literary_canon_verified": False,
        "knowledge_grants": [{
            "scene_id": "study_current", "choice_id": "note_current",
            "actor_id": ACTOR, "fact_id": NPC_FACT,
            "assertion_id": "bridge_damage",
        }],
        "witnesses": [
            {"scene_id": "study_current", "actor_id": ACTOR,
             "mode": "present", "assertion_id": "bridge_damage"},
            {"scene_id": "rope_rescue", "actor_id": ACTOR,
             "mode": "present", "assertion_id": "bank_rope"},
        ],
        "memories": [
            {
                "scene_id": "study_current", "choice_id": "note_current",
                "observer_id": ACTOR, "memory_id": "shared_warning",
                "kind": "helped", "related_actor_id": "player",
                "relationship_delta": 2, "max_triggers": 1,
                "assertion_id": "bridge_damage",
            },
            {
                "scene_id": "rope_rescue", "choice_id": "pull_up",
                "observer_id": ACTOR, "memory_id": "shore_rescue",
                "kind": "witnessed", "related_actor_id": "player",
                "relationship_delta": 0, "max_triggers": 1,
                "assertion_id": "bank_rope",
            },
        ],
        "choice_gates": [{
            "scene_id": "rescue_decision", "choice_id": "careful_route",
            "actor_id": ACTOR, "required_memory_id": "shared_warning",
            "minimum_trust_to_player": 1,
            "assertion_id": "bridge_call",
        }],
        "life_transitions": [{
            "scene_id": "rope_rescue", "choice_id": "pull_up",
            "actor_id": ACTOR, "next_state": "absent",
            "assertion_id": "bank_rope",
        }],
    }
    return result
