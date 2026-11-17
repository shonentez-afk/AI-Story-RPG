import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'source_semantic_provider.dart';
import 'source_semantic_review.dart';
import 'source_semantic_catalog.dart';
import 'source_narrative_chronology.dart';
import 'story_evidence_review_session.dart';
import 'authoring_engine.dart';

/// A durable, source-fingerprint-scoped checkpoint for ONLY the independent
/// offline candidate scan. It is never a CANON decision or playable RPG.
/// Embedded source snippets make this PRIVATE user data.
class OfflineScanCheckpoint {
  const OfflineScanCheckpoint({
    required this.sourceFingerprint,
    this.mentions,
    this.evidence,
    this.semantics,
  });

  static const format = 'ai_story_pure_dart_offline_scan_v1';
  final String sourceFingerprint;
  final String? mentions;
  final String? evidence;
  final String? semantics;

  Map<String, Object?> toJson() => {
    'format': format,
    'source_fingerprint': sourceFingerprint,
    'mentions': mentions,
    'evidence': evidence,
    'semantics': semantics,
  };

  factory OfflineScanCheckpoint.fromJson(
      BookSourceIndex index, Map<String, dynamic> raw) {
    const fields = {
      'format', 'source_fingerprint', 'mentions', 'evidence', 'semantics',
    };
    if (raw.keys.toSet().difference(fields).isNotEmpty ||
        raw.keys.length != fields.length ||
        raw['format'] != format ||
        raw['source_fingerprint'] != index.sourceFingerprint) {
      throw const FormatException('Чужая или повреждённая редакция анализа');
    }
    for (final field in ['mentions', 'evidence', 'semantics']) {
      if (raw[field] != null && raw[field] is! String) {
        throw const FormatException('Неверный тип checkpoint');
      }
    }
    final result = OfflineScanCheckpoint(
      sourceFingerprint: index.sourceFingerprint,
      mentions: raw['mentions'] as String?,
      evidence: raw['evidence'] as String?,
      semantics: raw['semantics'] as String?,
    );
    result.validate(index);
    return result;
  }

  void validate(BookSourceIndex index) {
    if (sourceFingerprint != index.sourceFingerprint ||
        (evidence != null && mentions == null) ||
        (semantics != null && evidence == null)) {
      throw const FormatException('Неполная или чужая очередь анализа');
    }
    if (mentions != null) {
      SourceAnalysisSession.decode(index, mentions!);
    }
    if (evidence != null) {
      StoryEvidenceReviewSession.decode(index, evidence!);
    }
    if (semantics != null) {
      SemanticReviewSession.decode(
          index, const OfflineRuleProvider(), semantics!);
    }
  }
}

/// Source-bound local result: an editable proposal, never literary truth.
/// All checkpoints replay against exact source chunks before reusing them.
class OfflineSourceReview {
  const OfflineSourceReview({
    required this.source,
    required this.mentions,
    required this.evidence,
    required this.semantics,
    required this.catalog,
    required this.chronology,
  });

  final SourceLockedBook source;
  final SourceAnalysisSession mentions;
  final StoryEvidenceReviewSession evidence;
  final SemanticReviewSession semantics;
  final SourceSemanticCatalog catalog;
  final SourceNarrativeChronology chronology;

  Map<String, Object?> get summary => {
    'stage': 'OFFLINE_SOURCE_PROPOSALS_ONLY',
    'source_fingerprint': source.index.sourceFingerprint,
    'chapters_indexed': source.index.indexedChapterCount,
    'source_chunks': source.index.chunks.length,
    'mentions': mentions.mentions.length,
    'mentions_pending_review': mentions.reviewCount,
    'evidence_proposals': evidence.graph.records.length,
    'evidence_pending_review': evidence.pendingReviewCount,
    'semantic_candidates': semantics.candidates.length,
    'semantic_assertions': catalog.assertions.length,
    'chronology_observations': chronology.observations.length,
    'gameplay_coverage': 0,
    'is_literary_canon': false,
    'is_playable_rpg': false,
    'requires_cloud': false,
  };
}

/// Single pure-Dart scanner for the existing deterministic extraction
/// algorithms. Flutter can keep its own platform persistence/paint layer.
/// Every accepted batch is emitted as an immutable verifiable checkpoint.
class OfflineBookAnalyzer {
  const OfflineBookAnalyzer();

  Future<OfflineSourceReview> scan(
      SourceLockedBook source, {
      OfflineScanCheckpoint? resume,
      void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
      bool Function()? shouldStop,
    }) async {
    if (!source.hasCompleteText) {
      throw const FormatException('Нужен полный текст перед анализом');
    }
    final index = source.index;
    if (resume != null) resume.validate(index);
    SourceAnalysisSession mentions = resume?.mentions == null
        ? SourceAnalysisSession.create(index)
        : SourceAnalysisSession.decode(index, resume!.mentions!);
    StoryEvidenceReviewSession evidence = resume?.evidence == null
        ? StoryEvidenceReviewSession.create(index)
        : StoryEvidenceReviewSession.decode(index, resume!.evidence!);
    SemanticReviewSession semantics = resume?.semantics == null
        ? SemanticReviewSession.create(index, const OfflineRuleProvider())
        : SemanticReviewSession.decode(
            index, const OfflineRuleProvider(), resume!.semantics!);

    void checkpoint() {
      onCheckpoint?.call(OfflineScanCheckpoint(
        sourceFingerprint: index.sourceFingerprint,
        mentions: mentions.encode(),
        evidence: evidence.encode(),
        semantics: semantics.encode(),
      ));
    }

    void checkStop() {
      if (shouldStop?.call() == true) {
        throw StateError('Анализ остановлен: сохранён последний checkpoint');
      }
    }
    while (mentions.pendingCount > 0) {
      checkStop();
      mentions = mentions.processBatch(index, limit: 24);
      checkpoint();
    }
    if (mentions.failedCount > 0) {
      throw const FormatException('Есть неудачно обработанные фрагменты');
    }
    while (evidence.scannedChunks < index.chunks.length) {
      checkStop();
      evidence = evidence.scanNext(index, limit: 24);
      checkpoint();
    }
    while (semantics.pendingCount > 0) {
      checkStop();
      semantics = await semantics.processNext(
          index, const OfflineRuleProvider(), limit: 8);
      checkpoint();
    }
    checkStop();
    // Recomputed from exact source and unapproved evidence. No hidden AI
    // assumptions, no actor identities or game effects are accepted.
    final catalog = SourceSemanticCatalog.fromLocalEvidence(
        index, evidence.graph);
    final chronology = SourceNarrativeChronology.build(
        index, evidence.graph);
    return OfflineSourceReview(
      source: source,
      mentions: mentions,
      evidence: evidence,
      semantics: semantics,
      catalog: catalog,
      chronology: chronology,
    );
  }
}
