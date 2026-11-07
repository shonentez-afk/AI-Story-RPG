"""Independent private-v3 scene dialogue proof; no AI model or E6d dependency.

Narrator beats and named Russian speakers must be an exact projection of
the signed BookWorld scene body, not a second mutable NPC/script authority.
"""
from __future__ import annotations

import unittest

from tools.bookworld import private_rich_bookworld as rich


class RichDialogueProjectionTests(unittest.TestCase):
    def test_exact_named_speakers_and_narrator_are_not_literary_canon(self):
        text = (
            "Дверь открылась.\n"
            "Лена: «Что произошло?»\n"
            "Страж: «Я ничего не обещал».\n"
            "Рассказчик не подтверждает чужие знания."
        )
        projection = rich._exact_scene_dialogue(text)
        self.assertIsNotNone(projection)
        self.assertEqual(len(projection["scene_text_sha256"]), 64)
        self.assertEqual(
            projection["turns"],
            [
                {"speaker": None, "text": "Дверь открылась."},
                {"speaker": "Лена", "text": "Что произошло?"},
                {"speaker": "Страж", "text": "Я ничего не обещал"},
                {"speaker": None, "text": "Рассказчик не подтверждает чужие знания."},
            ],
        )

    def test_unattributed_and_single_speaker_never_invent_npc(self):
        self.assertIsNone(rich._exact_scene_dialogue(
            "— Кто говорит?\n— Неизвестно."))
        self.assertIsNone(rich._exact_scene_dialogue(
            "Лена: «Постой!»\nЛена: «Я вернусь.»"))
        self.assertIsNone(rich._exact_scene_dialogue("Совсем обычная сцена."))
        self.assertIsNone(rich._exact_scene_dialogue(
            "Лена: «Да»\nСтраж: «Нет»\n" + "Долго.\n" * 70))

    def test_signed_sha_and_order_are_stable_by_exact_scene_text(self):
        text = 'Лена: «Открой»\nСтраж: «Не могу»'
        a = rich._exact_scene_dialogue(text)
        b = rich._exact_scene_dialogue(text)
        self.assertEqual(a, b)
        self.assertNotEqual(
            a["scene_text_sha256"],
            rich._exact_scene_dialogue(
                'Лена: «Открой»\nСтраж: «Сейчас»')["scene_text_sha256"],
        )



    def test_source_bound_prior_choice_is_verified_not_inferred(self):
        import copy
        import json
        from pathlib import Path

        sample = json.loads((
            Path(__file__).resolve().parents[1] /
            "shared_schemas/fixtures/private_classic_sample.json"
        ).read_text(encoding="utf-8"))
        bp = sample["blueprint"]
        npc = "npc_" + "c" * 32
        bp["actors"].append(npc)
        bp["facts"].append("npc_secret")
        bp["initial_state"]["knowledge"][npc] = []
        for choice in bp["scenes"][0]["choices"]:
            if choice["id"] == "wait":
                choice["effects"].append({
                    "op": "learn_fact", "id": "npc_secret", "actor": npc
                })
        body = 'Мария: «Теперь знаю тайну.»\nИгрок: «Слушаю.»'
        bp["scenes"][1]["text"] = body
        first = sample["provenance"]["scene_origins"][0]
        quote = first["source_refs"][0]["quote_sha256"]
        meta = {
            "hero": {"name": "Игрок", "description": "Тест"},
            "item_names": {}, "item_descriptions": {},
            "stat_names": {}, "fact_names": {"npc_secret": "Тайна"},
            "scene_names": {
                "entry": "Двор", "canon_end": "Диалог",
                "alternate_end": "Отказ",
            },
            "scene_dialogues": {
                "canon_end": rich._exact_scene_dialogue(body),
            },
            "scene_dialogue_knowledge": {
                "canon_end": [
                    {
                        "turn_index": 0, "speaker": "Мария",
                        "actor_id": npc, "required_fact_ids": ["npc_secret"],
                        "required_prior_choice_id": "wait",
                        "source_quote_sha256": quote,
                        "private_fiction_confirmed": True,
                    },
                    {
                        "turn_index": 1, "speaker": "Игрок",
                        "actor_id": "player", "required_fact_ids": [],
                    },
                ],
            },
        }
        origins = sample["provenance"]["scene_origins"]
        rich._presentation(meta, bp, origins=origins)
        cases = [
            ("source_quote_sha256", "0" * 64),
            ("required_prior_choice_id", "leave"),
            ("required_prior_choice_id", "help"),
            ("private_fiction_confirmed", False),
        ]
        for key, value in cases:
            forged = copy.deepcopy(meta)
            forged["scene_dialogue_knowledge"]["canon_end"][0][key] = value
            with self.subTest(field=key, value=value):
                with self.assertRaises(Exception):
                    rich._presentation(forged, bp, origins=origins)
        missing_consent = copy.deepcopy(meta)
        del missing_consent["scene_dialogue_knowledge"]["canon_end"][0][
            "private_fiction_confirmed"]
        with self.assertRaises(Exception):
            rich._presentation(missing_consent, bp, origins=origins)

if __name__ == "__main__":
    unittest.main()
