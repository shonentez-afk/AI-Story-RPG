"""CI-only, read-only checks against REAL Dart source/blueprint implementations.

Run from repo root after `dart pub get` in tests/rpg_author/dart. All input
texts are original synthetic fixtures. No user's book is sent to CI.
"""
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.rpg_author.source_adapter import make_index, parse_book
from tools.rpg_author.common import AuthoringError
from tools.rpg_author.validate import candidate_blueprint
from tests.rpg_author.fixtures import source, story, TEXT, analysis
from tests.rpg_author.fixtures_rich import enrichment
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author import project
from tools.rpg_author.legacy_package import compile_from_project
from tools.rpg_author.common import digest


def dart(request):
    result = subprocess.run(["dart", "run", "probe.dart"], cwd=ROOT / "tests/rpg_author/dart",
                            input=json.dumps(request, ensure_ascii=False), encoding="utf-8",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def main():
    fb2 = '''<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
    <description><title-info><book-title>Тест &amp; книга 😀</book-title>
    <author><first-name>Анна</first-name><last-name>Автор</last-name></author>
    </title-info></description><body><section><title><p>Глава</p></title>
    <p>До <emphasis>света</emphasis><image href="#x"/> после.</p>
    <section><p>Строка\r\nпродолжение.</p><v>Стих.</v></section></section></body>
    <body name="notes"><section><title><p>1</p></title><p>Сноска.</p></section></body>
    </FictionBook>'''
    numbered = '<FictionBook><body><section>' + ''.join(
        f'<p>Рассказ {word}</p><p>Текст.</p>' for word in ('первый', 'второй', 'третий')) + '</section></body></FictionBook>'
    inputs = [
        ("plain.txt", " \r\nС😀.\t\n" * 200, "utf-8-sig"),
        ("boundary.txt", "я" * 255 + "😀" + "б" * 100, "utf-8"),
        ("old.txt", "Старинный текст книги.", "cp1251"),
        ("utf16.txt", "Строка 😀\nВторая.", "utf-16"),
        ("structured.fb2", fb2, "utf-8"),
        ("numbered.fb2", numbered, "utf-8"),
        ("old.fb2", '<?xml version="1.0" encoding="windows-1251"?>' + numbered, "cp1251"),
        ("utf16.fb2", numbered, "utf-16"),
        ("media.fb2", '<FictionBook><body><section><image href="#x"/></section><section><p>Текст.</p></section></body></FictionBook>', "utf-8"),
        ("inline.fb2", '<FictionBook><body><p>А<strong>В</strong><!-- comment -->Г &#x1f600;.</p></body></FictionBook>', "utf-8"),
        ("whitespace.fb2", '<FictionBook>\r\n<body><p>Один\rдва.</p><p>А\r\n&lt;&amp; Б</p><image href="#name\r\nwith\ttabs"/></body></FictionBook>', "utf-8"),
    ]
    checked = 0
    for filename, text, encoding in inputs:
        data = text.encode(encoding)
        for chunk_size in (257, 4096):
            expected = make_index(parse_book(filename, data), chunk_size)
            actual = dart({"operation": "source", "filename": filename,
                           "data": base64.b64encode(data).decode(), "chunk_size": chunk_size})
            if actual != expected:
                keys = [k for k in expected if actual.get(k) != expected[k]]
                raise AssertionError(f"{filename}, chunk={chunk_size}: differing fields {keys}\n"
                                     f"Dart: {json.dumps(actual, ensure_ascii=False)}\n"
                                     f"Python: {json.dumps(expected, ensure_ascii=False)}")
            checked += 1
    blueprint = candidate_blueprint(story(), source())
    result = dart({"operation": "blueprint", "blueprint": blueprint})
    assert result == {"book_id": blueprint["book_id"], "scene_count": len(blueprint["scenes"])}
    # Regression from real Dart comparison: the native parser drops direct
    # CDATA inside p. Do not delete it in Python just to make indices equal.
    cdata = '<FictionBook><body><p>А<![CDATA[Б]]>В</p></body></FictionBook>'
    try:
        parse_book("cdata.fb2", cdata.encode())
    except AuthoringError as error:
        assert error.code == "unsupported_fb2_cdata"
    else:
        raise AssertionError("CDATA would silently lose content in the current app")
    # A real, independently verified four-entry BookWorld v2, not only a JSON
    # blueprint. Keep all synthetic book bytes/checkpoints outside checkout.
    with tempfile.TemporaryDirectory() as temporary:
        source_path = Path(temporary) / "test_story.txt"
        source_path.write_text(TEXT, encoding="utf-8")
        project_path = Path(temporary) / "author-project"
        project.init_project(project_path, source_path)
        project.submit_analysis(project_path, analysis())
        project.submit_story(project_path, story())
        archive, attribution = compile_from_project(project_path, model_id="gpt-6")
        imported = dart({"operation": "private_archive",
                         "data": base64.b64encode(archive).decode("ascii")})
        expected = candidate_blueprint(story(), source())
        assert imported == {
            "book_id": expected["book_id"],
            "source_fingerprint": expected["source_fingerprint"],
            "archive_sha256": digest(archive),
            "scene_count": len(expected["scenes"]),
            "can_distribute": False,
            "requires_network": False,
        }, imported
    # Current main application already handles true item/stat/fact effects in
    # its original-demo runtime. Exercise two different routes and deterministic
    # journal replay via the actual, unchanged Dart StoryWorld.
    from tests.rpg_author.panel_state_demo import build as build_panel_demo
    panel_world = dart({
        "operation": "panel_world",
        "data": base64.b64encode(build_panel_demo()).decode("ascii"),
        "paths": [
            ["take_lantern", "use_lantern", "help_child", "show_medal"],
            ["take_rope", "use_rope", "pass_child", "tell_crossing"],
            ["take_nothing", "abandon_quest"],
        ],
    })
    assert panel_world["world_id"] == "panel_state_demo_v1"
    lantern, rope, empty = panel_world["routes"]
    assert all(x["replayed"] and x["terminal"] for x in (lantern, rope, empty))
    assert lantern["turns"][0]["inventory"] == ["lantern"]
    assert lantern["turns"][0]["stats"]["insight"] == 2
    assert lantern["turns"][2]["inventory"] == ["lantern", "medal"]
    assert lantern["turns"][2]["stats"]["courage"] == 2
    assert lantern["turns"][3]["inventory"] == ["lantern"]
    assert lantern["turns"][3]["stats"]["insight"] == 4
    assert set(lantern["turns"][3]["known_facts"]) == {"river_crossed", "child_thanks"}
    assert lantern["turns"][3]["journal_choices"] == [
        "take_lantern", "use_lantern", "help_child", "show_medal"
    ]
    assert rope["turns"][0]["inventory"] == ["rope"]
    assert rope["turns"][1]["inventory"] == []
    assert rope["turns"][1]["stats"]["courage"] == 3
    assert rope["turns"][3]["inventory"] == []
    assert rope["turns"][3]["journal_choices"] == [
        "take_rope", "use_rope", "pass_child", "tell_crossing"
    ]
    assert empty["turns"][1]["inventory"] == []
    assert empty["turns"][1]["journal_choices"] == ["take_nothing", "abandon_quest"]
    with tempfile.TemporaryDirectory() as private_temp:
        root = Path(private_temp)
        source_path = root / "test_story.txt"
        source_path.write_text(TEXT, encoding="utf-8")
        checkpoint = root / "project"
        project.init_project(checkpoint, source_path)
        project.submit_analysis(checkpoint, analysis())
        project.submit_story(checkpoint, story())
        rich_bytes, rich_sidecar = compile_rich_from_project(
            checkpoint, enrichment(), model_id="gpt-6")
        actual = dart({
            "operation": "rich_private",
            "data": base64.b64encode(rich_bytes).decode("ascii"),
            "paths": [["take_rope", "rescue"], ["leave_rope", "go_for_help"]],
        })
        assert actual["v2_rejected_v3"] is True, actual
        assert actual["private_only"] is True, actual
        assert actual["source_fingerprint"] == source()["source_fingerprint"]
        assert actual["archive_sha256"] == digest(rich_bytes)
        assert actual["hero"]["name"] == "Лена"
        assert actual["item_names"]["rope"] == "Верёвка"
        assert actual["stat_names"]["courage"] == "Смелость"
        rescue, help_route = actual["journeys"]
        assert rescue["terminal"] and rescue["replay_ok"], rescue
        assert rescue["turns"][0]["inventory"] == ["rope"]
        assert rescue["turns"][0]["stats"]["courage"] == 2
        assert rescue["turns"][1]["inventory"] == []
        assert rescue["turns"][1]["stats"]["courage"] == 4
        assert rescue["turns"][1]["facts"] == ["rescue_fact"]
        assert rescue["turns"][1]["journal"] == ["take_rope", "rescue"]
        assert help_route["terminal"] and help_route["replay_ok"], help_route
        assert help_route["turns"][0]["inventory"] == []
        assert help_route["turns"][0]["stats"]["insight"] == 2
        assert help_route["turns"][1]["journal"] == ["leave_rope", "go_for_help"]
        durable = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(rich_bytes).decode("ascii"),
            "path": ["take_rope", "rescue"],
        })
        assert durable["revision"] == 2 and durable["inventory"] == []
        assert durable["stats"]["courage"] == 4
        assert durable["facts"] == ["rescue_fact"]
        assert durable["journal"] == ["take_rope", "rescue"]
        assert durable["restart_ok"] and durable["save_import_ok"] and durable["fork_ok"]
        alternative = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(rich_bytes).decode("ascii"),
            "path": ["leave_rope", "go_for_help"],
        })
        assert alternative["revision"] == 2 and alternative["inventory"] == []
        assert alternative["stats"]["insight"] == 2
        assert alternative["journal"] == ["leave_rope", "go_for_help"]
        assert alternative["restart_ok"] and alternative["save_import_ok"] and alternative["fork_ok"]
    print(json.dumps({"source_comparisons": checked, "candidate_accepted_by_dart_blueprint": True,
                      "known_lossy_source_forms_refused": 1,
                      "application_modified": False,
                      "external_ai_package_built": True,
                      "private_archive_accepted_by_dart_importer": True,
                      "panel_world_three_replay_verified_routes": True,
                      "panel_world_dynamic_items_stats_facts_journal": True,
                      "rich_v3_python_compiled_dart_imported": True,
                      "rich_v3_state_replayed_in_two_routes": True,
                      "legacy_v2_rejects_v3": True,
                      "rich_v3_sqlite_restart_fork_portable_save": True}))


if __name__ == "__main__":
    main()
