"""One PRIVATE source -> real native BookWorld v5 path, with no second RPG engine.

E6r integration: the previously separate literal-v5 and source-causal-v2
authoring steps now share one immutable project, one private Skill inbox, one
verified native checkout, and one final output. User approval is explicit.
Older v4 author-book and private saves are deliberately not migrated.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from .common import (AuthoringError, ROOT, atomic_write, digest, outside_repository,
                     parse_json, read_bytes, require)
from .compatibility import check_native_contract
from .source_adapter import MAX_SOURCE_BYTES
from .source_causal_v2 import _read_native_base, author_causal_v5
from . import project


def _native_cli(root: Path, *arguments: str) -> dict:
    require(shutil.which("dart") is not None, "native_dart_missing",
            "Dart SDK is needed for authentic BookWorld v5 compilation")
    app = root / "apps/rpg_cli"
    require((app / "bin/rpg_cli.dart").is_file(), "native_cli_missing",
            "The pinned native rpg_api CLI is not available")
    try:
        completed = subprocess.run(
            ["dart", "run", "bin/rpg_cli.dart", *arguments],
            cwd=app, text=True, encoding="utf-8",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AuthoringError("native_cli_unavailable",
                             "The verified native Dart command did not finish") from exc
    require(completed.returncode == 0, "native_cli_rejected",
            "Native Dart refused the private source or consent: " +
            completed.stderr[-1000:])
    result = parse_json(completed.stdout.encode("utf-8"))
    require(type(result) is dict, "native_cli_invalid_receipt",
            "Native Dart returned an invalid receipt")
    return result


def _literal_world(native_root: Path, source: Path, index: dict,
                   workdir: Path) -> Path:
    literal = workdir / "literal-source-v5.bworld"
    require(not literal.is_symlink(), "unsafe_private_file",
            "Do not follow links to private BookWorld files")
    if literal.exists():
        _read_native_base(literal, index)
        return literal
    preview = _native_cli(native_root, "prepare-literal-canon-v5",
                          "--book", str(source))
    require(preview.get("can_compile_literal_canon") is True and
            preview.get("source_fingerprint") == index["source_fingerprint"] and
            type(preview.get("approval_digest")) is str,
            "native_literal_unready",
            "Unindexed book media or source mismatch; no invented CANON")
    # Native CLI writes only to this fresh, private temporary destination.
    # The source-locked v5 manifest is verified BEFORE publishing the cache.
    with tempfile.TemporaryDirectory(prefix="rpg_native_v5_", dir=workdir) as tmp:
        candidate = Path(tmp) / "literal.bworld"
        receipt = _native_cli(native_root, "compile-literal-canon-v5",
                              "--book", str(source),
                              "--approved-digest", preview["approval_digest"],
                              "--user-confirmed", "true",
                              "--output", str(candidate))
        require(receipt.get("status") == "private_literal_v5_compiled" and
                receipt.get("source_fingerprint") == index["source_fingerprint"] and
                receipt.get("world_hash") == digest(read_bytes(candidate, 20 * 1024 * 1024)),
                "native_literal_receipt_changed",
                "Real Dart literal compiler returned an inconsistent receipt")
        _read_native_base(candidate, index)
        atomic_write(literal, read_bytes(candidate, 20 * 1024 * 1024))
    return literal


def author_game_v5(*, book: Path, project_root: Path, workdir: Path,
                   output: Path, provider, user_confirmed: bool = False,
                   native_root: Path | None = None,
                   literal_only: bool = False) -> dict:
    """Single resumable Skill-first command for a *reviewed* native v5 world.

    - Unapproved: creates an immutable private source checkpoint, no game.
    - Approved: native literal-v5 -> ChatGPT source-wide NPC/causal Skill
      requests -> independently reviewed source-causal-v2 -> actual native
      compiler. Missing Skill responses are recoverable, never faked.
    - Explicit literal_only: permit honest book-faithful reading WITHOUT
      pretending that a book has NPCs, causality or RPG alternatives.
    """
    require(type(user_confirmed) is bool and type(literal_only) is bool,
            "invalid_consent", "Consent must be explicit and boolean")
    book = outside_repository(book)
    project_root, workdir, output = (outside_repository(project_root),
                                     outside_repository(workdir),
                                     outside_repository(output))
    root = Path(native_root).expanduser().resolve() if native_root else ROOT
    check_native_contract(root)
    require(output.suffix.lower() == ".bworld" and not output.exists()
            and not output.is_symlink(), "unsafe_private_output",
            "Final private BookWorld destination must be new")
    require(project_root != workdir and
            project_root not in workdir.parents and
            workdir not in project_root.parents and
            output != project_root and output != workdir and
            project_root not in output.parents,
            "unsafe_private_paths", "Keep immutable source, Skill replies and game separate")
    require(not workdir.is_symlink(), "unsafe_private_paths",
            "Private Skill working directory must not be a symbolic link")
    raw = read_bytes(book, MAX_SOURCE_BYTES)
    if not project_root.exists():
        project.init_project(project_root, book)
    _, state, index, _, _ = project.load_project(project_root)
    require(state["source_name"] == book.name and
            state["source_bytes_sha256"] == digest(raw),
            "source_changed", "Resume requires the exact same source book bytes")
    if not user_confirmed:
        return {
            "status": "needs_explicit_owner_approval",
            "source_fingerprint": index["source_fingerprint"],
            "requested_mode": "literal_only_v5" if literal_only else "reviewed_causal_v5",
            "game_created": False,
            "external_model_required": False,
            "literary_canon_proven": False,
        }
    workdir.mkdir(parents=True, exist_ok=True, mode=0o700)
    literal = _literal_world(root, book, index, workdir)
    if literal_only:
        # This is a literal reading route, not a fictional two-ending RPG.
        payload = read_bytes(literal, 20 * 1024 * 1024)
        atomic_write(output, payload)
        return {
            "status": "private_source_literal_v5_compiled",
            "source_fingerprint": index["source_fingerprint"],
            "world_hash": digest(payload),
            "source_literal_only": True,
            "npc_causal_review_completed": False,
            "game_created": True,
            "literary_canon_proven": False,
        }
    review = workdir / "source-causal-review-v2.json"
    from .source_causal_v2 import author_causal_v5
    result = author_causal_v5(
        project_root=project_root, base_world=literal, workdir=workdir,
        output=review, provider=provider, user_confirmed=True,
        native_root=root, world_output=output)
    result["unified_native_v5_workflow"] = True
    result["source_literal_verified"] = True
    result["legacy_v4_saved_worlds_untouched"] = True
    result["cross_version_npc_ids_implicitly_migrated"] = False
    return result
