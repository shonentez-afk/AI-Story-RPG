"""Small deterministic rich-v3 runtime fixture, independent of RPG author E6d.

Used only in Flutter integration CI to check real inventory, hero, journal,
source-bound v3 ZIP, SQLite and replay. Not a literary adaptation, model
response, E6d generator, or replacement for cross-project compatibility tests.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path

from tools.bookworld import private_rich_bookworld as rich


_ROOT = Path(__file__).resolve().parents[2]
_SOURCE = _ROOT / "shared_schemas/fixtures/private_classic_sample.json"


def build_runtime_fixture() -> bytes:
    base = json.loads(_SOURCE.read_text(encoding="utf-8"))
    bp = deepcopy(base["blueprint"])
    prov = deepcopy(base["provenance"])
    index = base["source_index"]
    bp["book_id"] = "rich_ci_runtime_river"
    bp["entry_scene_id"] = "road"
    bp["items"] = ["rope"]
    bp["facts"] = ["rescue_fact"]
    bp["initial_state"] = {
        "scene_id": "road", "revision": 0, "tick": 0,
        "stats": {"courage": 1, "insight": 1},
        "inventory": [], "flags": {"helped": False},
        "knowledge": {"player": []},
    }

    def choice(name, label, dest, conditions=None, effects=None):
        return {
            "id": name, "label": label, "next_scene_id": dest,
            "conditions": conditions or [], "effects": effects or [],
        }

    bp["scenes"] = [
        {
            "id": "road",
            "text": "Лена вышла к дороге. Рядом лежала верёвка.",
            "terminal": False,
            "choices": [
                choice("take_rope", "Взять верёвку", "river",
                       effects=[{"op": "grant_item", "id": "rope"},
                                {"op": "stat_delta", "id": "courage",
                                 "amount": 1}]),
                choice("leave_rope", "Не брать верёвку", "river",
                       effects=[{"op": "stat_delta", "id": "insight",
                                 "amount": 1}]),
            ],
        },
        {
            "id": "river",
            "text": "У реки герой выбирает, как помочь мальчику.",
            "terminal": False,
            "choices": [
                choice("rescue", "Спасти мальчика", "safe",
                       conditions=[{"op": "has_item", "id": "rope"}],
                       effects=[{"op": "consume_item", "id": "rope"},
                                {"op": "learn_fact", "id": "rescue_fact",
                                 "actor": "player"},
                                {"op": "stat_delta", "id": "courage",
                                 "amount": 2}]),
                choice("go_for_help", "Искать помощь", "help"),
            ],
        },
        {
            "id": "safe", "text": "Мальчик спасён. Игра завершена.",
            "terminal": True, "choices": [],
        },
        {
            "id": "help", "text": "Лена отправилась за помощью.",
            "terminal": True, "choices": [],
        },
    ]
    origin = prov["scene_origins"]
    prov["format"] = "ai_story_private_provenance_v2"
    prov["bookworld_id"] = bp["book_id"]
    prov["model_provenance"] = {
        "provider": "none", "model_id": None,
        "model_id_status": "not_applicable",
        "tool": "none", "method": "local_fixture",
    }
    prov["scene_origins"] = [
        dict(deepcopy(origin[0]), scene_id="road"),
        dict(deepcopy(origin[1]), scene_id="river"),
        dict(deepcopy(origin[2]), scene_id="safe"),
        dict(deepcopy(origin[2]), scene_id="help"),
    ]
    prov["presentation"] = {
        "hero": {
            "name": "Лена",
            "description": "Путешественница в синтетическом тесте.",
        },
        "item_names": {"rope": "Верёвка"},
        "item_descriptions": {
            "rope": "Прочная верёвка у дороги, игровая выдумка."
        },
        "stat_names": {"courage": "Смелость", "insight": "Наблюдательность"},
        "fact_names": {"rescue_fact": "Мальчик спасён у реки"},
        "scene_names": {
            "road": "Дорога", "river": "У реки",
            "safe": "Спасение", "help": "Поиск помощи",
        },
    }
    data = rich.build(bp, prov, index)
    checked = rich.verify(data)
    if checked["format_version"] != 3 or checked["scene_count"] != 4:
        raise ValueError("Native rich-v3 fixture verification failed")
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dest = output / "River_Rich_Hero_v3.bworld"
    dest.write_bytes(build_runtime_fixture())


if __name__ == "__main__":
    main()
