import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';

import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'zai_causal_choice_notebook.dart';
import 'zai_editorial_consistency.dart';
import 'zai_m2c_source_bridge.dart';
import 'zai_semantic_review_queue.dart';

/// M2f3f2: a verified PRIVATE build, not yet installed or played.
/// A compiled package is intentionally kept in memory until a second,
/// separate user confirmation. Nothing leaves the device.
class ZaiCompiledPrivateWorld {
  ZaiCompiledPrivateWorld._({
    required this.archive,
    required this.sourceFingerprint,
    required this.bookworldId,
    required this.title,
    required this.archiveSha256,
  });

  final Uint8List archive;
  final String sourceFingerprint;
  final String bookworldId;
  final String title;
  final String archiveSha256;

  bool get canDistributePublicly => false;
  bool get usesCloud => false;
}

/// This adapter is the sole M2f3e → native M2e packaging entrance.
/// Re-evaluates the independent M2f3f1 bridge immediately before building;
/// the native compiler in turn runs M2c preflight and ZIP/SQLite validation.
/// No "keepForReview" mark can bypass M2c editorial acceptance.
class ZaiPrivateBookworldCompilation {
  const ZaiPrivateBookworldCompilation._();

  static Future<ZaiCompiledPrivateWorld> compile({
    required ZaiWindowReviewQueue queue,
    required ZaiCausalChoiceNotebook notebook,
    required ZaiEditorialConsistencyNotebook consistency,
    required SourceEvidenceGraph evidence,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required Set<String> sourceSceneIds,
    required Map<String, String> eventAssertionIds,
    required Map<String, String> authoredSceneTexts,
    required bool consentForPrivateCompilation,
  }) async {
    final verified = ZaiM2cSourceBridge.review(
      queue: queue,
      notebook: notebook,
      consistency: consistency,
      evidence: evidence,
      catalog: catalog,
      editorial: editorial,
      sourceSceneIds: sourceSceneIds,
      eventAssertionIds: eventAssertionIds,
      authoredSceneTexts: authoredSceneTexts,
      rights: PreparationRights.privateUse,
      consentForPrivateCompilation: consentForPrivateCompilation,
    );
    if (!verified.canStageForPrivateCompiler || verified.draft == null) {
      throw FormatException(
          'Частная компиляция заблокирована: ${verified.blockers.join(" ")}');
    }
    final archive = await compileReviewedPrivateBookworldInWorker(
        queue.index, evidence, catalog, editorial, verified.draft!);
    // Independent verifier must accept the entire ZIP manifest, typed
    // blueprint, provenance, rights status and embedded SQLite DB.
    final checked = const PrivateBookworldImporter().inspect(archive);
    if (checked.sourceFingerprint != queue.index.sourceFingerprint ||
        checked.blueprint.title != verified.draft!.title ||
        checked.canDistributePublicly || checked.requiresNetwork) {
      throw const FormatException(
          'Собранный пакет не соответствует исходной книге или частным правам');
    }
    return ZaiCompiledPrivateWorld._(
      archive: Uint8List.fromList(archive),
      sourceFingerprint: checked.sourceFingerprint,
      bookworldId: checked.bookworldId,
      title: checked.blueprint.title,
      archiveSha256: checked.archiveSha256,
    );
  }

}
