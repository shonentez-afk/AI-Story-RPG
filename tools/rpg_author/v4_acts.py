"""Source-locked, multi-act RPG v4 authoring on top of accepted E6g StoryPlan.

This layer verifies exact source evidence, branching scene graph, catalog-bound
typed rules and reviewer declarations. State simulation and native .bworld v4
verification belong exclusively to the pinned Dart engine.
"""
from __future__ import annotations

from copy import deepcopy

from .common import canonical, digest, fields, identifier, require, string, string_list
from .v4_expansion import _origin, _initial_review
from .validate import assertion_registry

FORMAT = "rpg_author_v4_acts_v1"
EXIT = "@exit"

CONDITIONS = {
    "flag_is": {"op", "id", "value"},
    "has_item": {"op", "id"},
    "stat_at_least": {"op", "id", "amount"},
    "knows_fact": {"op", "id", "actor"},
    "tick_at_least": {"op", "amount"},
}
EFFECTS = {
    "set_flag": {"op", "id", "value"},
    "grant_item": {"op", "id"},
    "consume_item": {"op", "id"},
    "stat_delta": {"op", "id", "amount"},
    "learn_fact": {"op", "id", "actor"},
    "advance_time": {"op", "amount"},
}


def _check_rule(raw: dict, blueprint: dict, *, effect: bool) -> None:
    """Enforce the native JSON DSL shape, not a duplicate gameplay engine."""
    valid = EFFECTS if effect else CONDITIONS
    require(type(raw) is dict and type(raw.get("op")) is str
            and raw["op"] in valid and set(raw) == valid[raw["op"]],
            "invalid_act_rule", "Unknown or malformed native typed rule")
    op = raw["op"]
    if "id" in raw:
        identifier(raw["id"], "act rule target")
        catalog = {
            "flag_is": blueprint["initial_state"]["flags"],
            "set_flag": blueprint["initial_state"]["flags"],
            "has_item": blueprint["items"],
            "grant_item": blueprint["items"],
            "consume_item": blueprint["items"],
            "stat_at_least": blueprint["initial_state"]["stats"],
            "stat_delta": blueprint["initial_state"]["stats"],
            "knows_fact": blueprint["facts"],
            "learn_fact": blueprint["facts"],
        }[op]
        require(raw["id"] in catalog, "unknown_act_catalog",
                "Rule references an item, fact, stat or flag not reviewed in base v3")
    if "actor" in raw:
        identifier(raw["actor"], "act actor id")
        require(raw["actor"] in blueprint["actors"], "unknown_act_actor",
                "Act references a missing actor")
        if effect:
            require(raw["actor"] == "player", "unreviewed_act_npc_grant",
                    "NPC learn_fact requires an independent witness and social review")
    if "value" in raw:
        require(type(raw["value"]) is bool, "invalid_act_rule",
                "A flag rule requires a strict boolean")
    if "amount" in raw:
        amount = raw["amount"]
        require(type(amount) is int, "invalid_act_rule", "Amount must be an integer")
        lo, hi = {
            "stat_at_least": (0, 1000000),
            "tick_at_least": (0, 1000000),
            "stat_delta": (-20, 20),
            "advance_time": (1, 1000),
        }[op]
        require(lo <= amount <= hi and (op != "stat_delta" or amount != 0),
                "invalid_act_rule", "Effect/condition amount outside native bounds")


def _check_graph(scenes: dict, entry: str, exit_chapter: int) -> int:
    """Prove all authored nodes reachable, acyclic and able to reach @exit."""
    visiting, finished, reachable, exits = set(), set(), set(), set()

    def walk(node):
        require(node not in visiting, "act_trapped_cycle",
                "Act contains a closed or cyclic path")
        if node in finished:
            return
        visiting.add(node)
        reachable.add(node)
        here = scenes[node]
        for choice in here["choices"]:
            target = choice["next_scene_id"]
            if target == EXIT:
                require(here["chapter_index"] <= exit_chapter,
                        "act_backward_exit", "Act exits before its own chapter")
                exits.add(node)
            else:
                require(target in scenes, "act_invalid_target",
                        "Act may link only to its own scenes or @exit")
                require(here["chapter_index"] <= scenes[target]["chapter_index"],
                        "act_backward_event", "Act moves backwards through the book")
                walk(target)
        visiting.remove(node)
        finished.add(node)
    walk(entry)
    require(reachable == set(scenes), "act_unreachable_event",
            "An authored event cannot be reached from the act entry")
    escapable = set(exits)
    changed = True
    while changed:
        changed = False
        for sid, scene in scenes.items():
            if sid not in escapable and any(c["next_scene_id"] in escapable
                                             for c in scene["choices"]):
                escapable.add(sid)
                changed = True
    require(escapable == set(scenes), "act_no_exit",
            "Every event must have an eventual route to the original destination")
    forks = 0
    for scene in scenes.values():
        if len(scene["choices"]) <= 1:
            continue
        outcomes = {
            canonical([c["next_scene_id"], c["conditions"], c["effects"]])
            for c in scene["choices"]
        }
        require(len(outcomes) == len(scene["choices"]), "act_equivalent_choices",
                "Two authored decisions have no distinct mechanical outcome")
        forks += 1
    require(forks >= 1, "act_no_branch",
            "A reviewed act must contain a branching decision, not filler scenes")
    return forks


def extend_reviewed_acts(blueprint: dict, provenance: dict, story: dict,
                         enrichment: dict, index: dict, analyses: list[dict],
                         proposal: dict) -> tuple[dict, dict, dict]:
    """Validate a private multi-act proposal; return native input and honest QA."""
    fields(proposal, {
        "format", "source_fingerprint", "story_sha256", "enrichment_sha256",
        "base_blueprint_sha256", "editorial_review", "acts", "initial_state",
    }, "multi-act proposal")
    fingerprint = index["source_fingerprint"]
    require(proposal["format"] == FORMAT and
            proposal["source_fingerprint"] == fingerprint and
            proposal["story_sha256"] == digest(canonical(story)) and
            proposal["enrichment_sha256"] == digest(canonical(enrichment)) and
            proposal["base_blueprint_sha256"] == digest(canonical(blueprint)) and
            blueprint["source_fingerprint"] == fingerprint and
            provenance["source_fingerprint"] == fingerprint,
            "act_source_mismatch", "Act review is tied to another book or draft")
    review = proposal["editorial_review"]
    fields(review, {"user_confirmed", "transition_causality_reviewed",
                    "character_continuity_reviewed", "literary_canon_verified"},
           "multi-act reviewer declaration")
    require(review["user_confirmed"] is True and
            review["transition_causality_reviewed"] is True and
            review["character_continuity_reviewed"] is True and
            review["literary_canon_verified"] is False,
            "act_unreviewed", "Need explicit human review without false CANON claim")
    acts = proposal["acts"]
    require(type(acts) is list and 1 <= len(acts) <= 32, "invalid_act_count",
            "Expected 1..32 ordered reviewed acts")
    originals = blueprint["scenes"]
    source_origins = provenance["scene_origins"]
    require(type(originals) is list and type(source_origins) is list and
            len(originals) == len(source_origins) and all(
                s["id"] == o["scene_id"] for s, o in zip(originals, source_origins)),
            "act_base_mismatch", "Reviewed v3 base scenes/provenance disagree")
    registry = assertion_registry(analyses, index)
    anchors = {c["id"]: (s["id"], c["next_scene_id"])
               for s in originals for c in s["choices"]}
    origins = {o["scene_id"]: o for o in source_origins}
    scene_ids = {s["id"] for s in originals}
    choice_ids = set(anchors)
    event_ids, act_ids, used_claims, quote_hashes = set(), set(), set(), set()
    insertions = {}
    previous_start = previous_end = -1
    added = fork_count = stateful_count = conditional_count = 0
    summaries = []
    for act in acts:
        fields(act, {"id", "after_choice_id", "chapter_start", "chapter_end",
                     "entry_scene_id", "scenes"}, "reviewed act")
        act_id, anchor = act["id"], act["after_choice_id"]
        identifier(act_id, "act id")
        identifier(anchor, "act anchor choice")
        require(act_id not in act_ids and anchor in anchors and
                anchor not in insertions, "duplicate_act",
                "Act ID or original anchor is repeated, missing or replaced")
        act_ids.add(act_id)
        parent, target = anchors[anchor]
        lower, upper = origins[parent]["chapter_index"], origins[target]["chapter_index"]
        start, end = act["chapter_start"], act["chapter_end"]
        require(type(start) is int and type(end) is int and
                0 <= lower <= start <= end <= upper < index["chapter_count"] and
                start >= previous_start and end >= previous_end,
                "act_chronology", "Acts must stay in ascending original-book order")
        previous_start, previous_end = start, end
        raw_scenes = act["scenes"]
        require(type(raw_scenes) is list and 2 <= len(raw_scenes) <= 128,
                "invalid_act_scene_count", "Each act needs 2..128 reviewed events")
        entry = act["entry_scene_id"]
        identifier(entry, "act entry")
        checked_scenes, scene_data = {}, {}
        own_consequences = 0
        for raw in raw_scenes:
            fields(raw, {"id", "event_id", "title", "text", "chapter_index",
                         "origin", "assertion_ids", "choices"}, "act event")
            sid, event = raw["id"], raw["event_id"]
            identifier(sid, "act scene")
            identifier(event, "literary event")
            require(sid not in scene_ids and event not in event_ids,
                    "act_duplicate_event", "New scenes/events must have stable unique IDs")
            scene_ids.add(sid)
            event_ids.add(event)
            chapter = raw["chapter_index"]
            require(type(chapter) is int and start <= chapter <= end,
                    "act_chapter_invalid", "Scene is outside its declared act")
            string(raw["title"], "act title", 120)
            string(raw["text"], "act narrative", 6000)
            require(raw["origin"] in ("SOURCE_PASSAGE", "EXPLICIT_ADAPTATION"),
                    "act_bad_origin", "Mark original vs explicitly changed book scene")
            string_list(raw["assertion_ids"], "event assertions", 24)
            require(bool(raw["assertion_ids"]), "act_missing_quote",
                    "Each event must cite an independently indexed passage")
            for claim_id in raw["assertion_ids"]:
                identifier(claim_id, "act source assertion")
                require(claim_id in registry, "act_unknown_quote",
                        "Act references a quote outside the reviewed book")
                record = registry[claim_id]
                require(record["chunk"]["chapter_index"] <= chapter,
                        "act_future_quote", "Act cites an unrevealed future chapter")
                if raw["origin"] == "SOURCE_PASSAGE":
                    require(record["assertion"]["kind"] == "NARRATED",
                            "act_reported_as_truth",
                            "Do not treat reported speech or inference as an established event")
                quote_sha = digest(record["assertion"]["quote"].encode("utf-8"))
                require(claim_id not in used_claims and quote_sha not in quote_hashes,
                        "act_reused_quote",
                        "Different authored events cannot claim the same source passage")
                used_claims.add(claim_id)
                quote_hashes.add(quote_sha)
            choices = raw["choices"]
            require(type(choices) is list and 1 <= len(choices) <= 16,
                    "act_choice_count", "Nonterminal act scenes need 1..16 decisions")
            checked_choices = []
            for choice in choices:
                fields(choice, {"id", "label", "next_scene_id", "conditions",
                                "effects", "effect_assertion_ids"}, "reviewed act choice")
                cid = choice["id"]
                identifier(cid, "act choice")
                require(cid not in choice_ids, "act_duplicate_choice",
                        "Choices must be globally unique, including base story")
                choice_ids.add(cid)
                string(choice["label"], "act action", 300)
                destination = choice["next_scene_id"]
                require(destination == EXIT or
                        (type(destination) is str and len(destination) <= 64 and
                         not destination.startswith("@")),
                        "act_bad_destination", "Only local scenes or @exit allowed")
                conditions, effects = choice["conditions"], choice["effects"]
                require(type(conditions) is list and type(effects) is list and
                        len(conditions) <= 16 and len(effects) <= 16,
                        "act_rules_oversized", "Too many typed gameplay rules")
                for condition in conditions:
                    _check_rule(condition, blueprint, effect=False)
                for effect_rule in effects:
                    _check_rule(effect_rule, blueprint, effect=True)
                proof = choice["effect_assertion_ids"]
                require(type(proof) is list and len(proof) == len(effects),
                        "act_unwitnessed_effect", "Every effect needs one matching quote ID")
                for claim_id in proof:
                    identifier(claim_id, "effect source quote")
                    require(claim_id in raw["assertion_ids"], "act_unwitnessed_effect",
                            "Effect must cite an assertion present in its event")
                consumed = {e["id"] for e in effects if e["op"] == "consume_item"}
                gated = {c["id"] for c in conditions if c["op"] == "has_item"}
                require(consumed <= gated, "act_unguarded_item",
                        "Every consumed item must be checked in the same action")
                own_consequences += bool(effects)
                stateful_count += bool(effects)
                conditional_count += bool(conditions)
                checked_choices.append({
                    "id": cid, "label": choice["label"],
                    "next_scene_id": destination,
                    "conditions": deepcopy(conditions), "effects": deepcopy(effects),
                })
            checked_scenes[sid] = {
                "id": sid, "text": raw["text"], "terminal": False,
                "choices": checked_choices, "chapter_index": chapter,
            }
            scene_data[sid] = raw
        require(entry in checked_scenes, "act_missing_entry",
                "Act entry must name one of its own scenes")
        forks = _check_graph(checked_scenes, entry, upper)
        require(own_consequences >= 1, "act_no_consequence",
                "A reviewed act must change real game state, not merely add text")
        witnessed = {raw["chapter_index"] for raw in raw_scenes
                     if raw["origin"] == "SOURCE_PASSAGE"}
        require(all(ch in witnessed for ch in range(start, end + 1)),
                "act_uncovered_chapter", "Every chapter in the act needs a source event")
        fork_count += forks
        added += len(raw_scenes)
        require(len(originals) + added <= 1024, "act_scene_limit",
                "Exceeded native Dart v4 world scene limit")
        insertions[anchor] = {
            "entry": entry, "scenes": checked_scenes, "raw": scene_data,
        }
        summaries.append({"act_id": act_id, "chapter_start": start,
                          "chapter_end": end, "new_scenes": len(raw_scenes),
                          "branching_scenes": forks,
                          "stateful_choices": own_consequences})
    bp, prov = deepcopy(blueprint), deepcopy(provenance)
    old_scenes, old_origins = bp["scenes"], prov["scene_origins"]
    bp["scenes"], prov["scene_origins"] = [], []
    names = prov["presentation"]["scene_names"]
    for old_scene, origin in zip(old_scenes, old_origins):
        bp["scenes"].append(old_scene)
        prov["scene_origins"].append(origin)
        for original_choice in old_scene["choices"]:
            act = insertions.get(original_choice["id"])
            if act is None:
                continue
            destination = original_choice["next_scene_id"]
            original_choice["next_scene_id"] = act["entry"]
            for sid, item in act["scenes"].items():
                scene = deepcopy(item)
                del scene["chapter_index"]
                for transition in scene["choices"]:
                    if transition["next_scene_id"] == EXIT:
                        transition["next_scene_id"] = destination
                bp["scenes"].append(scene)
                raw_scene = act["raw"][sid]
                prov["scene_origins"].append(_origin(raw_scene, registry, fingerprint))
                names[sid] = raw_scene["title"]
    initial = _initial_review(proposal["initial_state"], bp,
                              prov["scene_origins"], registry, fingerprint)
    if initial is not None:
        prov["initial_state_review"] = initial
    proposal_sha = digest(canonical(proposal))
    bp["book_id"] = "acts_" + digest(canonical({
        "original": digest(canonical(blueprint)), "proposal": proposal_sha}))[:32]
    prov["bookworld_id"] = bp["book_id"]
    prov["intermediate_draft_sha256"] = digest(canonical({
        "previous_review": provenance["intermediate_draft_sha256"],
        "act_review_sha256": proposal_sha,
    }))
    present_chapters = {origin["chapter_index"] for origin in prov["scene_origins"]
                        if origin["origin"] == "SOURCE_PASSAGE" and origin["source_refs"]}
    return bp, prov, {
        "status": "V4_MULTI_ACT_PREFLIGHT_REQUIRES_NATIVE_AND_LITERARY_REVIEW",
        "format_version": 4, "source_fingerprint": fingerprint,
        "act_count": len(acts), "acts": summaries,
        "base_scenes": len(originals), "added_scenes": added,
        "total_scenes": len(bp["scenes"]),
        "distinct_source_quotes": len(quote_hashes),
        "distinct_source_events": len(event_ids),
        "branching_scenes": fork_count,
        "stateful_choices": stateful_count,
        "conditional_choices": conditional_count,
        "chapters_without_source_scenes": [
            i for i in range(index["chapter_count"]) if i not in present_chapters],
        "native_causality_verified": False, "npc_social_grants_authored": False,
        "literary_canon_verified": False, "semantic_review_completed": False,
        "device_playtest_completed": False,
    }


def extend_checked_world(blueprint, provenance, story, enrichment, index,
                         analyses, extension):
    """Explicit v1/v2 dispatch; unknown formats fail, no hidden migrations."""
    require(type(extension) is dict, "invalid_extension", "Extension must be JSON")
    if extension.get("format") == FORMAT:
        return extend_reviewed_acts(blueprint, provenance, story, enrichment,
                                    index, analyses, extension)
    from .v4_expansion import FORMAT as BRIDGE, extend_reviewed_world
    require(extension.get("format") == BRIDGE, "invalid_extension",
            "Explicit v4 extension format must be recognized and versioned")
    return extend_reviewed_world(blueprint, provenance, story, enrichment,
                                 index, analyses, extension)
