"""Original synthetic 201-chapter book with a late NPC at chapter 100.

This has NO private user texts. ChatGPT is replaced ONLY in the test with
a transparent fake author; the BookWorld native Dart/SQLite path is real.
"""
from copy import deepcopy

from tests.rpg_author import long_book_fixture as plain

SOURCE_FILENAME = "original_201_late_npc.fb2"
SOURCE = plain.SOURCE.replace(
    "В главе номер 100 путница увидела отметку 100 и продолжила путь.",
    "Лодочник встретил путницу в главе номер 100 и показал дорогу."
).replace(
    "В главе номер 101 путница увидела отметку 101 и продолжила путь.",
    "Лодочник объяснил путнице значение отметки 101 у дороги."
).replace(
    "В главе номер 161 путница увидела отметку 161 и продолжила путь.",
    "Лодочник вспомнил о путнице возле отметки 161."
)

ANCHORS = (0, 80, 100, 160, 200)
FIRST_CHAPTER = 100
NAME = "Лодочник"
FACT_FIRST = "boatman_first_meeting"
FACT_LATER = "boatman_later_help"
MEMORY_BASE = "boatman_first_meeting_memory"
MEMORY_LATER = "boatman_cross_act_help_memory"


def late_story():
    plan = plain.backbone({"source_fingerprint": "unused"})
    for scene in plan["scenes"]:
        if scene["id"] == "chapter_080":
            scene["choices"] = [plain.choice("go_080_100", "chapter_100")]
    plan["scenes"].insert(2, {
        "id": "chapter_100", "chapter_index": FIRST_CHAPTER,
        "origin": "SOURCE_PASSAGE",
        "assertion_ids": [plain.aid(FIRST_CHAPTER)],
        "text": "Лодочник встретил путницу на дороге у отметки 100.",
        "terminal": False,
        "choices": [plain.choice("go_100_160", "chapter_160")],
    })
    plan.pop("source_fingerprint")
    return plan


def late_acts(actor):
    results = [plain._act(start, end, n)
               for n, (start, end) in enumerate(
                   zip(ANCHORS, ANCHORS[1:]))]
    post_contact = results[2]["scenes"][0]
    assert post_contact["id"] == "original_101"
    learned = next(c for c in post_contact["choices"]
                   if c["id"] == "choose_mark_101")
    learned["effects"].append({
        "op": "learn_fact", "actor": actor, "id": FACT_LATER,
    })
    learned["effect_assertion_ids"].append(plain.aid(101))
    return {
        "acts": results, "initial_state": None,
        "npc_actor_review": {
            "knowledge_grants": [{
                "scene_id": "original_101",
                "choice_id": "choose_mark_101",
                "actor_id": actor, "fact_id": FACT_LATER,
                "assertion_id": plain.aid(101),
            }],
            "witnesses": [{
                "scene_id": "original_101", "actor_id": actor,
                "mode": "present", "assertion_id": plain.aid(101),
            }],
            "memories": [{
                "scene_id": "original_101",
                "choice_id": "choose_mark_101",
                "observer_id": actor,
                "memory_id": MEMORY_LATER,
                "kind": "helped", "related_actor_id": "player",
                "relationship_delta": 2, "max_triggers": 1,
                "assertion_id": plain.aid(101),
            }],
            "choice_gates": [{
                "scene_id": "original_161",
                "choice_id": "choose_mark_161", "actor_id": actor,
                "required_memory_id": MEMORY_LATER,
                "minimum_trust_to_player": 2,
                "assertion_id": plain.aid(161),
            }],
            "life_transitions": [],
        },
    }


class FakeLateNpcAuthor(plain.FakeLongSourceLockedAuthor):
    """The synthetic provider proposes literary JSON; never invokes a model."""

    def __init__(self):
        super().__init__()
        self.actor_id = None

    def ask(self, stage, payload, feedback=""):
        if stage == "npc_cast":
            self.calls += 1
            self.stages.append(stage)
            return {
                "characters": [{
                    "ref": "boatman",
                    "name": NAME,
                    "description": "Свидетельствованный лодочник, впервые "
                                   "встреченный путницей в главе номер сто.",
                    "first_chapter_index": FIRST_CHAPTER,
                    "identity_assertion_id": plain.aid(FIRST_CHAPTER),
                }],
                "absence_reason": None,
            }
        if stage == "story":
            self.calls += 1
            self.stages.append(stage)
            assert payload["reviewed_major_npc_cast"][0][
                "first_chapter_index"] == FIRST_CHAPTER
            return late_story()
        if stage == "enrichment":
            response = super().ask(stage, payload, feedback)
            self.actor_id = payload["npc_dossiers"]["characters"][0][
                "character_id"]
            response["facts"] = {
                FACT_FIRST: "Лодочник знает, что путница встретила его.",
                FACT_LATER: "Лодочник помнит, как он помог ей позже.",
            }
            response["choices"]["go_100_160"] = {
                "conditions": [], "effects": [{
                    "op": "learn_fact", "id": FACT_FIRST,
                    "actor": self.actor_id,
                }],
            }
            return response
        if stage == "npc_review":
            self.calls += 1
            self.stages.append(stage)
            assert self.actor_id is not None
            return {
                "format": "rpg_author_skill_npc_review_v1",
                "knowledge_grants": [{
                    "scene_id": "chapter_100",
                    "choice_id": "go_100_160",
                    "actor_id": self.actor_id, "fact_id": FACT_FIRST,
                    "assertion_id": plain.aid(100),
                }],
                "witnesses": [{
                    "scene_id": "chapter_100",
                    "actor_id": self.actor_id,
                    "mode": "present", "assertion_id": plain.aid(100),
                }],
                "rules": [{
                    "scene_id": "chapter_100",
                    "choice_id": "go_100_160",
                    "observer_id": self.actor_id,
                    "memory_id": MEMORY_BASE,
                    "kind": "witnessed", "related_actor_id": "player",
                    "relationship_delta": 1, "max_triggers": 1,
                    "assertion_id": plain.aid(100),
                }],
                "choice_gates": [], "item_grants": [],
                "item_transfers": [],
                "life_transitions": [{
                    "scene_id": "chapter_100",
                    "choice_id": "go_100_160",
                    "actor_id": self.actor_id,
                    "next_state": "present",
                    "assertion_id": plain.aid(100),
                }],
                "dialogue_knowledge": {},
            }
        if stage == "extension":
            self.calls += 1
            self.stages.append(stage)
            assert self.actor_id is not None
            assert payload["long_book_backbone"][
                "missing_chapters_to_fill"] == 196
            return late_acts(self.actor_id)
        return super().ask(stage, payload, feedback)
