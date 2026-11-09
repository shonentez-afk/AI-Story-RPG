"""Private, portable, hash-checked ChatGPT Skill / BookWorld session archive.

The ZIP contains the source book (inside immutable project objects), private
AI replies, RPG editorial inputs, and optionally a compiled game. Never put
it in public GitHub, Actions, or the source checkout. This module does NOT
assert literary quality, user consent, device testing or BookWorld validity.
"""
from __future__ import annotations

from contextlib import ExitStack
import io
import os
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

from .common import (AuthoringError, atomic_write, canonical, digest, fields,
                     outside_repository, parse_json, read_bytes, require)
from .compatibility import toolchain_id
from . import project

FORMAT = "rpg_author_private_session_snapshot_v1"
MAX_ARCHIVE = 96 * 1024 * 1024
MAX_FILES = 4096
MAX_FILE = 24 * 1024 * 1024
GAME_PARTS = frozenset({
    "game.bworld", "game.attribution.json",
    "game.readiness.json", "game.finalization.json",
})
_SHA = re.compile(r"^[a-f0-9]{64}$")
_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def _private(path: Path) -> Path:
    raw = path.expanduser()
    require(not raw.is_symlink(), "snapshot_symlink",
            "Private directory or file must not be a symbolic link")
    return outside_repository(raw)


def _safe_part(name: str) -> bool:
    return (type(name) is str and bool(name) and
            len(name.encode("utf-8")) <= 255 and
            name not in (".", "..") and
            not any(c in name for c in ("/", "\\", "\x00", ":")))


def _safe_name(name: str) -> bool:
    parts = name.split("/")
    return (len(name.encode("utf-8")) <= 1024 and
            len(parts) >= 2 and all(_safe_part(p) for p in parts)
            and (parts[0] == "project" and
                 (parts[1:] == ["project.json"] or
                  (len(parts) == 3 and parts[1] == "objects" and
                   bool(_SHA.fullmatch(parts[2]))))
                 or parts[0] == "workdir" and len(parts) <= 7
                 or parts[0] == "game" and len(parts) == 2 and
                 parts[1] in GAME_PARTS))


def _read_directory(root: Path, prefix: str) -> dict[str, bytes]:
    require(root.is_dir(), "snapshot_missing_directory",
            "Private project/workdir must exist")
    result = {}
    for node in sorted(root.rglob("*")):
        require(not node.is_symlink(), "snapshot_symlink",
                "Refuse symbolic links anywhere in private session")
        if node.is_dir():
            continue
        require(node.is_file(), "snapshot_nonfile",
                "Only regular private session files are supported")
        name = prefix + "/" + node.relative_to(root).as_posix()
        require(_safe_name(name), "snapshot_unsafe_path",
                "Unexpected path in private project or workdir")
        data = read_bytes(node, MAX_FILE)
        result[name] = data
        require(len(result) <= MAX_FILES, "snapshot_too_many_files",
                "Private session contains too many files")
    return result


def _pack(meta: dict, members: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED,
                         allowZip64=False) as archive:
        for name, data in [("manifest.json", canonical(meta)), *sorted(members.items())]:
            info = zipfile.ZipInfo(name, date_time=_ZIP_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = (0o100600 << 16)
            archive.writestr(info, data)
    return buffer.getvalue()


def _targets(project_root: Path, workdir: Path, game_path: Path | None):
    root, work = _private(project_root), _private(workdir)
    game = _private(game_path) if game_path is not None else None
    targets = [root, work] + ([] if game is None else [game])
    require(all(t != other and t not in other.parents and
                other not in t.parents
                for i, t in enumerate(targets) for other in targets[i + 1:]),
            "snapshot_paths_overlap",
            "Private project, response inbox and game destinations must be separate")
    return root, work, game


def snapshot_private(project_root: Path, workdir: Path, output: Path,
                     *, game_path: Path | None = None) -> dict:
    root, work, game = _targets(project_root, workdir, game_path)
    destination = _private(output)
    require(destination.suffix.lower() == ".zip" and not destination.exists(),
            "snapshot_output_exists",
            "Use a new .zip name for each private session snapshot")
    require(all(destination != t and destination not in t.parents and
                t not in destination.parents for t in (root, work)),
            "snapshot_paths_overlap", "Snapshot must be outside source and workdir")
    _, state, index, _, _ = project.load_project(root)
    require(not (root / ".write-lock").exists(), "snapshot_project_busy",
            "Cannot copy a project during an active write")
    members = _read_directory(root, "project")
    members.update(_read_directory(work, "workdir"))
    require("project/project.json" in members and
            any(name.startswith("project/objects/") for name in members),
            "snapshot_project_missing", "Immutable project objects are missing")
    if game is not None:
        require(game.suffix.lower() == ".bworld" and game.is_file(),
                "snapshot_game_missing", "A completed game must be a local .bworld")
        members["game/game.bworld"] = read_bytes(game, MAX_FILE)
        for suffix in (".attribution.json", ".readiness.json",
                       ".finalization.json"):
            companion = game.with_suffix(suffix)
            if companion.exists():
                require(not companion.is_symlink() and companion.is_file(),
                        "snapshot_symlink", "Unsafe game companion path")
                members["game/game" + suffix] = read_bytes(companion, MAX_FILE)
    require(len(members) <= MAX_FILES and
            sum(len(data) for data in members.values()) <= MAX_ARCHIVE - 1024 * 1024,
            "snapshot_too_large", "Private session exceeds tested archive size")
    meta = {
        "format": FORMAT,
        "toolchain_sha256": state["toolchain_sha256"],
        "source_fingerprint": index["source_fingerprint"],
        "source_bytes_sha256": state["source_bytes_sha256"],
        "has_game": game is not None,
        "files": [
            {"path": name, "sha256": digest(members[name]),
             "size": len(members[name])}
            for name in sorted(members)
        ],
    }
    raw = _pack(meta, members)
    require(len(raw) <= MAX_ARCHIVE, "snapshot_too_large",
            "Private session ZIP exceeds tested size")
    atomic_write(destination, raw)
    return {
        "status": "private_session_snapshot_created",
        "path": str(destination), "sha256": digest(raw),
        "file_count": len(members), "has_game": game is not None,
        "source_fingerprint": index["source_fingerprint"],
        "toolchain_sha256": state["toolchain_sha256"],
        "user_ready": False, "literary_truth_attested": False,
        "device_playtest_completed": False,
        "contains_private_book_and_answers": True,
    }


def _decode_snapshot(path: Path) -> tuple[dict, dict[str, bytes], bytes]:
    raw = read_bytes(_private(path), MAX_ARCHIVE)
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            infos = archive.infolist()
            require(2 <= len(infos) <= MAX_FILES + 1,
                    "snapshot_invalid_archive", "Invalid snapshot member count")
            names = [item.filename for item in infos]
            require(names[0] == "manifest.json" and
                    len(set(names)) == len(names) and
                    all(item.compress_type == zipfile.ZIP_STORED and
                        not item.is_dir() and not item.flag_bits & 1 and
                        item.file_size <= MAX_FILE for item in infos),
                    "snapshot_invalid_archive", "Unsafe ZIP members")
            require(all(_safe_name(name) for name in names[1:]),
                    "snapshot_unsafe_path", "Unsafe private snapshot member path")
            require(names[1:] == sorted(names[1:]),
                    "snapshot_invalid_archive", "Snapshot members must be sorted")
            require(sum(info.file_size for info in infos) <= MAX_ARCHIVE,
                    "snapshot_too_large", "Snapshot contains too much data")
            metadata = archive.read("manifest.json")
            require(len(metadata) <= 1024 * 1024, "snapshot_invalid_archive",
                    "Manifest exceeds maximum size")
            meta = parse_json(metadata)
            fields(meta, {"format", "toolchain_sha256",
                          "source_fingerprint", "source_bytes_sha256",
                          "has_game", "files"}, "snapshot manifest")
            require(meta["format"] == FORMAT and
                    type(meta["has_game"]) is bool and
                    all(type(meta[k]) is str and
                        bool(_SHA.fullmatch(meta[k]))
                        for k in ("toolchain_sha256", "source_fingerprint",
                                  "source_bytes_sha256")) and
                    canonical(meta) == metadata and
                    type(meta["files"]) is list and
                    len(meta["files"]) == len(infos) - 1,
                    "snapshot_invalid_manifest", "Unrecognized snapshot manifest")
            entries = meta["files"]
            members = {}
            for expected, item in zip(entries, infos[1:]):
                fields(expected, {"path", "sha256", "size"}, "snapshot file")
                require(expected["path"] == item.filename and
                        type(expected["size"]) is int and
                        expected["size"] == item.file_size and
                        type(expected["sha256"]) is str and
                        bool(_SHA.fullmatch(expected["sha256"])),
                        "snapshot_invalid_manifest",
                        "Snapshot member metadata mismatch")
                data = archive.read(item)
                require(len(data) == expected["size"] and
                        digest(data) == expected["sha256"],
                        "snapshot_hash_mismatch", "Private file hash mismatch")
                members[item.filename] = data
    except (OSError, ValueError, zipfile.BadZipFile,
            zipfile.LargeZipFile, EOFError) as exc:
        if isinstance(exc, AuthoringError):
            raise
        raise AuthoringError("snapshot_invalid_archive",
                             "Unreadable private session ZIP") from exc
    require("project/project.json" in members and
            "project/objects/" + meta["source_bytes_sha256"] in members and
            any(name.startswith("workdir/") for name in members) and
            ("game/game.bworld" in members) == meta["has_game"],
            "snapshot_missing_files", "Source/project/workdir or game missing")
    require(raw == _pack(meta, members), "snapshot_noncanonical",
            "ZIP bytes or headers changed; portable snapshot must be canonical")
    return meta, members, raw


def verify_private_snapshot(input_path: Path) -> dict:
    meta, members, raw = _decode_snapshot(input_path)
    return {
        "status": "private_session_snapshot_verified",
        "sha256": digest(raw), "source_fingerprint": meta["source_fingerprint"],
        "toolchain_sha256": meta["toolchain_sha256"],
        "file_count": len(members), "has_game": meta["has_game"],
        "contains_private_book_and_answers": True,
        "compatibility_on_current_toolchain_not_claimed": True,
        "user_ready": False, "literary_truth_attested": False,
        "device_playtest_completed": False,
    }


def restore_private_snapshot(input_path: Path, project_root: Path,
                             workdir: Path, *, game_path: Path | None = None) -> dict:
    meta, members, raw = _decode_snapshot(input_path)
    root, work, game = _targets(project_root, workdir, game_path)
    require((game is not None) == meta["has_game"],
            "snapshot_game_destination_mismatch",
            "Supply --game exactly when the snapshot includes a compiled game")
    require(meta["toolchain_sha256"] == toolchain_id(),
            "snapshot_toolchain_changed",
            "Restore with the original pinned code; never rewrite toolchain SHA")
    destinations = {"project": root, "workdir": work}
    if game is not None:
        require(game.suffix.lower() == ".bworld", "snapshot_game_destination_mismatch",
                "Restored game must have a .bworld extension")
        destinations["game"] = game
    require(all(not p.exists() and not p.is_symlink() for p in destinations.values()),
            "snapshot_restore_exists", "Never overwrite an existing private project")
    if game is not None:
        for name in members:
            if name.startswith("game/") and name != "game/game.bworld":
                suffix = name[len("game/game"):]
                sibling = game.with_suffix(suffix)
                require(not sibling.exists() and not sibling.is_symlink(),
                        "snapshot_restore_exists", "Existing game sidecar cannot be overwritten")
    with ExitStack() as stack:
        staging = {}
        for key, target in destinations.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            require(not target.parent.is_symlink(), "snapshot_symlink",
                    "Destination parent must not be a symlink")
            temp = Path(stack.enter_context(
                tempfile.TemporaryDirectory(prefix=".rpg-restore-",
                                            dir=target.parent)))
            staging[key] = temp / "contents"
            if key != "game":
                staging[key].mkdir(mode=0o700)
        for name, data in members.items():
            role, relative = name.split("/", 1)
            if role == "game":
                if relative == "game.bworld":
                    staged = staging["game"]
                else:
                    staged = staging["game"].with_suffix(relative[len("game"):])
            else:
                staged = staging[role] / relative
            atomic_write(staged, data)
        # Every digest, immutable source chunk and original plan must pass
        # the actual pinned Python project validator BEFORE publishing files.
        _, state, index, _, _ = project.load_project(staging["project"])
        require(state["source_bytes_sha256"] == meta["source_bytes_sha256"] and
                state["toolchain_sha256"] == meta["toolchain_sha256"] and
                index["source_fingerprint"] == meta["source_fingerprint"],
                "snapshot_project_mismatch", "Restored project differs from manifest")
        published = []
        try:
            for key in ("project", "workdir"):
                target = destinations[key]
                require(not target.exists(), "snapshot_restore_exists",
                        "Destination appeared during restoration")
                os.replace(staging[key], target)
                published.append(target)
            if game is not None:
                for name in sorted(k for k in members if k.startswith("game/")):
                    # The archive's game/game.bworld is not a sidecar:
                    # map it to the caller's actual .bworld filename.
                    if name == "game/game.bworld":
                        target, staged = game, staging["game"]
                    else:
                        suffix = name[len("game/game"):]
                        target = game.with_suffix(suffix)
                        staged = staging["game"].with_suffix(suffix)
                    require(not target.exists(), "snapshot_restore_exists",
                            "Game destination appeared during restoration")
                    os.replace(staged, target)
                    published.append(target)
        except (OSError, AuthoringError):
            for published_path in reversed(published):
                if published_path.is_dir():
                    shutil.rmtree(published_path)
                else:
                    published_path.unlink(missing_ok=True)
            raise
    return {
        "status": "private_session_restored", "sha256": digest(raw),
        "project": str(root), "workdir": str(work),
        "game": str(game) if game is not None else None,
        "source_fingerprint": meta["source_fingerprint"],
        "resume_without_reanalyzing_book": True,
        "user_ready": False, "literary_truth_attested": False,
        "device_playtest_completed": False,
    }
