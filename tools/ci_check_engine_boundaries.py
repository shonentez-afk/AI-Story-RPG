#!/usr/bin/env python3
"""CI architectural gate for reusable, UI-independent Dart RPG packages.

This does not claim a new engine exists. It checks source dependency direction
for the four EXISTING engine packages and their pubspec runtime dependencies.
The application can import packages; these packages cannot import the app.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DIR = ROOT / "packages"

# This is a deliberately small contract, not a second dependency manager.
RUNTIME_DEPS = {
    "story_core": {"crypto"},
    "story_runtime_adapter": {"story_core", "story_engine"},
    "bookworld_format": {"story_core", "crypto", "sqlite3"},
    "story_authoring": {"archive", "xml", "crypto", "story_core", "bookworld_format"},
    "campaign_manager": {
        "story_core", "story_runtime_adapter", "bookworld_format",
        "crypto", "sqlite3",
    },
}
IMPORT = re.compile(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]")
PUBSPEC_DEP = re.compile(r"^  ([a-z][a-z0-9_]*):(?:\s|$)")
DART_CORE_ALLOWED = {
    "dart:async", "dart:collection", "dart:convert", "dart:core",
    "dart:math", "dart:typed_data",
}


def pubspec_runtime_dependencies(text: str) -> set[str]:
    in_dependencies = False
    result: set[str] = set()
    for line in text.splitlines():
        if line.startswith("dependencies:"):
            in_dependencies = True
            continue
        if in_dependencies and line and not line[0].isspace():
            break
        if in_dependencies:
            match = PUBSPEC_DEP.match(line)
            if match:
                result.add(match.group(1))
    return result


def validate() -> list[str]:
    issues: list[str] = []
    for package, allowed in RUNTIME_DEPS.items():
        folder = PACKAGE_DIR / package
        pubspec = folder / "pubspec.yaml"
        if not pubspec.is_file():
            issues.append(f"Missing engine pubspec: {pubspec}")
            continue
        manifest = pubspec.read_text(encoding="utf-8")
        if not re.search(r"(?m)^publish_to:\s*none\s*$", manifest):
            issues.append(f"{package}: must remain unpublished until split approval")
        if not re.search(r"(?m)^version:\s*\d+\.\d+\.\d+", manifest):
            issues.append(f"{package}: missing explicit semantic package version")
        actual_deps = pubspec_runtime_dependencies(manifest)
        for forbidden in sorted(actual_deps - allowed):
            issues.append(f"{package}: forbidden runtime dependency {forbidden}")

        library = folder / "lib"
        for source in (*library.rglob("*.dart"), *(folder / "example").rglob("*.dart"), *(folder / "bin").rglob("*.dart")):
            for line_no, line in enumerate(
                    source.read_text(encoding="utf-8").splitlines(), 1):
                match = IMPORT.match(line)
                if not match:
                    continue
                target = match.group(1)
                where = str(source.relative_to(ROOT)) + ":" + str(line_no)
                if target.startswith("dart:"):
                    if target == "dart:ui" or (
                            package == "story_core" and
                            target not in DART_CORE_ALLOWED):
                        issues.append(f"{where}: forbidden SDK dependency {target}")
                elif target.startswith("package:"):
                    imported_package = target[8:].split("/", 1)[0]
                    if imported_package != package and imported_package not in allowed:
                        issues.append(
                            f"{where}: engine-to-app or undeclared package import: "
                            f"{target}"
                        )
                    if imported_package != package and (
                            imported_package not in actual_deps):
                        issues.append(f"{where}: undeclared runtime import {target}")
                else:
                    # Plain relative imports/exports must stay within their own
                    # package and cannot escape into Flutter app sources.
                    resolved = (source.parent / target).resolve()
                    if not resolved.is_relative_to(folder.resolve()):
                        issues.append(f"{where}: relative import escapes package")

        if package == "story_core":
            for forbidden in ("flutter:", "sqlite3:", "story_engine:",
                              "story_runtime_adapter:", "zai:"):
                if forbidden in manifest:
                    issues.append(
                        f"story_core: core cannot declare service {forbidden}"
                    )
    return issues


def main() -> int:
    issues = validate()
    for issue in issues:
        print("ARCHITECTURE ERROR: " + issue, file=sys.stderr)
    if issues:
        return 1
    print(
        "Architecture boundary PASS: 5 versioned pure-Dart packages; "
        "story_core is service-independent; no engine -> app imports"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
