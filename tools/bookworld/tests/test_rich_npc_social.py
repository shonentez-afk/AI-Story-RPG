"""Exact NPC scene presence + committed social actions in private rich-v3.

This synthetic test does NOT assert literary truth or actual GLM authoring.
"""
from copy import deepcopy
import unittest

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_rich_bookworld as rich
from tools.bookworld.tests.test_rich_npc_knowledge import NPC, reviewed_sample


def social_sample():
    bp, prov, index = reviewed_sample()
    quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    bp["scenes"][0]["text"] = (
        "Встреча у ворот.\n"
        "Мария: «Я услышала обещание!»\n"
        "Игрок: «Обещаю».")
    prov["presentation"]["scene_dialogues"] = {
        "entry": rich._exact_scene_dialogue(bp["scenes"][0]["text"]),
    }
    prov["presentation"]["scene_dialogue_knowledge"] = {
        "entry": [
            {
                "turn_index": 1, "speaker": "Мария", "actor_id": NPC,
                "required_fact_ids": [],
                "required_social_memory_id": "guard_observed_promise",
                "minimum_trust_to_player": 7,
            },
            {
                "turn_index": 2, "speaker": "Игрок", "actor_id": "player",
                "required_fact_ids": [],
            },
        ],
    }
    prov["npc_social"] = {
        "format": rich.NPC_SOCIAL_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "user_confirmed": True,
        "literary_canon_verified": False,
        "witnesses": [{
            "scene_id": "entry", "actor_id": NPC, "mode": "present",
            "source_quote_sha256": quote,
        }],
        "rules": [{
            "memory_id": "guard_observed_promise", "scene_id": "entry",
            "choice_id": "wait", "observer_id": NPC,
            "kind": "promiseReceived", "related_actor_id": "player",
            "relationship_delta": 7, "max_triggers": 1,
            "source_quote_sha256": quote,
        }],
    }
    return bp, prov, index


class RichNpcSocialTests(unittest.TestCase):
    def test_bounded_source_review_writer_verifier_old_format_parity(self):
        bp, prov, source = social_sample()
        archive = rich.build(bp, prov, source)
        self.assertEqual(rich.verify(archive)["format_version"], 3)
        self.assertEqual(archive, rich.build(bp, prov, source))

        del prov["npc_social"]
        for spoken in prov["presentation"]["scene_dialogue_knowledge"]["entry"]:
            spoken.pop("required_social_memory_id", None)
            spoken.pop("minimum_trust_to_player", None)
        previous = rich.build(bp, prov, source)
        self.assertEqual(rich.verify(previous)["format_version"], 3)

    def test_invalid_source_presence_actor_trust_or_unapproved_rules(self):
        variants = (
            "no_approval", "fake_quote", "wrong_scene", "unknown_actor",
            "missing_witness", "duplicate_witness", "reported_trust",
            "report_not_eye", "future_quote", "orphan_witness",
            "invalid_relation", "duplicate_rule", "unexpected_field",
        )
        for name in variants:
            with self.subTest(name=name):
                bp, prov, index = social_sample()
                social = prov["npc_social"]
                witness = social["witnesses"][0]
                rule = social["rules"][0]
                if name == "no_approval":
                    social["user_confirmed"] = False
                elif name == "fake_quote":
                    rule["source_quote_sha256"] = "f" * 64
                elif name == "wrong_scene":
                    witness["scene_id"] = "missing"
                elif name == "unknown_actor":
                    witness["actor_id"] = "npc_" + "d" * 32
                elif name == "missing_witness":
                    social["witnesses"].clear()
                elif name == "duplicate_witness":
                    social["witnesses"].append(deepcopy(witness))
                elif name == "reported_trust":
                    witness["mode"] = "reported"
                elif name == "report_not_eye":
                    witness["mode"] = "reported"
                    rule["kind"] = "betrayed"
                    rule["relationship_delta"] = 0
                elif name == "future_quote":
                    social["witnesses"][0]["source_quote_sha256"] = "f" * 64
                elif name == "orphan_witness":
                    social["rules"][0]["observer_id"] = "player"
                elif name == "invalid_relation":
                    rule["related_actor_id"] = NPC
                elif name == "duplicate_rule":
                    social["rules"].append(deepcopy(rule))
                elif name == "unexpected_field":
                    rule["fake_social_authority"] = True
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_spoiler_dialogue_requires_reviewed_memory_and_trust(self):
        for mutation in ("missing_social", "wrong_memory", "missing_actor",
                         "false_trust", "missing_review"):
            with self.subTest(mutation=mutation):
                bp, prov, index = social_sample()
                review = prov["presentation"]["scene_dialogue_knowledge"]
                turn = review["entry"][0]
                if mutation == "missing_social":
                    del prov["npc_social"]
                elif mutation == "wrong_memory":
                    turn["required_social_memory_id"] = "fake_memory"
                elif mutation == "missing_actor":
                    turn["actor_id"] = "player"
                elif mutation == "false_trust":
                    turn["minimum_trust_to_player"] = -100
                elif mutation == "missing_review":
                    del prov["presentation"]["scene_dialogue_knowledge"]
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_reported_rumor_cannot_grant_trust(self):
        bp, prov, index = social_sample()
        social = prov["npc_social"]
        social["witnesses"][0]["mode"] = "reported"
        social["rules"][0]["kind"] = "rumorHeard"
        social["rules"][0]["relationship_delta"] = 0
        social["rules"][0]["related_actor_id"] = None
        for spoken in prov["presentation"]["scene_dialogue_knowledge"]["entry"]:
            spoken.pop("minimum_trust_to_player", None)
        self.assertEqual(rich.verify(rich.build(bp, prov, index))
                         ["format_version"], 3)


if __name__ == "__main__":
    unittest.main()
