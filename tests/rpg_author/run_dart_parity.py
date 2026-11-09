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
        # E6h: synthetic 203-scene source-locked, editor-confirmed
        # bridge. The real Dart importer/SQLite must accept both endings.
        # This is deliberately NOT a claim about a complete novel.
        from tests.rpg_author.test_v4_expansion import proposal
        import io
        import zipfile
        v3_for_ext, _ = compile_rich_from_project(checkpoint, enrichment())
        with zipfile.ZipFile(io.BytesIO(v3_for_ext)) as base_archive:
            base_bp = json.loads(base_archive.read("scenario/blueprint.json"))
        expansion = proposal(base_bp)
        long_world, long_attr = compile_extended_from_project(
            checkpoint, enrichment(), extension=expansion)
        with zipfile.ZipFile(io.BytesIO(long_world)) as zip_world:
            long_bp = json.loads(zip_world.read("scenario/blueprint.json"))
            long_origin = json.loads(zip_world.read("source/provenance.json"))
        assert len(long_bp["scenes"]) == 203
        assert len(long_origin["scene_origins"]) == 203
        long_path = ["take_rope"] + [
            f"pass_next_{i:03d}" for i in range(199)] + ["rescue"]
        long_dart = dart({
            "operation": "rich_private",
            "data": base64.b64encode(long_world).decode("ascii"),
            "paths": [long_path, ["leave_rope", "go_for_help"]],
        })
        assert long_dart["format_version"] == 4 and all(
            j["replay_ok"] and j["terminal"] for j in long_dart["journeys"]), long_dart
        long_extended_path = root / "long_v4.bworld"
        long_extended_sidecar = root / "long_v4.attribution.json"
        long_extended_path.write_bytes(long_world)
        long_extended_sidecar.write_bytes(long_attr)
        assert verify_extended_bundle(long_extended_path,
                                      long_extended_sidecar)["native_dart_verified"]
        # Initial item grants and clock need witnessed chapter-zero source,
        # never invented catalog items or an unreviewed provenance field.
        expansion_with_state = proposal(base_bp, 1)
        expansion_with_state["initial_state"] = {
            "tick": 3,
            "items": [{"item_id": "rope", "assertion_id": "rescue_event"}],
            "facts": [],
        }
        initial_bytes, _ = compile_extended_from_project(
            checkpoint, enrichment(), extension=expansion_with_state)
        with zipfile.ZipFile(io.BytesIO(initial_bytes)) as reviewed_zip:
            initial_bp = json.loads(reviewed_zip.read("scenario/blueprint.json"))
            initial_src = json.loads(reviewed_zip.read("source/provenance.json"))
        assert initial_bp["initial_state"]["inventory"] == ["rope"]
        assert initial_bp["initial_state"]["tick"] == 3
        assert initial_src["initial_state_review"]["user_confirmed"] is True
        # E6i: original synthetic THREE-chapter FB2, TWO reviewed acts,
        # player-knowledge gated branching, native Dart v4 runtime and saves.
        from tests.rpg_author import fixtures_acts as act_case
        from tools.rpg_author.native_v4_bridge import audited_extension
        act_book = root / act_case.SOURCE_FILENAME
        act_book.write_text(act_case.SOURCE, encoding="utf-8")
        act_project = root / "act_checkpoint"
        project.init_project(act_project, act_book)
        for record in act_case.analyses():
            project.submit_analysis(act_project, record)
        project.submit_story(act_project, act_case.story_plan())
        act_enrichment = act_case.rich_enrichment()
        act_v3, _ = compile_rich_from_project(act_project, act_enrichment)
        with zipfile.ZipFile(io.BytesIO(act_v3)) as archive:
            base_blueprint = json.loads(archive.read("scenario/blueprint.json"))
        act_review = act_case.reviewed_acts(base_blueprint)
        act_report = audited_extension(act_project, act_enrichment, act_review)
        assert act_report["act_count"] == 2 and act_report["distinct_source_events"] == 4
        assert act_report["chapters_without_source_scenes"] == []
        assert not act_report["native_causality_verified"]
        act_world, act_sidecar_data = compile_extended_from_project(
            act_project, act_enrichment, extension=act_review)
        with zipfile.ZipFile(io.BytesIO(act_world)) as archive:
            bp = json.loads(archive.read("scenario/blueprint.json"))
            origin = json.loads(archive.read("source/provenance.json"))
        assert len(bp["scenes"]) == 8
        assert len(origin["scene_origins"]) == 8
        assert origin["source_chapters_total"] == 3
        careful_path = [
            "take_rope", "study_bridge", "note_current",
            "rescue", "careful_route", "pull_up",
        ]
        hurried_path = ["take_rope", "rush_on", "rescue", "bold_route"]
        help_path = ["leave_rope", "call_help"]
        played = dart({
            "operation": "rich_private",
            "data": base64.b64encode(act_world).decode("ascii"),
            "paths": [careful_path, hurried_path, help_path],
        })
        assert played["format_version"] == 4
        assert all(j["replay_ok"] and j["terminal"] for j in played["journeys"]), played
        assert "current" in played["journeys"][0]["turns"][2]["facts"], played
        assert played["journeys"][0]["turns"][-1]["journal"] == careful_path
        assert played["journeys"][1]["turns"][-1]["journal"] == hurried_path
        assert played["journeys"][2]["turns"][-1]["journal"] == help_path
        persisted = dart({
            "operation": "rich_campaign",
            "data": base64.b64encode(act_world).decode("ascii"),
            "path": careful_path,
        })
        assert persisted["restart_ok"] and persisted["save_import_ok"] and persisted["fork_ok"]
        game_path = root / "multi_act_v4.bworld"
        attribution_path = root / "multi_act_v4.attribution.json"
        game_path.write_bytes(act_world)
        attribution_path.write_bytes(act_sidecar_data)
        assert verify_extended_bundle(game_path, attribution_path)["native_dart_verified"]
        # E6j: SAME original 3-chapter FB2 with a persistent NPC actor.
        # Exact chapter-1 knowledge + witnessed trust affects act two.
        # Verify both the native v4 author and the public Flutter/CLI RPG API.
        from tests.rpg_author import fixtures_npc_acts as npc_case
        npc_overlay, npc_base_review = npc_case.reviewed_base()
        base_npc_world, _ = compile_rich_from_project(
            act_project, npc_overlay, npc_review=npc_base_review)
        with zipfile.ZipFile(io.BytesIO(base_npc_world)) as npc_base_zip:
            npc_bp = json.loads(npc_base_zip.read("scenario/blueprint.json"))
            npc_prov = json.loads(npc_base_zip.read("source/provenance.json"))
        npc_act_review = npc_case.reviewed_npc_acts(
            npc_bp, npc_prov, npc_overlay)
        npc_preflight = audited_extension(
            act_project, npc_overlay, npc_act_review,
            npc_review=npc_base_review)
        assert npc_preflight["npc_known_grants_added"] == 1, npc_preflight
        assert npc_preflight["npc_memories_added"] == 2, npc_preflight
        assert npc_preflight["npc_cross_act_gates_added"] == 1, npc_preflight
        assert npc_preflight["npc_life_transitions_added"] == 1, npc_preflight
        assert not npc_preflight["npc_social_v5_validated_by_native"]
        extended_npc, npc_act_sidecar = compile_extended_from_project(
            act_project, npc_overlay, npc_review=npc_base_review,
            extension=npc_act_review)
        with zipfile.ZipFile(io.BytesIO(extended_npc)) as bundle:
            npc_act_bp = json.loads(bundle.read("scenario/blueprint.json"))
            npc_act_source = json.loads(bundle.read("source/provenance.json"))
        assert len(npc_act_bp["scenes"]) == 8
        assert len(npc_act_source["npc_knowledge"]["grants"]) == 2
        assert len(npc_act_source["npc_social"]["rules"]) == 3
        assert len(npc_act_source["npc_social"]["choice_gates"]) == 1
        assert npc_act_source["npc_social"]["format"] == (
            "ai_story_npc_social_witness_v5")
        npc_careful = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(extended_npc).decode("ascii"),
            "path": careful_path,
        })
        assert npc_careful["terminal"] and npc_careful["portable_save_verified"], npc_careful
        assert npc_case.NPC_FACT in (
            npc_careful["npc_knowledge"][npc_case.ACTOR]), npc_careful
        assert npc_careful["npc_life_states"][npc_case.ACTOR] == "absent", npc_careful
        npc_preview_earned = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(extended_npc).decode("ascii"),
            "path": careful_path[:4],
        })
        npc_preview_missed = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(extended_npc).decode("ascii"),
            "path": hurried_path[:3],
        })
        available_earned = {
            c["id"]: c["enabled"] for c in npc_preview_earned["choices"]}
        available_missed = {
            c["id"]: c["enabled"] for c in npc_preview_missed["choices"]}
        assert available_earned["careful_route"] is True, npc_preview_earned
        assert available_missed["careful_route"] is False, npc_preview_missed
        earned_relation = [x for x in npc_preview_earned["npc_relations"]
                           if x["actor_id"] == npc_case.ACTOR]
        assert len(earned_relation) == 1, npc_preview_earned
        assert earned_relation[0]["directed_score"] >= 2, npc_preview_earned
        assert earned_relation[0]["memory_count"] >= 1, npc_preview_earned
        early = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(extended_npc).decode("ascii"),
            "path": help_path,
        })
        assert early["terminal"] and early["portable_save_verified"], early
        assert early["npc_life_states"][npc_case.ACTOR] == "absent", early
        npc_result = dart({
            "operation": "rich_private",
            "data": base64.b64encode(extended_npc).decode("ascii"),
            "paths": [careful_path, hurried_path, help_path],
        })
        assert npc_result["format_version"] == 4
        assert all(j["terminal"] and j["replay_ok"]
                   for j in npc_result["journeys"]), npc_result
        e6j_world_path = root / "reviewed_npc_acts_v4.bworld"
        e6j_sidecar_path = root / "reviewed_npc_acts_v4.attribution.json"
        e6j_world_path.write_bytes(extended_npc)
        e6j_sidecar_path.write_bytes(npc_act_sidecar)
        assert verify_extended_bundle(e6j_world_path,
                                      e6j_sidecar_path)["native_dart_verified"]
        # E6k: exact signed two-speaker NPC dialogue, redaction, stable
        # character-ID portraits and a first-act item acquired before
        # its reviewed second-act transfer. NO second game rules runtime.
        from tests.rpg_author import fixtures_npc_scene_items as e6k
        item_overlay, item_npc_review = e6k.reviewed_base_with_owned_item()
        item_v3, _ = compile_rich_from_project(
            act_project, item_overlay, npc_review=item_npc_review)
        with zipfile.ZipFile(io.BytesIO(item_v3)) as item_zip:
            item_base_bp = json.loads(item_zip.read("scenario/blueprint.json"))
            item_base_src = json.loads(item_zip.read("source/provenance.json"))
        e6k_ext = e6k.reviewed_dialogue_and_custody(
            item_base_bp, item_base_src, item_overlay)
        e6k_report = audited_extension(
            act_project, item_overlay, e6k_ext, npc_review=item_npc_review)
        assert e6k_report["npc_dialogue_signed_turns"] == 2
        assert e6k_report["npc_item_transfers_reviewed"] == 1
        assert not e6k_report["dialogue_redaction_verified_by_native"]
        item_npc_world, item_npc_attr = compile_extended_from_project(
            act_project, item_overlay, npc_review=item_npc_review,
            extension=e6k_ext)
        with zipfile.ZipFile(io.BytesIO(item_npc_world)) as verified:
            signed = json.loads(verified.read("source/provenance.json"))
            item_bp = json.loads(verified.read("scenario/blueprint.json"))
        assert len(item_bp["scenes"]) == 8
        signed_scene = signed["presentation"]["scene_dialogues"]["rescue_decision"]
        signed_actors = signed["presentation"]["scene_dialogue_knowledge"][
            "rescue_decision"]
        assert signed_scene["turns"][1]["speaker"] == "Лодочник"
        assert signed_actors[1]["actor_id"] == npc_case.ACTOR
        assert signed_actors[1]["required_social_memory_id"] == "shared_warning"
        assert signed["npc_social"]["item_transfers"][0]["to_actor_id"] == npc_case.ACTOR
        gained = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(item_npc_world).decode("ascii"),
            "path": careful_path[:4],
        })
        missed = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(item_npc_world).decode("ascii"),
            "path": hurried_path[:3],
        })
        assert gained["scene_id"] == "rescue_decision" and missed["scene_id"] == "rescue_decision"
        assert gained["scene_dialogue_turns"][1]["speaker"] == "Лодочник", gained
        assert gained["visible_speaker_actor_ids"]["Лодочник"] == npc_case.ACTOR
        assert gained["portrait_storage_key"] == npc_case.ACTOR
        assert missed["scene_dialogue_turns"][1]["speaker"] is None, missed
        assert "недоступна" in missed["scene_dialogue_turns"][1]["text"], missed
        assert "Лодочник" not in missed["visible_speaker_actor_ids"], missed
        assert missed["portrait_storage_key"] != npc_case.ACTOR, missed
        acquired = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(item_npc_world).decode("ascii"),
            "path": careful_path,
        })
        assert acquired["terminal"] and acquired["portable_save_verified"], acquired
        assert acquired["inventory"] == [], acquired
        assert acquired["npc_item_owners"]["rope"] == npc_case.ACTOR, acquired
        assert acquired["npc_life_states"][npc_case.ACTOR] == "absent", acquired
        returned = dart({
            "operation": "npc_public_api",
            "data": base64.b64encode(item_npc_world).decode("ascii"),
            "path": hurried_path,
        })
        assert returned["terminal"] and returned["portable_save_verified"]
        assert "rope" in returned["inventory"], returned
        assert returned["npc_item_owners"] == {}, returned
        e6k_file = root / "npc_scene_items_v4.bworld"
        e6k_sidecar = root / "npc_scene_items_v4.attribution.json"
        e6k_file.write_bytes(item_npc_world)
        e6k_sidecar.write_bytes(item_npc_attr)
        assert verify_extended_bundle(e6k_file, e6k_sidecar)["native_dart_verified"]
        # The author's complete-book automation must discover, not invent,
        # two distinct endings via the public native game API.
        from tools.rpg_author.auto_author import _discover_real_endings
        discovered = _discover_real_endings(item_npc_world)
        assert len(discovered) == 2
        assert {r["expected_ending_scene_id"] for r in discovered} == {
            "safe", "help"
        }, discovered
        assert all(len(r["choice_ids"]) >= 2 for r in discovered)
        # ONE holistic acceptance, no micro-gate success claims: all reviewed
        # scenes, ALL original chapters, two truly different endings, real
        # LocalRpgGameApi/SQLite replay, private attribution and report.
        from unittest.mock import patch as patch_function
        from tests.rpg_author.test_complete_game import reviewed_campaign_fixture
        from tools.rpg_author.complete_game import finalize_extended_campaign
        from tools.rpg_author.common import canonical
        complete_review = reviewed_campaign_fixture(item_bp, signed, e6k_ext)
        complete_overlay = root / "complete_overlay.json"
        complete_npc = root / "complete_npc_base.json"
        complete_extension = root / "complete_extension.json"
        complete_editorial = root / "complete_editorial.json"
        complete_target = root / "complete_multi_act.bworld"
        complete_overlay.write_bytes(canonical(item_overlay))
        complete_npc.write_bytes(canonical(item_npc_review))
        complete_extension.write_bytes(canonical(e6k_ext))
        # First invocation produces a source-bound, UNAPPROVED private
        # worksheet without writing a world or pretending review is complete.
        with patch_function(
            "tools.rpg_author.complete_game.compile_extended_from_project",
            return_value=(item_npc_world, item_npc_attr)
        ):
            needs_review = finalize_extended_campaign(
                act_project, complete_overlay, complete_extension,
                complete_editorial, complete_target,
                npc_review=complete_npc,
                no_interactive_questions=True)
        assert needs_review["status"] == "needs_independent_editorial_review"
        assert not complete_target.exists() and complete_editorial.is_file()
        pending = json.loads(complete_editorial.read_text(encoding="utf-8"))
        assert len(pending["scenes"]) == 8 and pending["routes"] == []
        assert not pending["user_confirmed"] and not pending["review_completed"]
        # The private independent editorial/AI pass now fills the worksheet.
        complete_editorial.write_bytes(canonical(complete_review))
        # Compilation of exactly these bytes was ALREADY executed with the
        # native Dart writer above. Avoid a second expensive native compile
        # inside the same test, but DO replay all routes with the real public
        # API from the NEW finalizer; normal CLI does NOT patch anything.
        with patch_function(
            "tools.rpg_author.complete_game.compile_extended_from_project",
            return_value=(item_npc_world, item_npc_attr)
        ):
            complete_result = finalize_extended_campaign(
                act_project, complete_overlay, complete_extension,
                complete_editorial, complete_target,
                npc_review=complete_npc,
                no_interactive_questions=True)
        assert complete_result["status"] == (
            "native_multi_act_campaign_mechanically_verified"), complete_result
        assert complete_result["source_review"]["verified_scene_review_records"] == 8
        assert complete_result["source_review"]["reviewed_book_chapters"] == 3
        assert complete_result["native_routes"]["route_count"] == 2
        assert complete_result["native_routes"]["endings_verified"] == 2
        assert {r["ending_scene_id"] for r in
                complete_result["native_routes"]["routes"]} == {"safe", "help"}
        assert all(r["portable_save_verified"] for r in
                   complete_result["native_routes"]["routes"])
        assert not complete_result["literary_truth_attested"]
        assert not complete_result["device_playtest_completed"]
        assert not complete_result["user_ready"]
        assert complete_target.exists() and (
            complete_target.with_suffix(".readiness.json")).exists()
        assert verify_extended_bundle(
            complete_target,
            complete_target.with_suffix(".attribution.json"))["native_dart_verified"]
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
                       "native_v4_attribution_mismatch_rejected": True,
                       "native_v4_203_source_locked_scenes_replayed": True,
                       "native_v4_initial_item_and_tick_review_verified": True,
                       "native_v4_three_chapter_two_act_branching_verified": True,
                       "native_v4_stateful_knowledge_gate_and_save_replayed": True,
                       "native_v4_npc_actor_scoped_cross_act_grants_verified": True,
                       "native_v4_npc_social_memory_trust_and_life_replayed": True,
                       "native_v4_npc_public_api_choice_gates_and_saves": True,
                       "native_v4_npc_signed_dialogue_redaction_and_portraits": True,
                       "native_v4_npc_item_custody_public_api_save_verified": True,
                       "complete_private_book_two_native_ending_routes_verified": True,
                       "automatic_native_two_distinct_ending_discovery": True}))


if __name__ == "__main__":
    main()
