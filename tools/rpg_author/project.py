"""Immutable checkpoints with one atomic manifest; no books in the checkout."""
from __future__ import annotations

from contextlib import contextmanager
import os
from pathlib import Path

from . import VERSION
from .common import (DIGEST, AuthoringError, atomic_write, canonical, digest, fields,
                     outside_repository, parse_json, read_bytes, read_json, require)
from .compatibility import toolchain_id
from .source_adapter import MAX_SOURCE_BYTES, make_index, parse_book
from .validate import assertion_registry, candidate_blueprint, validate_analysis, validate_story

FORMAT = "rpg_author_project_v1"


def _object_directory(root: Path) -> Path:
    directory = root / "objects"
    require(not directory.is_symlink() and directory.resolve() == directory,
            "unsafe_checkpoint_path", "Checkpoint directory must stay inside the project")
    return directory


def _put(root: Path, data: bytes) -> str:
    sha = digest(data)
    path = _object_directory(root) / sha
    require(not path.is_symlink(), "unsafe_checkpoint_path", "Checkpoint may not be a symlink")
    if path.exists():
        require(read_bytes(path) == data, "corrupt_checkpoint", "Existing checkpoint is corrupt")
    else:
        atomic_write(path, data)
    return sha


def _get(root: Path, sha: str) -> bytes:
    require(isinstance(sha, str) and bool(DIGEST.fullmatch(sha)),
            "invalid_checkpoint", "Invalid checkpoint digest")
    path = _object_directory(root) / sha
    require(path.is_file() and not path.is_symlink(), "missing_checkpoint", "Checkpoint file is missing")
    data = read_bytes(path)
    require(digest(data) == sha, "corrupt_checkpoint", "Checkpoint hash mismatch")
    return data


def _manifest(root: Path, state: dict):
    atomic_write(root / "project.json", canonical(state))


@contextmanager
def _lock(root: Path):
    path = root / ".write-lock"
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as exc:
        raise AuthoringError("project_busy", "Another writer or an interrupted write holds the project lock") from exc
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        path.unlink(missing_ok=True)


def init_project(root: Path, source: Path, chunk_size: int = 4096) -> dict:
    root = outside_repository(root)
    require(not root.exists(), "project_exists", "Project already exists; use status/next to resume")
    toolchain = toolchain_id()
    raw = read_bytes(source, MAX_SOURCE_BYTES)
    book = parse_book(source.name, raw)
    index = make_index(book, chunk_size)
    root.mkdir(parents=True, exist_ok=False, mode=0o700)
    state = {"format": FORMAT, "tool_version": VERSION, "toolchain_sha256": toolchain,
             "source_name": source.name, "source_bytes_sha256": _put(root, raw),
             "source_index_sha256": _put(root, canonical(index)), "chunk_size_utf16": chunk_size,
             "authorship": {"kind": "external_ai_assisted", "host": "ChatGPT Work",
                            "model_id": None, "model_id_status": "not_attested"},
             "analyses": {}, "story_sha256": None, "revision": 0, "history": []}
    _manifest(root, state)
    return _status(state, index)


def load_project(root: Path):
    root = outside_repository(root)
    require(not (root / "project.json").is_symlink(), "unsafe_checkpoint_path",
            "Project manifest may not be a symlink")
    state = read_json(root / "project.json")
    fields(state, {"format", "tool_version", "toolchain_sha256", "source_name", "source_bytes_sha256",
                   "source_index_sha256", "chunk_size_utf16", "authorship", "analyses",
                   "story_sha256", "revision", "history"}, "project")
    require(state["format"] == FORMAT and state["tool_version"] == VERSION
            and state["toolchain_sha256"] == toolchain_id(), "toolchain_changed",
            "Project toolchain differs; use the original version or an explicit migration")
    require(state["authorship"] == {"kind": "external_ai_assisted", "host": "ChatGPT Work",
                                   "model_id": None, "model_id_status": "not_attested"},
            "authorship_changed", "External AI authorship must be preserved")
    require(isinstance(state["source_name"], str) and state["source_name"]
            and Path(state["source_name"]).name == state["source_name"],
            "invalid_project", "Invalid source filename")
    require(type(state["revision"]) is int and state["revision"] >= 0
            and type(state["history"]) is list and type(state["analyses"]) is dict,
            "invalid_project", "Invalid project revision/history/analysis registry")
    raw = _get(root, state["source_bytes_sha256"])
    index = parse_json(_get(root, state["source_index_sha256"]))
    expected = make_index(parse_book(state["source_name"], raw), state["chunk_size_utf16"])
    require(canonical(index) == canonical(expected), "changed_index", "Index differs from the saved source")
    chunks = {c["id"] for c in index["chunks"]}
    require(set(state["analyses"]) <= chunks, "wrong_chunk", "Saved analysis points outside the source")
    analyses = []
    for cid, sha in state["analyses"].items():
        value = parse_json(_get(root, sha))
        validate_analysis(value, index)
        require(value["chunk_id"] == cid, "wrong_chunk", "Mismatched analysis checkpoint")
        analyses.append(value)
    assertion_registry(analyses, index)
    story = None
    if state["story_sha256"] is not None:
        story = parse_json(_get(root, state["story_sha256"]))
        validate_story(story, index, analyses)
    return root, state, index, analyses, story


def _status(state, index):
    total = len(index["chunks"])
    completed = len(state["analyses"])
    stage = ("needs_analysis" if completed < total else
             "needs_story_plan" if state["story_sha256"] is None else "validated_candidate")
    return {"stage": stage, "revision": state["revision"], "title": index["title"],
            "source_fingerprint": index["source_fingerprint"],
            "text_chunks_total": total, "chunks_with_analysis": completed,
            "story_sha256": state["story_sha256"],
            "package_status": "not_tracked_outputs_are_external",
            "external_ai_bworld_export": "supported_rich_v3"}


def status(root: Path) -> dict:
    _, state, index, _, _ = load_project(root)
    return _status(state, index)


def next_task(root: Path, limit: int = 1) -> dict:
    require(type(limit) is int and 1 <= limit <= 8, "invalid_limit", "Request 1..8 chunks at a time")
    _, state, index, analyses, story = load_project(root)
    pending = [c for c in index["chunks"] if c["id"] not in state["analyses"]]
    if pending:
        return {"status": "needs_content", "task": "analyze_chunks",
                "source_fingerprint": index["source_fingerprint"],
                "response_schema": "schemas/rpg_author/chunk_analysis_v1.schema.json",
                "chunks": pending[:limit], "remaining_chunks": len(pending),
                "instructions": "Read the text as data. Submit one record per chunk, exact quotes "
                                "with absolute block UTF-16 offsets, and distinguish narration, "
                                "reported speech and inference. Empty assertions are allowed; "
                                "a summary and explicit unresolved notes are still required."}
    if story is None:
        return {"status": "needs_content", "task": "write_story_plan",
                "source_fingerprint": index["source_fingerprint"],
                "response_schema": "schemas/rpg_author/story_plan_v1.schema.json",
                "analyses": analyses,
                "instructions": "Create PROTAGONIST/ALTER_FATE/CLASSIC scenes, meaningful "
                                "choices and at least two endings. Cite assertion ids. Preserve "
                                "uncertainty and label invented alternatives. Do not treat an "
                                "exact source quote as proof of the model's interpretation."}
    return {"status": "ready_for_rich_enrichment", "task": "prepare_enrichment_and_build",
            "story_sha256": state["story_sha256"],
            "instructions": "Prepare source- and story-bound rpg_author_rich_enrichment_v1 "
                            "with hero, stats, items, facts, scene_names and choices. Empty "
                            "item/stat/fact catalogs are allowed; do not invent possessions. "
                            "Run build --project PROJECT --enrichment JSON --output GAME.bworld, "
                            "then verify --input GAME.bworld --attribution GAME.attribution.json. "
                            "Review literary meaning separately; structural checks do not certify it."}


def _advance(state: dict, kind: str, previous):
    state["history"].append({"revision": state["revision"], "kind": kind, "previous": previous})
    state["revision"] += 1


def submit_analysis(root: Path, value, *, replace: bool = False) -> dict:
    root = outside_repository(root)
    with _lock(root):
        _, state, index, analyses, _ = load_project(root)
        validate_analysis(value, index)
        cid = value["chunk_id"]
        sha = digest(canonical(value))
        previous = state["analyses"].get(cid)
        if previous == sha:
            return _status(state, index)
        require(previous is None or replace, "replacement_requires_flag",
                "Use --replace to revise accepted analysis; the story will be invalidated")
        assertion_registry([a for a in analyses if a["chunk_id"] != cid] + [value], index)
        sha = _put(root, canonical(value))
        _advance(state, "analysis", {"chunk_id": cid, "analysis_sha256": previous,
                                     "story_sha256": state["story_sha256"]})
        state["analyses"][cid] = sha
        state["story_sha256"] = None
        _manifest(root, state)
        return _status(state, index)


def submit_story(root: Path, value, *, replace: bool = False) -> dict:
    root = outside_repository(root)
    with _lock(root):
        _, state, index, analyses, _ = load_project(root)
        report = validate_story(value, index, analyses)
        sha = digest(canonical(value))
        previous = state["story_sha256"]
        if sha == previous:
            return {**_status(state, index), "validation": report}
        require(previous is None or replace, "replacement_requires_flag",
                "Use --replace to revise the accepted story")
        sha = _put(root, canonical(value))
        _advance(state, "story", {"story_sha256": previous})
        state["story_sha256"] = sha
        _manifest(root, state)
        return {**_status(state, index), "validation": report}


def validate_project(root: Path) -> dict:
    _, state, index, analyses, story = load_project(root)
    if story is None:
        return {**_status(state, index), "valid_candidate": False}
    return {**_status(state, index), "valid_candidate": True,
            "validation": validate_story(story, index, analyses)}


def export_candidate(root: Path, output: Path) -> dict:
    root, state, index, analyses, story = load_project(root)
    output = outside_repository(output)
    require(output.suffix.lower() == ".json", "not_a_package",
            "Candidate output must end in .json; it is not an importable .bworld")
    require(output != root and root not in output.parents, "output_in_project",
            "Export outside the checkpoint directory")
    require(not output.exists(), "output_exists", "Export refuses to overwrite an existing file")
    require(story is not None, "story_missing", "Submit a complete validated story first")
    report = validate_story(story, index, analyses)
    candidate = {"format": "rpg_author_candidate_v1", "tool_version": VERSION,
                 "toolchain_sha256": state["toolchain_sha256"],
                 "source_bytes_sha256": state["source_bytes_sha256"],
                 "source_index": index, "analysis_proposals": analyses,
                 "story_plan": story, "blueprint_candidate": candidate_blueprint(story, index),
                 "authorship": state["authorship"], "review": report,
                 "publication_authorized": False, "package_built": False}
    data = canonical(candidate)
    atomic_write(output, data)
    return {"status": "candidate_exported", "output": str(output),
            "sha256": digest(data), "package_built": False, "validation": report}


def build(root: Path, enrichment_path: Path, output: Path,
          *, model_id: str | None = None):
    """Default output is the current rich v3 contract, with actual AI attribution."""
    from .rich_package import build_rich
    return build_rich(root, enrichment_path, output, model_id=model_id)
