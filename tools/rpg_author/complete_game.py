"""One fail-closed BOOK -> verified native-v4 campaign acceptance, not game rules.

This completes a previously reviewed private RPG project with an explicit
multi-act proposal and independently declared editorial/route review. The
ONLY gameplay execution is the existing public Dart RpgGameApi/SQLite.
No Flutter dependency, no automatic literary-canon assertion, no network.
"""
from __future__ import annotations

import base64
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from .common import (AuthoringError, ROOT, atomic_write, canonical, digest,
                     fields, identifier, outside_repository, parse_json,
                     read_json, require)
from .compatibility import check_contract
from .native_v4_bridge import (
    _MAX_V4_BYTES, _inspect_v4, audited_extension,
    compile_extended_from_project,
)
from .project import load_project
from .validate import validate_story

REVIEW_FORMAT = "rpg_author_complete_multi_act_review_v1"
ROUTE_REQUEST_FORMAT = "rpg_author_two_routes_native_v1"
ROUTE_RESULT_FORMAT = "rpg_author_native_two_routes_evidence_v1"
REPORT_FORMAT = "rpg_author_complete_native_campaign_acceptance_v1"
ASPECTS = frozenset(("motivation", "knowledge", "items", "causality",
                     "chronology", "endings"))
ACT_FORMATS = frozenset(("rpg_author_v4_acts_v1", "rpg_author_v4_acts_v2",
                         "rpg_author_v4_acts_v3"))
_DART_SCRIPT = ROOT / "tools/rpg_author/dart/route_probe.dart"
_TOOL_PACKAGE_CONFIG = ROOT / "tools/rpg_author/dart/.dart_tool/package_config.json"
_TEST_PACKAGE_CONFIG = ROOT / "tests/rpg_author/dart/.dart_tool/package_config.json"
_HEX_SHA = re.compile(r"^[0-9a-f]{64}$")


def _reviewed_text(value: object, where: str) -> None:
    require(type(value) is str and value == value.strip()
            and 20 <= len(value) <= 2000,
            "campaign_review_notes_missing", where + " needs a concrete written assessment")


def review_complete_campaign(review: dict, blueprint: dict, provenance: dict,
                             extension: dict) -> dict:
    """Verify DECLARED review coverage against every signed scene and source.

    This validates presence, exact revision and quotes, never semantic truth.
    Two complete routes still need ACTUAL Dart engine replay afterwards.
    """
    fields(review, {
        "format", "source_fingerprint", "extension_sha256", "blueprint_sha256",
        "user_confirmed", "review_method", "review_completed",
        "literary_canon_verified", "aspects", "issues", "scenes", "routes",
    }, "one complete multi-act editorial review")
    require(review["format"] == REVIEW_FORMAT and
            review["source_fingerprint"] == blueprint["source_fingerprint"]
            == provenance["source_fingerprint"] and
            review["extension_sha256"] == digest(canonical(extension)) and
            review["blueprint_sha256"] == digest(canonical(blueprint)) and
            review["user_confirmed"] is True and
            review["review_method"] == "independent_ai_pass" and
            review["review_completed"] is True and
            review["literary_canon_verified"] is False and
            type(review["aspects"]) is dict and
            set(review["aspects"]) == ASPECTS and
            all(review["aspects"][key] == "pass" for key in ASPECTS) and
            review["issues"] == [],
            "campaign_review_stale",
            "Complete-book review must match exact source, extension and blueprint")
    require(type(extension) is dict and
            extension.get("format") in ACT_FORMATS and
            type(extension.get("acts")) is list and
            len(extension["acts"]) >= 2,
            "campaign_not_multi_act",
            "A complete campaign must include at least two source-reviewed acts")
    require(blueprint["rights_status"] == "private_adaptation" and
            provenance["rights_status"] == "private_adaptation",
            "campaign_not_private", "This workflow accepts private adaptation only")
    scenes = {scene["id"]: scene for scene in blueprint["scenes"]}
    sources = provenance["scene_origins"]
    origin_by_id = {row["scene_id"]: row for row in sources}
    require(len(scenes) == len(blueprint["scenes"]) and
            len(origin_by_id) == len(sources) and
            set(scenes) == set(origin_by_id),
            "campaign_source_incomplete",
            "Every compiled scene needs an unambiguous recorded provenance")
    chapter_count = provenance["source_chapters_total"]
    require(type(chapter_count) is int and chapter_count >= 2,
            "campaign_source_incomplete", "Full-book source index is required")
    covered = {
        row["chapter_index"] for row in sources
        if row["origin"] == "SOURCE_PASSAGE"
    }
    require(covered == set(range(chapter_count)),
            "campaign_chapters_uncovered",
            "Every original chapter must have a source-backed gameplay scene")
    reviews = review["scenes"]
    require(type(reviews) is list and len(reviews) == len(scenes),
            "campaign_review_scene_missing",
            "One explicitly reviewed scene record is required per signed scene")
    seen = set()
    for item in reviews:
        fields(item, {"scene_id", "verdict", "notes", "source_quote_sha256"},
               "complete-game scene review")
        sid = item["scene_id"]
        require(sid in scenes and sid not in seen and item["verdict"] == "pass",
                "campaign_review_scene_missing",
                "A signed scene must have exactly one passing review")
        _reviewed_text(item["notes"], "Scene " + sid)
        quote_hashes = [ref["quote_sha256"]
                        for ref in origin_by_id[sid]["source_refs"]]
        require(type(item["source_quote_sha256"]) is list and
                item["source_quote_sha256"] == sorted(set(quote_hashes)) and
                all(type(q) is str and _HEX_SHA.fullmatch(q) for q in quote_hashes),
                "campaign_source_review_mismatch",
                "Scene review must cite ALL and ONLY its signed source excerpts")
        seen.add(sid)
    require(seen == set(scenes),
            "campaign_review_scene_missing", "Editorial review omitted a signed scene")

    paths = review["routes"]
    require(type(paths) is list and len(paths) == 2,
            "campaign_two_routes_required",
            "Submit exactly two independently reviewed complete routes")
    route_ids, endings, sequences = set(), set(), set()
    for route in paths:
        fields(route, {"id", "choice_ids", "expected_ending_scene_id", "notes"},
               "reviewed complete game route")
        identifier(route["id"], "reviewed route ID")
        ending = route["expected_ending_scene_id"]
        seq = route["choice_ids"]
        require(route["id"] not in route_ids and
                type(ending) is str and ending in scenes and
                scenes[ending]["terminal"] is True and ending not in endings and
                type(seq) is list and 2 <= len(seq) <= 24 and
                all(type(x) is str for x in seq) and
                tuple(seq) not in sequences,
                "campaign_route_review_invalid",
                "Each route needs unique choices and a distinct reviewed ending")
        _reviewed_text(route["notes"], "Complete route " + route["id"])
        route_ids.add(route["id"])
        endings.add(ending)
        sequences.add(tuple(seq))
    require(len(endings) == 2,
            "campaign_two_endings_required", "Two different endings are necessary")

    return {
        "format": REVIEW_FORMAT,
        "source_fingerprint": review["source_fingerprint"],
        "verified_scene_review_records": len(reviews),
        "reviewed_book_chapters": chapter_count,
        "source_chapters_with_gameplay": len(covered),
        "reviewed_full_routes": 2,
        "reviewed_distinct_ending_scenes": 2,
        "source_evidence_binds_exact_revision": True,
        "review_report_complete": True,
        "literary_truth_attested": False,
        "author_report_cannot_prove_literary_quality": True,
    }


def replay_two_native_routes(raw: bytes, routes: list[dict]) -> dict:
    """No Python RPG state traversal: invoke the real Dart rpg_api port."""
    check_contract()
    require(len(raw) <= _MAX_V4_BYTES and len(routes) == 2,
            "native_route_invalid_input", "A private world and two routes are required")
    package_config = (_TOOL_PACKAGE_CONFIG if _TOOL_PACKAGE_CONFIG.is_file()
                      else _TEST_PACKAGE_CONFIG)
    require(_DART_SCRIPT.is_file() and package_config.is_file(),
            "native_route_not_resolved",
            "Run 'dart pub get' in tools/rpg_author/dart for public API route verification")
    require(shutil.which("dart") is not None,
            "native_dart_unavailable", "Dart SDK required for native route verification")
    request = {
        "format": ROUTE_REQUEST_FORMAT,
        "archive_b64": base64.b64encode(raw).decode("ascii"),
        "routes": [{"id": route["id"], "choice_ids": route["choice_ids"]}
                   for route in routes],
    }
    with tempfile.TemporaryDirectory(prefix="rpg_native_route_") as tmp:
        try:
            run = subprocess.run(
                ["dart", "--packages=" + str(package_config), str(_DART_SCRIPT)],
                cwd=tmp, input=json.dumps(request, ensure_ascii=False),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding="utf-8", timeout=240)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise AuthoringError("native_route_unavailable",
                                 "Native public RPG API route check could not run") from exc
    require(run.returncode == 0,
            "native_route_rejected",
            "Public Dart RPG engine refused a route or portable SQLite replay")
    try:
        report = parse_json(run.stdout.encode("utf-8"))
    except (UnicodeError, ValueError) as exc:
        raise AuthoringError("native_route_invalid_response",
                             "Native route engine did not emit validated JSON") from exc
    require(type(report) is dict and
            report.get("format") == ROUTE_RESULT_FORMAT and
            report.get("archive_sha256") == digest(raw) and
            report.get("true_rpg_api") is True and
            report.get("native_sqlite_portable_saves") is True,
            "native_route_invalid_response",
            "Native route evidence is not bound to the source-checked archive")
    return report


def verify_route_evidence(report: dict, routes: list[dict], blueprint: dict,
                          provenance: dict, raw: bytes) -> dict:
    require(type(report) is dict and
            report.get("format") == ROUTE_RESULT_FORMAT and
            report.get("archive_sha256") == digest(raw) and
            report.get("true_rpg_api") is True and
            report.get("native_sqlite_portable_saves") is True and
            type(report.get("verified_routes")) is list and
            len(report["verified_routes"]) == 2,
            "native_route_invalid_response", "Two archive-bound native route proofs required")
    by_id = {row["id"]: row for row in routes}
    scenes = {s["id"]: s for s in blueprint["scenes"]}
    chapters = {s["scene_id"]: s["chapter_index"]
                for s in provenance["scene_origins"]}
    seen_routes, endings = set(), set()
    summaries = []
    for actual in report["verified_routes"]:
        require(type(actual) is dict and actual.get("id") in by_id and
                actual["id"] not in seen_routes,
                "native_route_invalid_response", "Native report has a forged or repeated route")
        claim = by_id[actual["id"]]
        trace = actual.get("scene_ids")
        end = actual.get("ending_scene_id")
        require(actual.get("terminal") is True and
                actual.get("portable_save_verified") is True and
                actual.get("choice_ids") == claim["choice_ids"] and
                end == claim["expected_ending_scene_id"] and
                end in scenes and scenes[end]["terminal"] is True and
                end not in endings and
                type(trace) is list and
                len(trace) == len(claim["choice_ids"]) + 1 and
                all(type(x) is str and x in scenes for x in trace) and
                trace[0] == blueprint["entry_scene_id"] and
                trace[-1] == end and
                actual.get("revisions") == len(claim["choice_ids"]) and
                actual.get("journal_count") == len(claim["choice_ids"]) and
                type(actual.get("state_hash")) is str and
                _HEX_SHA.fullmatch(actual["state_hash"]),
                "native_route_invalid_response",
                "Native final replay did not match the editorial full-route claim")
        seen_routes.add(actual["id"])
        endings.add(end)
        summaries.append({
            "route_id": actual["id"],
            "ending_scene_id": end,
            "replayed_choices": len(claim["choice_ids"]),
            "visited_source_chapters": sorted({chapters[s] for s in trace}),
            "portable_save_verified": True,
            "native_state_sha256": actual["state_hash"],
            "private_npc_item_owner_count": len(actual.get("visible_npc_item_owners", {})),
        })
    require(seen_routes == set(by_id) and len(endings) == 2,
            "native_route_invalid_response", "Both authored endings must independently replay")
    return {
        "status": "two_complete_routes_native_rpg_api_and_sqlite_verified",
        "archive_sha256": digest(raw),
        "route_count": 2,
        "endings_verified": 2,
        "routes": summaries,
        "native_game_rules_reused": True,
        "python_game_rule_fork_used": False,
    }


def finalize_extended_campaign(project: Path, enrichment: Path, extension: Path,
                               review: Path, output: Path, *,
                               npc_review: Path | None = None,
                               report_path: Path | None = None,
                               dialogues: Path | None = None,
                               question_inventory: Path | None = None,
                               no_interactive_questions: bool = False) -> dict:
    """One launch, one acceptance, one immutable private .bworld v4.

    Compiles in memory, verifies exact source/editorial records, then proves
    two REAL ending paths with native rpg_api. Only after ALL checks pass are
    the archive, attribution and readiness report written atomically.
    """
    check_contract()
    root = outside_repository(project)
    output = outside_repository(output)
    overlay_path = outside_repository(enrichment)
    extension_path = outside_repository(extension)
    review_path = outside_repository(review)
    review_npc_path = outside_repository(npc_review) if npc_review else None
    report = outside_repository(report_path or output.with_suffix(".readiness.json"))
    attribution = output.with_suffix(".attribution.json")
    all_outputs = (output, attribution, report)
    require(output.suffix.lower() == ".bworld" and
            len(set(all_outputs)) == 3 and
            all(root != path and root not in path.parents
                for path in all_outputs) and
            not set(all_outputs).intersection(
                {overlay_path, extension_path, review_path, review_npc_path}),
            "invalid_complete_campaign_paths",
            "All result files must be separate and outside the private project")
    require(all(not path.exists() for path in all_outputs),
            "output_exists", "Do not overwrite an existing game, sidecar or report")
    require((dialogues is None and question_inventory is None and
             no_interactive_questions) or
            (dialogues is not None and question_inventory is not None and
             not no_interactive_questions),
            "dialogue_declaration_missing",
            "Supply reviewed dialogue questions + inventory, OR explicitly declare none")
    _, state, index, analyses, story = load_project(root)
    require(story is not None, "story_missing", "Reviewed full book StoryPlan is required")
    source_report = validate_story(story, index, analyses)
    require(source_report["source_citations_verified"] and
            source_report["engine_blueprint_valid"],
            "campaign_source_invalid", "Original book review is not complete")
    overlay = read_json(overlay_path)
    proposal = read_json(extension_path)
    reviewer = read_json(review_path)
    npc_review_data = read_json(review_npc_path) if review_npc_path else None
    preliminary = audited_extension(root, overlay, proposal,
                                    npc_review=npc_review_data)
    require(preliminary.get("chapters_without_source_scenes") == [],
            "campaign_chapters_uncovered",
            "All original chapters need confirmed gameplay events")

    raw, disclosure = compile_extended_from_project(
        root, overlay, npc_review=npc_review_data, extension=proposal)
    _manifest, _bp, _prov = _inspect_v4(raw)
    blueprint = parse_json(_bp)
    provenance = _prov
    require(type(blueprint) is dict and type(provenance) is dict and
            blueprint.get("source_fingerprint") == index["source_fingerprint"] and
            provenance.get("source_fingerprint") == index["source_fingerprint"] and
            provenance.get("source_chapters_total") == index["chapter_count"],
            "campaign_native_source_mismatch",
            "Native v4 compilation changed the indexed source revision")
    editorial = review_complete_campaign(reviewer, blueprint, provenance,
                                         proposal)

    if no_interactive_questions:
        dialogue_gate = {
            "status": "author_declared_no_interactive_questions",
            "independently_verified_absence": False,
            "structured_npc_dialogue_is_separate": True,
        }
    else:
        from .dialogue_quality import audit_blueprint as dialogue_audit
        from .finalize import dialogue_inventory
        contract = read_json(outside_repository(dialogues))
        inventory = read_json(outside_repository(question_inventory))
        dialogue_gate = dialogue_inventory(blueprint, contract, inventory)
        result = dialogue_audit(blueprint, contract)
        require(result["warning_count"] == 0, "dialogue_warnings",
                "Source-reviewed interactive questions contain unresolved warnings")
        dialogue_gate["warning_count"] = 0

    native_report = replay_two_native_routes(raw, reviewer["routes"])
    native_check = verify_route_evidence(native_report, reviewer["routes"],
                                         blueprint, provenance, raw)
    summary = {
        "format": REPORT_FORMAT,
        "status": "native_multi_act_campaign_mechanically_verified",
        "game": str(output), "attribution": str(attribution),
        "report": str(report),
        "format_version": 4,
        "archive_sha256": digest(raw),
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "extension_sha256": digest(canonical(proposal)),
        "review_sha256": digest(canonical(reviewer)),
        "toolchain_sha256": state["toolchain_sha256"],
        "source_review": editorial,
        "reviewed_extension": {
            "format": proposal["format"],
            "act_count": preliminary.get("act_count"),
            "chapters_without_source_scenes": [],
        },
        "native_routes": native_check,
        "question_audit": dialogue_gate,
        "private_only": True,
        "literary_truth_attested": False,
        "editorial_review_is_author_declared": True,
        "device_playtest_completed": False,
        "automatic_ai_book_canon_verified": False,
        "user_ready": False,
    }
    written = []
    try:
        for path, data in ((attribution, disclosure), (output, raw),
                           (report, canonical(summary))):
            atomic_write(path, data)
            written.append(path)
    except BaseException:
        for path in written:
            path.unlink(missing_ok=True)
        raise
    return summary
