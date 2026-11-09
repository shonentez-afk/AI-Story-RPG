"""One resumable book -> ChatGPT Skill authoring -> native-v4 RPG workflow.

Strict separation:
 * The model proposes Russian summaries, plot, enrichment, acts and criticism.
 * Exact quotes, source references and all game rules belong to pinned code.
 * Native Dart finds REAL reachable endings and replays private SQLite saves.
 * Auto approval is EXPLICIT owner opt-in, never literary-canon attestation.
 * Private model responses and original FB2/TXT never enter public GitHub.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from .ai_provider import PrivateResponseInbox
from .common import (AuthoringError, ROOT, atomic_write, canonical, digest,
                     fields, outside_repository, parse_json, read_bytes,
                     read_json, require, utf16_len)
from .compatibility import check_contract
from . import project
from .complete_game import (REVIEW_FORMAT, prepare_full_review_template,
                            review_complete_campaign,
                            finalize_extended_campaign, replay_two_native_routes,
                            verify_route_evidence)
from .native_v4_bridge import (_MAX_V4_BYTES, _inspect_v4,
                               audited_extension, compile_extended_from_project)
from .rich_package import compile_rich_from_project
from .npc_skill import (
    prepare_npc_dossiers, prepare_npc_review,
    prepare_npc_v4_extension, preflight_pending_npc_enrichment,
    verify_source_dossiers,
)
from .validate import (assertion_registry, candidate_blueprint,
                       validate_analysis, validate_story)
from .v4_acts import FORMAT as ACT_FORMAT
from .long_npc import (
    prepare_long_npc_cast, verify_long_npc_cast, bind_long_npc_cast,
    check_native_long_npc_continuity,
)
from .long_book import (
    is_long_book, chapter_windows, review_chapter_window,
    verify_chapter_window, outline_context, check_long_backbone,
    verify_featured_gameplay, MAX_ANCHOR_GAP, MAX_LONG_CHAPTERS,
)

REVISION = "rpg_author_ai_book_pipeline_v1"
MAX_AUTO_REVISIONS = 3
_STAGE_FILES = {
    "npc_cast": "long_npc_cast.json",
    "npc_dossiers": "npc_dossiers.json",
    "enrichment": "enrichment.json",
    "npc_review": "npc_review.json",
    "extension": "multi_act.json",
    "literary_review": "literary_review.json",
}
_DART_ROUTE = ROOT / "tools/rpg_author/dart/discover_routes.dart"
_DART_CONFIG = ROOT / "tools/rpg_author/dart/.dart_tool/package_config.json"
_PARITY_CONFIG = ROOT / "tests/rpg_author/dart/.dart_tool/package_config.json"


def _fresh_or_existing(folder: Path, name: str, content: dict) -> dict:
    path = folder / name
    require(not path.is_symlink(), "unsafe_private_file", "Private stage path is a symlink")
    if path.exists():
        existing = read_json(path)
        require(canonical(existing) == canonical(content), "stage_changed",
                "Do not overwrite source-bound private author data; make a new project revision")
        return existing
    atomic_write(path, canonical(content))
    return content


def _ask_verified(provider, stage: str, payload: dict, normalizer) -> dict:
    feedback = ""
    for _ in range(MAX_AUTO_REVISIONS):
        proposed = provider.ask(stage, payload, feedback=feedback)
        try:
            require(type(proposed) is dict, "model_invalid_response",
                    "Model JSON must be an object")
            return normalizer(proposed)
        except (AuthoringError, KeyError, TypeError, ValueError) as exc:
            feedback = (exc.code if isinstance(exc, AuthoringError)
                        else "invalid_model_structure")
    raise AuthoringError("model_contract_rejected",
                         "AI did not satisfy verified " + stage +
                         " source and game contracts after bounded revision")


def _source_analysis(response: dict, chunk: dict, fingerprint: str,
                     ordinal: int) -> dict:
    fields(response, {"summary", "assertions", "unresolved"}, "AI source analysis")
    proposed = response["assertions"]
    require(type(proposed) is list and len(proposed) <= 32,
            "invalid_assertions", "Chunk has too many AI claims")
    citations = []
    seen = set()
    for index, claim in enumerate(proposed):
        fields(claim, {"statement", "kind", "quote"}, "source claim")
        quote = claim["quote"]
        require(type(quote) is str and 0 < utf16_len(quote) <= 180,
                "invalid_quote", "AI claim must cite exact bounded source text")
        require(chunk["text"].count(quote) == 1 and quote not in seen,
                "ambiguous_quote", "Source quotation missing or ambiguous")
        seen.add(quote)
        start = chunk["text"].index(quote)
        offset = chunk["start_utf16"] + utf16_len(chunk["text"][:start])
        citations.append({
            "id": "a_%05d_%02d" % (ordinal, index),
            "statement": claim["statement"],
            "kind": claim["kind"],
            "start_utf16": offset,
            "end_utf16": offset + utf16_len(quote),
            "quote": quote,
        })
    checked = {
        "format": "rpg_author_chunk_analysis_v1",
        "source_fingerprint": fingerprint,
        "chunk_id": chunk["id"], "source_sha256": chunk["sha256_text"],
        "summary": response["summary"],
        "assertions": citations,
        "unresolved": response["unresolved"],
    }
    return validate_analysis(checked, {"source_fingerprint": fingerprint,
                                       "chunks": [chunk]})


def _brief_evidence(index: dict, analyses: list[dict]) -> list[dict]:
    ordered = {a["chunk_id"]: a for a in analyses}
    return [{
        "chapter_index": chunk["chapter_index"],
        "chunk_id": chunk["id"],
        "summary": ordered[chunk["id"]]["summary"],
        "claims": [{"id": c["id"], "kind": c["kind"],
                    "statement": c["statement"], "quote": c["quote"]}
                   for c in ordered[chunk["id"]]["assertions"]],
        "unresolved": ordered[chunk["id"]]["unresolved"],
    } for chunk in index["chunks"]]


def _full_chapter_coverage(story: dict, index: dict,
                           analyses: list[dict] | None = None) -> None:
    """Small books are exhaustive; long books require a checked act backbone."""
    if is_long_book(index):
        require(analyses is not None, "long_book_missing_analyses",
                "A long source backbone must be bound to exact evidence")
        check_long_backbone(story, index, analyses)
        return
    chapters = {s["chapter_index"] for s in story["scenes"]
                if s["origin"] == "SOURCE_PASSAGE"}
    require(chapters == set(range(index["chapter_count"])),
            "bookwide_coverage_missing",
            "The AI plan omitted source-grounded events from some chapters")


def _derive_reviewed_extension(answer: dict, index: dict, story: dict,
                               enrichment: dict, base_blueprint: dict,
                               *, allow_machine_review: bool) -> dict:
    fields(answer, {"acts", "initial_state"}, "AI authored v4 acts")
    return {
        "format": ACT_FORMAT,
        "source_fingerprint": index["source_fingerprint"],
        "story_sha256": digest(canonical(story)),
        "enrichment_sha256": digest(canonical(enrichment)),
        "base_blueprint_sha256": digest(canonical(base_blueprint)),
        "editorial_review": {
            "user_confirmed": allow_machine_review,
            "transition_causality_reviewed": allow_machine_review,
            "character_continuity_reviewed": allow_machine_review,
            "literary_canon_verified": False,
        },
        "acts": answer["acts"],
        "initial_state": answer["initial_state"],
    }


def _source_chapter_proof_spec(provenance: dict) -> dict:
    """Bind playable chapter claims to SIGNED BookWorld provenance, not AI text.

    This describes what must be visited, NOT how RPG state should advance.
    A missing chapter in the archive is an immediate error, rather than a
    reason to silently omit the chapter from the native check.
    """
    require(type(provenance) is dict and
            type(provenance.get("source_chapters_total")) is int and
            1 <= provenance["source_chapters_total"] <= 10000 and
            type(provenance.get("scene_origins")) is list,
            "native_chapter_provenance_invalid",
            "Native BookWorld needs bounded original chapter provenance")
    total = provenance["source_chapters_total"]
    originals = []
    ids = set()
    covered = set()
    for entry in provenance["scene_origins"]:
        require(type(entry) is dict and
                type(entry.get("scene_id")) is str and
                type(entry.get("chapter_index")) is int and
                0 <= entry["chapter_index"] < total and
                entry.get("origin") in ("SOURCE_PASSAGE", "EXPLICIT_ADAPTATION"),
                "native_chapter_provenance_invalid",
                "Native scene provenance has invalid chapter/source fields")
        if entry["origin"] != "SOURCE_PASSAGE":
            continue
        # A chapter may not be 'covered' by a scene that only reuses a quote
        # from an EARLIER chapter. The signed v4 provenance retains exact
        # original chapter_index for every quote (not the claimed scene index).
        refs = entry.get("source_refs")
        require(type(refs) is list and any(
            type(ref) is dict and
            type(ref.get("chapter_index")) is int and
            ref["chapter_index"] == entry["chapter_index"]
            for ref in refs),
            "native_chapter_quote_unbound",
            "An original scene must cite actual text from its own book chapter")
        sid = entry["scene_id"]
        require(bool(sid) and sid not in ids,
                "native_chapter_provenance_invalid",
                "A checked original scene may appear only once")
        ids.add(sid)
        chapter = entry["chapter_index"]
        covered.add(chapter)
        originals.append({"scene_id": sid, "chapter_index": chapter})
    require(covered == set(range(total)),
            "native_chapter_provenance_incomplete",
            "Signed BookWorld itself omits original source chapters")
    return {"source_chapters_total": total,
            "source_passages": originals}


def _discover_real_endings(raw: bytes, *, strict_source_chapters: bool = False,
                           with_proof: bool = False) -> list[dict] | dict:
    """Discover two actual endings; optionally prove *ALL* source chapters playable.

    The source/chapter map comes from hash-bound v4 provenance, while the
    state reachability proof is executed only by the pinned Dart RPG API.
    A finite budget can reject a large valid game; never downgrade that
    unresolved result to PASS.
    """
    check_contract()
    package_config = (_DART_CONFIG if _DART_CONFIG.is_file()
                      else _PARITY_CONFIG)
    require(_DART_ROUTE.is_file() and package_config.is_file() and
            shutil.which("dart") is not None,
            "native_route_not_resolved",
            "Dart SDK and resolved rpg_api required for native route discovery")
    require(len(raw) <= _MAX_V4_BYTES, "native_route_invalid_input",
            "Oversized native v4 game")
    import base64
    request = {"format": "rpg_author_native_route_discovery_v1",
               "archive_b64": base64.b64encode(raw).decode("ascii")}
    source_spec = None
    if strict_source_chapters:
        _, _, provenance = _inspect_v4(raw)
        source_spec = _source_chapter_proof_spec(provenance)
        request.update(source_spec)
    with tempfile.TemporaryDirectory(prefix="ai_rpg_private_discover_") as tmp:
        try:
            response = subprocess.run(
                ["dart", "--packages=" + str(package_config), str(_DART_ROUTE)],
                cwd=tmp, input=json.dumps(request),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding="utf-8", timeout=600)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise AuthoringError("native_discovery_unavailable",
                                 "Native route discovery unavailable") from exc
    # Dart route exploration prints no book text or private NPC lines.
    # Preserve its bounded structural failure reason (missing chapter IDs,
    # game-state path, BFS limit) so ChatGPT can fix the *actual* cause
    # rather than repeatedly retry an opaque generic error.
    failure_detail = response.stderr.strip().replace("\n", " ")[-1000:]
    require(response.returncode == 0,
            ("native_source_chapters_unplayable" if strict_source_chapters
             else "native_route_not_found"),
            "Native RPG API could not prove two endings and all original "
            "chapters within bounded gameplay search. "
            + ("Dart reason: " + failure_detail if failure_detail
               else "No native diagnostic output"))
    reply = parse_json(response.stdout.encode("utf-8"))
    routes = reply.get("routes")
    require(reply.get("format") == "rpg_author_native_two_discovered_routes_v1"
            and reply.get("archive_sha256") == digest(raw)
            and reply.get("true_rpg_api") is True
            and type(routes) is list and len(routes) == 2
            and len({r["expected_ending_scene_id"] for r in routes}) == 2,
            "native_discovery_invalid",
            "Native route discovery is not bound to compiled BookWorld")
    if strict_source_chapters:
        count = source_spec["source_chapters_total"]
        require(reply.get("native_source_chapter_coverage") is True
                and reply.get("source_chapters_total") == count
                and reply.get("reachable_source_chapters") == list(range(count))
                and type(reply.get("reachable_original_scene_count")) is int
                and 1 <= reply["reachable_original_scene_count"] <=
                    len(source_spec["source_passages"])
                and reply.get("source_passage_scene_count") ==
                    len(source_spec["source_passages"]),
                "native_chapter_proof_invalid",
                "Native game did not independently attest all book chapters")
    if with_proof:
        return {key: value for key, value in reply.items()
                if key != "routes"} | {"routes": routes}
    return routes


def _independent_review(answer: dict, template: dict,
                        discovered: list[dict],
                        *, allow_machine_review: bool) -> dict:
    fields(answer, {"aspects", "issues", "scenes", "routes"},
           "independent AI literary review")
    require(type(answer["scenes"]) is list and
            type(answer["routes"]) is list and
            len(answer["scenes"]) == len(template["scenes"]) and
            len(answer["routes"]) == 2,
            "review_missing_scenes", "AI review omitted scenes or complete routes")
    by_scene = {s["scene_id"]: s for s in answer["scenes"]}
    require(len(by_scene) == len(answer["scenes"]) and
            set(by_scene) == {s["scene_id"] for s in template["scenes"]},
            "review_missing_scenes", "AI review has invented or repeated scenes")
    by_route = {r["id"]: r for r in answer["routes"]}
    require(len(by_route) == 2 and
            set(by_route) == {r["id"] for r in discovered},
            "review_routes_changed", "Literary critic rewrote native route identities")
    reviewed = dict(template)
    reviewed["aspects"] = answer["aspects"]
    reviewed["issues"] = answer["issues"]
    reviewed["scenes"] = []
    reviewed["routes"] = []
    for signed in template["scenes"]:
        suggestion = by_scene[signed["scene_id"]]
        fields(suggestion, {"scene_id", "verdict", "notes"}, "literary scene verdict")
        reviewed["scenes"].append({**signed,
                                   "verdict": suggestion["verdict"],
                                   "notes": suggestion["notes"]})
    for fixed in discovered:
        suggestion = by_route[fixed["id"]]
        fields(suggestion, {"id", "choice_ids", "expected_ending_scene_id",
                            "notes"}, "literary route verdict")
        require(all(suggestion[key] == fixed[key] for key in
                    ("id", "choice_ids", "expected_ending_scene_id")),
                "review_routes_changed",
                "AI review must NOT rewrite actually playable native routes")
        reviewed["routes"].append(suggestion)
    approved = (allow_machine_review and not reviewed["issues"] and
                type(reviewed["aspects"]) is dict and
                all(v == "pass" for v in reviewed["aspects"].values()) and
                all(s["verdict"] == "pass" for s in reviewed["scenes"]))
    reviewed["review_completed"] = approved
    reviewed["user_confirmed"] = approved
    return reviewed


def author_complete_book(*, project_root: Path, workdir: Path,
                         output: Path, provider, book: Path | None = None,
                         delegate_review: bool = False,
                         npc_review_path: Path | None = None) -> dict:
    """One resumable command; never overwrite signed source or accepted stages."""
    check_contract()
    root = outside_repository(project_root)
    private = outside_repository(workdir)
    output = outside_repository(output)
    require(root != private and root not in private.parents and
            private != root and private not in root.parents and
            output not in (root, private) and root not in output.parents and
            output.suffix.lower() == ".bworld",
            "invalid_authoring_paths",
            "Book checkpoints, AI stage outputs and game must be separate private paths")
    if book is not None:
        book = outside_repository(book)
    if npc_review_path is not None:
        npc_review_path = outside_repository(npc_review_path)
    native_npc_review = (read_json(npc_review_path)
                         if npc_review_path is not None else None)
    if not root.exists():
        require(book is not None, "missing_book",
                "A new private project needs an FB2/TXT book")
        project.init_project(root, book, 4096)
    if book is not None:
        _, state, _, _, _ = project.load_project(root)
        require(book.name == state["source_name"] and
                digest(read_bytes(book, 20 * 1024 * 1024)) ==
                state["source_bytes_sha256"],
                "book_changed",
                "Source book differs from the preserved private checkpoint")
    private.mkdir(parents=True, exist_ok=True, mode=0o700)
    _, state, idx, analyses, story = project.load_project(root)
    require(idx["chapter_count"] <= MAX_LONG_CHAPTERS,
            "long_book_requires_volumes",
            "Book exceeds the verified 384-chapter single-world limit. "
            "Do not call ChatGPT for this unsupported source or truncate it.")

    # All source chunks are checked individually and atomically checkpointed.
    chunk_order = {c["id"]: i for i, c in enumerate(idx["chunks"])}
    existing = {a["chunk_id"] for a in analyses}
    for chunk in idx["chunks"]:
        if chunk["id"] in existing:
            continue
        payload = {"title": idx["title"], "author": idx["author"],
                   "chapter_count": idx["chapter_count"], "chunk": chunk,
                   "instruction": "Cite unique exact contiguous source excerpts"}
        checked = _ask_verified(
            provider, "analysis", payload,
            lambda response: _source_analysis(
                response, chunk, idx["source_fingerprint"],
                chunk_order[chunk["id"]]))
        project.submit_analysis(root, checked)
    _, state, idx, analyses, story = project.load_project(root)
    evidence = _brief_evidence(idx, analyses)
    long_mode = is_long_book(idx)
    require(idx["chapter_count"] <= MAX_LONG_CHAPTERS,
            "long_book_requires_volumes",
            "Book exceeds the verified 384-chapter single-world limit. "
            "Do not analyze/truncate this source; design volumes separately.")
    long_outlines = []
    context = evidence
    backbone = None
    long_cast = None
    long_dossiers = None
    long_bindings = None
    if long_mode:
        # The Skill must read all source chunks, then author small, immutable
        # cited windows before a sparse v3 base StoryPlan is even proposed.
        # This avoids sending an entire novel in one private model request.
        specs = chapter_windows(idx, analyses)
        for spec in specs:
            name = "chapter_outline_" + spec["window_id"] + ".json"
            saved = private / name
            if saved.exists():
                checked = verify_chapter_window(read_json(saved), spec)
            else:
                checked = _ask_verified(
                    provider, "chapter_outline", spec,
                    lambda answer, spec=spec: review_chapter_window(answer, spec))
                _fresh_or_existing(private, name, checked)
            long_outlines.append(checked)
        context = outline_context(long_outlines, idx, analyses)
        # The literary skill reviews the WHOLE indexed book before
        # selecting major NPC identities. Later actors become mandatory
        # first-mention base anchors, never guessed new v4 NPCs.
        cast_file = private / _STAGE_FILES["npc_cast"]
        if cast_file.exists():
            long_cast = verify_long_npc_cast(
                read_json(cast_file), idx, analyses, long_outlines)
        else:
            long_cast = _ask_verified(
                provider, "npc_cast",
                {"book_title": idx["title"],
                 "source_fingerprint": idx["source_fingerprint"],
                 "chapter_count": idx["chapter_count"],
                 "reviewed_chapter_outlines": context,
                 "instruction": "Select up to 15 significant source-attested "
                                "characters from the ENTIRE book. Cite the "
                                "EARLIEST full-name textual mention in an "
                                "exact NARRATED featured assertion from that "
                                "same chapter. New NPC first encounters "
                                "become mandatory REAL StoryPlan anchors, "
                                "even between current sparse anchors. "
                                "Never invent or move an actor to an "
                                "earlier chapter; Python derives actor IDs. "
                                "If no major NPCs exist, explain why."},
                lambda answer: prepare_long_npc_cast(
                    answer, idx, analyses, long_outlines))
            _fresh_or_existing(private, _STAGE_FILES["npc_cast"], long_cast)
    if story is None:
        def checked_story(response):
            require(response.get("source_fingerprint", idx["source_fingerprint"])
                    == idx["source_fingerprint"], "wrong_source",
                    "Model story references another source")
            value = {"format": "rpg_author_story_plan_v1",
                     "source_fingerprint": idx["source_fingerprint"],
                     **{k: v for k, v in response.items()
                        if k not in ("format", "source_fingerprint")}}
            _full_chapter_coverage(value, idx, analyses)
            validate_story(value, idx, analyses)
            if long_mode:
                # Reject an invented or missing late first-contact anchor
                # BEFORE this model StoryPlan enters immutable checkpoint.
                bind_long_npc_cast(long_cast, value, idx, analyses)
            return value
        if long_mode:
            story_task = {
                "book_title": idx["title"],
                "chapter_count": idx["chapter_count"],
                "reviewed_chapter_outlines": context,
                "reviewed_major_npc_cast": long_cast["characters"],
                "story_mode": "source_locked_sparse_v3_backbone_for_v4_acts",
                "max_base_scenes": 192,
                "max_gap_between_original_anchors": MAX_ANCHOR_GAP,
                "instruction": "Create an actually playable sparse base "
                               "StoryPlan with 3..192 scenes, SOURCE_PASSAGE "
                               "anchors in chapter 0 and the LAST chapter, "
                               "direct original-source choice edges no more "
                               "than 96 chapters apart, two distinct endings "
                               "and an EXPLICIT_ADAPTATION. Each anchor "
                               "needs a NARRATED citation from its OWN chapter. "
                               "The upcoming v4 acts MUST fill ALL missing "
                               "chapters from the reviewed chapter outlines. "
                               "For EACH reviewed major NPC also add a "
                               "NONTERMINAL SOURCE_PASSAGE first-contact "
                               "base scene with exactly its original "
                               "first_chapter_index and "
                               "identity_assertion_id. Keep all those "
                               "anchors in chronological source-to-source "
                               "edges; use real choices for the native "
                               "NPC witness, memory and knowledge review. "
                               "Never fake a complete base plan.",
            }
        else:
            story_task = {
                "book_title": idx["title"],
                "chapter_count": idx["chapter_count"],
                "all_verified_evidence": context,
                "instruction": "Two distinct endings; no omitted chapter evidence",
            }
        story = _ask_verified(provider, "story", story_task, checked_story)
        project.submit_story(root, story)
    _full_chapter_coverage(story, idx, analyses)
    if long_mode:
        backbone = check_long_backbone(story, idx, analyses)
        _fresh_or_existing(private, "long_backbone.json", backbone)
        long_dossiers, long_bindings = bind_long_npc_cast(
            long_cast, story, idx, analyses)
        _fresh_or_existing(private, "long_npc_bound_anchors.json",
                           long_bindings)

    # A complete book first receives a literary NPC cast, with source-bound
    # permanent character IDs, BEFORE enrichment adds actor-scoped effects.
    # An already signed, externally reviewed native NPC v3 dossier remains
    # supported and is never silently replaced by a Skill proposal.
    dossiers = None
    if npc_review_path is None:
        dossiers_file = private / _STAGE_FILES["npc_dossiers"]
        if long_mode:
            # The literary identity is already source-checked in npc_cast.
            # Reuse the pinned SAME native dossier contract, not a second
            # character-ID or NPC rules implementation.
            dossiers = long_dossiers
            _fresh_or_existing(private, _STAGE_FILES["npc_dossiers"],
                               dossiers)
        elif dossiers_file.exists():
            dossiers = verify_source_dossiers(
                read_json(dossiers_file), idx, story, analyses)
        else:
            dossiers = _ask_verified(
                provider, "npc_dossiers",
                {"book_title": idx["title"], "story": story,
                 "all_verified_evidence": context,
                 "source_fingerprint": idx["source_fingerprint"],
                 "instruction": "Identify every major evidenced NPC, or "
                                "explain why none exist. Names must occur "
                                "in the exact NARRATED source assertion."},
                lambda response: prepare_npc_dossiers(
                    response, idx, story, analyses))
            _fresh_or_existing(private, _STAGE_FILES["npc_dossiers"],
                               dossiers)

    enrich_path = private / _STAGE_FILES["enrichment"]
    if enrich_path.exists():
        overlay = read_json(enrich_path)
        if dossiers is not None and dossiers["characters"]:
            preflight_pending_npc_enrichment(overlay, dossiers, idx, story)
        else:
            compile_rich_from_project(root, overlay,
                                      npc_review=native_npc_review)
    else:
        def checked_enrichment(response):
            require(response.get("source_fingerprint", idx["source_fingerprint"])
                    == idx["source_fingerprint"], "wrong_source",
                    "Enrichment references another book")
            value = {"format": "rpg_author_rich_enrichment_v1",
                     "source_fingerprint": idx["source_fingerprint"],
                     "story_sha256": digest(canonical(story)),
                     **{k: v for k, v in response.items()
                        if k not in ("format", "source_fingerprint", "story_sha256")}}
            require(response.get("story_sha256", value["story_sha256"])
                    == value["story_sha256"], "wrong_enrichment",
                    "Enrichment references another story revision")
            if dossiers is not None and dossiers["characters"]:
                preflight_pending_npc_enrichment(
                    value, dossiers, idx, story)
            else:
                compile_rich_from_project(root, value,
                                          npc_review=native_npc_review)
            return value
        overlay = _ask_verified(
            provider, "enrichment",
            {"story": story, "verified_evidence": context,
             "npc_dossiers": dossiers,
             "existing_native_npc_actors": (
                 [] if native_npc_review is None
                 else native_npc_review["actors"]),
             "instruction": "Typed rule IDs only; when NPC dossiers exist, "
                            "use their exact permanent character_id in "
                            "actor-scoped learn_fact and knows_fact rules. "
                            "No fabricated items, knowledge or identities."},
            checked_enrichment)
        _fresh_or_existing(private, _STAGE_FILES["enrichment"], overlay)

    # The original rich world is the source authority for NPC citations
    # and choices. The Skill supplies assertion_id, never a quote digest.
    if dossiers is not None and dossiers["characters"]:
        # Source witness graph must be composed BEFORE native enrichment:
        # the final overlay may already grant NPC-scoped facts, and compiling
        # it without the newly reviewed actor list would be correctly
        # rejected by the native RPG catalog validator.
        from .validate import candidate_blueprint
        from .legacy_package import _provenance
        bare_bp = candidate_blueprint(story, idx)
        bare_prov = _provenance(story, idx, analyses, bare_bp)
        npc_review_path = private / _STAGE_FILES["npc_review"]
        if npc_review_path.exists():
            native_npc_review = read_json(npc_review_path)
        else:
            def checked_npc(response):
                proposed = prepare_npc_review(
                    response, dossiers, idx, story, analyses, overlay,
                    bare_bp, bare_prov, user_confirmed=delegate_review)
                if delegate_review:
                    compile_rich_from_project(
                        root, overlay, npc_review=proposed)
                return proposed
            native_npc_review = _ask_verified(
                provider, "npc_review",
                {"book_title": idx["title"], "npc_dossiers": dossiers,
                 "verified_evidence": context, "story": story,
                 "enrichment": overlay, "base_blueprint": bare_bp,
                 "original_scene_origins": bare_prov["scene_origins"],
                 "long_book_first_npc_contacts": (
                     long_bindings["characters"] if long_mode else None),
                 "instruction": "For each long-book NPC provide the first "
                                "SOURCE_PASSAGE witness, knowledge grant "
                                "and memory at its exact anchored chapter. "
                                "Do not reveal future encounters. "
                                "Sign all NPC grants, witnesses, memories, "
                                "life events and dialogues with original "
                                "assertion_id. Native quote SHA and IDs "
                                "are computed by the verifier."},
                checked_npc)
            _fresh_or_existing(private, _STAGE_FILES["npc_review"],
                               native_npc_review)
        if (native_npc_review["npc_knowledge"]["user_confirmed"] is not True
                or native_npc_review["npc_social"]["user_confirmed"] is not True):
            return {
                "status": "needs_explicit_npc_review",
                "npc_dossiers": str(private / _STAGE_FILES["npc_dossiers"]),
                "npc_review": str(npc_review_path),
                "game_created": False, "user_ready": False,
                "skill_responses_this_run": provider.calls,
            }

    base_raw, _ = compile_rich_from_project(
        root, overlay, npc_review=native_npc_review)
    with zipfile.ZipFile(io.BytesIO(base_raw)) as archive:
        base_bp = parse_json(archive.read("scenario/blueprint.json"))
        base_prov = parse_json(archive.read("source/provenance.json"))

    ext_path = private / _STAGE_FILES["extension"]
    if ext_path.exists():
        extension = read_json(ext_path)
    else:
        def checked_extension(response):
            value = prepare_npc_v4_extension(
                response, idx, story, overlay, base_bp, base_prov,
                npc_present=native_npc_review is not None,
                user_confirmed=delegate_review)
            if delegate_review:
                audited_extension(
                    root, overlay, value, npc_review=native_npc_review)
            return value
        extension = _ask_verified(
            provider, "extension",
            {"book_title": idx["title"], "verified_evidence": context,
             "story": story, "enrichment": overlay,
             "base_blueprint": base_bp,
             "npc_dossiers": dossiers,
             "base_npc_knowledge": base_prov.get("npc_knowledge"),
             "base_npc_social": base_prov.get("npc_social"),
             "required_format": (
                 "rpg_author_v4_acts_v2_or_v3"
                 if native_npc_review is not None else ACT_FORMAT),
             "review_declared_by_user": delegate_review,
             "required_act_count_at_least": 2,
             "long_book_backbone": backbone,
             "long_book_first_npc_contacts": (
                 long_bindings["characters"] if long_mode else None),
             "long_book_reviewed_chapter_outlines": (
                 context if long_mode else None),
             "instruction": ("For sources with more than 192 chapters, "
                            "fill EVERY missing chapter in the confirmed "
                            "source-to-source anchor gaps with a distinct "
                            "NARRATED SOURCE_PASSAGE act event; include all "
                            "featured assertions from each outline exactly "
                            "once across base and v4 acts; at most 32 acts, "
                            "128 events per act and 1024 total native scenes. "
                            "Never silently discard a deferred assertion. "
                            "Use every inserted act on a direct base choice. "
                            "All acts must have a real branch and causal effect. "
                            if long_mode else "") +
                            "With NPC cast, prepare actor-scoped cross-act "
                            "source review using existing NPC Social v5. "
                            "Use v3 for full signed dialogue review and/or "
                            "a real source-acquired item with a typed transfer. "
                            "Keep unsupported dialogue or item lists empty; "
                            "never fabricate missing speech or ownership."},
            checked_extension)
        _fresh_or_existing(private, _STAGE_FILES["extension"], extension)

    if not extension["editorial_review"]["user_confirmed"]:
        return {"status": "needs_explicit_act_review",
                "extension": str(ext_path),
                "book_chapters_analyzed": idx["chapter_count"],
                "source_chunks_analyzed": len(idx["chunks"]),
                "game_created": False, "user_ready": False,
                "skill_responses_this_run": provider.calls}

    audited = audited_extension(
        root, overlay, extension, npc_review=native_npc_review)
    require(audited.get("act_count", 0) >= 2 and
            audited.get("chapters_without_source_scenes") == [],
            "incomplete_book_acts", "Bookwide story acts omit source chapters")
    raw, _ = compile_extended_from_project(
        root, overlay, npc_review=native_npc_review, extension=extension)
    _, bp_bytes, prov = _inspect_v4(raw)
    bp = parse_json(bp_bytes)
    long_event_coverage = None
    long_npc_continuity = None
    if long_mode:
        long_event_coverage = verify_featured_gameplay(
            idx, analyses, long_outlines, prov)
        _fresh_or_existing(private, "long_event_coverage.json",
                           long_event_coverage)
        long_npc_continuity = check_native_long_npc_continuity(
            long_cast, long_bindings, bp, prov)
        _fresh_or_existing(private, "long_npc_continuity.json",
                           long_npc_continuity)
    # The compiled ZIP can claim source events in every chapter while some
    # chapters are actually inaccessible via native game choices. Prove
    # *playable* chapter coverage through the real Dart/SQLite client.
    discovery = _discover_real_endings(
        raw, strict_source_chapters=True, with_proof=True)
    candidates = discovery["routes"]
    _fresh_or_existing(private, "native_chapter_playability.json", discovery)
    template = prepare_full_review_template(bp, prov, extension)
    review_path = private / _STAGE_FILES["literary_review"]

    if review_path.exists():
        review = read_json(review_path)
    elif not delegate_review:
        _fresh_or_existing(private, _STAGE_FILES["literary_review"], template)
        return {"status": "needs_independent_editorial_review",
                "review_template": str(review_path),
                "two_native_ending_routes_discovered": True,
                "all_book_chapters_playable_in_native_api": True,
                "native_playability_report": str(private / "native_chapter_playability.json"),
                "book_chapters_analyzed": idx["chapter_count"],
                "game_created": False, "user_ready": False,
                "skill_responses_this_run": provider.calls}
    else:
        def checked_review(response):
            value = _independent_review(
                response, template, candidates,
                allow_machine_review=delegate_review)
            require(value["review_completed"] is True, "literary_review_failed",
                    "Independent AI reviewer found unresolved evidence issues")
            review_complete_campaign(value, bp, prov, extension)
            # Do NOT replay both 200+-choice routes twice. The reviewed
            # routes were discovered through the genuine Dart RPG API and
            # cannot be altered by the literary reviewer. The one authoritative
            # finalizer below recompiles the same source-bound archive, then
            # runs replay_two_native_routes + verify_route_evidence and portable
            # SQLite checks BEFORE writing any finished game or readiness
            # receipt. A failed finalizer is NEVER a successful BookWorld.
            return value
        review = _ask_verified(
            provider, "literary_review",
            {"book_title": idx["title"], "all_verified_evidence": context,
             "source_locked_blueprint": bp,
             "scene_origins": prov["scene_origins"],
             "review_template": template,
             "native_discovered_routes": candidates,
             "long_book_reviewed_chapter_outlines": (
                 context if long_mode else None),
             "long_book_event_coverage": long_event_coverage,
             "long_book_npc_source_continuity": long_npc_continuity,
             "native_playable_chapter_proof": {
                 key: discovery[key] for key in (
                     "archive_sha256", "source_chapters_total",
                     "reachable_source_chapters",
                     "reachable_original_scene_count",
                     "native_source_chapter_coverage")},
             "explicit_machine_review_consent": delegate_review},
            checked_review)
        _fresh_or_existing(private, _STAGE_FILES["literary_review"], review)

    if not review["review_completed"] or not review["user_confirmed"]:
        return {"status": "needs_independent_editorial_review",
                "review_template": str(review_path),
                "game_created": False, "user_ready": False,
                "skill_responses_this_run": provider.calls}
    result = finalize_extended_campaign(
        root, enrich_path, ext_path, review_path, output,
        npc_review=npc_review_path, no_interactive_questions=True)
    require(result["native_routes"]["route_count"] == 2,
            "full_game_not_verified", "Two native routes are mandatory")
    # The pinned native BookWorld still contains historical external
    # authorship metadata. It is NOT evidence that ChatGPT generated a
    # session actually served by Z.ai. Add an explicit truthful private
    # receipt without changing the accepted native schema.
    # The production CLI ONLY constructs PrivateResponseInbox. The
    # integration suite injects a synthetic local answer object to exercise
    # the entire real Dart path; never describe that fake as ChatGPT.
    if type(provider) is PrivateResponseInbox:
        provider_name = "chatgpt_skill"
    else:
        require(type(provider).__module__.startswith("tests.rpg_author."),
                "skill_bridge_required",
                "Production authoring must be driven by ChatGPT Skill")
        provider_name = "synthetic_test_provider"
    declared_model = None
    receipt_path = private / "authoring_provenance.json"
    receipt = {
        "format": "rpg_author_ai_authorship_receipt_v1",
        "source_fingerprint": idx["source_fingerprint"],
        "bookworld_sha256": result["archive_sha256"],
        "authoring_provider": provider_name,
        "authoring_model_id": declared_model,
        "model_id_status": "not_attested",
        "private_skill_answer_origin_requires_human_attestation": True,
        "workflow": REVISION,
        "review_mode": ("explicitly_delegated_independent_ai_pass" if
                        delegate_review else "owner_confirmed_private_review"),
        "skill_responses_consumed_in_final_invocation": provider.calls,
        "book_content_in_receipt": False,
        "api_key_in_receipt": False,
        "native_package_model_label_is_not_author_proof": True,
        "semantic_review_certified": False,
        "device_playtest_completed": False,
    }
    _fresh_or_existing(private, receipt_path.name, receipt)
    result["authoring_workflow"] = REVISION
    result["native_all_source_chapters_playable"] = True
    result["long_book_event_coverage"] = long_event_coverage
    result["long_book_npc_source_continuity"] = long_npc_continuity
    result["long_book_deferred_events_remain_unverified"] = (
        long_event_coverage is not None and
        not long_event_coverage["all_source_events_adapted"])
    result["native_playable_chapter_count"] = len(
        discovery["reachable_source_chapters"])
    result["native_chapter_playability_report"] = str(
        private / "native_chapter_playability.json")
    result["authoring_provenance_receipt"] = str(receipt_path)
    result["skill_responses_this_run"] = provider.calls
    result["autonomous_review_requested"] = delegate_review
    result["user_ready"] = False
    return result
