"""Original public synthetic three-chapter book with distinct source events.

Never use these fixture events as evidence of literary correctness for users'
private books. All book bytes and generated worlds live in temp directories.
"""
from tools.rpg_author.common import canonical, digest
from tools.rpg_author.source_adapter import make_index, parse_book
from tests.rpg_author.fixtures import choice, scene

PARAGRAPHS = [
    ["Лена нашла верёвку у дороги.", "Лена проверила узел на верёвке.",
     "Лена осмотрела тропу."],
    ["Лодочник предупредил о течении.", "Лена заметила разбитые доски моста.",
     "Мальчик позвал на помощь."],
    ["Лена вытянула мальчика на берег.", "Верёвка помогла у самого берега.",
     "Спасатели подошли к воде."],
]
SOURCE_FILENAME = "three_banks.fb2"
SOURCE = ('<?xml version="1.0" encoding="utf-8"?>'
          '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
          '<description><title-info><book-title>Три берега</book-title>'
          '</title-info></description><body>' +
          "".join("<section><p>" + " ".join(para) + "</p></section>"
                  for para in PARAGRAPHS) + "</body></FictionBook>")
ASSERTION_IDS = [
    ["road_found", "road_knot", "road_path"],
    ["bridge_warning", "bridge_damage", "bridge_call"],
    ["bank_rescue", "bank_rope", "bank_helpers"],
]


def index():
    return make_index(parse_book(SOURCE_FILENAME, SOURCE.encode("utf-8")))


def analyses(idx=None):
    idx = idx or index()
    assert len(idx["chunks"]) == 3, "Three physical book chapters required"
    result = []
    for chapter, chunk in enumerate(idx["chunks"]):
        assertions = []
        for sentence, aid in zip(PARAGRAPHS[chapter], ASSERTION_IDS[chapter]):
            start = chunk["text"].index(sentence)
            assertions.append({
                "id": aid,
                "statement": "Синтетическое авторское предложение из главы",
                "kind": "NARRATED",
                "start_utf16": chunk["start_utf16"] + start,
                "end_utf16": chunk["start_utf16"] + start + len(sentence),
                "quote": sentence,
            })
        result.append({
            "format": "rpg_author_chunk_analysis_v1",
            "source_fingerprint": idx["source_fingerprint"],
            "chunk_id": chunk["id"], "source_sha256": chunk["sha256_text"],
            "summary": "Оригинальный тестовый текст",
            "assertions": assertions, "unresolved": [],
        })
    return result


def story_plan(idx=None):
    idx = idx or index()
    scenes = [
        scene("road", "Лена нашла верёвку.", [
            choice("take_rope", "river", adds=["rope"]),
            choice("leave_rope", "river", removes=["rope"])],
              origin="SOURCE_PASSAGE", claims=["road_found"]),
        scene("river", "Лодочник рассказал о мосте.", [
            choice("rescue", "safe", requires=["rope"]),
            choice("call_help", "help", forbids=["rope"])],
              origin="SOURCE_PASSAGE", claims=["bridge_warning"]),
        scene("safe", "Мальчик спасён у берега.", origin="SOURCE_PASSAGE",
              claims=["bank_rescue"]),
        scene("help", "Позваны спасатели.", origin="EXPLICIT_ADAPTATION",
              claims=["bank_helpers"]),
    ]
    for item, chapter in zip(scenes, (0, 1, 2, 2)):
        item["chapter_index"] = chapter
    return {
        "format": "rpg_author_story_plan_v1",
        "source_fingerprint": idx["source_fingerprint"],
        "title": "Три берега: контрольный сюжет",
        "entry_scene_id": "road", "flags": ["rope"], "initial_flags": [],
        "scenes": scenes,
    }


def rich_enrichment(idx=None, plan=None):
    idx = idx or index()
    plan = plan or story_plan(idx)
    return {
        "format": "rpg_author_rich_enrichment_v1",
        "source_fingerprint": idx["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "hero": {"name": "Лена", "description": "Героиня синтетического рассказа."},
        "stats": {"courage": {"name": "Смелость", "initial": 1}},
        "items": {"rope": {"name": "Верёвка", "description": "Найдена у дороги."}},
        "facts": {"current": "Предупреждение о течении"},
        "scene_names": {"road": "Дорога", "river": "Мост",
                        "safe": "Спасение", "help": "Помощь"},
        "choices": {
            "take_rope": {"conditions": [],
                          "effects": [{"op": "grant_item", "id": "rope"}]},
            "rescue": {"conditions": [{"op": "has_item", "id": "rope"}],
                       "effects": [{"op": "consume_item", "id": "rope"}]},
            "call_help": {"conditions": [],
                          "effects": [{"op": "learn_fact", "id": "current",
                                       "actor": "player"}]},
        },
    }


def reviewed_acts(blueprint, idx=None, plan=None, overlay=None):
    from tools.rpg_author.v4_acts import FORMAT
    idx = idx or index()
    plan = plan or story_plan(idx)
    overlay = overlay or rich_enrichment(idx, plan)

    def event(sid, event_id, chapter, quote, options):
        return {
            "id": sid, "event_id": event_id,
            "title": sid,
            "text": "Уточнённое оригинальное событие синтетического рассказа.",
            "chapter_index": chapter, "origin": "SOURCE_PASSAGE",
            "assertion_ids": [quote], "choices": options,
        }

    def decision(cid, label, target, *, conditions=(), effects=(), refs=()):
        return {
            "id": cid, "label": label, "next_scene_id": target,
            "conditions": list(conditions), "effects": list(effects),
            "effect_assertion_ids": list(refs),
        }

    return {
        "format": FORMAT,
        "source_fingerprint": idx["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "enrichment_sha256": digest(canonical(overlay)),
        "base_blueprint_sha256": digest(canonical(blueprint)),
        "editorial_review": {
            "user_confirmed": True, "transition_causality_reviewed": True,
            "character_continuity_reviewed": True,
            "literary_canon_verified": False,
        },
        "acts": [
            {
                "id": "act_road", "after_choice_id": "take_rope",
                "chapter_start": 0, "chapter_end": 1,
                "entry_scene_id": "inspect_knot",
                "scenes": [
                    event("inspect_knot", "knot_event", 0, "road_knot", [
                        decision("study_bridge", "Узнать о течении", "study_current",
                                 effects=[{"op": "advance_time", "amount": 2}],
                                 refs=["road_knot"]),
                        decision("rush_on", "Поспешить", "@exit",
                                 effects=[{"op": "stat_delta", "id": "courage",
                                           "amount": 1}],
                                 refs=["road_knot"]),
                    ]),
                    event("study_current", "current_event", 1, "bridge_damage", [
                        decision("note_current", "Запомнить опасность", "@exit",
                                 effects=[{"op": "learn_fact", "id": "current",
                                           "actor": "player"}],
                                 refs=["bridge_damage"]),
                    ]),
                ],
            },
            {
                "id": "act_rescue", "after_choice_id": "rescue",
                "chapter_start": 1, "chapter_end": 2,
                "entry_scene_id": "rescue_decision",
                "scenes": [
                    event("rescue_decision", "help_event", 1, "bridge_call", [
                        decision("careful_route", "Учесть течение", "rope_rescue",
                                 conditions=[{"op": "knows_fact", "id": "current",
                                              "actor": "player"}],
                                 effects=[{"op": "advance_time", "amount": 1}],
                                 refs=["bridge_call"]),
                        decision("bold_route", "Быстрый путь", "@exit",
                                 effects=[{"op": "stat_delta", "id": "courage",
                                           "amount": 1}],
                                 refs=["bridge_call"]),
                    ]),
                    event("rope_rescue", "rope_event", 2, "bank_rope", [
                        decision("pull_up", "Помочь на берегу", "@exit",
                                 effects=[{"op": "stat_delta", "id": "courage",
                                           "amount": 1}],
                                 refs=["bank_rope"]),
                    ]),
                ],
            },
        ],
        "initial_state": None,
    }
