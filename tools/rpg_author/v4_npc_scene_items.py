"""E6k: reviewed NPC dialogue and item custody on ACTUAL v4 act/NPC rules.

The signed-turn parser and item/social validators are the PINNED native
BookWorld writer's implementations. This module only converts explicit,
source-cited human reviews to its existing JSON. No game rules, no portrait
inference, no fabricated source assertions, no AI prose proof.
"""
from __future__ import annotations

from copy import deepcopy

from tools.bookworld import private_rich_bookworld as rich
from tools.bookworld.bookworld import BookworldError
from .common import canonical, digest, fields, identifier, require
from .validate import assertion_registry
from .v4_npc_acts import FORMAT as NPC_V2, extend_reviewed_npc_acts

FORMAT = "rpg_author_v4_acts_v3"
REVIEW_FORMAT = "rpg_author_v4_npc_scene_review_v1"

_EXTENSION_FIELDS = {
    "format", "source_fingerprint", "story_sha256", "enrichment_sha256",
    "base_blueprint_sha256", "editorial_review", "acts", "initial_state",
    "npc_actor_review", "npc_scene_review",
}
_REVIEW_FIELDS = {
    "format", "source_fingerprint", "base_npc_act_review_sha256",
    "user_confirmed", "literary_canon_verified",
    "dialogues", "item_grants", "item_transfers",
}
_PLAYER_TURN = {"turn_index", "speaker", "actor_id", "required_fact_ids"}
_NPC_TURN = _PLAYER_TURN | {
    "required_social_memory_id", "minimum_trust_to_player",
    "required_prior_choice_id", "assertion_id", "private_fiction_confirmed",
}


def extend_reviewed_npc_scenes(
    blueprint: dict, provenance: dict, story: dict, enrichment: dict,
    index: dict, analyses: list[dict], proposal: dict
) -> tuple[dict, dict, dict]:
    fields(proposal, _EXTENSION_FIELDS, "v4 npc dialogue and custody")
    require(proposal["format"] == FORMAT, "scene_review_wrong_version",
            "Explicit v4 scene review contract is required")
    review = proposal["npc_scene_review"]
    fields(review, _REVIEW_FIELDS, "npc scene, dialogue and item review")
    require(review["format"] == REVIEW_FORMAT and
            review["source_fingerprint"] == index["source_fingerprint"] and
            review["base_npc_act_review_sha256"] ==
            digest(canonical(proposal["npc_actor_review"])) and
            review["user_confirmed"] is True and
            review["literary_canon_verified"] is False,
            "scene_review_unapproved",
            "NPC scene review must match the exact accepted actor/act revision")
    for field in ("dialogues", "item_grants", "item_transfers"):
        require(type(review[field]) is list and len(review[field]) <= 48,
                "scene_review_invalid", "NPC scene review list is malformed")
    # A book may contain a source-backed conversation without a transferable
    # object, or real item custody without any attributable spoken line.
    # Do NOT fabricate the missing kind merely to enter the reviewed v3 path.
    require(any(review[name] for name in
                ("dialogues", "item_grants", "item_transfers")),
            "scene_review_incomplete",
            "A reviewed signed conversation or source-locked item transfer is required")
    require(bool(review["item_grants"]) == bool(review["item_transfers"]),
            "scene_unbalanced_item_review",
            "A source-acquired item must have its separately reviewed transfer")

    base = deepcopy(proposal)
    base["format"] = NPC_V2
    del base["npc_scene_review"]
    bp, prov, report = extend_reviewed_npc_acts(
        blueprint, provenance, story, enrichment, index, analyses, base)
    scene_by_id = {s["id"]: s for s in bp["scenes"]}
    origin_by_id = {o["scene_id"]: o for o in prov["scene_origins"]}
    original_ids = {s["id"] for s in blueprint["scenes"]}
    authored = {
        s["id"]: s for act in proposal["acts"] for s in act["scenes"]
    }
    registry = assertion_registry(analyses, index)
    social = prov["npc_social"]
    knowledge = prov["npc_knowledge"]
    actors = set(bp["actors"]) - {"player"}

    def witnessed_quote(scene_id: str, claim_id: str) -> str:
        """Retrieve exact previously verified source quote, not a model SHA."""
        require(type(claim_id) is str and claim_id in registry,
                "scene_unknown_assertion", "Unknown exact source assertion")
        require(scene_id in origin_by_id and
                origin_by_id[scene_id]["origin"] == "SOURCE_PASSAGE",
                "scene_missing_source", "This action has no original sourced scene")
        if scene_id in authored:
            require(claim_id in authored[scene_id]["assertion_ids"],
                    "scene_unknown_assertion",
                    "NPC text or item review quotes an unrelated scene assertion")
        quote = digest(registry[claim_id]["assertion"]["quote"].encode("utf-8"))
        source = origin_by_id[scene_id]
        require(any(ref["quote_sha256"] == quote and
                    ref["chapter_index"] <= source["chapter_index"] and
                    ref["visible_after_chapter"] <= source["chapter_index"]
                    for ref in source["source_refs"]),
                "scene_missing_source", "No exact, visible review evidence")
        return quote

    def action(scene_id: str, choice_id: str) -> dict:
        identifier(scene_id, "NPC scene")
        identifier(choice_id, "NPC action")
        scene = scene_by_id.get(scene_id)
        choices = ([] if scene is None else
                   [c for c in scene["choices"] if c["id"] == choice_id])
        require(len(choices) == 1, "scene_unknown_action",
                "NPC action must name one compiled scene decision")
        return choices[0]

    def valid_actor(actor: str) -> None:
        identifier(actor, "permanent NPC id")
        require(actor in actors, "scene_unknown_actor",
                "Actor must already be present in signed NPC v3/v4 history")

    # Item history: previous acquisition in an ORIGINAL sourced action, then
    # transfer in a NEW sourced, witnessed act action. Native validates the
    # ledger and the actual inventory state; this is editorial preflight only.
    require(not social["item_grants"] and not social["item_transfers"],
            "scene_item_history_present",
            "Existing NPC item ledger needs a distinct independently reviewed migration")
    acquired = {}
    for row in review["item_grants"]:
        fields(row, {"scene_id", "choice_id", "item_id", "assertion_id"},
               "source-backed item acquisition")
        sid, cid, item = row["scene_id"], row["choice_id"], row["item_id"]
        identifier(item, "item")
        require(sid in original_ids and item in bp["items"] and
                item not in acquired and
                item not in bp["initial_state"]["inventory"],
                "scene_invalid_acquisition",
                "Item must be acquired once in an existing, reviewed source scene")
        selected = action(sid, cid)
        require(sum(e["op"] == "grant_item" and e.get("id") == item
                    for e in selected["effects"]) == 1,
                "scene_invalid_acquisition",
                "Original choice does not create exactly this item")
        q = witnessed_quote(sid, row["assertion_id"])
        acquired[item] = (sid, cid)
        social["item_grants"].append({
            "scene_id": sid, "choice_id": cid, "item_id": item,
            "source_quote_sha256": q,
        })

    transferred = set()
    for row in review["item_transfers"]:
        fields(row, {"scene_id", "choice_id", "item_id", "from_actor_id",
                     "to_actor_id", "assertion_id"}, "reviewed NPC item transfer")
        sid, cid, item = row["scene_id"], row["choice_id"], row["item_id"]
        identifier(item, "item")
        destination = row["to_actor_id"]
        valid_actor(destination)
        require(row["from_actor_id"] == "player" and
                item in acquired and item not in transferred and
                sid in authored, "scene_invalid_transfer",
                "Only a source-granted player's item can transfer to an observed NPC")
        selected = action(sid, cid)
        owns = any(c["op"] == "has_item" and c.get("id") == item
                   for c in selected["conditions"])
        gives = sum(e["op"] == "consume_item" and e.get("id") == item
                    for e in selected["effects"])
        witnessed = any(w["scene_id"] == sid and
                        w["actor_id"] == destination and w["mode"] == "present"
                        for w in social["witnesses"])
        require(owns and gives == 1 and witnessed and
                origin_by_id[acquired[item][0]]["chapter_index"] <=
                origin_by_id[sid]["chapter_index"],
                "scene_invalid_transfer",
                "Item transfer needs an existing item, typed consumption and present NPC")
        q = witnessed_quote(sid, row["assertion_id"])
        transferred.add(item)
        social["item_transfers"].append({
            "scene_id": sid, "choice_id": cid, "item_id": item,
            "from_actor_id": "player", "to_actor_id": destination,
            "source_quote_sha256": q,
        })
    require(set(acquired) == transferred, "scene_unbalanced_item_review",
            "Item source, custody and destination must form one reviewed ledger")

    presentation = prov["presentation"]
    existing_signed = presentation.get("scene_dialogues", {})
    existing_review = presentation.get("scene_dialogue_knowledge", {})
    require(type(existing_signed) is dict and type(existing_review) is dict,
            "scene_dialogue_base_invalid", "Existing speaker identity review changed")
    seen = set()
    signed, reviews = deepcopy(existing_signed), deepcopy(existing_review)
    newly_signed = {
        sid for sid in authored
        if rich._exact_scene_dialogue(scene_by_id[sid]["text"]) is not None
    }
    for entry in review["dialogues"]:
        fields(entry, {"scene_id", "turns"}, "new signed npc dialogue")
        sid = entry["scene_id"]
        require(sid in newly_signed and sid not in seen and
                sid not in signed, "scene_dialogue_missing",
                "Each new attributed scene must have its own review")
        seen.add(sid)
        parsed = rich._exact_scene_dialogue(scene_by_id[sid]["text"])
        spoken = {i: row["speaker"] for i, row in
                  enumerate(parsed["turns"]) if row["speaker"] is not None}
        turns = entry["turns"]
        require(type(turns) is list and len(turns) == len(spoken),
                "scene_dialogue_incomplete", "Every signed speaker turn must be reviewed")
        final = []
        encountered = set()
        for line in turns:
            require(type(line) is dict, "scene_dialogue_invalid_turn",
                    "Dialogue reviews must be structured objects")
            actor = line.get("actor_id")
            fields(line, _PLAYER_TURN if actor == "player" else _NPC_TURN,
                   "reviewed dialogue speaker and prior knowledge")
            idx = line["turn_index"]
            require(type(idx) is int and idx in spoken and idx not in encountered
                    and line["speaker"] == spoken[idx],
                    "scene_dialogue_mismatch",
                    "Signed scene turn index, text and reviewed speaker must match")
            encountered.add(idx)
            identifier(actor, "reviewed dialogue actor")
            require(actor in bp["actors"] and
                    (actor == "player" or actor in actors),
                    "scene_unknown_actor", "Do not guess a speaker by display name")
            fact_ids = line["required_fact_ids"]
            require(type(fact_ids) is list and fact_ids ==
                    sorted(set(fact_ids)) and
                    all(type(f) is str and f in bp["facts"] for f in fact_ids),
                    "scene_dialogue_invalid_facts", "Unknown or repeated NPC fact")
            output = {
                "turn_index": idx, "speaker": line["speaker"],
                "actor_id": actor, "required_fact_ids": fact_ids,
            }
            if actor != "player":
                require(line["private_fiction_confirmed"] is True and
                        line["required_social_memory_id"] is not None and
                        type(line["minimum_trust_to_player"]) is int and
                        1 <= line["minimum_trust_to_player"] <= 100 and
                        bool(fact_ids),
                        "scene_dialogue_not_approved",
                        "NPC knowledge-bearing speech requires an explicit reviewer")
                prior_choice = line["required_prior_choice_id"]
                identifier(prior_choice, "earlier NPC grant choice")
                producer = [g for g in knowledge["grants"]
                            if g["choice_id"] == prior_choice and
                            g["actor_id"] == actor and
                            g["fact_id"] in fact_ids]
                require(len(producer) == len(fact_ids) and
                        len({g["fact_id"] for g in producer}) == len(fact_ids),
                        "scene_dialogue_missing_learning",
                        "A prior, separately reviewed action must teach every fact")
                from_scene = producer[0]["scene_id"]
                require(from_scene != sid and
                        origin_by_id[from_scene]["chapter_index"] <=
                        origin_by_id[sid]["chapter_index"],
                        "scene_dialogue_future_learning",
                        "NPC may not speak a fact from an unseen future event")
                quote = witnessed_quote(from_scene, line["assertion_id"])
                require(all(g["source_quote_sha256"] == quote
                            for g in producer),
                        "scene_dialogue_wrong_source",
                        "Dialogue must cite the exact source-backed NPC learning action")
                memory = line["required_social_memory_id"]
                identifier(memory, "NPC memory id")
                require(any(rule["memory_id"] == memory and
                            rule["observer_id"] == actor and
                            rule["related_actor_id"] == "player" and
                            rule["relationship_delta"] > 0 and
                            origin_by_id[rule["scene_id"]]["chapter_index"] <=
                            origin_by_id[sid]["chapter_index"]
                            for rule in social["rules"]),
                        "scene_dialogue_unearned_memory",
                        "NPC speech cannot leak private memories or future trust")
                output.update({
                    "required_social_memory_id": memory,
                    "minimum_trust_to_player": line["minimum_trust_to_player"],
                    "required_prior_choice_id": prior_choice,
                    "source_quote_sha256": quote,
                    "private_fiction_confirmed": True,
                })
            final.append(output)
        require(encountered == set(spoken), "scene_dialogue_incomplete",
                "No dialogue turn can remain unreviewed")
        signed[sid] = parsed
        reviews[sid] = final
    require(seen == newly_signed, "scene_dialogue_missing",
            "All newly attributed NPC scenes must be signed and reviewed")
    presentation["scene_dialogues"] = signed
    presentation["scene_dialogue_knowledge"] = reviews

    # Use the already-pinned native BookWorld Python validator immediately,
    # then require the independent native DART compiler/importer on build.
    try:
        rich._npc_social(prov, bp)
        rich._npc_knowledge(prov, bp)
        rich._presentation(presentation, bp, social, prov["scene_origins"])
    except (BookworldError, KeyError, TypeError, ValueError) as err:
        from .common import AuthoringError
        raise AuthoringError("scene_native_review_rejected", str(err)) from err

    revision = digest(canonical(proposal))
    bp["book_id"] = "npc_scene_" + digest(canonical({
        "base": blueprint["book_id"], "review": revision,
    }))[:32]
    prov["bookworld_id"] = bp["book_id"]
    prov["intermediate_draft_sha256"] = digest(canonical({
        "previous": provenance["intermediate_draft_sha256"],
        "npc_scene_review": revision,
    }))
    report.update({
        "status": "V4_NPC_SCENE_PREFLIGHT_NEEDS_NATIVE_AND_EDITORIAL_ACCEPTANCE",
        "npc_dialogue_scenes_reviewed": len(seen),
        "npc_dialogue_signed_turns": sum(
            len(reviews[sid]) for sid in seen),
        "npc_source_items_reviewed": len(acquired),
        "npc_item_transfers_reviewed": len(transferred),
        "npc_portrait_uses_verified_character_id": True,
        "npc_item_owners_verified_by_native": False,
        "dialogue_redaction_verified_by_native": False,
        "semantic_review_completed": False,
        "device_playtest_completed": False,
    })
    return bp, prov, report
