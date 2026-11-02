import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_extractor.dart';

/// Separate from the M2b1 queue. Existing M2b1 checkpoints and saved games
/// are never rewritten. The data is review WORK, not gameplay or canon.
class StoryEvidenceReviewSession {
  StoryEvidenceReviewSession._(
    this.sourceFingerprint,
    this.scannedChunks,
    this.graph,
  );

  static const format = 'ai_story_evidence_review_m2b3b_v1';
  static const maxBytes = 12 * 1024 * 1024;
  static const maxEvidence = 12000;

  final String sourceFingerprint;
  final int scannedChunks;
  final SourceEvidenceGraph graph;

  int get pendingReviewCount => graph.records
      .where((e) => e.status == EvidenceStatus.inferred).length;
  int get confirmedPassageCount => graph.records
      .where((e) => e.status == EvidenceStatus.confirmed).length;

  /// No narrative blueprint, scene graph or game world exists yet.
  bool get canPublishBookworld => false;
  double get gameplayCoverage => 0;

  factory StoryEvidenceReviewSession.create(BookSourceIndex index) =>
      StoryEvidenceReviewSession._(
        index.sourceFingerprint, 0, SourceEvidenceGraph.empty(index),
      );

  void _checkIndex(BookSourceIndex index) {
    if (index.sourceFingerprint != sourceFingerprint ||
        scannedChunks < 0 || scannedChunks > index.chunks.length) {
      throw const FormatException('Другая редакция или нарезка книги');
    }
  }

  /// New M2b1 ACCEPTED means "text exists". It must not silently confirm
  /// a character's identity or transform a quote into a game fact.
  StoryEvidenceReviewSession syncAcceptedMentions(
      BookSourceIndex index, SourceAnalysisSession? mentions) {
    _checkIndex(index);
    if (mentions == null) return this;
    final converted = SourceEvidenceGraph.fromReviewedMentions(
        index, mentions);
    final already = {for (final item in graph.records) item.id};
    final additions = [
      for (final item in converted.records)
        if (already.add(item.id)) item,
    ];
    if (additions.isEmpty) return this;
    if (graph.records.length + additions.length > maxEvidence) {
      throw const FormatException('Слишком много проверяемых сведений');
    }
    return StoryEvidenceReviewSession._(
      sourceFingerprint, scannedChunks, graph.addAll(index, additions),
    );
  }

  /// Bounded, deterministic, transactional in-memory update. The caller
  /// persists the candidate before showing progress or beginning next batch.
  StoryEvidenceReviewSession scanNext(BookSourceIndex index,
      {int limit = 24}) {
    _checkIndex(index);
    if (limit < 1 || limit > 64) {
      throw RangeError.range(limit, 1, 64, 'limit');
    }
    final end = (scannedChunks + limit).clamp(
        scannedChunks, index.chunks.length).toInt();
    if (end == scannedChunks) return this;
    final existing = {for (final item in graph.records) item.id};
    final proposals = <SourceEvidence>[];
    for (var i = scannedChunks; i < end; i++) {
      final chunk = index.chunks[i];
      for (final item in SourceNarrativeExtractor.extractChunk(index, chunk)) {
        if (existing.add(item.id)) proposals.add(item);
      }
    }
    if (graph.records.length + proposals.length > maxEvidence) {
      throw const FormatException('Достигнут лимит локальных кандидатов');
    }
    final updated = proposals.isEmpty
        ? graph : graph.addAll(index, proposals);
    return StoryEvidenceReviewSession._(
      sourceFingerprint, end, updated,
    );
  }

  /// Confirmation applies to the exact passage ONLY and never declares
  /// that a claim is true, an entity merged, or a plot action executable.
  StoryEvidenceReviewSession review(
      BookSourceIndex index, String id, EvidenceStatus decision) {
    _checkIndex(index);
    return StoryEvidenceReviewSession._(
      sourceFingerprint, scannedChunks, graph.review(index, id, decision),
    );
  }

  static String _sha(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  String encode() {
    final payload = {
      'source_fingerprint': sourceFingerprint,
      'scanned_chunks': scannedChunks,
      'stage': 'EVIDENCE_REVIEW_ONLY',
      'gameplay_coverage': 0,
      'can_publish_bookworld': false,
      'graph': jsonDecode(graph.encode()),
    };
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint утверждений');
    }
    return raw;
  }

  static StoryEvidenceReviewSession decode(BookSourceIndex index, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint утверждений');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root['format'] != format) {
        throw const FormatException('Неизвестная версия анализа утверждений');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (root['sha256'] != _sha(jsonEncode(payload)) ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['stage'] != 'EVIDENCE_REVIEW_ONLY' ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Повреждённая контрольная точка утверждений');
      }
      final cursor = payload['scanned_chunks'] as int;
      if (cursor < 0 || cursor > index.chunks.length) {
        throw const FormatException('Повреждён счётчик обработанных фрагментов');
      }
      final graph = SourceEvidenceGraph.decode(index,
          jsonEncode(payload['graph']));
      if (graph.records.length > maxEvidence) {
        throw const FormatException('Превышен лимит сохранённых утверждений');
      }

      // A FACT/EVENT must not be injected outside the processed source span.
      final positions = <String, int>{
        for (var i = 0; i < index.chunks.length; i++)
          index.chunks[i].id: i,
      };
      for (final item in graph.records) {
        if (item.kind == EvidenceKind.fact ||
            item.kind == EvidenceKind.event) {
          final position = positions[item.chunkId];
          if (position == null || position >= cursor) {
            throw const FormatException('Утверждение вне проверенного диапазона');
          }
        }
      }
      return StoryEvidenceReviewSession._(
        index.sourceFingerprint, cursor, graph,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённый checkpoint утверждений');
    }
  }
}
