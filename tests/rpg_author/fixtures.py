"""Original tiny synthetic input, never a claim of adapting a real book."""
from tools.rpg_author.common import utf16_len
from tools.rpg_author.source_adapter import parse_book, make_index

TEXT = ("Лена нашла верёвку у дороги. У реки стоял мальчик. "
        "Лена протянула ему верёвку и помогла выбраться на берег.")


def source():
    return make_index(parse_book("test_story.txt", TEXT.encode("utf-8")))


def analysis(index=None):
    index = index or source()
    chunk = index["chunks"][0]
    return {"format": "rpg_author_chunk_analysis_v1", "source_fingerprint": index["source_fingerprint"],
            "chunk_id": chunk["id"], "source_sha256": chunk["sha256_text"],
            "summary": "Лена находит верёвку и помогает мальчику у реки.",
            "assertions": [{"id": "rescue_event", "statement": "В рассказе Лена помогает мальчику.",
                            "kind": "NARRATED", "start_utf16": 0,
                            "end_utf16": utf16_len(TEXT), "quote": TEXT}], "unresolved": []}


def choice(cid, target, *, requires=(), forbids=(), adds=(), removes=()):
    return {"id": cid, "label": cid, "next_scene_id": target, "requires": list(requires),
            "forbids": list(forbids), "adds": list(adds), "removes": list(removes)}


def scene(sid, text, choices=(), *, origin="EXPLICIT_ADAPTATION", claims=()):
    return {"id": sid, "chapter_index": 0, "origin": origin, "assertion_ids": list(claims),
            "text": text, "terminal": not bool(choices), "choices": list(choices)}


def story(index=None):
    index = index or source()
    return {"format": "rpg_author_story_plan_v1", "source_fingerprint": index["source_fingerprint"],
            "title": "Синтетическая проверка двух маршрутов", "entry_scene_id": "road",
            "flags": ["rope"], "initial_flags": [], "scenes": [
                scene("road", "У дороги лежит верёвка.", [
                    choice("take_rope", "river", adds=["rope"]),
                    choice("leave_rope", "river", removes=["rope"])],
                    origin="SOURCE_PASSAGE", claims=["rescue_event"]),
                scene("river", "У реки нужна помощь.", [
                    choice("rescue", "safe", requires=["rope"]),
                    choice("go_for_help", "help", forbids=["rope"])]),
                scene("safe", "Мальчик выбрался на берег.", origin="SOURCE_PASSAGE", claims=["rescue_event"]),
                scene("help", "Лена позвала лодочника на помощь.")]}
