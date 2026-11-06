import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/foundation.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'source_character_dossiers.dart';
import 'private_classic_scenario_translator.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// Only transferable JSON structures cross the isolate boundary. Never pass
/// BuildContext, State, a SQLite connection, or user books to a cloud service.
Uint8List _compilePrivateWorld(Map<String, dynamic> payload) {
  return const PrivateBookworldWriter().build(
    blueprint: Map<String, dynamic>.from(payload['blueprint'] as Map),
    provenance: Map<String, dynamic>.from(payload['provenance'] as Map),
    sourceIndex: Map<String, dynamic>.from(payload['source_index'] as Map),
  );
}

/// M2e: only explicit editorial acceptance and causal preflight can reach the
/// native builder. The returned package still receives an independent ZIP,
/// manifest, SQLite and source-provenance validation before it is playable.
///
/// This function builds bytes without installing games or mutating campaigns.
/// Call WorldLibraryGateway.install only after explicit user confirmation.
Future<Uint8List> compileReviewedPrivateBookworldInWorker(
  BookSourceIndex index,
  SourceEvidenceGraph evidence,
  SourceSemanticCatalog catalog,
  SemanticEditorialReviewSession editorial,
  IntermediateStoryBlueprint draft, {
  NpcKnowledgeRulebook? npcRules,
  NpcEditorialNotebook? npcNotebook,
  SourceCharacterDossierIndex? npcDossiers,
}) async {
  final translation = PrivateClassicScenarioTranslator.translate(
      index, evidence, catalog, editorial, draft,
      npcRules: npcRules, npcNotebook: npcNotebook,
      npcDossiers: npcDossiers);
  if (!translation.preflight.isStructurallyReady) {
    throw const FormatException('Не завершена проверка игрового сценария');
  }
  // index.toJson contains source text only in this transient in-memory worker
  // message, never in the compiled .bworld or an external request.
  final archive = await compute(_compilePrivateWorld, <String, dynamic>{
    'blueprint': translation.blueprintJson,
    'provenance': translation.provenanceJson,
    'source_index': Map<String, dynamic>.from(index.toJson()),
  });
  final verified = const PrivateBookworldImporter().inspect(archive);
  if (verified.sourceFingerprint != index.sourceFingerprint) {
    throw const FormatException('Собранный мир относится к другой книге');
  }
  return archive;
}


/// The app-side native bridge: vetted v2 output -> single rich v3 format.
/// All original M2c preflight, exact-source validation and v2 importer checks
/// are performed FIRST; the rich writer then rebuilds ZIP+SQLite and independently
/// reopens it through v3. No API request or mandatory enrichment JSON.
Uint8List _upgradeReviewedPrivateWorld(Map<String, dynamic> data) {
  return const RichPrivateBookworldWriter().upgradeReviewedV2(
    verifiedPrivateV2Archive: data['archive'] as Uint8List,
    sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
    heroName: data['hero_name'] as String,
    sceneTitles: Map<String, String>.from(data['scene_titles'] as Map),
  );
}

Future<Uint8List> compileReviewedRichPrivateBookworldInWorker(
  BookSourceIndex index,
  SourceEvidenceGraph evidence,
  SourceSemanticCatalog catalog,
  SemanticEditorialReviewSession editorial,
  IntermediateStoryBlueprint draft, {
  String heroName = 'Игрок',
  Map<String, String> sceneTitles = const {},
}) async {
  // Preserve the accepted fail-closed M2c checks rather than inventing
  // another path that trusts LLM-authored source offsets.
  final v2 = await compileReviewedPrivateBookworldInWorker(
      index, evidence, catalog, editorial, draft);
  final archive = await compute(_upgradeReviewedPrivateWorld, {
    'archive': v2,
    'source_index': Map<String, dynamic>.from(index.toJson()),
    'hero_name': heroName,
    'scene_titles': sceneTitles,
  });
  final checked = const RichPrivateBookworldImporter().inspect(archive);
  if (checked.sourceFingerprint != index.sourceFingerprint ||
      checked.blueprint.scenes.length != draft.scenes.length ||
      checked.canDistributePublicly || checked.requiresNetwork) {
    throw const FormatException(
        'Богатая частная RPG не соответствует проверенной книге');
  }
  return archive;
}
