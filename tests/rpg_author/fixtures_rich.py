"""Small original fixture based on the already public E1 synthetic river story.

Never a claim that this proves semantic correctness for arbitrary literature.
The sample exercises literal source quotes, player state and two endings.
"""
from __future__ import annotations

from tools.rpg_author.common import canonical, digest
from tests.rpg_author.fixtures import source, story


def enrichment(index=None, plan=None):
    index = index or source()
    plan = plan or story(index)
    return {
        "format": "rpg_author_rich_enrichment_v1",
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "hero": {
            "name": "Лена",
            "description": "Путешественница, которая встречает мальчика у реки. "
                           "Снаряжение и поступки влияют на исход переправы.",
        },
        "stats": {
            "courage": {"name": "Смелость", "initial": 1},
            "insight": {"name": "Наблюдательность", "initial": 1},
        },
        "items": {
            "rope": {"name": "Верёвка",
                     "description": "Прочная верёвка, найденная у дороги."},
        },
        "facts": {"rescue_fact": "Мальчик спасён у реки"},
        "scene_names": {
            "road": "Дорога",
            "river": "У реки",
            "safe": "Спасение",
            "help": "Поиск помощи",
        },
        "choices": {
            "take_rope": {
                "conditions": [],
                "effects": [
                    {"op": "grant_item", "id": "rope"},
                    {"op": "stat_delta", "id": "courage", "amount": 1},
                ],
            },
            "leave_rope": {
                "conditions": [],
                "effects": [
                    {"op": "stat_delta", "id": "insight", "amount": 1},
                ],
            },
            "rescue": {
                "conditions": [{"op": "has_item", "id": "rope"}],
                "effects": [
                    {"op": "consume_item", "id": "rope"},
                    {"op": "learn_fact", "id": "rescue_fact", "actor": "player"},
                    {"op": "stat_delta", "id": "courage", "amount": 2},
                ],
            },
            "go_for_help": {"conditions": [], "effects": []},
        },
    }
