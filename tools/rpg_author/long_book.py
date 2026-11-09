"""Bounded whole-book planning above the legacy 192-scene StoryPlan limit.

No second game engine: the short StoryPlan remains a verified, playable
narrative backbone; source-locked v4 acts add missing chapter scenes, and Dart
LocalRpgGameApi must reach every chapter. This first edition supports up to 384
chapters, 1024 native scenes and bounded 512-choice route checks. Larger
sources must be handled as separately designed volumes, never silently cut.
All text, citations, proposals and checkpoints stay in the private workspace.
"""
from __future__ import annotations

from .common import (AuthoringError, canonical, digest, fields, identifier,
                     require, string, string_list)
from .validate import assertion_registry

FIRST_LONG_CHAPTER = 193
MAX_LONG_CHAPTERS = 384
WINDOW_CHAPTERS = 8
MAX_WINDOW_BYTES = 360 * 1024
MAX_ANCHOR_GAP = 96
MAX_SELECTED_PER_CHAPTER = 3


def is_long_book(index: dict) -> bool:
    return index["chapter_count"] > 192


def _supported(index: dict) -> None:
    count = index["chapter_count"]
    require(type(count) is int and
            FIRST_LONG_CHAPTER <= count <= MAX_LONG_CHAPTERS,
            "long_book_requires_volumes",
            "The current verified single-BookWorld author supports 193..384 "
            "source chapters. Do not truncate larger books or bypass native "
            "1024-scene / 512-step limits: plan verified volumes separately.")


def chapter_windows(index: dict, analyses: list[dict]) -> list[dict]:
    """Build bounded, independently cited ChatGPT jobs from EVERY source chunk."""
    _supported(index)
    by_chunk = {row["chunk_id"]: row for row in analyses}
    require(len(by_chunk) == len(index["chunks"]) and
            set(by_chunk) == {c["id"] for c in index["chunks"]},
            "analysis_incomplete", "Every indexed source chunk must be reviewed")
    # This validates the stored quote ranges and prevents duplicate claims.
    assertion_registry(analyses, index)
    chapters = [{"chapter_index": i, "chunks": []}
                for i in range(index["chapter_count"])]
    for chunk in index["chunks"]:
        analysis = by_chunk[chunk["id"]]
        chapters[chunk["chapter_index"]]["chunks"].append({
            "chunk_id": chunk["id"], "summary": analysis["summary"],
            "claims": [
                {"assertion_id": c["id"], "kind": c["kind"],
                 "statement": c["statement"], "quote": c["quote"]}
                for c in analysis["assertions"]
            ],
            "unresolved": analysis["unresolved"],
        })
    for chapter in chapters:
        require(any(c["kind"] == "NARRATED"
                    for ch in chapter["chunks"] for c in ch["claims"]),
                "long_book_missing_narrated_evidence",
                "A book chapter with no original narrated evidence cannot "
                "be turned into a proven SOURCE_PASSAGE chapter scene: " +
                str(chapter["chapter_index"]))
    windows = []
    begin = 0
    while begin < len(chapters):
        # 8 chapters is the *maximum*, not a fixed compulsory block. Dense
        # novel chapters can contain many verified source assertions. Shrink
        # the request to as few as one chapter instead of discarding evidence
        # or spending ChatGPT context on an oversized private JSON request.
        end = min(begin + WINDOW_CHAPTERS, len(chapters))
        while True:
            proposal = {
                "window_id": f"w{begin:04d}_{end - 1:04d}",
                "source_fingerprint": index["source_fingerprint"],
                "chapter_start": begin,
                "chapter_end": end - 1,
                "chapters": chapters[begin:end],
            }
            if len(canonical(proposal)) <= MAX_WINDOW_BYTES:
                break
            if end == begin + 1:
                raise AuthoringError(
                    "long_book_single_chapter_over_budget",
                    "One dense chapter exceeds the tested private Skill "
                    "window limit. Requires a reviewed chunk-level "
                    "synthesis, not evidence truncation.")
            end -= 1
        windows.append(proposal)
        begin = end
    return windows


def review_chapter_window(answer: dict, request: dict) -> dict:
    """Reject missing, invented, duplicated or silently dropped narrated facts."""
    fields(answer, {"window_id", "chapters"}, "chapter-window response")
    require(answer["window_id"] == request["window_id"] and
            type(answer["chapters"]) is list and
            len(answer["chapters"]) == len(request["chapters"]),
            "long_book_outline_changed",
            "Skill outline must exactly cover its source-bound chapter window")
    chapters = []
    for proposal, source in zip(answer["chapters"], request["chapters"]):
        fields(proposal, {
            "chapter_index", "summary", "featured_assertion_ids",
            "deferred_assertion_ids", "deferred_reason",
        }, "chapter-window literary outline")
        index = source["chapter_index"]
        require(type(proposal["chapter_index"]) is int and
                proposal["chapter_index"] == index,
                "long_book_outline_changed",
                "Chapter outline reordered or invented a book chapter")
        string(proposal["summary"], f"chapter {index} summary", 1500)
        featured = proposal["featured_assertion_ids"]
        deferred = proposal["deferred_assertion_ids"]
        string_list(featured, f"chapter {index} featured evidence",
                    MAX_SELECTED_PER_CHAPTER)
        string_list(deferred, f"chapter {index} deferred evidence", 12000)
        all_narrated = {
            c["assertion_id"] for chunk in source["chunks"]
            for c in chunk["claims"] if c["kind"] == "NARRATED"
        }
        require(bool(featured) and
                not (set(featured) & set(deferred)) and
                set(featured) | set(deferred) == all_narrated,
                "long_book_source_events_dropped",
                "Every original NARRATED event in each chapter must be "
                "explicitly featured or declared deferred for later review")
        for aid in (*featured, *deferred):
            identifier(aid, "book chapter evidence")
        reason = proposal["deferred_reason"]
        if deferred:
            string(reason, f"chapter {index} deferred reason", 1200)
            require(len(reason.strip()) >= 20,
                    "long_book_unreviewed_deferred_event",
                    "Deferred original source events require a real explanation")
        else:
            require(reason is None,
                    "long_book_unreviewed_deferred_event",
                    "Do not claim deferrals that did not occur")
        chapters.append({
            "chapter_index": index,
            "summary": proposal["summary"],
            "featured_assertion_ids": list(featured),
            "deferred_assertion_ids": list(deferred),
            "deferred_reason": reason,
        })
    return {
        "format": "rpg_author_long_chapter_outline_v1",
        "source_fingerprint": request["source_fingerprint"],
        "window_id": request["window_id"],
        "source_evidence_sha256": digest(canonical(request)),
        "chapters": chapters,
    }


def verify_chapter_window(record: dict, request: dict) -> dict:
    fields(record, {"format", "source_fingerprint", "window_id",
                    "source_evidence_sha256", "chapters"},
           "stored chapter-window review")
    require(record["format"] == "rpg_author_long_chapter_outline_v1" and
            record["source_fingerprint"] == request["source_fingerprint"] and
            record["source_evidence_sha256"] == digest(canonical(request)),
            "long_book_outline_stale",
            "Private chapter outline belongs to another book/evidence revision")
    checked = review_chapter_window({
        "window_id": record["window_id"], "chapters": record["chapters"],
    }, request)
    require(canonical(checked) == canonical(record),
            "long_book_outline_stale",
            "Tampered or changed chapter review must not be silently accepted")
    return checked


def outline_context(outlines: list[dict], index: dict,
                    analyses: list[dict]) -> list[dict]:
    """Compact verified source context; no 200-chapter mega-request to a Skill."""
    _supported(index)
    registry = assertion_registry(analyses, index)
    chapters = [chapter for outline in outlines
                for chapter in outline["chapters"]]
    require([c["chapter_index"] for c in chapters] ==
            list(range(index["chapter_count"])),
            "long_book_outline_incomplete",
            "The full book outline omitted or reordered source chapters")
    context = []
    for chapter in chapters:
        featured = []
        for aid in chapter["featured_assertion_ids"]:
            claim = registry[aid]
            require(claim["chunk"]["chapter_index"] == chapter["chapter_index"] and
                    claim["assertion"]["kind"] == "NARRATED",
                    "long_book_outline_stale",
                    "Selected event changed source chapter or citation class")
            featured.append({
                "assertion_id": aid,
                "statement": claim["assertion"]["statement"],
                "quote": claim["assertion"]["quote"],
            })
        context.append({
            "chapter_index": chapter["chapter_index"],
            "summary": chapter["summary"],
            "featured": featured,
            "deferred_source_events": len(chapter["deferred_assertion_ids"]),
            "deferred_reason": chapter["deferred_reason"],
        })
    return context


def check_long_backbone(story: dict, index: dict,
                        analyses: list[dict]) -> dict:
    """Prove sparse original anchors can receive the omitted v4 act ranges."""
    _supported(index)
    registry = assertion_registry(analyses, index)
    sources = {}
    ids = {scene["id"]: scene for scene in story["scenes"]}
    for row in story["scenes"]:
        if row["origin"] != "SOURCE_PASSAGE":
            continue
        chapter = row["chapter_index"]
        require(any(aid in registry and
                    registry[aid]["chunk"]["chapter_index"] == chapter and
                    registry[aid]["assertion"]["kind"] == "NARRATED"
                    for aid in row["assertion_ids"]),
                "long_book_anchor_quote_missing",
                "Every original backbone scene must cite a NARRATED event "
                "from its own source chapter")
        sources.setdefault(chapter, []).append(row)
    anchors = sorted(sources)
    require(anchors and anchors[0] == 0 and
            anchors[-1] == index["chapter_count"] - 1,
            "long_book_anchor_bounds",
            "Narrative backbone must retain real source events in the "
            "first and last chapters")
    gaps = []
    for before, after in zip(anchors, anchors[1:]):
        require(after - before <= MAX_ANCHOR_GAP,
                "long_book_anchor_gap",
                "A missing book chapter interval exceeds the 96-chapter "
                "verified v4 act-window limit")
        if after - before > 1:
            require(any(c["next_scene_id"] in ids and
                        ids[c["next_scene_id"]]["origin"] == "SOURCE_PASSAGE" and
                        ids[c["next_scene_id"]]["chapter_index"] == after
                        for scene in sources[before]
                        for c in scene["choices"]),
                    "long_book_anchor_not_insertable",
                    "Missing source chapters require a real original "
                    "choice spanning two adjacent original anchors; "
                    "an act can be inserted only into that verified edge")
            gaps.append({
                "after_chapter": before, "before_chapter": after,
                "missing_chapters": after - before - 1,
            })
    return {
        "format": "rpg_author_long_backbone_v1",
        "source_chapters_total": index["chapter_count"],
        "base_scene_count": len(story["scenes"]),
        "original_anchor_chapters": anchors,
        "max_verified_gap": MAX_ANCHOR_GAP,
        "insertable_source_gaps": gaps,
        "missing_chapters_to_fill": sum(g["missing_chapters"] for g in gaps),
        "base_plan_is_full_book": False,
        "requires_native_extended_chapter_coverage": True,
    }


def verify_featured_gameplay(index: dict, analyses: list[dict],
                             outlines: list[dict], provenance: dict) -> dict:
    """Every selected event must be represented by native SOURCE_PASSAGE proof.

    All other NARRATED events are tracked as explicit deferred citations,
    not misleadingly certified as adapted gameplay.
    """
    context = outline_context(outlines, index, analyses)
    registry = assertion_registry(analyses, index)
    expected = {}
    for chapter in context:
        for record in chapter["featured"]:
            aid = record["assertion_id"]
            chunk = registry[aid]["chunk"]
            proof = digest(b"claim:" + canonical({
                "source_fingerprint": index["source_fingerprint"],
                "chunk_id": chunk["id"], "assertion_id": aid,
            }))[:32]
            expected[proof] = chapter["chapter_index"]
    represented = set()
    for scene in provenance.get("scene_origins", []):
        if scene.get("origin") != "SOURCE_PASSAGE":
            continue
        for claim in scene.get("assertion_ids", []):
            if claim in expected and expected[claim] == scene["chapter_index"]:
                represented.add(claim)
    missing = set(expected) - represented
    require(not missing, "long_book_featured_event_missing",
            "Native BookWorld omits source-reviewed featured events from "
            "some chapters; scene-count coverage alone is insufficient")
    deferred = sum(c["deferred_source_events"] for c in context)
    return {
        "format": "rpg_author_long_event_coverage_v1",
        "source_chapters_total": index["chapter_count"],
        "featured_source_events_in_game": len(expected),
        "featured_source_events_missing": 0,
        "deferred_original_events_not_attested_as_playable": deferred,
        "all_source_events_adapted": deferred == 0,
        "complete_literary_canon_verified": False,
    }
