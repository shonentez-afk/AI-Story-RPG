import 'dart:typed_data';

import 'authoring_engine.dart';
import 'book_import.dart';
import 'book_source_selection.dart';
import 'offline_book_analyzer.dart';
import 'portable_reviewed_draft_compiler.dart';
import 'preparation_readiness_report.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';
import 'intermediate_story_blueprint.dart';

/// Pure-Dart, source-bound checkpoint of the *preparation* phase.
///
/// It is deliberately not a completed RPG: extracted candidates and source
/// quotations cannot grant story facts, NPC secrets or gameplay choices.
final class BookPreparationSnapshot {
  const BookPreparationSnapshot({
    required this.source,
    required this.scan,
    required this.readiness,
  });

  final SourceLockedBook source;
  final OfflineSourceReview scan;
  final PreparationReadinessReport readiness;

  String get sourceFingerprint => source.index.sourceFingerprint;
  bool get hasPlayableWorld => false;
  bool get isLiteraryCanon => false;

  /// Safe metadata for clients, without text excerpts or private checkpoints.
  Map<String, Object?> get status => {
    'stage': 'BOOK_SOURCE_PREPARED_NEEDS_REVIEW',
    'source_fingerprint': sourceFingerprint,
    'indexed_chapters': source.index.indexedChapterCount,
    'total_chapters': source.index.chapterCount,
    'mentions_pending_review': scan.mentions.reviewCount,
    'evidence_pending_review': scan.evidence.pendingReviewCount,
    'reviewed_assertions': readiness.reviewedAssertions,
    'total_assertions': readiness.totalAssertions,
    'gates': [
      for (final gate in readiness.gates) {
        'id': gate.id,
        'status': gate.status.name,
        'explanation': gate.explanation,
      },
    ],
    'is_playable_rpg': false,
    'is_literary_canon': false,
    'requires_cloud': false,
  };
}

/// Headless orchestration of the *existing* verified authoring building blocks.
///
/// The client owns UI, checkpoints persistence, network transport and consent.
/// A source/edition selection produces a distinct immutable fingerprint.
/// This service cannot publish candidate meanings or auto-approve AI content.
final class BookToRpgWorkflow {
  const BookToRpgWorkflow();

  static const BookAuthoringEngine _author = BookAuthoringEngine();

  SourceLockedBook openSource(String filename, Uint8List bytes,
      {int? selectedChapter}) {
    final book = BookImporter.parse(filename, bytes);
    final scope = selectedChapter == null
        ? book : BookSourceSelection.selectChapter(book, selectedChapter);
    return _author.indexImported(scope);
  }

  Future<BookPreparationSnapshot> prepare(SourceLockedBook source, {
    OfflineScanCheckpoint? resume,
    void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
    bool Function()? shouldStop,
  }) async {
    final scan = await const OfflineBookAnalyzer().scan(source,
        resume: resume,
        onCheckpoint: onCheckpoint,
        shouldStop: shouldStop);
    if (scan.source.index.sourceFingerprint !=
        source.index.sourceFingerprint ||
        scan.evidence.scannedChunks != source.index.chunks.length) {
      throw const FormatException(
          'Результат проверки не соответствует этой редакции');
    }
    return BookPreparationSnapshot(
      source: source,
      scan: scan,
      readiness: PreparationReadinessReport.assess(
        source.index,
        mentions: scan.mentions,
        narrative: scan.evidence,
        evidence: scan.evidence.graph,
        catalog: scan.catalog,
      ),
    );
  }

  /// Re-evaluate an editorial stage with its exact source and all previews.
  /// This is informational until the strict reviewed compiler succeeds.
  PreparationReadinessReport assessEditorial(
      BookPreparationSnapshot snapshot, {
    StoryEvidenceReviewSession? narrative,
    SourceEvidenceGraph? evidence,
    SourceSemanticCatalog? catalog,
    SemanticEditorialReviewSession? editorial,
    IntermediateStoryBlueprint? draft,
  }) => PreparationReadinessReport.assess(
      snapshot.source.index,
      mentions: snapshot.scan.mentions,
      narrative: narrative ?? snapshot.scan.evidence,
      evidence: evidence ?? snapshot.scan.evidence.graph,
      catalog: catalog ?? snapshot.scan.catalog,
      editorial: editorial,
      draft: draft);

  /// No "one-click canon". A reviewed bundle must pass every original
  /// independent evidence, editorial, NPC and world-format check.
  Future<Uint8List> buildReviewedDraft({
    required BookPreparationSnapshot snapshot,
    required Map<String, dynamic> review,
    bool expanded = false,
  }) {
    if (review['source_fingerprint'] != snapshot.sourceFingerprint ||
        !snapshot.source.hasCompleteText ||
        snapshot.scan.evidence.scannedChunks !=
            snapshot.source.index.chunks.length) {
      throw const FormatException(
          'Сценарий или контрольные точки от другой редакции книги');
    }
    return const PortableReviewedDraftCompiler().build(
        source: snapshot.source, review: review, expanded: expanded);
  }
}
