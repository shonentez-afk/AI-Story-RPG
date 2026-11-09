"""Source-locked v4 scene batches and explicitly reviewed initial state.

The v3 project/analyses remain immutable. Additional source-witnessed
bridge scenes have no executable effects; the actual Dart v4 compiler and
importer remain authoritative for all game states and causal transitions.
"""
from __future__ import annotations

from copy import deepcopy

from .common import canonical, digest, fields, identifier, require, string, string_list
from .legacy_package import _source_ref
from .validate import assertion_registry

FORMAT = "rpg_author_v4_extension_v1"
INITIAL_FORMAT = "ai_story_private_initial_state_review_v1"


def _origin(scene, registry, fingerprint):
    claims, refs = [], []
    for aid in scene["assertion_ids"]:
        entry = registry[aid]
        claim, chunk = entry["assertion"], entry["chunk"]
        key = canonical({"source_fingerprint": fingerprint,
                         "chunk_id": chunk["id"], "assertion_id": aid})
        claims.append(digest(b"claim:" + key)[:32])
        refs.append(_source_ref(scene, claim, chunk, fingerprint))
    require(len(set(claims)) == len(claims) and
            len({r["id"] for r in refs}) == len(refs),
            "duplicate_citation", "Colliding expanded source references")
    return {"scene_id": scene["id"], "chapter_index": scene["chapter_index"],
            "origin": scene["origin"], "assertion_ids": claims, "source_refs": refs}


def _initial_review(raw, blueprint, origins, registry, fingerprint):
    if raw is None:
        return None
    fields(raw, {"tick", "items", "facts"}, "v4 initial state")
    tick, items, facts = raw["tick"], raw["items"], raw["facts"]
    require(type(tick) is int and 0 <= tick <= 100000000,
            "invalid_initial_tick", "Initial tick is outside native v4 limits")
    require(type(items) is list and type(facts) is list and
            len(items) <= 96 and len(facts) <= 128 and bool(items or facts or tick),
            "invalid_initial_grants", "Initial review is empty or oversized")
    available = {q["quote_sha256"] for o in origins
                 if o["origin"] == "SOURCE_PASSAGE" and o["chapter_index"] == 0
                 for q in o["source_refs"]
                 if q["chapter_index"] == 0 and q["visible_after_chapter"] == 0}
    def witnessed(aid):
        identifier(aid, "initial source assertion")
        require(aid in registry and registry[aid]["chunk"]["chapter_index"] == 0,
                "initial_future_evidence", "Initial grants require chapter-zero evidence")
        sha = digest(registry[aid]["assertion"]["quote"].encode("utf-8"))
        require(sha in available, "initial_unwitnessed_evidence",
                "Grant citation must already be witnessed by a source passage at the opening")
        return sha
    initial = blueprint["initial_state"]
    require(initial["tick"] == 0 and not initial["inventory"] and
            not any(initial["knowledge"].values()), "already_initialized",
            "Refuse replacing an already reviewed initial state")
    item_ids, item_reviews = set(), []
    for grant in items:
        fields(grant, {"item_id", "assertion_id"}, "initial item")
        key = grant["item_id"]
        identifier(key, "initial item")
        require(key in blueprint["items"] and key not in item_ids,
                "unknown_initial_item", "Unknown or duplicate item grant")
        item_ids.add(key)
        item_reviews.append({"item_id": key,
                             "source_quote_sha256": witnessed(grant["assertion_id"])})
    pairs, fact_reviews = set(), []
    for grant in facts:
        fields(grant, {"actor_id", "fact_id", "assertion_id"}, "initial fact")
        actor, key = grant["actor_id"], grant["fact_id"]
        identifier(actor, "initial actor")
        identifier(key, "initial fact")
        require(actor in blueprint["actors"] and key in blueprint["facts"] and
                (actor, key) not in pairs,
                "unknown_initial_fact", "Unknown or duplicate actor knowledge")
        pairs.add((actor, key))
        fact_reviews.append({"actor_id": actor, "fact_id": key,
                             "source_quote_sha256": witnessed(grant["assertion_id"])})
    initial["tick"] = tick
    initial["inventory"] = sorted(item_ids)
    for actor, fact in sorted(pairs):
        initial["knowledge"][actor].append(fact)
    for actor in initial["knowledge"]:
        initial["knowledge"][actor].sort()
    return {"format": INITIAL_FORMAT, "source_fingerprint": fingerprint,
            "review_scope": "user_declared_private_game_fiction",
            "user_confirmed": True, "literary_canon_verified": False,
            "initial_tick": tick, "item_grants": item_reviews,
            "fact_grants": fact_reviews}


def extend_reviewed_world(blueprint, provenance, story, enrichment,
                          index, analyses, extension):
    """Convert an explicitly reviewed batch to native inputs, never a CANON claim."""
    fields(extension, {"format", "source_fingerprint", "story_sha256",
                       "enrichment_sha256", "base_blueprint_sha256",
                       "editorial_review", "insertions", "initial_state"},
           "v4 extension")
    fingerprint = index["source_fingerprint"]
    require(extension["format"] == FORMAT and
            extension["source_fingerprint"] == fingerprint and
            extension["story_sha256"] == digest(canonical(story)) and
            extension["enrichment_sha256"] == digest(canonical(enrichment)) and
            extension["base_blueprint_sha256"] == digest(canonical(blueprint)) and
            blueprint["source_fingerprint"] == fingerprint and
            provenance["source_fingerprint"] == fingerprint,
            "extension_mismatch", "Extension targets another book or authoring revision")
    editorial = extension["editorial_review"]
    fields(editorial, {"user_confirmed", "transition_causality_reviewed",
                       "literary_canon_verified"}, "editorial approval")
    require(editorial["user_confirmed"] is True and
            editorial["transition_causality_reviewed"] is True and
            editorial["literary_canon_verified"] is False,
            "extension_not_reviewed", "Require explicit review, not a false CANON label")
    groups = extension["insertions"]
    require(type(groups) is list and len(groups) <= 64 and
            (bool(groups) or extension["initial_state"] is not None),
            "invalid_extension_batches", "Missing or oversized v4 scene batches")
    registry = assertion_registry(analyses, index)
    base_scenes = blueprint["scenes"]
    base_origins = provenance["scene_origins"]
    require(len(base_scenes) == len(base_origins) and
            all(s["id"] == o["scene_id"] for s, o in zip(base_scenes, base_origins)),
            "base_provenance_mismatch", "Accepted base scene and source orders differ")
    scene_ids = {s["id"] for s in base_scenes}
    choice_ids = {c["id"] for s in base_scenes for c in s["choices"]}
    origins = {o["scene_id"]: o for o in base_origins}
    anchors = {c["id"]: (s["id"], c["next_scene_id"])
               for s in base_scenes for c in s["choices"]}
    batches, added = {}, 0
    for group in groups:
        fields(group, {"after_choice_id", "scenes"}, "scene insertion")
        anchor = group["after_choice_id"]
        identifier(anchor, "original choice")
        require(anchor in anchors and anchor not in batches,
                "invalid_extension_anchor", "Unknown or repeated anchor choice")
        insertions = group["scenes"]
        require(type(insertions) is list and 1 <= len(insertions) <= 1000,
                "invalid_extension_batch_size", "Scene batch is empty or oversized")
        parent, target = anchors[anchor]
        minimum, maximum = origins[parent]["chapter_index"], origins[target]["chapter_index"]
        require(minimum <= maximum, "nonmonotone_base_edge",
                "Cannot add scenes across a backward chapter transition")
        checked = []
        for raw in insertions:
            fields(raw, {"id", "title", "text", "chapter_index", "origin",
                         "assertion_ids", "choice_id", "choice_label"},
                   "reviewed v4 scene")
            sid, cid = raw["id"], raw["choice_id"]
            identifier(sid, "scene id")
            identifier(cid, "bridge choice id")
            require(sid not in scene_ids and cid not in choice_ids,
                    "duplicate_extension_id", "Scene or choice ID is already used")
            scene_ids.add(sid)
            choice_ids.add(cid)
            string(raw["text"], "scene text", 6000)
            string(raw["title"], "scene title", 120)
            string(raw["choice_label"], "next scene action", 300)
            chapter = raw["chapter_index"]
            require(type(chapter) is int and minimum <= chapter <= maximum and
                    (not checked or checked[-1]["chapter_index"] <= chapter),
                    "extension_chapter_order", "Scene sequence violates act chronology")
            require(raw["origin"] in ("SOURCE_PASSAGE", "EXPLICIT_ADAPTATION"),
                    "extension_origin", "Label source passage vs invented adaptation")
            string_list(raw["assertion_ids"], "source assertions", 24)
            require(bool(raw["assertion_ids"]),
                    "extension_evidence_missing", "Every new scene needs exact citations")
            for aid in raw["assertion_ids"]:
                identifier(aid, "source assertion")
                require(aid in registry, "extension_unknown_assertion", "Unknown citation")
                require(registry[aid]["chunk"]["chapter_index"] <= chapter,
                        "extension_future_quote", "New scene cites a later chapter")
            checked.append(raw)
        batches[anchor] = checked
        added += len(checked)
        require(len(base_scenes) + added <= 1024,
                "extended_scene_count", "Native private v4 supports up to 1024 scenes")

    bp, prov = deepcopy(blueprint), deepcopy(provenance)
    old_scenes, old_origins = bp["scenes"], prov["scene_origins"]
    bp["scenes"], prov["scene_origins"] = [], []
    titles = prov["presentation"]["scene_names"]
    for scene, origin in zip(old_scenes, old_origins):
        bp["scenes"].append(scene)
        prov["scene_origins"].append(origin)
        for choice in scene["choices"]:
            batch = batches.get(choice["id"])
            if not batch:
                continue
            destination = choice["next_scene_id"]
            choice["next_scene_id"] = batch[0]["id"]
            for i, raw in enumerate(batch):
                nxt = batch[i + 1]["id"] if i + 1 < len(batch) else destination
                bp["scenes"].append({
                    "id": raw["id"], "text": raw["text"], "terminal": False,
                    "choices": [{"id": raw["choice_id"],
                                 "label": raw["choice_label"],
                                 "next_scene_id": nxt,
                                 "conditions": [], "effects": []}],
                })
                prov["scene_origins"].append(_origin(raw, registry, fingerprint))
                titles[raw["id"]] = raw["title"]
    initial = _initial_review(extension["initial_state"], bp,
                              prov["scene_origins"], registry, fingerprint)
    if initial is not None:
        prov["initial_state_review"] = initial
    extension_hash = digest(canonical(extension))
    bp["book_id"] = "ext_" + digest(canonical({
        "base": digest(canonical(blueprint)), "extension": extension_hash}))[:32]
    prov["bookworld_id"] = bp["book_id"]
    prov["intermediate_draft_sha256"] = digest(canonical({
        "previous_review": provenance["intermediate_draft_sha256"],
        "v4_extension": extension_hash,
    }))
    covered = {o["chapter_index"] for o in prov["scene_origins"]
               if o["origin"] == "SOURCE_PASSAGE" and o["source_refs"]}
    return bp, prov, {
        "status": "V4_EDITORIAL_EXTENSION_PENDING_NATIVE_VERIFICATION",
        "format_version": 4,
        "source_fingerprint": fingerprint,
        "base_scenes": len(base_scenes),
        "added_scenes": added,
        "total_scenes": len(bp["scenes"]),
        "chapters_with_source_scenes": len(covered),
        "chapters_without_source_scenes": [
            i for i in range(index["chapter_count"]) if i not in covered],
        "initial_tick": bp["initial_state"]["tick"],
        "initial_items": len(bp["initial_state"]["inventory"]),
        "initial_facts": sum(len(v) for v in bp["initial_state"]["knowledge"].values()),
        "native_causality_verified": False,
        "literary_canon_verified": False,
        "device_playtest_completed": False,
    }
