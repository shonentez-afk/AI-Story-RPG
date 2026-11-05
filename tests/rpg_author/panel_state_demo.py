"""Original synthetic BookWorld v1 demonstrating live Hero/Items/Journal tabs.

This is intentionally NOT an adaptation of a real book. Existing private v2
cannot encode items/stats; never silently upgrade or rewrite an older archive.
"""
from __future__ import annotations

import json
from pathlib import Path

from tools.bookworld import bookworld


def _effect(op, **extra):
    return {"op": op, **extra}


def _choice(id, label, next_id, conditions=(), effects=()):
    return {"id": id, "label": label, "next_scene_id": next_id,
            "conditions": list(conditions), "effects": list(effects)}


def _scene(id, text, choices=()):
    return {"id": id, "text": text, "terminal": not bool(choices),
            "choices": list(choices)}


def blueprint():
    """Original brief branching story; all item/stat/fact changes are real DSL."""
    return {
        "format": "ai_story_blueprint_v1", "schema_version": 1,
        "book_id": "panel_state_demo_v1",
        "title": "Переправа: испытание героя, предметов и журнала",
        "entry_scene_id": "crossroads",
        "rights_status": "original_demo",
        "source_fingerprint": None,
        "supported_modes": {
            "roles": ["PROTAGONIST"],
            "plots": ["CANON"],
            "interactions": ["CLASSIC"],
        },
        "items": ["lantern", "rope", "medal"],
        "facts": ["river_crossed", "child_thanks"],
        "actors": ["player"],
        "initial_state": {
            "scene_id": "crossroads", "revision": 0, "tick": 0,
            "stats": {"courage": 1, "insight": 1},
            "inventory": [], "flags": {"saved_child": False},
            "knowledge": {"player": []},
        },
        "scenes": [
            _scene("crossroads",
                "Вы — путник на дороге к старой башне. У обочины лежат "
                "фонарь и крепкая верёвка. Вы можете взять что-то одно.",
                [
                    _choice("take_lantern", "Взять фонарь", "river",
                            effects=[
                                _effect("grant_item", id="lantern"),
                                _effect("stat_delta", id="insight", amount=1),
                            ]),
                    _choice("take_rope", "Взять верёвку", "river",
                            effects=[
                                _effect("grant_item", id="rope"),
                                _effect("stat_delta", id="courage", amount=1),
                            ]),
                    _choice("take_nothing", "Идти без снаряжения", "river"),
                ]),
            _scene("river",
                "Река разлилась и скрыла переправу. Далеко за водой "
                "виднеется деревня. Нести вещи придётся самому.",
                [
                    _choice("use_lantern", "Осветить безопасный брод", "village",
                            conditions=[_effect("has_item", id="lantern")],
                            effects=[
                                _effect("learn_fact", id="river_crossed", actor="player"),
                                _effect("stat_delta", id="insight", amount=1),
                            ]),
                    _choice("use_rope", "Закрепить верёвку и перейти", "village",
                            conditions=[_effect("has_item", id="rope")],
                            effects=[
                                _effect("consume_item", id="rope"),
                                _effect("learn_fact", id="river_crossed", actor="player"),
                                _effect("stat_delta", id="courage", amount=1),
                            ]),
                    _choice("abandon_quest", "Вернуться назад", "end_away"),
                ]),
            _scene("village",
                "На окраине деревни ребёнок просит помощи. У ворот "
                "башни караульный принимает знак благодарности.",
                [
                    _choice("help_child", "Помочь ребёнку и получить медальон", "gate",
                            effects=[
                                _effect("grant_item", id="medal"),
                                _effect("learn_fact", id="child_thanks", actor="player"),
                                _effect("stat_delta", id="courage", amount=1),
                                _effect("set_flag", id="saved_child", value=True),
                            ]),
                    _choice("pass_child", "Не задерживаться", "gate"),
                ]),
            _scene("gate",
                "У входа в башню привратник спрашивает, почему вы "
                "пришли. Предметы и полученные сведения влияют на решения.",
                [
                    _choice("show_medal", "Отдать медальон привратнику", "end_saved",
                            conditions=[_effect("has_item", id="medal")],
                            effects=[
                                _effect("consume_item", id="medal"),
                                _effect("stat_delta", id="insight", amount=1),
                            ]),
                    _choice("tell_crossing", "Рассказать о найденном броде", "end_saved",
                            conditions=[_effect("knows_fact", id="river_crossed", actor="player")]),
                    _choice("walk_home", "Уйти домой", "end_away"),
                ]),
            _scene("end_saved",
                "Привратник впускает вас в башню. Вы прошли испытание. "
                "Оставшиеся предметы, характеристики и журнал сохраняются."),
            _scene("end_away",
                "Вы решили не продолжать путешествие. Журнал сохранит "
                "этот выбор, а найденные предметы останутся при вас."),
        ],
    }


def build() -> bytes:
    # A real ZIP/SQLite original-demo package via the unchanged compiler.
    data = bookworld.build(blueprint())
    result = bookworld.verify(data)
    assert result["format_version"] == 1
    return data


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite existing folder: {output}")
    output.mkdir(parents=True, mode=0o700)
    data = build()
    archive = output / "Panel_State_Demo_v1.bworld"
    archive.write_bytes(data)
    (output / "README_RU.txt").write_text(
        "ПРОВЕРКА ВКЛАДОК ГЕРОЙ / ПРЕДМЕТЫ / ЖУРНАЛ\n"
        "Это собственный короткий тестовый мир в формате original_demo v1.\n"
        "Он НЕ создан по «Королю-лягушонку» и НЕ заменяет приватный v2.\n"
        "Импортируйте .bworld в приложение как новый игровой мир.\n"
        "Маршрут 1: Взять фонарь -> Осветить брод -> Помочь ребёнку\n"
        "-> Отдать медальон. Проверяйте предметы и характеристики после\n"
        "каждого хода, затем журнал и перезапуск приложения.\n"
        "Маршрут 2: Взять верёвку -> Закрепить верёвку и перейти\n"
        "-> Помочь ребёнку -> Рассказать о найденном броде.\n"
        "После переправы верёвка должна исчезнуть: она израсходована.\n"
        "Журнал должен показывать ВСЕ реальные решения, включая выход.\n"
        "Известная граница v1: идентификаторы предметов показываются\n"
        "на английском (lantern/rope/medal); русские имена в будущем v3.\n"
        "Старые миры и сохранения не изменяются.\n",
        encoding="utf-8",
    )
    (output / "panel_demo_blueprint.json").write_text(
        json.dumps(blueprint(), ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(
        f"{bookworld.digest(data)}  {archive.name}\n", encoding="ascii")


if __name__ == "__main__":
    main()
