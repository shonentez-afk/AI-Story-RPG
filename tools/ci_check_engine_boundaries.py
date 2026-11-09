#!/usr/bin/env python3
"""CI architectural gate for reusable, UI-independent Dart RPG packages.

This does not claim a new engine exists. It checks source dependency direction
for the independent engine packages and their pubspec runtime dependencies.
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
    # All view models, NPC evidence, replayed journal, inventory ownership,
    # choice authorization and save gates belong to this headless service.
    # No Flutter, path_provider, cloud provider or app may cross this edge.
    "rpg_gameplay": {
        "story_core", "bookworld_format", "campaign_manager",
        "story_engine", "crypto",
    },
    "rpg_api": {
        "rpg_gameplay", "story_authoring", "campaign_manager",
        "bookworld_format",
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
                            package in {"story_core", "rpg_api"} and
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
    # No other client may silently reintroduce the four extracted rules.
    # An alias file must remain an export-only compatibility shim.
    pure_authoring = {
        "npc_continuity_audit",
        "draft_scene_graph_overview",
        "cross_act_source_evidence_packet",
        "preparation_readiness_report",
    }
    for name in sorted(pure_authoring):
        shim = ROOT / "apps" / "story_reader" / "lib" / (name + ".dart")
        text = shim.read_text(encoding="utf-8") if shim.is_file() else ""
        active = [line.strip() for line in text.splitlines()
                  if line.strip() and not line.lstrip().startswith("//")]
        if len(active) < 1 or not active[0].startswith(
                "export 'package:story_authoring/story_authoring.dart' show") or (
                any(line.startswith(("class ", "enum ", "import ", "typedef "))
                    for line in active)):
            issues.append(f"{shim}: Flutter must re-export pure authoring rules")
        if len(text) > 800:
            issues.append(f"{shim}: compatibility shim contains too much code")

    llm_adapters = (
        "zai_npc_dialogue_draft.dart",
        "zai_source_locked_prose_preview.dart",
        "zai_source_locked_gameplay_candidates.dart",
        "zai_source_locked_prose_audit.dart",
    )
    for filename in llm_adapters:
        adapter = ROOT / "apps" / "story_reader" / "lib" / filename
        content = adapter.read_text(encoding="utf-8") if adapter.is_file() else ""
        if ("LocalRpgProposalReviewApi" not in content or
                "package:rpg_api/rpg_api.dart" not in content):
            issues.append(f"{adapter}: AI proposals must use pure API")
        if ("RichNpcDialogueKnowledge.validate" in content or
                "RichSceneDialogue.verify" in content):
            issues.append(f"{adapter}: source rules still in Flutter")

    # A real second application must use the public RPG API, not the engine.
    cli = ROOT / "apps" / "rpg_cli"
    allowed_cli = {"rpg_api", "campaign_manager"}
    pubspec = cli / "pubspec.yaml"
    if not pubspec.is_file():
        issues.append("Standalone RPG CLI is missing")
    elif pubspec_runtime_dependencies(pubspec.read_text(encoding="utf-8")) != allowed_cli:
        issues.append("rpg_cli must depend only on public API and SQLite client port")
    for source in (*(cli / "lib").rglob("*.dart"), *(cli / "bin").rglob("*.dart")):
        for line_no, line in enumerate(
                source.read_text(encoding="utf-8").splitlines(), 1):
            match = IMPORT.match(line)
            if match is None:
                continue
            target = match.group(1)
            if target.startswith("package:"):
                pkg = target[8:].split("/", 1)[0]
                if pkg not in allowed_cli | {"ai_story_rpg_cli"}:
                    issues.append(
                        f"{source.relative_to(ROOT)}:{line_no}: "
                        f"CLI must use public RPG API instead of {target}")
            elif not target.startswith("dart:"):
                resolved = (source.parent / target).resolve()
                if not resolved.is_relative_to(cli.resolve()):
                    issues.append(
                        f"{source.relative_to(ROOT)}:{line_no}: "
                        "CLI import escapes its client package")

    prose_adapter = ROOT / "apps" / "story_reader" / "lib" / "campaign_prose_authoring.dart"
    prose_code = prose_adapter.read_text(encoding="utf-8") if prose_adapter.is_file() else ""
    if ("package:rpg_api/rpg_api.dart" not in prose_code or
            "LocalRpgCampaignProseApi" not in prose_code):
        issues.append(f"{prose_adapter}: whole-campaign prose must use RPG API")
    if ("StoryInventoryRouteAudit.inspect" in prose_code or
            "ReviewedCampaignProseWriter().build(" in prose_code or
            "CampaignProseManifest._(" in prose_code):
        issues.append(f"{prose_adapter}: campaign prose rules returned to Flutter")

    campaign_flow = ROOT / "packages" / "story_authoring" / "lib" / "src" / "reviewed_campaign_workflow.dart"
    flow_code = campaign_flow.read_text(encoding="utf-8") if campaign_flow.is_file() else ""
    if ("ReviewedCampaignWorkflow" not in flow_code or
            "StoryCampaignCausalAudit.inspect" not in flow_code or
            "BookwideNpcCampaignAuthoring.compile" not in flow_code or
            "CampaignProseFinalizer.compile" not in flow_code):
        issues.append(f"{campaign_flow}: workflow must call canonical compilers and audits")
    if ("package:flutter/" in flow_code or "ai_connection.dart" in flow_code or
            "ZaiModel." in flow_code):
        issues.append(f"{campaign_flow}: workflow must remain standalone")

    npc_wizard = ROOT / "apps" / "story_reader" / "lib" / "whole_book_npc_campaign_page.dart"
    wizard_code = npc_wizard.read_text(encoding="utf-8") if npc_wizard.is_file() else ""
    for api_method in (
        "_workflow.compileBase(", "_workflow.acceptEffects(",
        "_workflow.acceptNpc(", "_workflow.prepareNarration(",
        "_workflow.completeWithNarration(", "_workflow.completeWithoutNarration(",
    ):
        if api_method not in wizard_code:
            issues.append(f"{npc_wizard}: missing RPG API call {api_method}")
    for direct_call in (
        "source.compileBase(", "NpcCampaignConsequences.accept(",
        "BookwideNpcCampaignAuthoring.compile(", "CampaignProseManifest.prepare(",
    ):
        if direct_call in wizard_code:
            issues.append(f"{npc_wizard}: a compiler rule returned to Flutter: {direct_call}")

    legacy_editor = ROOT / "apps" / "story_reader" / "lib" / "multi_act_trial_editor.dart"
    legacy_code = legacy_editor.read_text(encoding="utf-8") if legacy_editor.is_file() else ""
    for delegated in (
        "_trialApi.compileTrial(", "_trialApi.composePreviewPlan(",
        "_trialApi.previewOneGameplay(",
        "_trialApi.previewWholeGameplay(", "_trialApi.acceptGameplay(",
        "_trialApi.verifyPrivateWorld(",
    ):
        if delegated not in legacy_code:
            issues.append(f"{legacy_editor}: multi-act editor must call public RPG API {delegated}")
    for direct in (
        "MultiActTrialCompiler.compile(",
        "BookwideSourceEncounters.attach(",
        "ReviewedGameplayCompiler.preview(",
        "ReviewedGameplayCompiler.previewAcrossBatches(",
        "ReviewedGameplayCompiler.compileAfterUserConfirmation(",
        "RichPrivateBookworldImporter().inspect(",
    ):
        if direct in legacy_code:
            issues.append(f"{legacy_editor}: engine rule returned to Flutter: {direct}")

    creation_policy = ROOT / "packages" / "story_authoring" / "lib" / "src" / "rpg_creation_contract.dart"
    policy_code = creation_policy.read_text(encoding="utf-8") if creation_policy.is_file() else ""
    if ("RpgCreationPolicy" not in policy_code or
            "RpgCreationPlot.canon" not in policy_code or
            "RpgCreationInteraction.fixedChoices" not in policy_code):
        issues.append(f"{creation_policy}: creation modes must be explicitly verified")
    if "package:flutter/" in policy_code or "Zai" in policy_code:
        issues.append(f"{creation_policy}: creation policy must not use a Flutter or cloud dependency")
    short_screen = ROOT / "apps" / "story_reader" / "lib" / "quick_rpg_page.dart"
    short_code = short_screen.read_text(encoding="utf-8") if short_screen.is_file() else ""
    for direct in ("QuickRpgBuilder.propose(", "QuickRpgBuilder.proposeFromEventOutline(", "QuickRpgBuilder.compile("):
        if direct in short_code:
            issues.append(f"{short_screen}: short game must use public RpgCreationApi, not {direct}")
    if "_api.compileShort(" not in short_code or "_api.previewShort(" not in short_code:
        issues.append(f"{short_screen}: short game must call the creation API")
    gateway = ROOT / "apps" / "story_reader" / "lib" / "world_library_gateway.dart"
    workers = ROOT / "apps" / "story_reader" / "lib" / "book_isolate_workers.dart"
    for path in (gateway, workers):
        if not path.is_file() or "package:rpg_api/rpg_api.dart" not in path.read_text(
                encoding="utf-8"):
            issues.append(f"{path}: Flutter must use the public RPG API")
    return issues


def main() -> int:
    issues = validate()
    for issue in issues:
        print("ARCHITECTURE ERROR: " + issue, file=sys.stderr)
    if issues:
        return 1
    print(
        "Architecture boundary PASS: 7 versioned pure-Dart packages; "
        "story_core is service-independent; no engine -> app imports"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
