"""Bookwide, source-locked NPC identity and first-contact chronology.

An NPC first narrated in chapter 100 must become an actual StoryPlan anchor
at chapter 100 BEFORE the v4 act composer runs. Its immutable actor ID is
derived by the same verified native NPC adapter, not by a guessed model ID.

This is a *literary selection and verification* layer, NOT a second NPC game
engine or a claim that all named persons were discovered automatically.
Actual meetings, knowledge, social memory, item custody and redacted dialogue
are still executed solely by native rpg_api/BookWorld/SQLite.
"""
from __future__ import annotations

import re

from .common import canonical, digest, fields, identifier, require, string
from .validate import assertion_registry
from .npc_skill import prepare_npc_dossiers
from .long_book import outline_context, _supported

FORMAT = "rpg_author_long_npc_cast_v1"
MAX_MAJOR_NPCS = 15


def _named(name: str, text: str) -> bool:
    return re.search(r"(?<!\w)" + re.escape(name) + r"(?!\w)",
                     text, flags=re.IGNORECASE | re.UNICODE) is not None


def _first_source_chapter(name: str, index: dict) -> int | None:
    matches = [chunk["chapter_index"] for chunk in index["chunks"]
               if _named(name, chunk["text"])]
    return min(matches) if matches else None


def prepare_long_npc_cast(answer: dict, index: dict, analyses: list[dict],
                          outlines: list[dict]) -> dict:
    """Verify every selected major NPC against ORIGINAL source bytes.

    The identity MUST be first textually mentioned in its stated chapter,
    must have an exact narrated quote in a selected chapter outline, and may
    never be moved backwards by the story/act author. Missing/unnamed source
    persons remain an explicitly non-certified literary scope, not CANON.
    """
    _supported(index)
    fields(answer, {"characters", "absence_reason"}, "full-book NPC proposal")
    rows = answer["characters"]
    require(type(rows) is list and len(rows) <= MAX_MAJOR_NPCS,
            "long_npc_roster_overflow",
            "Only up to 15 significant, first-source-verified NPC identities "
            "can be enrolled in the pinned native BookWorld roster")
    reason = answer["absence_reason"]
    require((rows and reason is None) or
            (not rows and type(reason) is str and len(reason.strip()) >= 20),
            "long_npc_absence_unexplained",
            "Empty major NPC cast requires an explicit private literary reason")
    by_chapter = {c["chapter_index"]: c for c in
                  outline_context(outlines, index, analyses)}
    registry = assertion_registry(analyses, index)
    actors = []
    refs, ids, names = set(), set(), set()
    for row in rows:
        fields(row, {"ref", "name", "description", "first_chapter_index",
                     "identity_assertion_id"}, "source-major NPC identity")
        ref, name, aid = row["ref"], row["name"], row["identity_assertion_id"]
        identifier(ref, "permanent source NPC ref")
        identifier(aid, "original identity assertion id")
        string(name, "NPC source-attested display name", 120)
        string(row["description"], "NPC non-canon literary dossier", 1200)
        chapter = row["first_chapter_index"]
        require(type(chapter) is int and
                0 <= chapter < index["chapter_count"] and
                ref not in refs and name.casefold() not in names,
                "long_npc_duplicate_or_invalid_identity",
                "NPC references, names and chapter indices must be unique/valid")
        claim = registry.get(aid)
        require(claim is not None and
                claim["chunk"]["chapter_index"] == chapter and
                claim["assertion"]["kind"] == "NARRATED" and
                _named(name, claim["assertion"]["quote"]),
                "long_npc_identity_unproven",
                "NPC first contact must cite its exact original NARRATED "
                "passage containing the FULL character name")
        require(aid in {row["assertion_id"] for row in
                        by_chapter[chapter]["featured"]},
                "long_npc_identity_deferred",
                "Major NPC first encounter cannot use an event omitted from "
                "the reviewed playable chapter outline")
        earliest = _first_source_chapter(name, index)
        require(earliest == chapter,
                "long_npc_earlier_mention",
                "Named NPC already occurs in an earlier source chapter; "
                "move its first-contact anchor to the real earliest mention "
                "or revise the literary actor selection")
        actor = "npc_" + digest(canonical({
            "source_fingerprint": index["source_fingerprint"],
            "npc_ref": ref, "identity_assertion": aid,
        }))[:32]
        require(actor not in ids, "long_npc_duplicate_or_invalid_identity",
                "Source NPC actor identifiers collide")
        refs.add(ref)
        ids.add(actor)
        names.add(name.casefold())
        actors.append({
            "ref": ref, "name": name, "description": row["description"],
            "first_chapter_index": chapter,
            "identity_assertion_id": aid,
            "identity_quote_sha256":
                digest(claim["assertion"]["quote"].encode("utf-8")),
            "character_id": actor,
        })
    return {
        "format": FORMAT, "source_fingerprint": index["source_fingerprint"],
        "chapter_outlines_sha256": digest(canonical(outlines)),
        "characters": sorted(actors, key=lambda c: c["character_id"]),
        "absence_reason": reason,
        "all_named_book_characters_certified": False,
        "narrated_first_mentions_checked": True,
        "native_gameplay_not_yet_verified": True,
    }


def verify_long_npc_cast(record: dict, index: dict,
                         analyses: list[dict], outlines: list[dict]) -> dict:
    fields(record, {"format", "source_fingerprint",
                    "chapter_outlines_sha256", "characters", "absence_reason",
                    "all_named_book_characters_certified",
                    "narrated_first_mentions_checked",
                    "native_gameplay_not_yet_verified"},
           "private long-book NPC checkpoint")
    require(record["format"] == FORMAT and
            record["source_fingerprint"] == index["source_fingerprint"] and
            record["chapter_outlines_sha256"] == digest(canonical(outlines)),
            "long_npc_roster_stale", "NPC cast no longer matches private source")
    raw = {
        "characters": [{
            "ref": c["ref"], "name": c["name"],
            "description": c["description"],
            "first_chapter_index": c["first_chapter_index"],
            "identity_assertion_id": c["identity_assertion_id"],
        } for c in record["characters"]],
        "absence_reason": record["absence_reason"],
    }
    prepared = prepare_long_npc_cast(raw, index, analyses, outlines)
    require(canonical(prepared) == canonical(record),
            "long_npc_roster_stale",
            "Character ID, original quote or first-contact chapter changed")
    return prepared


def bind_long_npc_cast(cast: dict, story: dict, index: dict,
                       analyses: list[dict]) -> tuple[dict, dict]:
    """Bind full-book literary cast to REAL playable base scenes.

    Every first contact must have an original BASE scene, a matching chapter
    and exact assertion ID. The external Skill will supply social grants and
    witness reviews for these scenes; no NPC is magically born inside Python.
    """
    sources = [s for s in story["scenes"]
               if s["origin"] == "SOURCE_PASSAGE"]
    native = []
    bindings = []
    for record in cast["characters"]:
        chapter = record["first_chapter_index"]
        aid = record["identity_assertion_id"]
        anchors = [s for s in sources
                   if s["chapter_index"] == chapter and
                   aid in s["assertion_ids"] and not s["terminal"] and
                   s["choices"]]
        require(len(anchors) == 1,
                "long_npc_missing_first_contact_anchor",
                "A full-book major NPC needs ONE SOURCE_PASSAGE base "
                "contact scene, with a real choice and EXACT first-mention "
                "assertion, BEFORE any later v4 authored acts")
        # Prevent fictional or alternate scene prose from naming an NPC
        # before the first verified book mention.
        require(not any(s["chapter_index"] < chapter and
                        _named(record["name"], s["text"])
                        for s in story["scenes"]),
                "long_npc_early_spoiler",
                "StoryPlan reveals a character before the first confirmed "
                "source chapter")
        native.append({
            "ref": record["ref"], "name": record["name"],
            "description": record["description"],
            "source_scene_id": anchors[0]["id"],
            "assertion_id": aid,
        })
        bindings.append({
            "character_id": record["character_id"],
            "first_chapter_index": chapter,
            "source_scene_id": anchors[0]["id"],
            "identity_assertion_id": aid,
            "identity_quote_sha256": record["identity_quote_sha256"],
        })
    dossiers = prepare_npc_dossiers({
        "characters": native,
        "absence_reason": cast["absence_reason"],
    }, index, story, analyses)
    for a, b in zip(sorted(dossiers["characters"],
                            key=lambda x: x["character_id"]),
                    sorted(cast["characters"],
                           key=lambda x: x["character_id"])):
        require(a["character_id"] == b["character_id"] and
                a["identity_quote_sha256"] == b["identity_quote_sha256"],
                "long_npc_identity_changed",
                "Native dossier is not the original source-wide NPC identity")
    return dossiers, {
        "format": "rpg_author_long_npc_bound_anchors_v1",
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "cast_sha256": digest(canonical(cast)),
        "characters": sorted(bindings, key=lambda x: x["character_id"]),
        "first_contacts_source_reviewed": True,
        "native_playthrough_not_yet_verified": True,
    }


def check_native_long_npc_continuity(cast: dict, bound: dict,
                                      blueprint: dict, provenance: dict) -> dict:
    """Read-only audit of actual native v4 NPC provenance and causal history.

    Do not claim the WHOLE literary cast. Require every selected NPC to have
    a first-source witness, a typed knowledge grant and no early named scene
    or NPC effect. Actor identity is not introduced by v4 acts or Python.
    """
    actors = {a["character_id"] for a in cast["characters"]}
    require(set(blueprint["actors"]) == {"player", *actors},
            "long_npc_native_actor_mismatch",
            "Native BookWorld lost or invented permanent NPC actor identities")
    origins = {o["scene_id"]: o for o in provenance["scene_origins"]}
    require(len(origins) == len(blueprint["scenes"]),
            "long_npc_native_provenance_invalid", "Native scene origins missing")
    social = provenance.get("npc_social", {})
    knowledge = provenance.get("npc_knowledge", {})
    witnesses = social.get("witnesses", [])
    grants = knowledge.get("grants", [])
    if actors:
        require(type(witnesses) is list and type(grants) is list,
                "long_npc_native_review_missing",
                "The native NPC social/knowledge review is missing")
    by_actor = {c["character_id"]: c for c in cast["characters"]}
    by_anchor = {c["character_id"]: c for c in bound["characters"]}
    def event_after(actor: str, scene_id: str) -> bool:
        origin = origins.get(scene_id)
        return origin is not None and type(origin.get("chapter_index")) is int and (
            origin["chapter_index"] >= by_actor[actor]["first_chapter_index"])

    for actor in actors:
        source = by_actor[actor]
        intro = by_anchor[actor]
        require(any(w.get("scene_id") == intro["source_scene_id"] and
                    w.get("actor_id") == actor and
                    w.get("mode") == "present" and
                    w.get("source_quote_sha256") == source["identity_quote_sha256"]
                    for w in witnesses),
                "long_npc_native_first_witness_missing",
                "Actual base NPC social contract must attest the FIRST "
                "encounter with the named character and exact quote")
        require(any(g.get("actor_id") == actor and
                    event_after(actor, g.get("scene_id"))
                    for g in grants),
                "long_npc_native_knowledge_missing",
                "A selected major NPC must receive a real, source-reviewed "
                "native knowledge grant at or after first contact")
        for row in witnesses:
            if row.get("actor_id") == actor:
                require(event_after(actor, row.get("scene_id")),
                        "long_npc_future_presence",
                        "An NPC witness precedes its verified first contact")
        for rows, fields_in_row in [
            (grants, ("actor_id",)),
            (social.get("rules", []),
             ("observer_id", "related_actor_id")),
            (social.get("choice_gates", []), ("actor_id",)),
            (social.get("life_transitions", []), ("actor_id",)),
            (social.get("item_transfers", []),
             ("from_actor_id", "to_actor_id")),
        ]:
            for row in rows:
                if actor in (row.get(k) for k in fields_in_row):
                    require(event_after(actor, row.get("scene_id")),
                            "long_npc_premature_social_history",
                            "NPC knowledge, memory, trust or custody was "
                            "recorded before the signed original first contact")
        for scene in blueprint["scenes"]:
            origin = origins.get(scene["id"])
            if origin is not None and (origin["chapter_index"] <
                    source["first_chapter_index"]):
                require(not _named(source["name"], scene["text"]),
                        "long_npc_compiled_early_spoiler",
                        "Compiled narrative reveals this NPC before the first "
                        "verified source mention")
    later = {
        actor: sum(1 for w in witnesses if w.get("actor_id") == actor and
                   origins[w["scene_id"]]["chapter_index"] >
                   by_actor[actor]["first_chapter_index"])
        for actor in actors
    }
    return {
        "format": "rpg_author_long_npc_native_continuity_v1",
        "source_fingerprint": cast["source_fingerprint"],
        "native_blueprint_sha256": digest(canonical(blueprint)),
        "reviewed_npc_count": len(actors),
        "first_source_witnessed_npc_count": len(actors),
        "later_source_witness_counts": dict(sorted(later.items())),
        "all_important_npcs_in_book_certified": False,
        "source_first_contact_gameplay_checked": True,
        "no_premature_npc_history": True,
        "automatic_literary_canon_attested": False,
    }
