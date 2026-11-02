import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/foundation.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
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
  IntermediateStoryBlueprint draft,
) async {
  final translation = PrivateClassicScenarioTranslator.translate(
      index, evidence, catalog, editorial, draft);
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
