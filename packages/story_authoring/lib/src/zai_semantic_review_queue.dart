import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_semantic_provider.dart';
import 'source_semantic_window.dart';
import 'semantic_preview_models.dart';

/// Editorial marks are only private hypotheses; neither mark is canon.
enum ZaiEditorialDecision { keepForReview, rejected }

class ZaiWindowReviewResult {
  ZaiWindowReviewResult({
    required List<SemanticCandidate> candidates,
    required this.totalSuggestions,
    required this.rejectedCount,
    required this.rejectedNonRussian,
  }) : candidates = List<SemanticCandidate>.unmodifiable(candidates);

  final List<SemanticCandidate> candidates;
  final int totalSuggestions;
  final int rejectedCount;
  final int rejectedNonRussian;

  Map<String, Object> toJson(int position, SourceSemanticWindow window) => {
    'position': position,
    'chunk_ids': [for (final chunk in window.chunks) chunk.id],
    'total_suggestions': totalSuggestions,
    'rejected_count': rejectedCount,
    'rejected_non_russian': rejectedNonRussian,
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  };
}

/// M2f3a: explicitly consented, ONE-window-at-a-time cloud results.
/// All checkpoints are private, edition-locked and NOT authoritative world data.
/// No raw full-book text, API keys, provider credentials or game saves stored.
class ZaiWindowReviewQueue {
  ZaiWindowReviewQueue._(
    this.index,
    this.windows,
    Map<int, ZaiWindowReviewResult> results,
    Map<String, ZaiEditorialDecision> decisions,
  ) : results = Map<int, ZaiWindowReviewResult>.unmodifiable(results),
      decisions = Map<String, ZaiEditorialDecision>.unmodifiable(decisions);

  static const format = 'ai_story_zai_window_review_m2f3a_v1';
  static const maxCheckpointUtf8Bytes = 10 * 1024 * 1024;

  final BookSourceIndex index;
  final List<SourceSemanticWindow> windows;
  final Map<int, ZaiWindowReviewResult> results;
  final Map<String, ZaiEditorialDecision> decisions;

  factory ZaiWindowReviewQueue.empty(BookSourceIndex index) =>
      ZaiWindowReviewQueue._(
        index,
        SourceSemanticWindowPlanner.plan(index),
        const {},
        const {},
      );

  int get completedCount => results.length;
  int get pendingCount => windows.length - results.length;
  int get candidateCount =>
      results.values.fold<int>(0, (sum, result) => sum + result.candidates.length);
  int get pendingReviewCount => candidateCount - decisions.length;
  int get keptForReviewCount => decisions.values
      .where((decision) => decision == ZaiEditorialDecision.keepForReview)
      .length;
  bool get canPublishBookworld => false;

  List<SemanticCandidate> get allCandidates => List.unmodifiable([
    for (final position in results.keys.toList()..sort())
      ...results[position]!.candidates,
  ]);

  /// Find the next unsent window without sending it. Caller must still show
  /// the FULL consent dialog for this exact window and title.
  int? nextPendingAfter(int position) {
    for (var offset = 1; offset <= windows.length; offset++) {
      final next = (position + offset) % windows.length;
      if (!results.containsKey(next) && windows[next].hasNarrativeText) {
        return next;
      }
    }
    return null;
  }

  void _validateResult(int position, ZaiWindowReviewResult result) {
    if (position < 0 || position >= windows.length ||
        !windows[position].hasNarrativeText ||
        result.candidates.length > SemanticPreviewWireContract.maxProposals ||
        result.totalSuggestions < 0 ||
        result.rejectedCount < 0 ||
        result.rejectedNonRussian < 0 ||
        result.rejectedNonRussian > result.rejectedCount ||
        result.totalSuggestions != result.candidates.length + result.rejectedCount) {
      throw const FormatException('Невалидный результат смыслового окна');
    }
    final window = windows[position];
    SourceSemanticWindowPlanner.validate(index, window);
    final request = SemanticExtractionRequest(
      index: index,
      chunks: window.chunks,
      categories: SemanticPreviewWireContract.categories,
    );
    final batch = SemanticCandidateBatch(
      providerId: SemanticPreviewWireContract.providerId,
      providerVersion: SemanticPreviewWireContract.providerVersion,
      sourceFingerprint: index.sourceFingerprint,
      chunkIds: [for (final chunk in window.chunks) chunk.id],
      candidates: result.candidates,
    );
    SemanticCandidateValidator.validateBatch(
      request, batch,
      providerId: SemanticPreviewWireContract.providerId,
      providerVersion: SemanticPreviewWireContract.providerVersion,
    );
  }

  /// A replaced window loses its old editorial marks, never silently keeps
  /// decisions on potentially changed suggestions.
  ZaiWindowReviewQueue record(int position, ZaiSemanticPreviewResult preview) {
    if (position < 0 || position >= windows.length) {
      throw RangeError.index(position, windows);
    }
    final expected = windows[position];
    final batch = preview.batch;
    if (batch.providerId != SemanticPreviewWireContract.providerId ||
        batch.providerVersion != SemanticPreviewWireContract.providerVersion ||
        batch.sourceFingerprint != index.sourceFingerprint ||
        batch.chunkIds.length != expected.chunks.length ||
        !batch.chunkIds.indexed.every(
            (entry) => entry.$2 == expected.chunks[entry.$1].id)) {
      throw const FormatException('Ответ относится к чужому окну или модели');
    }
    final value = ZaiWindowReviewResult(
      candidates: batch.candidates,
      totalSuggestions: preview.totalSuggestions,
      rejectedCount: preview.rejectedCount,
      rejectedNonRussian: preview.rejectedNonRussian,
    );
    _validateResult(position, value);
    final next = Map<int, ZaiWindowReviewResult>.from(results);
    final marks = Map<String, ZaiEditorialDecision>.from(decisions);
    for (final item in results[position]?.candidates ?? <SemanticCandidate>[]) {
      marks.remove(item.id);
    }
    next[position] = value;
    return ZaiWindowReviewQueue._(index, windows, next, marks);
  }

  ZaiWindowReviewQueue decide(String candidateId, ZaiEditorialDecision? mark) {
    if (!allCandidates.any((item) => item.id == candidateId)) {
      throw const FormatException('Решение без проверенной исходной цитаты');
    }
    final marks = Map<String, ZaiEditorialDecision>.from(decisions);
    if (mark == null) {
      marks.remove(candidateId);
    } else {
      marks[candidateId] = mark;
    }
    return ZaiWindowReviewQueue._(index, windows, results, marks);
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': index.sourceFingerprint,
    'stage': 'PRIVATE_INFERRED_REVIEW_ONLY',
    'can_publish_bookworld': false,
    'results': [
      for (final position in results.keys.toList()..sort())
        results[position]!.toJson(position, windows[position]),
    ],
    'decisions': {
      for (final id in decisions.keys.toList()..sort())
        id: decisions[id]!.name,
    },
  };

  String encode() {
    for (final entry in results.entries) {
      _validateResult(entry.key, entry.value);
    }
    final allIds = allCandidates.map((item) => item.id).toList();
    if (allIds.toSet().length != allIds.length ||
        decisions.keys.any((id) => !allIds.contains(id))) {
      throw const FormatException('Дублирующаяся цитата или чужое решение');
    }
    final payload = _payload();
    final serialized = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
    });
    if (utf8.encode(serialized).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Очередь смысловых окон слишком велика');
    }
    return serialized;
  }

  static ZaiWindowReviewQueue decode(BookSourceIndex index, String raw) {
    if (utf8.encode(raw).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой checkpoint очереди ИИ');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root.keys.toSet().difference({'format', 'payload', 'sha256'}).isNotEmpty ||
          root.length != 3 || root['format'] != format) {
        throw const FormatException('Неизвестный формат очереди ИИ');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (payload.length != 5 ||
          payload.keys.toSet().difference({
            'source_fingerprint', 'stage', 'can_publish_bookworld',
            'results', 'decisions',
          }).isNotEmpty ||
          root['sha256'] != sha256.convert(
              utf8.encode(jsonEncode(payload))).toString() ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['stage'] != 'PRIVATE_INFERRED_REVIEW_ONLY' ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Очередь повреждена или другая редакция');
      }
      final queue = ZaiWindowReviewQueue.empty(index);
      final entries = payload['results'] as List;
      if (entries.length > queue.windows.length) {
        throw const FormatException('Лишние окна');
      }
      final results = <int, ZaiWindowReviewResult>{};
      final allIds = <String>{};
      for (final rawEntry in entries) {
        final entry = Map<String, dynamic>.from(rawEntry as Map);
        if (entry.length != 6 ||
            entry.keys.toSet().difference({
              'position', 'chunk_ids', 'total_suggestions',
              'rejected_count', 'rejected_non_russian', 'candidates',
            }).isNotEmpty) {
          throw const FormatException('Неизвестные поля результата');
        }
        final position = entry['position'] as int;
        if (position < 0 || position >= queue.windows.length ||
            results.containsKey(position)) {
          throw const FormatException('Повтор окна или неверный индекс');
        }
        final exactIds = [
          for (final piece in queue.windows[position].chunks) piece.id,
        ];
        final savedIds = List<String>.from(entry['chunk_ids'] as List);
        if (jsonEncode(exactIds) != jsonEncode(savedIds)) {
          throw const FormatException('Окно не совпало с книгой');
        }
        final candidates = <SemanticCandidate>[];
        for (final value in entry['candidates'] as List) {
          final item = SemanticCandidate.fromJson(
              Map<String, dynamic>.from(value as Map));
          if (!allIds.add(item.id)) {
            throw const FormatException('Повторённая цитата');
          }
          candidates.add(item);
        }
        final result = ZaiWindowReviewResult(
          candidates: candidates,
          totalSuggestions: entry['total_suggestions'] as int,
          rejectedCount: entry['rejected_count'] as int,
          rejectedNonRussian: entry['rejected_non_russian'] as int,
        );
        queue._validateResult(position, result);
        results[position] = result;
      }
      final decisions = <String, ZaiEditorialDecision>{};
      final decisionsJson =
          Map<String, dynamic>.from(payload['decisions'] as Map);
      for (final entry in decisionsJson.entries) {
        if (!allIds.contains(entry.key)) {
          throw const FormatException('Решение без исходной цитаты');
        }
        decisions[entry.key] = ZaiEditorialDecision.values.byName(
            entry.value as String);
      }
      final decoded = ZaiWindowReviewQueue._(
          index, queue.windows, results, decisions);
      if (decoded.encode() != raw) {
        throw const FormatException('Неполная или изменённая очередь ИИ');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Невозможно прочитать очередь ИИ');
    }
  }
}
