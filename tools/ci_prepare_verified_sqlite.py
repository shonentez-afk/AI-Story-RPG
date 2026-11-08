#!/usr/bin/env python3
"""Prepare a release-pinned SQLite source for Linux/Android CI.

Do not disable sqlite3.dart native-library hash checking. Instead build
SQLite from the official, independently SHA3-verified amalgamation in the
normal sqlite3 Dart native build hook. This script edits ONLY checked-out
CI workspace pubspec files and never commits a generated source or binary.

Invocation:
  python3 tools/ci_prepare_verified_sqlite.py \
    --project apps/story_reader

The same relative workspace source path works for apps/* and packages/*.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import pathlib
import time
import urllib.request
import zipfile

RELEASE = "3540100"
URL = f"https://www.sqlite.org/2026/sqlite-amalgamation-{RELEASE}.zip"
# Official sqlite.org/download.html (SQLite 3.54.1) SHA3-256 for ZIP.
EXPECTED_ZIP_SHA3_256 = (
    "92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30"
)
MAX_ZIP_BYTES = 7 * 1024 * 1024
MAX_SOURCE_BYTES = 16 * 1024 * 1024
HOOKS = """
hooks:
  user_defines:
    sqlite3:
      source:
        android: source
        linux: source
        default: sqlite3
      path: ../../artifacts/sqlite/sqlite3.c
"""


def verified_source(raw_zip: bytes, expected: str = EXPECTED_ZIP_SHA3_256) -> bytes:
    """Extract only a pinned SQLite amalgamation, no arbitrary ZIP members."""
    if not (1000 < len(raw_zip) < MAX_ZIP_BYTES):
        raise ValueError("SQLite download size is invalid")
    digest = hashlib.sha3_256(raw_zip).hexdigest()
    if digest != expected:
        raise ValueError(
            f"SQLite archive SHA3-256 mismatch ({digest}); refuse native build"
        )
    with zipfile.ZipFile(io.BytesIO(raw_zip)) as archive:
        exact = f"sqlite-amalgamation-{RELEASE}/sqlite3.c"
        if exact not in archive.namelist():
            raise ValueError("SQLite source is missing")
        entry = archive.getinfo(exact)
        if entry.file_size <= 1000 or entry.file_size > MAX_SOURCE_BYTES:
            raise ValueError("SQLite amalgamation size is invalid")
        source = archive.read(exact)
    if not source.startswith(b"/*") or b"sqlite3_open" not in source:
        raise ValueError("SQLite amalgamation sanity check failed")
    return source


def patch_ci_pubspec(source: str) -> str:
    if "\nhooks:" in source or source.startswith("hooks:"):
        raise ValueError("Refusing to replace an existing package hooks contract")
    if "\r" in source or not source.strip() or "\nname:" not in "\n" + source:
        raise ValueError("Not a supported UTF-8 Dart pubspec")
    return source.rstrip() + "\n" + HOOKS.lstrip("\n")


def download_verified() -> bytes:
    errors: list[str] = []
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                URL, headers={"User-Agent": "AI-Story-RPG-CI-verified-SQLite"}
            )
            with urllib.request.urlopen(req, timeout=50) as stream:
                raw = stream.read(MAX_ZIP_BYTES + 1)
            return verified_source(raw)
        except (OSError, ValueError, zipfile.BadZipFile) as error:
            errors.append(str(error))
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
    raise RuntimeError(
        "Official SQLite source unavailable or unverified; "
        "CI will not use untrusted native binaries. " + "; ".join(errors)
    )


def prepare(repo: pathlib.Path, projects: list[str]) -> None:
    if not projects:
        raise ValueError("At least one project must be selected")
    root = repo.resolve()
    allowed = {
        "apps/story_reader",
        "packages/bookworld_format",
        "packages/campaign_manager",
        "packages/story_authoring",
        "packages/rpg_api",
        "apps/rpg_cli",
    }
    if any(project not in allowed for project in projects):
        raise ValueError("Refusing to write outside approved Dart workspaces")
    pubspecs = {p: root / p / "pubspec.yaml" for p in projects}
    patched = {
        p: patch_ci_pubspec(path.read_text(encoding="utf-8"))
        for p, path in pubspecs.items()
    }
    source = download_verified()  # Fail before touching any pubspec.
    sqlite = root / "artifacts" / "sqlite" / "sqlite3.c"
    sqlite.parent.mkdir(parents=True, exist_ok=True)
    sqlite.write_bytes(source)
    for project, path in pubspecs.items():
        path.write_text(patched[project], encoding="utf-8")
    print(
        "SQLite official amalgamation SHA3 verified (",
        EXPECTED_ZIP_SHA3_256,
        "); native source build enabled only for Linux and Android.",
        sep="",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", action="append", required=True)
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parent.parent
    prepare(repo, args.project)


if __name__ == "__main__":
    main()
