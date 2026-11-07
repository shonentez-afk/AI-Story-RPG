import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/foundation.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'npc_knowledge_rich_world_bridge.dart';
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
    reviewedNpcArc: data['reviewed_npc_arc'] == null ? null
        : Map<String, dynamic>.from(data['reviewed_npc_arc'] as Map),
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
  Map<String, dynamic>? reviewedNpcArc,
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
    'reviewed_npc_arc': reviewedNpcArc,
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

/* One source-reviewed functional pipeline, not a new compiler/engine.
 *
 * The caller must supply an explicit, user-confirmed quotation for every
 * private NPC grant; changing the note, source, character_id or scene
 * invalidates the entire build. The standard rich writer/importers check the
 * final archive again, and no campaign is installed automatically.
 */
Uint8List _compilePrivateNpcRichWorld(Map<String, dynamic> data) {
  return const RichPrivateBookworldWriter().build(
    blueprint: Map<String, dynamic>.from(data['blueprint'] as Map),
    provenance: Map<String, dynamic>.from(data['provenance'] as Map),
    sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
  );
}

Future<Uint8List> compileReviewedNpcRichPrivateBookworldInWorker(
  BookSourceIndex index,
  SourceEvidenceGraph evidence,
  SourceSemanticCatalog catalog,
  SemanticEditorialReviewSession editorial,
  IntermediateStoryBlueprint draft, {
  required NpcKnowledgeRulebook npcRules,
  required NpcEditorialNotebook npcNotebook,
  required SourceCharacterDossierIndex npcDossiers,
  required Map<String, String> sourceQuoteByRuleId,
  required bool userConfirmed,
  Map<String, dynamic>? reviewedNpcSocial,
  List<Map<String, dynamic>> reviewedBookItems = const [],
  Map<String, List<Map<String, dynamic>>> reviewedDialogueTurns = const {},
  Map<String, String> reviewedSpeakerBindings = const {},
  ReviewedNpcDialoguePlan? reviewedDialogueProposal,
  String? approvedDialogueDigest,
  ReviewedNpcResponsePlan? reviewedResponseProposal,
  String? approvedResponseDigest,
  String heroName = 'Игрок',
}) async {
  // Exactly the already accepted preflight/translator, no second engine.
  final translation = PrivateClassicScenarioTranslator.translate(
    index, evidence, catalog, editorial, draft,
    npcRules: npcRules, npcNotebook: npcNotebook, npcDossiers: npcDossiers,
  );
  if (!translation.preflight.isStructurallyReady) {
    throw const FormatException('Не завершена приёмка игрового сценария NPC');
  }
  final blueprint = translation.blueprintJson;
  final provenance = NpcKnowledgeRichWorldBridge.prepare(
    index: index, dossiers: npcDossiers, graph: evidence,
    catalog: catalog, editorial: editorial,
    notebook: npcNotebook, scenario: draft, rulebook: npcRules,
    blueprint: blueprint, provenance: translation.provenanceJson,
    sourceQuoteByRuleId: sourceQuoteByRuleId,
    userConfirmed: userConfirmed, heroName: heroName,
    reviewedDialogueTurns: reviewedDialogueTurns,
    reviewedSpeakerBindings: reviewedSpeakerBindings,
    reviewedDialogueProposal: reviewedDialogueProposal,
    approvedDialogueDigest: approvedDialogueDigest,
    reviewedResponseProposal: reviewedResponseProposal,
    approvedResponseDigest: approvedResponseDigest,
    reviewedNpcSocial: reviewedNpcSocial,
    reviewedBookItems: reviewedBookItems,
  );
  final archive = await compute(_compilePrivateNpcRichWorld, {
    'blueprint': blueprint,
    'provenance': provenance,
    'source_index': Map<String, dynamic>.from(index.toJson()),
  });
  final verified = const RichPrivateBookworldImporter().inspect(archive);
  if (verified.sourceFingerprint != index.sourceFingerprint ||
      verified.blueprint.bookId != blueprint['book_id'] ||
      verified.blueprint.actors.length != (blueprint['actors'] as List).length ||
      verified.canDistributePublicly || verified.requiresNetwork) {
    throw const FormatException('Собран чужой или повреждённый NPC .bworld');
  }
  return archive;
}
