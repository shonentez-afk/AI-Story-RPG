"""E6j: versioned, actor-scoped NPC evidence for source-locked v4 acts.

An accepted v3 NPC reviewer remains authoritative for identity, history and
social v5. New grants, witnesses, memories, trust gates and life events must
be explicitly reviewed against the exact new scene/choice/source citation.
Native Dart writer/importer and rpg_api do all real game-state execution.
"""
from __future__ import annotations

from copy import deepcopy

from .common import canonical, digest, fields, identifier, require
from .v4_acts import FORMAT as BASE_FORMAT, extend_reviewed_acts
from .validate import assertion_registry

FORMAT = "rpg_author_v4_acts_v2"
REVIEW_FORMAT = "rpg_author_v4_npc_act_review_v1"
SOCIAL_V5 = "ai_story_npc_social_witness_v5"
KNOWLEDGE_V1 = "ai_story_npc_knowledge_grants_v1"

_REVIEW_FIELDS = {
    "format", "source_fingerprint", "base_npc_knowledge_sha256",
    "base_npc_social_sha256", "user_confirmed", "literary_canon_verified",
    "knowledge_grants", "witnesses", "memories", "choice_gates",
    "life_transitions",
}
_MEMORY_KINDS = frozenset({
    "witnessed", "promiseReceived", "promiseBroken", "helped", "betrayed",
    "rumorHeard",
})


def _strict_source(scene_id, assertion_id, authored: dict, source_origins: dict,
                   registry: dict, *, allow_reported: bool = False) -> str:
    """Return the original quote hash, NEVER trust a supplied SHA-256."""
    require(scene_id in authored, "npc_unreviewed_scene",
            "NPC act annotation references a non-authored or original scene")
    require(assertion_id in authored[scene_id]["assertion_ids"] and
            assertion_id in registry, "npc_unreviewed_quote",
            "The NPC annotation must cite its own reviewed scene assertion")
    claim = registry[assertion_id]["assertion"]
    require(allow_reported or claim["kind"] == "NARRATED",
            "npc_unreliable_witness",
            "A present NPC or direct fact cannot be attested from hearsay")
    quote = digest(claim["quote"].encode("utf-8"))
    origin = source_origins[scene_id]
    require(origin["origin"] == "SOURCE_PASSAGE" and any(
        ref["quote_sha256"] == quote and
        ref["chapter_index"] <= origin["chapter_index"] and
        ref["visible_after_chapter"] <= origin["chapter_index"]
        for ref in origin["source_refs"]),
        "npc_missing_source_witness",
        "NPC assertion must be witnessed by the exact currently visible passage")
    return quote


def extend_reviewed_npc_acts(blueprint: dict, provenance: dict,
                             story: dict, enrichment: dict,
                             index: dict, analyses: list[dict],
                             extension: dict) -> tuple[dict, dict, dict]:
    """Generate a v4-scoped review; NO new NPC or rule implementation."""
    fields(extension, {
        "format", "source_fingerprint", "story_sha256", "enrichment_sha256",
        "base_blueprint_sha256", "editorial_review", "acts", "initial_state",
        "npc_actor_review",
    }, "npc-enhanced v4 act extension")
    require(extension["format"] == FORMAT, "npc_act_wrong_format",
            "Unknown source-reviewed multi-act NPC contract")
    review = extension["npc_actor_review"]
    fields(review, _REVIEW_FIELDS, "npc actor-scoped review")
    previous_knowledge = provenance.get("npc_knowledge")
    previous_social = provenance.get("npc_social")
    require(type(previous_knowledge) is dict and
            previous_knowledge.get("format") == KNOWLEDGE_V1 and
            type(previous_social) is dict and
            previous_social.get("format") == SOCIAL_V5,
            "npc_base_review_required",
            "New NPC events require existing verified v3 actor identities and social v5")
    require(review["format"] == REVIEW_FORMAT and
            review["source_fingerprint"] == index["source_fingerprint"] and
            review["base_npc_knowledge_sha256"] ==
            digest(canonical(previous_knowledge)) and
            review["base_npc_social_sha256"] ==
            digest(canonical(previous_social)) and
            review["user_confirmed"] is True and
            review["literary_canon_verified"] is False,
            "npc_act_review_mismatch",
            "Review is not consented or does not match the exact previous NPC history")
    for section in ("knowledge_grants", "witnesses", "memories",
                    "choice_gates", "life_transitions"):
        require(type(review[section]) is list and len(review[section]) <= 128,
                "npc_invalid_section", "NPC review section is malformed or oversized")
    require(bool(review["knowledge_grants"]) and bool(review["witnesses"]) and
            bool(review["memories"]) and bool(review["choice_gates"]),
            "npc_empty_act_review",
            "Cross-act NPC authority needs grant, presence, memory and a later gate")

    keys = set()
    for raw in review["knowledge_grants"]:
        fields(raw, {"scene_id", "choice_id", "actor_id",
                     "fact_id", "assertion_id"}, "npc act grant")
        for key in ("scene_id", "choice_id", "actor_id", "fact_id", "assertion_id"):
            identifier(raw[key], "npc grant " + key)
        require(raw["actor_id"] != "player" and
                raw["actor_id"] in blueprint["actors"],
                "npc_identity_missing",
                "NPC grant must reuse a verified persistent actor in the base world")
        tup = (raw["scene_id"], raw["choice_id"],
               raw["actor_id"], raw["fact_id"])
        require(tup not in keys, "npc_duplicate_grant",
                "An actor/choice/fact may have only one matching reviewer")
        keys.add(tup)
    # Existing v1 act author will permit ONLY these exact NPC grants as native
    # typed effects. The strict quote/scene/witness/actor binding runs below,
    # BEFORE native Dart is invoked.
    v1 = deepcopy(extension)
    v1.pop("npc_actor_review")
    v1["format"] = BASE_FORMAT
    bp, prov, report = extend_reviewed_acts(
        blueprint, provenance, story, enrichment, index, analyses, v1,
        approved_npc_grants=frozenset(keys))

    acts = extension["acts"]
    act_number, authored = {}, {}
    for ix, act in enumerate(acts):
        for scene in act["scenes"]:
            act_number[scene["id"]] = ix
            authored[scene["id"]] = scene
    indexed = {s["id"]: s for s in bp["scenes"]}
    origins = {origin["scene_id"]: origin for origin in prov["scene_origins"]}
    registry = assertion_registry(analyses, index)
    npcs = set(bp["actors"]) - {"player"}
    require(bool(npcs), "npc_base_review_required",
            "An NPC act cannot create its own character identities")

    def valid_action(scene: str, choice: str) -> dict:
        require(scene in authored and scene in indexed,
                "npc_unreviewed_scene",
                "Annotations may refer only to explicitly authored act scenes")
        found = [c for c in indexed[scene]["choices"] if c["id"] == choice]
        require(len(found) == 1, "npc_invalid_choice",
                "NPC annotation refers to no actual signed choice")
        return found[0]

    def eligible_actor(actor: str) -> None:
        identifier(actor, "persistent NPC character_id")
        require(actor in npcs, "npc_identity_missing",
                "The actor must already exist in the pinned, reviewed base world")

    new_grants = []
    for raw in review["knowledge_grants"]:
        scene, choice = raw["scene_id"], raw["choice_id"]
        actor, fact = raw["actor_id"], raw["fact_id"]
        eligible_actor(actor)
        require(fact in bp["facts"], "npc_unknown_fact",
                "An actor cannot learn a fact invented outside the reviewed catalog")
        action = valid_action(scene, choice)
        require(sum(e["op"] == "learn_fact" and e.get("actor") == actor and
                    e.get("id") == fact for e in action["effects"]) == 1,
                "npc_grant_without_effect",
                "A knowledge grant must match exactly one committed typed action")
        q = _strict_source(scene, raw["assertion_id"], authored, origins, registry)
        new_grants.append({"scene_id": scene, "choice_id": choice,
                           "actor_id": actor, "fact_id": fact,
                           "source_quote_sha256": q})
    require(len(previous_knowledge["grants"]) + len(new_grants) <= 128,
            "npc_grant_limit", "NPC grants exceed native importer limit")
    prov["npc_knowledge"]["grants"].extend(new_grants)

    seen_witnesses = {(w["scene_id"], w["actor_id"])
                      for w in previous_social["witnesses"]}
    new_witnesses, present = [], {}
    for raw in review["witnesses"]:
        fields(raw, {"scene_id", "actor_id", "mode", "assertion_id"},
               "act npc presence")
        scene, actor, mode = raw["scene_id"], raw["actor_id"], raw["mode"]
        eligible_actor(actor)
        require(mode in ("present", "reported") and
                (scene, actor) not in seen_witnesses,
                "npc_duplicate_witness", "NPC presence must be uniquely witnessed")
        seen_witnesses.add((scene, actor))
        q = _strict_source(scene, raw["assertion_id"], authored, origins,
                           registry, allow_reported=mode == "reported")
        present[(scene, actor)] = mode
        new_witnesses.append({"scene_id": scene, "actor_id": actor,
                              "mode": mode, "source_quote_sha256": q})
    prov["npc_social"]["witnesses"].extend(new_witnesses)

    seen_memory = {(r["observer_id"], r["memory_id"])
                   for r in previous_social["rules"]}
    new_memories, earlier_memory = [], {}
    for raw in review["memories"]:
        fields(raw, {"scene_id", "choice_id", "observer_id", "memory_id",
                     "kind", "related_actor_id", "relationship_delta",
                     "max_triggers", "assertion_id"}, "reviewed npc memory")
        scene, choice = raw["scene_id"], raw["choice_id"]
        observer, memory = raw["observer_id"], raw["memory_id"]
        eligible_actor(observer)
        identifier(memory, "npc memory id")
        action = valid_action(scene, choice)
        kind, delta = raw["kind"], raw["relationship_delta"]
        require(kind in _MEMORY_KINDS and type(delta) is int and
                -20 <= delta <= 20 and
                type(raw["max_triggers"]) is int and
                1 <= raw["max_triggers"] <= 10,
                "npc_invalid_memory", "Invalid NPC memory kind or trust bounds")
        mode = present.get((scene, observer))
        require(mode is not None and (mode != "reported" or
                (kind == "rumorHeard" and delta == 0)),
                "npc_unwitnessed_memory",
                "Trust/memory cannot be created without first-hand presence")
        related = raw["related_actor_id"]
        require(related == "player" or related in npcs and related != observer,
                "npc_invalid_relation", "A memory must refer to a known other actor")
        require((observer, memory) not in seen_memory,
                "npc_duplicate_memory", "NPC memory ID collides with previous history")
        seen_memory.add((observer, memory))
        q = _strict_source(scene, raw["assertion_id"], authored, origins,
                           registry, allow_reported=mode == "reported")
        new_memories.append({
            "scene_id": scene, "choice_id": choice,
            "observer_id": observer, "memory_id": memory,
            "kind": kind, "related_actor_id": related,
            "relationship_delta": delta, "max_triggers": raw["max_triggers"],
            "source_quote_sha256": q,
        })
        earlier_memory[(observer, memory)] = (scene, choice, act_number[scene], delta, related)
    require(len(previous_social["rules"]) + len(new_memories) <= 128,
            "npc_memory_limit", "NPC memories exceed the native v5 limit")
    prov["npc_social"]["rules"].extend(new_memories)

    new_gates, seen_gates = [], {(g["scene_id"], g["choice_id"])
                                  for g in previous_social["choice_gates"]}
    for raw in review["choice_gates"]:
        fields(raw, {"scene_id", "choice_id", "actor_id", "required_memory_id",
                     "minimum_trust_to_player", "assertion_id"},
               "cross-act npc trust gate")
        scene, choice, actor = raw["scene_id"], raw["choice_id"], raw["actor_id"]
        eligible_actor(actor)
        valid_action(scene, choice)
        memory, trust = raw["required_memory_id"], raw["minimum_trust_to_player"]
        identifier(memory, "earned memory id")
        require(type(trust) is int and 0 <= trust <= 20,
                "npc_bad_trust_gate", "Trust threshold must be bounded and nonnegative")
        prior = earlier_memory.get((actor, memory))
        require(prior is not None and prior[2] < act_number[scene] and
                prior[3] > 0 and prior[4] == "player",
                "npc_unearned_cross_act_memory",
                "NPC trust gate needs a positive memory from an EARLIER reviewed act")
        require((scene, choice) not in seen_gates,
                "npc_duplicate_gate", "A choice cannot receive conflicting social gates")
        seen_gates.add((scene, choice))
        q = _strict_source(scene, raw["assertion_id"], authored, origins, registry)
        new_gates.append({
            "scene_id": scene, "choice_id": choice, "actor_id": actor,
            "required_memory_id": memory, "minimum_trust_to_player": trust,
            "source_quote_sha256": q,
        })
    require(len(previous_social["choice_gates"]) + len(new_gates) <= 128,
            "npc_gate_limit", "Too many NPC decision gates")
    prov["npc_social"]["choice_gates"].extend(new_gates)

    new_life, seen_life = [], {
        (row["scene_id"], row["choice_id"], row["actor_id"])
        for row in previous_social["life_transitions"]}
    for raw in review["life_transitions"]:
        fields(raw, {"scene_id", "choice_id", "actor_id", "next_state",
                     "assertion_id"}, "npc life transition")
        scene, choice, actor = raw["scene_id"], raw["choice_id"], raw["actor_id"]
        eligible_actor(actor)
        valid_action(scene, choice)
        require(raw["next_state"] in ("present", "absent", "dead") and
                (scene, choice, actor) not in seen_life and
                present.get((scene, actor)) == "present",
                "npc_invalid_life_event",
                "Life transition needs a unique choice and present source witness")
        seen_life.add((scene, choice, actor))
        q = _strict_source(scene, raw["assertion_id"], authored, origins, registry)
        new_life.append({
            "scene_id": scene, "choice_id": choice, "actor_id": actor,
            "next_state": raw["next_state"], "source_quote_sha256": q,
        })
    require(len(previous_social["life_transitions"]) + len(new_life) <= 128,
            "npc_life_limit", "Too many NPC life transitions")
    prov["npc_social"]["life_transitions"].extend(new_life)

    # Authoring versions with different reviews cannot share the same world ID.
    unique = digest(canonical(extension))
    bp["book_id"] = "npc_acts_" + digest(canonical({
        "previous": blueprint["book_id"], "source": unique,
    }))[:32]
    prov["bookworld_id"] = bp["book_id"]
    prov["intermediate_draft_sha256"] = digest(canonical({
        "previous_review": provenance["intermediate_draft_sha256"],
        "source_locked_npc_acts": unique,
    }))
    report.update({
        "status": "V4_ACT_NPC_REVIEW_PENDING_NATIVE_AND_LITERARY_ACCEPTANCE",
        "npc_base_review_locked": True,
        "npc_known_grants_added": len(new_grants),
        "npc_witnesses_added": len(new_witnesses),
        "npc_memories_added": len(new_memories),
        "npc_cross_act_gates_added": len(new_gates),
        "npc_life_transitions_added": len(new_life),
        "npc_social_v5_validated_by_native": False,
        "actor_identity_reused_from_base": True,
        "literary_canon_verified": False,
        "device_playtest_completed": False,
    })
    return bp, prov, report
