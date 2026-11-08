"""Source-locked opt-in rich-v4 packaging via the ACTUAL standalone Dart compiler.

No Python fork of the v4 causal rules or guessed initial-state citations.
The E6g literary/gameplay review remains the source; Dart builds/validates v4.
Until an explicitly reviewed v4 StoryPlan contract exists, this path retains
E6f authoring's v3 scene/flag/item limits, even though the resulting archive
has native format_version=4. Private sources and intermediate JSON live only
inside an isolated temporary directory, never the repository or GitHub CI.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

from .common import (AuthoringError, ROOT, atomic_write, canonical, digest,
                     outside_repository, parse_json, read_bytes, read_json, require)
from .compatibility import check_contract
from .project import _get, load_project
from .rich_package import _attribution, compile_rich_from_project

_NATIVE_PROBE = ROOT / "tests/rpg_author/dart"
_PACKAGE_CONFIG = _NATIVE_PROBE / ".dart_tool/package_config.json"
_AUTHOR_PACKAGE_CONFIG = ROOT / "packages/story_authoring/.dart_tool/package_config.json"
_MEMBER_NAMES = {
    "manifest.json", "scenario/blueprint.json", "source/provenance.json",
    "world.sqlite",
}
_MAX_V4_BYTES = 20 * 1024 * 1024


def _native(operation: str, *args: Path) -> dict:
    """Invoke only the pinned, platform-independent native story_authoring CLI."""
    package_config = (_AUTHOR_PACKAGE_CONFIG if _AUTHOR_PACKAGE_CONFIG.is_file()
                      else _PACKAGE_CONFIG)
    require(package_config.is_file(), "native_dart_not_resolved",
            "Run 'dart pub get' in packages/story_authoring "
            "(or tests/rpg_author/dart) before native v4 packaging")
    require(shutil.which("dart") is not None, "native_dart_unavailable",
            "Dart SDK is required for native v4 build/verification")
    require(operation in ("build-extended", "verify-world"), "invalid_native_operation",
            "Unsupported native compiler command")
    # Native BookImporter derives TXT title from the *filename argument*.
    # Its independent source fingerprint must exactly match the Python
    # project. Passing '/tmp/private/book.txt' would turn the temporary path
    # into a false book title, so invoke Dart from the private book directory
    # with 'book.txt', never weaken the title or provenance gate.
    package_dir = ROOT / "packages/story_authoring"
    script = package_dir / "bin/author_book.dart"
    require(script.is_file() and bool(args), "native_dart_unavailable",
            "Missing pinned standalone authoring command")
    workdir = args[0].parent.resolve()
    require(all(p.parent.resolve() == workdir and p.is_absolute() for p in args),
            "invalid_native_paths", "All native compiler files must share one private directory")
    command = ["dart", f"--packages={package_config}", str(script),
               operation, *(p.name for p in args)]
    try:
        result = subprocess.run(command, cwd=workdir,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, encoding="utf-8", timeout=180)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AuthoringError("native_v4_unavailable",
                             "The native Dart v4 compiler could not run") from error
    require(result.returncode == 0, "native_v4_rejected",
            "The native source-bound v4 compiler rejected this package: "
            + result.stderr.strip()[-1200:])
    try:
        response = json.loads(result.stdout.strip())
    except (ValueError, TypeError) as error:
        raise AuthoringError("native_v4_invalid_response",
                             "Native compiler did not return validated JSON") from error
    require(type(response) is dict, "native_v4_invalid_response",
            "Native compiler reply must be an object")
    return response


def _inspect_v4(raw: bytes) -> tuple[dict, bytes, dict]:
    """Fail closed on archive structure and sidecar data before Dart verification."""
    require(len(raw) <= _MAX_V4_BYTES, "extended_package_oversize",
            "Native v4 package exceeds external-author memory bound")
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as package:
            info = package.infolist()
            require(len(info) == 4 and {i.filename for i in info} == _MEMBER_NAMES
                    and all(i.compress_type == zipfile.ZIP_STORED for i in info),
                    "invalid_extended_archive", "Expected four uncompressed ZIP entries")
            manifest = parse_json(package.read("manifest.json"))
            blueprint = package.read("scenario/blueprint.json")
            provenance = parse_json(package.read("source/provenance.json"))
            require(type(manifest) is dict and type(provenance) is dict,
                    "invalid_extended_archive", "Missing manifest/provenance")
            require(manifest.get("format_version") == 4
                    and manifest.get("build_status") == "private_extended_structural"
                    and manifest.get("rights_status") == "private_use_only"
                    and manifest.get("model_provenance") == provenance.get("model_provenance")
                    and manifest.get("blueprint_sha256") == digest(blueprint),
                    "invalid_extended_archive",
                    "Native v4 manifest does not match its source/blueprint")
            for name in ("scenario/blueprint.json", "source/provenance.json",
                         "world.sqlite"):
                data = package.read(name)
                require(manifest["hashes"].get(name) == digest(data)
                        and manifest["sizes"].get(name) == len(data),
                        "invalid_extended_archive",
                        "Native v4 hashes or sizes are inconsistent")
            return manifest, blueprint, provenance
    except (OSError, zipfile.BadZipFile, KeyError, TypeError, ValueError) as error:
        raise AuthoringError("invalid_extended_archive",
                             "Native v4 archive failed structural validation") from error


def compile_extended_from_project(root: Path, enrichment: dict,
                                  *, model_id: str | None = None,
                                  npc_review: dict | None = None) -> tuple[bytes, bytes]:
    """Produce only native-verified v4; no implicit v3 -> v4 schema migration."""
    check_contract()
    root = outside_repository(root)
    source_root, state, index, _, _ = load_project(root)
    require(state["chunk_size_utf16"] == 4096, "native_chunk_size_mismatch",
            "Native author_book.dart uses 4096 UTF-16 source chunks; "
            "rebuild the private author project with the same source index")
    # The independent v3 authoring/evidence/gameplay proof runs FIRST. It
    # refuses future/unreviewed rules and never invents v4 initial possessions.
    checked_v3, _ = compile_rich_from_project(
        root, enrichment, model_id=model_id, npc_review=npc_review)
    with zipfile.ZipFile(io.BytesIO(checked_v3)) as existing:
        blueprint = parse_json(existing.read("scenario/blueprint.json"))
        provenance = parse_json(existing.read("source/provenance.json"))
    require(type(blueprint) is dict and type(provenance) is dict,
            "invalid_reviewed_authoring", "Missing reviewed v3 blueprint")
    # Only v3-reviewed initial state is representable here. Rich-v4
    # initial_state_review, tick, and >192 scenes remain a separate feature.
    require(not provenance.get("initial_state_review"),
            "unsupported_extended_initial_state",
            "Initial-state v4 review is not supported by this bridge")
    original = _get(source_root, state["source_bytes_sha256"])
    with tempfile.TemporaryDirectory(prefix="ai_rpg_native_v4_") as temp:
        private = Path(temp)
        source = private / state["source_name"]
        reviewed = private / "source_reviewed.json"
        out = private / "native_v4.bworld"
        atomic_write(source, original)
        atomic_write(reviewed, canonical({"blueprint": blueprint,
                                          "provenance": provenance}))
        native = _native("build-extended", source, reviewed, out)
        require(native.get("format_version") == 4
                and native.get("result") == "PRIVATE_EXTENDED_V4_VERIFIED"
                and native.get("source_fingerprint") == index["source_fingerprint"]
                and native.get("requires_network") is False
                and native.get("can_distribute_publicly") is False,
                "native_v4_invalid_response",
                "Native compiler did not verify private v4")
        raw = read_bytes(out, _MAX_V4_BYTES)
    manifest, payload, origin = _inspect_v4(raw)
    require(manifest["source_fingerprint"] == index["source_fingerprint"]
            and native.get("archive_sha256") == digest(raw),
            "native_v4_mismatch", "Native v4 world is from another book or revision")
    disclosure = canonical(_attribution(raw, digest(payload), origin,
                                        format_version=4))
    return raw, disclosure


def build_extended(root: Path, enrichment_path: Path, output: Path,
                   *, model_id: str | None = None,
                   npc_review_path: Path | None = None) -> dict:
    root = outside_repository(root)
    output = outside_repository(output)
    require(output.suffix.lower() == ".bworld" and output != root
            and root not in output.parents, "invalid_output",
            "Native v4 output must be a .bworld file outside its project")
    sidecar = output.with_suffix(".attribution.json")
    require(not output.exists() and not sidecar.exists(), "output_exists",
            "Never overwrite a world or its attribution")
    raw, disclosure = compile_extended_from_project(
        root, read_json(outside_repository(enrichment_path)),
        model_id=model_id,
        npc_review=read_json(outside_repository(npc_review_path))
        if npc_review_path is not None else None)
    atomic_write(sidecar, disclosure)
    try:
        atomic_write(output, raw)
    except BaseException:
        sidecar.unlink(missing_ok=True)
        raise
    return {
        "status": "private_extended_v4_built",
        "format_version": 4,
        "package": str(output), "attribution": str(sidecar),
        "archive_sha256": digest(raw), "private_only": True,
        "authoring_bounds": "E6g v3-reviewed StoryPlan; no enlarged scene or initial-state authoring",
        "device_playtest_completed": False,
    }


def verify_extended_bundle(package: Path, attribution: Path) -> dict:
    check_contract()
    package = outside_repository(package)
    attribution = outside_repository(attribution)
    raw = read_bytes(package, _MAX_V4_BYTES)
    manifest, blueprint, provenance = _inspect_v4(raw)
    expected = _attribution(raw, digest(blueprint), provenance, format_version=4)
    actual = read_json(attribution)
    require(type(actual) is dict and canonical(actual) == canonical(expected),
            "attribution_mismatch",
            "External v4 attribution sidecar does not match the archive")
    checked = _native("verify-world", package)
    require(checked.get("archive_sha256") == digest(raw)
            and checked.get("source_fingerprint") == manifest["source_fingerprint"],
            "native_v4_mismatch", "Native importer rejected this world")
    return {
        "status": "private_extended_v4_structurally_verified",
        "archive_sha256": digest(raw), "format_version": 4,
        "attribution_matches_archive": True,
        "native_dart_verified": True,
        "authorship_cryptographically_attested": False,
        "semantic_review_completed": False,
        "device_playtest_completed": False,
    }
