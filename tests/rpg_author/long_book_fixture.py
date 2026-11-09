"""Original, wholly synthetic 201-chapter source; never a user's book.

Single end-to-end long novel fixture for the ORIGINAL native Dart engine.
All literary AI answers in this file are explicit test doubles.
"""
from copy import deepcopy

COUNT = 201
ANCHORS = (0, 80, 160, 200)
SOURCE_FILENAME = "long_201_original.fb2"
SOURCE = (
    '<?xml version="1.0" encoding="utf-8"?>'
    '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
    '<description><title-info><book-title>Синтетические пути: 201 глава'
    '</book-title></title-info></description><body>'
    + "".join(
        '<section><p>В главе номер %03d путница увидела отметку %03d '
        'и продолжила путь.</p></section>' % (i, i)
        for i in range(COUNT))
    + '</body></FictionBook>'
)


def aid(chapter):
    return "a_%05d_00" % chapter


def choice(cid, target):
    return {
        "id": cid, "label": "Продолжить путь: " + cid,
        "next_scene_id": target,
        "requires": [], "forbids": [], "adds": [], "removes": [],
    }


def backbone(index):
    sources = [
        {"id": "chapter_%03d" % ch, "chapter_index": ch,
         "origin": "SOURCE_PASSAGE", "assertion_ids": [aid(ch)],
         "text": "Из книги: в главе %03d отмечен путь." % ch,
         "terminal": ch == 200, "choices": (
             [choice("go_%03d_%03d" % (ch, ANCHORS[i + 1]),
                     "chapter_%03d" % ANCHORS[i + 1])]
             if i < len(ANCHORS) - 1 else []),
         }
        for i, ch in enumerate(ANCHORS)
    ]
    # A distinct terminal route is a correctly marked explicit adaptation.
    sources[2]["choices"].append(choice("alternative_ending", "other_end"))
    sources.append({
        "id": "other_end", "chapter_index": 200,
        "origin": "EXPLICIT_ADAPTATION", "assertion_ids": [aid(200)],
        "text": "Альтернативное завершение: путница выбрала иную дорогу.",
        "terminal": True, "choices": [],
    })
    return {
        "format": "rpg_author_story_plan_v1",
        "source_fingerprint": index["source_fingerprint"],
        "title": "Синтетическая RPG из 201 главы",
        "entry_scene_id": "chapter_000",
        "flags": ["branch_mark"], "initial_flags": [],
        "scenes": sources,
    }


def _act(after, before, after_id):
    scenes = []
    for chapter in range(after + 1, before):
        sid = "original_%03d" % chapter
        nxt = "original_%03d" % (chapter + 1) if chapter + 1 < before else "@exit"
        item = {
            "id": sid, "event_id": "event_%03d" % chapter,
            "title": "Глава %d" % chapter,
            "text": "Из книги: путница изучает отметку из главы %d." % chapter,
            "chapter_index": chapter, "origin": "SOURCE_PASSAGE",
            "assertion_ids": [aid(chapter)],
            "choices": [{
                "id": "continue_%03d" % chapter,
                "label": "Продолжить исходный путь",
                "next_scene_id": nxt,
                "conditions": [], "effects": [],
                "effect_assertion_ids": [],
            }],
        }
        if chapter == after + 1:
            item["choices"] = [
                {
                    "id": "choose_mark_%03d" % chapter,
                    "label": "Запомнить развилку",
                    "next_scene_id": nxt,
                    "conditions": [],
                    "effects": [{"op": "set_flag", "id": "branch_mark",
                                 "value": True}],
                    "effect_assertion_ids": [aid(chapter)],
                },
                {
                    "id": "choose_no_mark_%03d" % chapter,
                    "label": "Не запоминать развилку",
                    "next_scene_id": nxt,
                    "conditions": [],
                    "effects": [{"op": "set_flag", "id": "branch_mark",
                                 "value": False}],
                    "effect_assertion_ids": [aid(chapter)],
                },
            ]
        elif chapter == after + 2:
            item["choices"][0]["effects"] = [{
                "op": "set_flag", "id": "branch_mark", "value": False,
            }]
            item["choices"][0]["effect_assertion_ids"] = [aid(chapter)]
        scenes.append(item)
    return {
        "id": "act_%03d_%03d" % (after, before),
        "after_choice_id": "go_%03d_%03d" % (after, before),
        "chapter_start": after + 1,
        "chapter_end": before - 1,
        "entry_scene_id": scenes[0]["id"],
        "scenes": scenes,
    }


def acts():
    return {
        "acts": [_act(a, b, i) for i, (a, b) in enumerate(
            zip(ANCHORS, ANCHORS[1:]))],
        "initial_state": None,
    }


class FakeLongSourceLockedAuthor:
    """Deterministic negative of a model: all checked Python/Dart code is REAL."""

    def __init__(self):
        self.calls = 0
        self.stages = []

    def ask(self, stage, payload, feedback=""):
        self.calls += 1
        self.stages.append(stage)
        if feedback:
            raise AssertionError("Synthetic source proof unexpectedly rejected: " +
                                 feedback)
        if stage == "analysis":
            return {
                "summary": "Синтетическая глава с отметкой пути.",
                "assertions": [{
                    "kind": "NARRATED",
                    "statement": "Путница наблюдает исходное событие",
                    "quote": payload["chunk"]["text"],
                }],
                "unresolved": [],
            }
        if stage == "chapter_outline":
            return {
                "window_id": payload["window_id"],
                "chapters": [
                    {
                        "chapter_index": row["chapter_index"],
                        "summary": "Отметка, действие, хронология и путь "
                                   "синтетической главы.",
                        "featured_assertion_ids": [
                            claim["assertion_id"]
                            for chunk in row["chunks"]
                            for claim in chunk["claims"]
                            if claim["kind"] == "NARRATED"
                        ],
                        "deferred_assertion_ids": [],
                        "deferred_reason": None,
                    }
                    for row in payload["chapters"]
                ],
            }
        if stage == "npc_cast":
            return {
                "characters": [],
                "absence_reason": "Синтетические исходные главы содержат "
                                  "только путницу, без других персонажей.",
            }
        if stage == "story":
            assert payload["story_mode"] == (
                "source_locked_sparse_v3_backbone_for_v4_acts")
            # The source fingerprint is passed in the reviewed context,
            # not guessed from the actual private book.
            fingerprint = payload["reviewed_chapter_outlines"][0]["featured"][0][
                "assertion_id"]
            assert fingerprint == aid(0)
            plan = backbone({"source_fingerprint":
                            payload["source_fingerprint"]}
                            if "source_fingerprint" in payload
                            else {"source_fingerprint": "provided_by_author"})
            # The normalizer always supplies the actual source fingerprint.
            plan.pop("source_fingerprint")
            return plan
        if stage == "npc_dossiers":
            return {
                "characters": [], "absence_reason":
                    "Синтетический материал специально не содержит NPC и "
                    "проверяет многоактный путь без персонажей.",
            }
        if stage == "enrichment":
            story = payload["story"]
            return {
                "hero": {"name": "Путница", "description":
                         "Главный герой оригинальной синтетической книги."},
                "stats": {}, "items": {}, "facts": {},
                "scene_names": {
                    row["id"]: "Сцена: " + row["id"]
                    for row in story["scenes"]},
                "choices": {},
            }
        if stage == "extension":
            assert payload["long_book_backbone"]["missing_chapters_to_fill"] > 192
            return deepcopy(acts())
        if stage == "literary_review":
            return {
                "aspects": {
                    key: "pass" for key in
                    ("motivation", "knowledge", "items", "causality",
                     "chronology", "endings")
                },
                "issues": [],
                "scenes": [
                    {"scene_id": row["scene_id"], "verdict": "pass",
                     "notes": "Синтетическая рецензия на источник и игровой "
                              "переход; не является литературным аудитом."}
                    for row in payload["review_template"]["scenes"]
                ],
                "routes": [
                    {**r, "notes":
                     "Проверен синтетический маршрут без утверждения "
                     "подлинности или качества художественного текста."}
                    for r in payload["native_discovered_routes"]
                ],
            }
        raise AssertionError("Unknown synthetic author stage: " + stage)
