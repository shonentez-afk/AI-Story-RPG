"""Run here with: python3 -m tools.rpg_author --help."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from . import VERSION
from .common import AuthoringError, read_bytes, read_json
from .compatibility import check_contract, doctor
from . import project


def parser():
    cli = argparse.ArgumentParser(description="Offline, resumable external book-to-RPG authoring")
    cli.add_argument("--version", action="version", version=VERSION)
    commands = cli.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="Check the pinned application contract, without changing it")
    init = commands.add_parser("init", help="Copy and index a TXT/FB2 in a private project")
    init.add_argument("--book", required=True, type=Path)
    init.add_argument("--project", required=True, type=Path)
    init.add_argument("--chunk-size", type=int, default=4096)
    for name in ("status", "next", "accept-analysis", "accept-story", "validate", "export"):
        command = commands.add_parser(name)
        command.add_argument("--project", required=True, type=Path)
        if name == "next":
            command.add_argument("--limit", default=1, type=int)
        if name in ("accept-analysis", "accept-story"):
            command.add_argument("--input", required=True, type=Path)
            command.add_argument("--replace", action="store_true")
        if name == "export":
            command.add_argument("--output", required=True, type=Path)
    legacy = commands.add_parser("build-legacy", help="Explicitly package a private v2 world with an AI attribution sidecar")
    legacy.add_argument("--project", required=True, type=Path)
    legacy.add_argument("--output", required=True, type=Path)
    legacy.add_argument("--model-id", choices=["gpt-6"], default=None,
                        help="User-declared, not independently attested model ID")
    legacy.add_argument("--ack-legacy-provenance", action="store_true",
                        help="Acknowledge provider=none in v2 is only a legacy packaging constant")
    quality = commands.add_parser("gameplay-audit", help="E6: exhaustive game-design quality review, read-only")
    quality.add_argument("--project", type=Path)
    quality.add_argument("--enrichment", type=Path)
    quality.add_argument("--bworld", type=Path,
                         help="Read-only audit of any structurally verified E5/E6 rich v3 archive")
    quality.add_argument("--attribution", type=Path,
                         help="Optional matching attribution sidecar for --bworld")
    quality.add_argument("--output", type=Path,
                         help="Write a private, immutable JSON report outside the repository")
    quality.add_argument("--npc-review", type=Path,
                         help="Private source-bound NPC review for project pre-audit")
    quality.add_argument("--strict", action="store_true",
                         help="Exit 3 when any mechanical quality warning remains")
    dialogue = commands.add_parser("dialogue-audit", help="E6c: read-only NPC question and answer QA")
    dialogue.add_argument("--bworld", required=True, type=Path)
    dialogue.add_argument("--contract", required=True, type=Path,
                          help="Private source-bound dialogue topics manifest")
    dialogue.add_argument("--attribution", type=Path)
    dialogue.add_argument("--output", type=Path)
    dialogue.add_argument("--strict", action="store_true")
    final = commands.add_parser("finalize", help="E6e: fail-closed private v3 build and QA report")
    final.add_argument("--project", required=True, type=Path)
    final.add_argument("--enrichment", required=True, type=Path)
    final.add_argument("--review", required=True, type=Path)
    final.add_argument("--npc-review", type=Path,
                       help="Private source-locked, explicitly confirmed NPC social v1-v5 overlay")
    final.add_argument("--output", required=True, type=Path)
    final.add_argument("--report", type=Path)
    final.add_argument("--dialogues", type=Path)
    final.add_argument("--question-inventory", type=Path)
    final.add_argument("--no-interactive-questions", action="store_true",
                       help="Explicit author declaration; absence not independently proven")
    bundle = commands.add_parser("verify-bundle", help="Check package and sidecar SHA binding")
    bundle.add_argument("--input", required=True, type=Path)
    bundle.add_argument("--attribution", required=True, type=Path)
    richer = commands.add_parser("build", aliases=["build-rich"],
                                 help="Build source-checked rich private v3 game and attribution")
    richer.add_argument("--project", required=True, type=Path)
    richer.add_argument("--enrichment", required=True, type=Path)
    richer.add_argument("--npc-review", type=Path,
                        help="Optional separately reviewed NPC witnesses, memories, items and life")
    richer.add_argument("--output", required=True, type=Path)
    richer.add_argument("--model-id", choices=["gpt-6"], default=None)
    native_v4 = commands.add_parser(
        "build-extended", help="Explicit reviewed v3 source -> native Dart v4, without expanding story-plan limits")
    native_v4.add_argument("--project", required=True, type=Path)
    native_v4.add_argument("--enrichment", required=True, type=Path)
    native_v4.add_argument("--npc-review", type=Path,
                           help="Optional previously reviewed NPC social v5 overlay")
    native_v4.add_argument("--output", required=True, type=Path)
    native_v4.add_argument("--model-id", choices=["gpt-6"], default=None)
    native_v4_check = commands.add_parser(
        "verify-extended", help="Require real Dart importer plus private v4 SHA and attribution checks")
    native_v4_check.add_argument("--input", required=True, type=Path)
    native_v4_check.add_argument("--attribution", required=True, type=Path)
    richer_check = commands.add_parser("verify", aliases=["verify-rich"],
                                       help="Verify v3 archive and matching attribution")
    richer_check.add_argument("--input", required=True, type=Path)
    richer_check.add_argument("--attribution", required=True, type=Path)
    verify = commands.add_parser("verify-legacy", help="Inspect a historical v2 test package, read-only")
    verify.add_argument("--input", required=True, type=Path)
    return cli


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    try:
        name = args.command
        if name == "doctor":
            result = doctor()
        elif name == "init":
            result = project.init_project(args.project, args.book, args.chunk_size)
        elif name == "status":
            result = project.status(args.project)
        elif name == "next":
            result = project.next_task(args.project, args.limit)
        elif name == "accept-analysis":
            result = project.submit_analysis(args.project, read_json(args.input), replace=args.replace)
        elif name == "accept-story":
            result = project.submit_story(args.project, read_json(args.input), replace=args.replace)
        elif name == "validate":
            result = project.validate_project(args.project)
        elif name == "export":
            result = project.export_candidate(args.project, args.output)
        elif name == "gameplay-audit":
            from .gameplay_quality import audit_archive, audit_project
            from .common import atomic_write, canonical, outside_repository, require
            if args.bworld is not None:
                require(args.project is None and args.enrichment is None and
                        args.npc_review is None, "invalid_args",
                        "Use --bworld OR --project with --enrichment")
                result = audit_archive(args.bworld, args.attribution)
            else:
                require(args.project is not None and args.enrichment is not None
                        and args.attribution is None, "invalid_args",
                        "Provide --project and --enrichment, or --bworld")
                result = audit_project(args.project, args.enrichment,
                                       npc_review_path=args.npc_review)
            if args.output is not None:
                out = outside_repository(args.output)
                require(not out.exists(), "output_exists", "Report cannot overwrite an existing file")
                atomic_write(out, canonical(result))
                result["report_output"] = str(out)
        elif name == "dialogue-audit":
            from .dialogue_quality import audit_archive
            from .common import atomic_write, canonical, outside_repository, require
            result = audit_archive(args.bworld, args.contract, args.attribution)
            if args.output is not None:
                out = outside_repository(args.output)
                require(not out.exists(), "output_exists", "Report cannot overwrite another file")
                atomic_write(out, canonical(result))
                result["report_output"] = str(out)
        elif name == "finalize":
            from .finalize import finalize
            result = finalize(args.project, args.enrichment, args.review,
                              args.output, dialogues=args.dialogues,
                              question_inventory_path=args.question_inventory,
                              no_interactive_questions=args.no_interactive_questions,
                              report_path=args.report,
                              npc_review_path=args.npc_review)
        elif name == "build-legacy":
            from .legacy_package import build_legacy
            result = build_legacy(args.project, args.output,
                                  acknowledgement=args.ack_legacy_provenance,
                                  model_id=args.model_id)
        elif name == "verify-bundle":
            from .legacy_package import verify_bundle
            result = verify_bundle(args.input, args.attribution)
        elif name in ("build", "build-rich"):
            result = project.build(args.project, args.enrichment, args.output,
                                   model_id=args.model_id,
                                   npc_review_path=args.npc_review)
        elif name in ("verify", "verify-rich"):
            from .rich_package import verify_rich_bundle
            result = verify_rich_bundle(args.input, args.attribution)
        elif name == "build-extended":
            from .native_v4_bridge import build_extended
            result = build_extended(args.project, args.enrichment, args.output,
                                    model_id=args.model_id,
                                    npc_review_path=args.npc_review)
        elif name == "verify-extended":
            from .native_v4_bridge import verify_extended_bundle
            result = verify_extended_bundle(args.input, args.attribution)
        else:
            check_contract()
            from tools.bookworld import private_bookworld
            from tools.bookworld.bookworld import BookworldError
            try:
                result = {"status": "legacy_package_structurally_verified",
                          "result": private_bookworld.verify(read_bytes(args.input, 12 * 1024 * 1024)),
                          "authorship_certified": False, "device_playtest_completed": False}
            except (BookworldError, KeyError, TypeError, ValueError) as exc:
                raise AuthoringError("invalid_package", str(exc)) from exc
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        if name == "finalize" and result["status"] == "rejected":
            return 3
        if name in ("gameplay-audit", "dialogue-audit") and args.strict and result["warning_count"]:
            return 3
        return 0
    except AuthoringError as exc:
        print(json.dumps({"status": "error", "code": exc.code, "message": str(exc)},
                         ensure_ascii=False), file=sys.stderr)
        return 2
    except (OSError, UnicodeError, RecursionError) as exc:
        print(json.dumps({"status": "error", "code": "file_error", "message": str(exc)},
                         ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())