"""E6e: fail-closed finalization for one private, source-bound BookWorld.

A completed structural pipeline is NOT proof of literary truth or a device test.
No input files are modified, and generated artifacts stay outside the checkout.
"""
from __future__ import annotations

from pathlib import Path

from .common import (AuthoringError, atomic_write, canonical, digest,
                     outside_repository, read_json, require)
from .compatibility import check_contract
from .project import load_project
from .validate import validate_story
from .rich_package import build_rich, verify_rich_bundle
from .gameplay_quality import audit_project, audit_archive
from .dialogue_quality import audit_blueprint as dialogue_blueprint_audit
from .dialogue_quality import audit_archive as dialogue_archive_audit
from .rich_package import _enrich
from .validate import candidate_blueprint

ASPECTS = frozenset(("motivation", "knowledge", "items", "causality",
                     "chronology", "endings"))
REVIEW_FORMAT = "ai_story_literary_review_v1"
INVENTORY_FORMAT = "ai_story_question_inventory_v1"


def review_coverage(story: dict, enrichment: dict, review: dict) -> dict:
    """Validate a separately authored review REPORT, never literary truth."""
    require(type(review) is dict and set(review) == {
        "format", "source_fingerprint", "story_sha256", "enrichment_sha256",
        "review_method", "review_completed", "aspects", "issues",
        "scenes", "endings"}, "literary_review_incomplete",
        "Literary review fields missing or extra")
    require(story.get("format") == "rpg_author_story_plan_v1" and
            review["format"] == REVIEW_FORMAT and
            review["source_fingerprint"] == story["source_fingerprint"] and
            review["story_sha256"] == digest(canonical(story)) and
            enrichment.get("source_fingerprint") == story["source_fingerprint"] and
            enrichment.get("story_sha256") == digest(canonical(story)) and
            review["enrichment_sha256"] == digest(canonical(enrichment)),
            "literary_review_stale", "Review must match exact source, story and enrichment")
    require(review["review_method"] == "independent_ai_pass" and
            review["review_completed"] is True and
            type(review["aspects"]) is dict and
            set(review["aspects"]) == ASPECTS and
            all(review["aspects"][aspect] == "pass" for aspect in ASPECTS) and
            review["issues"] == [],
            "literary_review_incomplete", "Independent literary review is incomplete or has issues")
    scenes = story["scenes"]
    ids = {s["id"] for s in scenes}
    endings = {s["id"] for s in scenes if s["terminal"] is True}
    require(len(ids) == len(scenes) and len(endings) >= 2,
            "literary_review_incomplete", "Source story needs distinct reviewed endings")
    reports = review["scenes"]
    require(type(reports) is list and len(reports) == len(scenes),
            "literary_review_incomplete", "Every scene needs a separate review")
    seen = set()
    for row in reports:
        require(type(row) is dict and set(row) == {
            "scene_id", "verdict", "notes", "source_assertion_ids"},
            "literary_review_incomplete", "Scene review fields missing or extra")
        sid = row["scene_id"]
        require(sid in ids and sid not in seen and row["verdict"] == "pass" and
                type(row["notes"]) is str and len(row["notes"].strip()) >= 15 and
                type(row["source_assertion_ids"]) is list,
                "literary_review_incomplete", "Scene review not complete")
        claims = row["source_assertion_ids"]
        expected = next(s for s in scenes if s["id"] == sid).get("assertion_ids", [])
        require(len(claims) == len(set(claims)) and set(claims) == set(expected),
                "literary_review_incomplete", "Scene claims do not match story citations")
        seen.add(sid)
    require(seen == ids and type(review["endings"]) is list and
            len(review["endings"]) == len(endings),
            "literary_review_incomplete", "Missing scenes or ending assessments")
    observed_endings = set()
    for row in review["endings"]:
        require(type(row) is dict and set(row) == {"scene_id", "verdict", "notes"} and
                row["scene_id"] in endings and row["scene_id"] not in observed_endings and
                row["verdict"] == "pass" and type(row["notes"]) is str and
                len(row["notes"].strip()) >= 15,
                "literary_review_incomplete", "Ending assessment is missing")
        observed_endings.add(row["scene_id"])
    require(observed_endings == endings,
            "literary_review_incomplete", "Every ending must be reviewed")
    return {"status": "review_report_complete_not_literary_certified",
            "reviewed_scenes": len(seen), "reviewed_endings": len(endings),
            "literary_truth_attested": False}


def dialogue_inventory(blueprint: dict, contract: dict,
                       inventory: dict) -> dict:
    """Two independently supplied inventories must agree, including source ID."""
    require(type(inventory) is dict and set(inventory) == {
        "format", "source_fingerprint", "question_ids"},
        "question_inventory_invalid", "Provide exact source-bound question inventory")
    questions = inventory["question_ids"]
    require(inventory["format"] == INVENTORY_FORMAT and
            inventory["source_fingerprint"] == blueprint["source_fingerprint"] and
            type(questions) is list and 1 <= len(questions) <= 48 and
            all(type(s) is str for s in questions) and
            len(questions) == len(set(questions)),
            "question_inventory_invalid", "Bad question IDs or source fingerprint")
    present = {c["id"] for s in blueprint["scenes"] for c in s["choices"]}
    require(set(questions) <= present,
            "question_inventory_invalid", "Question inventory refers to missing choices")
    declared = [row["question_id"] for row in contract["topics"]]
    require(len(declared) == len(set(declared)) and set(questions) == set(declared),
            "dialogue_coverage_incomplete",
            "Topics must cover the exact independently supplied question inventory")
    return {"status": "author_declared_inventory_matches_topics",
            "question_count": len(questions),
            "automated_discovery_of_unlisted_questions": False}


def finalize(project: Path, enrichment: Path, review: Path, output: Path,
             *, dialogues: Path | None = None,
             question_inventory_path: Path | None = None,
             no_interactive_questions: bool = False,
             report_path: Path | None = None) -> dict:
    """All applicable checks must pass before creating a user-facing archive."""
    root = outside_repository(project)
    output = outside_repository(output)
    report = outside_repository(report_path or output.with_suffix(".finalization.json"))
    sidecar = output.with_suffix(".attribution.json")
    require(output.suffix == ".bworld" and report not in (output, sidecar) and
            report != root and root not in report.parents and
            root not in output.parents,
            "invalid_finalization_paths", "Output/report must be separate private files")
    require(not output.exists() and not sidecar.exists() and not report.exists(),
            "output_exists", "Finalization never overwrites existing outputs")
    require((dialogues is None) != (not no_interactive_questions),
            "dialogue_declaration_missing",
            "Specify --dialogues and --question-inventory, or --no-interactive-questions")
    require((dialogues is None) == (question_inventory_path is None),
            "dialogue_declaration_missing",
            "The dialogue contract and independent question inventory are both required")

    summary = {
        "format": "ai_story_external_finalization_e6e_v1",
        "status": "rejected",
        "game": str(output),
        "attribution": str(sidecar),
        "report": str(report),
        "inputs_sha256": {},
        "stages": {},
        "literary_truth_attested": False,
        "device_playtest_completed": False,
        "user_ready": False,
    }
    try:
        check_contract()
        _, state, index, analyses, story = load_project(root)
        require(story is not None, "story_missing", "Accepted StoryPlan required")
        validation = validate_story(story, index, analyses)
        summary["stages"]["source_validation"] = {
            "source_citations_verified": validation["source_citations_verified"],
            "engine_blueprint_valid": validation["engine_blueprint_valid"]}
        require(validation["source_citations_verified"] and validation["engine_blueprint_valid"],
                "source_validation_failed", "StoryPlan source validation failed")
        overlay = read_json(enrichment)
        review_data = read_json(review)
        summary["inputs_sha256"] = {
            "source_fingerprint": index["source_fingerprint"],
            "story_sha256": digest(canonical(story)),
            "enrichment_sha256": digest(canonical(overlay)),
            "review_sha256": digest(canonical(review_data)),
            "toolchain_sha256": state["toolchain_sha256"],
        }
        summary["stages"]["literary_review"] = review_coverage(story, overlay, review_data)

        game = audit_project(root, enrichment)
        summary["stages"]["gameplay"] = {
            "warning_count": game["warning_count"], "status": game["status"]}
        require(game["warning_count"] == 0, "gameplay_warnings",
                "Resolve all gameplay warnings before finalization")

        blueprint, _ = _enrich(candidate_blueprint(story, index), story, index, overlay)
        if no_interactive_questions:
            summary["stages"]["dialogues"] = {
                "status": "not_applicable_author_declared_no_interactive_questions",
                "independently_verified_absence": False}
        else:
            contract = read_json(dialogues)
            inv = read_json(question_inventory_path)
            summary["stages"]["dialogue_inventory"] = dialogue_inventory(blueprint, contract, inv)
            checked = dialogue_blueprint_audit(blueprint, contract)
            summary["stages"]["dialogues"] = {
                "status": checked["status"], "warning_count": checked["warning_count"]}
            require(checked["warning_count"] == 0, "dialogue_warnings",
                    "Resolve all dialogue warnings before finalization")

        built = build_rich(root, enrichment, output)
        summary["archive_sha256"] = built["archive_sha256"]
        verified = verify_rich_bundle(output, sidecar)
        require(verified["archive_sha256"] == built["archive_sha256"],
                "archive_changed", "Built archive differs from verified archive")
        post_game = audit_archive(output, sidecar)
        require(post_game["warning_count"] == 0, "gameplay_warnings",
                "Archive-level gameplay warnings")
        if dialogues is not None:
            post_dialogue = dialogue_archive_audit(output, dialogues, sidecar)
            require(post_dialogue["warning_count"] == 0, "dialogue_warnings",
                    "Archive-level dialogue warnings")
        summary["stages"]["archive"] = {
            "status": "verified", "archive_sha256": verified["archive_sha256"],
            "source_index_verified": True}
        summary["status"] = "structurally_complete_literary_report_checked_device_untested"
        # Structural and author-reported literary checks alone cannot assert USER_READY.
    except (AuthoringError, OSError, KeyError, TypeError, ValueError) as exc:
        summary["failure"] = {
            "code": exc.code if isinstance(exc, AuthoringError) else "finalization_error",
            "reason": str(exc)}
    atomic_write(report, canonical(summary))
    return summary
