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


if __name__ == "__main__":
    unittest.main()
