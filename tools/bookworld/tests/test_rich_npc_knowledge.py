"""Cross-language contract: reviewed per-NPC facts in a private rich-v3 world.

The quoted source is only a human-reviewed witness, not literary proof that
the NPC said a particular line or held a certain belief.
"""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from tools.bookworld import private_rich_bookworld as rich
from tools.bookworld import bookworld as legacy


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "shared_schemas/fixtures/private_classic_sample.json"
NPC = "npc_" + "c" * 32
FACT = "npc_secret"


def reviewed_sample():
    raw = json.loads(BASE.read_text(encoding="utf-8"))
    bp, source, index = raw["blueprint"], raw["provenance"], raw["source_index"]
    bp["actors"] = ["player", NPC]
    bp["facts"] = [FACT]
    bp["initial_state"]["knowledge"][NPC] = []
    entry = bp["scenes"][0]
    entry["choices"][0]["effects"].append(
        {"op": "learn_fact", "id": FACT, "actor": NPC})
    entry["choices"][1]["conditions"].append(
        {"op": "knows_fact", "id": FACT, "actor": NPC})
    source["format"] = "ai_story_private_provenance_v2"
    source["model_provenance"] = {
        "provider": "none", "model_id": None,
        "model_id_status": "not_applicable",
        "tool": "none", "method": "local_fixture",
    }
    source["presentation"] = {
        "hero": {
            "name": "Игрок",
            "description": "Герой в частной проверке фактов персонажа.",
        },
        "item_names": {}, "item_descriptions": {}, "stat_names": {},
        "fact_names": {FACT: "Секрет, переданный стражу"},
        "scene_names": {
            "entry": "Начало", "canon_end": "Помощь",
            "alternate_end": "Уход",
        },
    }
    quote = source["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    source["npc_knowledge"] = {
        "format": rich.NPC_GRANTS_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "user_confirmed": True,
        "literary_canon_verified": False,
        "grants": [
            {
                "scene_id": "entry", "choice_id": "wait",
                "actor_id": NPC, "fact_id": FACT,
                "source_quote_sha256": quote,
            },
        ],
    }
    return bp, source, index


class RichNpcKnowledgeContractTests(unittest.TestCase):
    def test_python_writer_and_reader_agree(self):
        bp, prov, index = reviewed_sample()
        archive = rich.build(bp, prov, index)
        result = rich.verify(archive)
        self.assertEqual(result["format_version"], 3)
        self.assertEqual(result["scene_count"], 3)
        self.assertEqual(rich.build(bp, prov, index), archive)

    def test_rejects_future_secret_wrong_actor_and_fake_quote(self):
        for mutation in ("missing_review", "missing_grant",
                         "changed_quote", "wrong_actor",
                         "unreviewed_second_fact", "wrong_marker"):
            with self.subTest(mutation=mutation):
                bp, prov, index = reviewed_sample()
                review = prov["npc_knowledge"]
                if mutation == "missing_review":
                    del prov["npc_knowledge"]
                elif mutation == "missing_grant":
                    review["grants"].clear()
                elif mutation == "changed_quote":
                    review["grants"][0]["source_quote_sha256"] = "f" * 64
                elif mutation == "wrong_actor":
                    review["grants"][0]["actor_id"] = "player"
                elif mutation == "unreviewed_second_fact":
                    bp["scenes"][0]["choices"][2]["effects"].append(
                        {"op": "learn_fact", "id": FACT, "actor": NPC})
                elif mutation == "wrong_marker":
                    review["format"] = "ai_story_npc_knowledge_unknown_v9"
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_reviewed_speaker_turns_hide_future_npc_knowledge(self):
        bp, prov, index = reviewed_sample()
        text = ("Встреча у ворот.\n"
                "Мария: «Мне известен секрет!»\n"
                "Игрок: «Я слушаю».")
        bp["scenes"][0]["text"] = text
        signed = rich._exact_scene_dialogue(text)
        self.assertEqual(len(signed["turns"]), 3)
        prov["presentation"]["scene_dialogues"] = {"entry": signed}
        prov["presentation"]["scene_dialogue_knowledge"] = {
            "entry": [
                {"turn_index": 1, "speaker": "Мария", "actor_id": NPC,
                 "required_fact_ids": [FACT]},
                {"turn_index": 2, "speaker": "Игрок", "actor_id": "player",
                 "required_fact_ids": []},
            ],
        }
        raw = rich.build(bp, prov, index)
        self.assertEqual(rich.verify(raw)["format_version"], 3)

        for mutation in ("no_review", "wrong_actor", "missing_turn",
                         "future_fact", "changed_speaker",
                         "unsigned_bypass"):
            with self.subTest(mutation=mutation):
                changed = deepcopy(prov)
                if mutation == "no_review":
                    del changed["presentation"]["scene_dialogue_knowledge"]
                elif mutation == "unsigned_bypass":
                    del changed["presentation"]["scene_dialogue_knowledge"]
                    del changed["presentation"]["scene_dialogues"]
                else:
                    rows = changed["presentation"]["scene_dialogue_knowledge"]["entry"]
                    if mutation == "wrong_actor":
                        rows[0]["actor_id"] = "npc_fake_name"
                    elif mutation == "missing_turn":
                        rows.pop()
                    elif mutation == "future_fact":
                        rows[0]["required_fact_ids"] = ["not_a_fact"]
                    elif mutation == "changed_speaker":
                        rows[0]["speaker"] = "Другое имя"
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, changed, index)

    def test_wrong_npc_identity_and_preknown_secret_fail(self):
        bp, prov, index = reviewed_sample()
        bp["actors"][1] = "npc_legacy_name"
        bp["initial_state"]["knowledge"]["npc_legacy_name"] = []
        del bp["initial_state"]["knowledge"][NPC]
        with self.assertRaises(legacy.BookworldError):
            rich.build(bp, prov, index)

        bp, prov, index = reviewed_sample()
        bp["initial_state"]["knowledge"][NPC] = [FACT]
        with self.assertRaises(legacy.BookworldError):
            rich.build(bp, prov, index)

    def test_deadlocked_knowledge_self_grant_is_not_a_playable_route(self):
        bp, prov, index = reviewed_sample()
        entry = bp["scenes"][0]
        entry["choices"][0]["effects"].clear()
        entry["choices"][1]["effects"].append(
            {"op": "learn_fact", "id": FACT, "actor": NPC})
        prov["npc_knowledge"]["grants"][0]["choice_id"] = "help"
        with self.assertRaises(legacy.BookworldError):
            rich.build(bp, prov, index)

    def test_old_player_only_rich_world_has_no_unreviewed_npc_marker(self):
        bp, prov, index = reviewed_sample()
        bp["actors"] = ["player"]
        bp["facts"] = []
        del bp["initial_state"]["knowledge"][NPC]
        bp["scenes"][0]["choices"][0]["effects"].clear()
        bp["scenes"][0]["choices"][1]["conditions"].clear()
        prov["presentation"]["fact_names"] = {}
        del prov["npc_knowledge"]
        self.assertEqual(rich.verify(rich.build(bp, prov, index))
                         ["format_version"], 3)


if __name__ == "__main__":
    unittest.main()
