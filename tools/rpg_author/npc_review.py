"""E6f: source-bound, opt-in bridge to the EXISTING native NPC v1-v5 contract.

The author must supply a separately reviewed private JSON. We never infer
NPC identity, consent, witnesses, life state, custody, secrets or turns from
prose. The native Python rich writer and Dart importer remain authoritative.
"""
from __future__ import annotations

import json
import re

from tools.bookworld import private_rich_bookworld as rich
from .common import canonical, digest, fields, require

FORMAT = "rpg_author_reviewed_npc_overlay_v1"
ACTOR_RE = re.compile(r"npc_[0-9a-f]{32}\Z")
SOCIAL_FORMATS = frozenset((
    rich.NPC_SOCIAL_FORMAT, rich.NPC_SOCIAL_GATE_FORMAT,
    rich.NPC_SOCIAL_ITEM_FORMAT, rich.NPC_SOCIAL_AUTHOR_ITEM_FORMAT,
    rich.NPC_SOCIAL_LIFE_FORMAT,
))


def validate_review(review: dict, story: dict, index: dict,
                    enrichment: dict) -> list[str]:
    """Check independent source bindings, explicit approval and actor IDs."""
    fields(review, {"format", "source_fingerprint", "story_sha256",
                    "enrichment_sha256", "actors", "npc_knowledge",
                    "npc_social", "dialogue_knowledge"}, "reviewed NPC overlay")
    require(review["format"] == FORMAT and
            review["source_fingerprint"] == index["source_fingerprint"] and
            review["story_sha256"] == digest(canonical(story)) and
            review["enrichment_sha256"] == digest(canonical(enrichment)),
            "npc_review_stale", "NPC review belongs to another source, story or enrichment")
    actors = review["actors"]
    require(type(actors) is list and 1 <= len(actors) <= 15 and
            all(type(a) is str and ACTOR_RE.fullmatch(a) for a in actors) and
            len(set(actors)) == len(actors) and actors == sorted(actors),
            "npc_review_invalid", "NPCs need unique, sorted, persisted character_id values")
    knowledge, social = review["npc_knowledge"], review["npc_social"]
    require(type(knowledge) is dict and
            knowledge.get("format") == rich.NPC_GRANTS_FORMAT and
            knowledge.get("source_fingerprint") == index["source_fingerprint"] and
            knowledge.get("review_scope") == "user_declared_private_game_fiction" and
            knowledge.get("user_confirmed") is True and
            knowledge.get("literary_canon_verified") is False,
            "npc_review_unconfirmed", "NPC knowledge requires explicit private source review")
    require(type(social) is dict and
            social.get("format") in SOCIAL_FORMATS and
            social.get("source_fingerprint") == index["source_fingerprint"] and
            social.get("review_scope") == "user_declared_private_game_fiction" and
            social.get("user_confirmed") is True and
            social.get("literary_canon_verified") is False,
            "npc_review_unconfirmed", "NPC social v1-v5 requires explicit private source review")
    require(type(review["dialogue_knowledge"]) is dict,
            "npc_dialogue_review_missing", "Provide a complete per-scene speaker review")
    return actors


def add_review(blueprint: dict, presentation: dict, provenance: dict,
               review: dict) -> None:
    """Attach reviewed payload only after the exact blueprint is assembled.

    Main's native writer verifies every quote/actor/choice, every grant/effect,
    every witness/gate/transfer/life transition and every signed speaker turn.
    """
    require(set(blueprint["actors"]) == {"player", *review["actors"]},
            "npc_review_invalid", "NPC actor list and compiled blueprint disagree")
    dialogues = {}
    for scene in blueprint["scenes"]:
        signed = rich._exact_scene_dialogue(scene["text"])
        if signed is not None:
            dialogues[scene["id"]] = signed
    guards = review["dialogue_knowledge"]
    require(set(guards) == set(dialogues),
            "npc_dialogue_review_missing",
            "Every signed NPC dialogue scene needs its exact reviewed speaker list")
    if dialogues:
        presentation["scene_dialogues"] = dialogues
        presentation["scene_dialogue_knowledge"] = json.loads(canonical(guards))
    provenance["npc_knowledge"] = json.loads(canonical(review["npc_knowledge"]))
    provenance["npc_social"] = json.loads(canonical(review["npc_social"]))
