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
from tests.rpg_author.test_npc_review import reviewed_fixture, reviewed_transfer_fixture
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.native_v4_bridge import (compile_extended_from_project,
                                               verify_extended_bundle)
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
        # E6f: the EXTERNAL Python author must emit a v5 NPC world that
        # the actual Dart importer and SQLite replay understand. No fake
        # social data, main engine modification, network or real book here.
        reviewed_enrichment, reviewed_npc = reviewed_fixture()
        npc_bytes, _ = compile_rich_from_project(
            checkpoint, reviewed_enrichment, npc_review=reviewed_npc)
        npc_world = dart({
            "operation": "rich_private",
            "data": base64.b64encode(npc_bytes).decode("ascii"),
            "paths": [["take_rope", "rescue"], ["leave_rope", "go_for_help"]],
        })
        assert npc_world["private_only"] and npc_world["v2_rejected_v3"]
        assert npc_world["archive_sha256"] == digest(npc_bytes)
        assert npc_world["journeys"][0]["replay_ok"]
        assert npc_world["journeys"][1]["replay_ok"]
        npc_save = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(npc_bytes).decode("ascii"),
            "path": ["take_rope", "rescue"],
        })
        assert npc_save["revision"] == 2
        assert npc_save["restart_ok"] and npc_save["save_import_ok"]
        assert npc_save["fork_ok"]
        # E6f custody: source-backed player acquisition, NPC gift and
        # departure are serialized by the external author and replayed by
        # the main Dart importer/campaign store, not a forked engine.
        transfer_plan, transfer_overlay, transfer_review = reviewed_transfer_fixture()
        transfer_project = root / "transfer_project"
        project.init_project(transfer_project, source_path)
        project.submit_analysis(transfer_project, analysis())
        project.submit_story(transfer_project, transfer_plan)
        transferred_bytes, _ = compile_rich_from_project(
            transfer_project, transfer_overlay, npc_review=transfer_review)
        transferred = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(transferred_bytes).decode("ascii"),
            "path": ["take_rope", "rescue"],
        })
        assert transferred["inventory"] == [] and transferred["revision"] == 2
        assert (transferred["restart_ok"] and transferred["save_import_ok"]
                and transferred["fork_ok"]), transferred
        # Verify Python -> Dart -> SQLite on both real flag-only routes.
        plain = enrichment()
        plain["items"] = {}
        plain["stats"] = {}
        plain["facts"] = {}
        plain["choices"] = {}
        plain_bytes, _ = compile_rich_from_project(
            checkpoint, plain, model_id="gpt-6")
        plain_world = dart({
            "operation": "rich_private",
            "data": base64.b64encode(plain_bytes).decode("ascii"),
            "paths": [["take_rope", "rescue"], ["leave_rope", "go_for_help"]],
        })
        assert plain_world["item_names"] == {}, plain_world
        assert plain_world["stat_names"] == {}, plain_world
        assert plain_world["fact_names"] == {}, plain_world
        for route in plain_world["journeys"]:
            assert route["terminal"] and route["replay_ok"], route
            assert all(t["stats"] == {} and t["inventory"] == [] and
                       t["facts"] == [] for t in route["turns"]), route
        plain_campaign = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(plain_bytes).decode("ascii"),
            "path": ["leave_rope", "go_for_help"],
        })
        assert plain_campaign["inventory"] == []
        assert plain_campaign["stats"] == {}
        assert plain_campaign["facts"] == []
        assert plain_campaign["journal"] == ["leave_rope", "go_for_help"]
        assert (plain_campaign["restart_ok"] and
                plain_campaign["save_import_ok"] and plain_campaign["fork_ok"])
        # E6g v4: prepare the very same source-reviewed external E6f project,
        # then call the ACTUAL standalone native Dart v4 authoring CLI. The
        # Python writer never impersonates the 1024-scene v4 causal engine.
        extended_bytes, extended_attribution = compile_extended_from_project(
            checkpoint, enrichment())
        v4_path = root / "private_extended_v4.bworld"
        sidecar_path = root / "private_extended_v4.attribution.json"
        v4_path.write_bytes(extended_bytes)
        sidecar_path.write_bytes(extended_attribution)
        verified_v4 = verify_extended_bundle(v4_path, sidecar_path)
        assert verified_v4["format_version"] == 4, verified_v4
        assert verified_v4["native_dart_verified"]
        assert verified_v4["archive_sha256"] == digest(extended_bytes)
        v4_world = dart({
            "operation": "rich_private",
            "data": base64.b64encode(extended_bytes).decode("ascii"),
            "paths": [["take_rope", "rescue"], ["leave_rope", "go_for_help"]],
        })
        assert v4_world["format_version"] == 4, v4_world
        assert v4_world["archive_sha256"] == digest(extended_bytes)
        assert all(j["replay_ok"] and j["terminal"]
                   for j in v4_world["journeys"]), v4_world
        v4_restart = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(extended_bytes).decode("ascii"),
            "path": ["take_rope", "rescue"],
        })
        assert v4_restart["restart_ok"] and v4_restart["save_import_ok"]
        assert v4_restart["fork_ok"]
        # Deliberately forged sidecar remains rejected even when Dart accepts
        # the underlying v4 archive. Do not confuse hashes with model proof.
        sidecar_data = json.loads(extended_attribution)
        sidecar_data["scenario_generation"]["provider"] = "forged"
        sidecar_path.write_text(json.dumps(sidecar_data), encoding="utf-8")
        try:
            verify_extended_bundle(v4_path, sidecar_path)
        except AuthoringError as error:
            assert error.code == "attribution_mismatch", error.code
        else:
            raise AssertionError("v4 accepted forged attribution")
        sidecar_path.write_bytes(extended_attribution)
        # NPC witness/social/custody/life v5 is still governed by native core.
        npc_extended, npc_v4_attribution = compile_extended_from_project(
            checkpoint, reviewed_enrichment, npc_review=reviewed_npc)
        assert npc_extended != extended_bytes
        npc_v4 = dart({
            "operation": "rich_private",
            "data": base64.b64encode(npc_extended).decode("ascii"),
            "paths": [["take_rope", "rescue"], ["leave_rope", "go_for_help"]],
        })
        assert npc_v4["format_version"] == 4
        assert all(j["replay_ok"] for j in npc_v4["journeys"]), npc_v4
        npc_v4_save = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(npc_extended).decode("ascii"),
            "path": ["take_rope", "rescue"],
        })
        assert npc_v4_save["restart_ok"] and npc_v4_save["save_import_ok"]
        assert npc_v4_save["fork_ok"]
        assert json.loads(npc_v4_attribution)["bookworld_packaging"]["version"] == "4.0"
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
                      "rich_v3_sqlite_restart_fork_portable_save": True,
                      "rich_v3_empty_catalogs_dart_sqlite": True,
                      "external_reviewed_npc_social_v5_dart_sqlite": True,
                      "external_reviewed_npc_item_custody_life_v5_dart_sqlite": True,
                       "native_v4_python_reviewed_dart_compiled_and_imported": True,
                       "native_v4_sqlite_replay_and_save": True,
                       "native_v4_npc_v5_dart_sqlite": True,
                       "native_v4_attribution_mismatch_rejected": True}))


if __name__ == "__main__":
    main()
