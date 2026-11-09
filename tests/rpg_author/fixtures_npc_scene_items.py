"""E6k original synthetic source: signed NPC conversation and one genuine item.

Uses reviewed E6j NPC actor and 3-chapter authored FB2; the reviewed lines
are PRIVATE FICTION, not quotations from the source book.
"""
from copy import deepcopy

from tools.rpg_author.common import canonical, digest
from tools.rpg_author.v4_npc_scene_items import FORMAT, REVIEW_FORMAT
from tests.rpg_author.fixtures_npc_acts import (
    ACTOR, NPC_FACT, reviewed_base, reviewed_npc_acts,
)


def reviewed_base_with_owned_item():
    overlay, review = reviewed_base()
    # The native first base choice acquires the rope, but the E6k act later
    # transfers it. Do not consume it in the original rescue choice.
    overlay["choices"]["rescue"]["effects"] = []
    review["enrichment_sha256"] = digest(canonical(overlay))
    return overlay, review


def reviewed_dialogue_and_custody(bp, prov, overlay=None):
    overlay = overlay or reviewed_base_with_owned_item()[0]
    proposal = deepcopy(reviewed_npc_acts(bp, prov, overlay))
    proposal["format"] = FORMAT
    reviewed = proposal["npc_actor_review"]
    # An explicit author-rewritten game dialogue, not a claim of literal words.
    scenes = proposal["acts"][1]["scenes"]
    scenes[0]["text"] = (
        "Лена: «Как нам перебраться через опасное течение?»\n"
        "Лодочник: «Здесь сильное течение, обойди мост справа.»")
    reviewed["witnesses"].append({
        "scene_id": "rescue_decision", "actor_id": ACTOR,
        "mode": "present", "assertion_id": "bridge_call",
    })
    # Every NPC witness must be used by an actual memory/event; otherwise
    # the native social-v5 author must correctly reject an orphaned witness.
    reviewed["memories"].append({
        "scene_id": "rescue_decision", "choice_id": "bold_route",
        "observer_id": ACTOR, "memory_id": "bridge_bold_attempt",
        "kind": "witnessed", "related_actor_id": "player",
        "relationship_delta": 0, "max_triggers": 1,
        "assertion_id": "bridge_call",
    })
    pull_up = scenes[1]["choices"][0]
    pull_up["conditions"].append({"op": "has_item", "id": "rope"})
    pull_up["effects"].append({"op": "consume_item", "id": "rope"})
    pull_up["effect_assertion_ids"].append("bank_rope")

    proposal["npc_scene_review"] = {
        "format": REVIEW_FORMAT,
        "source_fingerprint": proposal["source_fingerprint"],
        "base_npc_act_review_sha256": digest(canonical(reviewed)),
        "user_confirmed": True, "literary_canon_verified": False,
        "dialogues": [{
            "scene_id": "rescue_decision",
            "turns": [
                {"turn_index": 0, "speaker": "Лена",
                 "actor_id": "player", "required_fact_ids": []},
                {
                    "turn_index": 1, "speaker": "Лодочник",
                    "actor_id": ACTOR,
                    "required_fact_ids": [NPC_FACT],
                    "required_social_memory_id": "shared_warning",
                    "minimum_trust_to_player": 1,
                    "required_prior_choice_id": "note_current",
                    "assertion_id": "bridge_damage",
                    "private_fiction_confirmed": True,
                },
            ],
        }],
        "item_grants": [{
            "scene_id": "road", "choice_id": "take_rope",
            "item_id": "rope", "assertion_id": "road_found",
        }],
        "item_transfers": [{
            "scene_id": "rope_rescue", "choice_id": "pull_up",
            "item_id": "rope", "from_actor_id": "player",
            "to_actor_id": ACTOR, "assertion_id": "bank_rope",
        }],
    }
    return proposal
