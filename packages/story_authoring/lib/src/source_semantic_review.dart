import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_semantic_provider.dart';

/// M2b4a: a separate, private, resumable semantic proposal checkpoint.
/// This never writes to BookWorld, source review checkpoints or game saves.
enum SemanticChunkStatus { pending, done }
enum SemanticReviewDecision { keptForReview, rejected }

class SemanticChunkTask {
  const SemanticChunkTask(this.chunkId, this.sha256Text, this.status);

  final String chunkId;
  final String sha256Text;
  final SemanticChunkStatus status;

  SemanticChunkTask complete() =>
      SemanticChunkTask(chunkId, sha256Text, SemanticChunkStatus.done);

  Map<String, Object> toJson() => {
    'chunk_id': chunkId,
    'sha256_text': sha256Text,
    'status': status.name.toUpperCase(),
  };

  factory SemanticChunkTask.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        json.keys.toSet().difference(
          {'chunk_id', 'sha256_text', 'status'}).isNotEmpty) {
      throw const FormatException('Повреждённая очередь семантического анализа');
    }
    try {
      return SemanticChunkTask(
        json['chunk_id'] as String,
        json['sha256_text'] as String,
        SemanticChunkStatus.values.byName(
          (json['status'] as String).toLowerCase()),
      );
    } catch (_) {
      throw const FormatException('Неизвестный статус фрагмента');
    }
  }
}

/// Explicit editor markings are NOT proof, canon confirmation or world state.
class SemanticReviewSession {
  SemanticReviewSession._({
    required this.sourceFingerprint,
    required this.providerId,
    required this.providerVersion,
    required List<SemanticChunkTask> tasks,
    required List<SemanticCandidate> candidates,
    required Map<String, SemanticReviewDecision> decisions,
  }) : tasks = List.unmodifiable(tasks),
       candidates = List.unmodifiable(candidates),
       decisions = Map.unmodifiable(decisions);

  static const format = 'ai_story_semantic_review_m2b4a_v1';
  static const maxCheckpointUtf8Bytes = 12 * 1024 * 1024;
  static const maxStoredCandidates = 60000;
  static const maxBatchChunks = 8;

  static const Set<SemanticCategory> _categories = {
    SemanticCategory.character,
    SemanticCategory.location,
  };

  final String sourceFingerprint;
  final String providerId;
  final String providerVersion;
  final List<SemanticChunkTask> tasks;
  final List<SemanticCandidate> candidates;
  final Map<String, SemanticReviewDecision> decisions;

  int get processedCount =>
      tasks.where((t) => t.status == SemanticChunkStatus.done).length;
  int get pendingCount => tasks.length - processedCount;
  int get undecidedCount => candidates.length - decisions.length;
  int get keptCount =>
      decisions.values.where((v) => v == SemanticReviewDecision.keptForReview).length;

  double get gameplayCoverage => 0;
  bool get canPublishBookworld => false;

  static String _sha(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  static void _checkProvider(SourceSemanticProvider provider) {
    if (!provider.isAvailable ||
        provider.mode != SemanticProviderMode.offlineRules ||
        provider.id.isEmpty || provider.id.length > 80 ||
        provider.version.isEmpty || provider.version.length > 80) {
      throw const FormatException('Семантический провайдер недоступен');
    }
  }

  factory SemanticReviewSession.create(
      BookSourceIndex index, SourceSemanticProvider provider) {
    _checkProvider(provider);
    return SemanticReviewSession._(
      sourceFingerprint: index.sourceFingerprint,
      providerId: provider.id,
      providerVersion: provider.version,
      tasks: [
        for (final chunk in index.chunks)
          SemanticChunkTask(chunk.id, chunk.sha256Text, SemanticChunkStatus.pending),
      ],
      candidates: const [],
      decisions: const {},
    );
  }

  /// A batch is fully validated before any caller may persist the new state.
  /// Failure or cancellation leaves this immutable instance unchanged.
  Future<SemanticReviewSession> processNext(
      BookSourceIndex index, SourceSemanticProvider provider, {
      int limit = maxBatchChunks,
  }) async {
    _checkProvider(provider);
    if (limit < 1 || limit > maxBatchChunks) {
      throw RangeError.range(limit, 1, maxBatchChunks, 'limit');
    }
    _verifyTasks(index, provider);
    if (pendingCount == 0) return this;
    final selected = <SourceChunk>[];
    final positions = <int>[];
    for (var i = 0; i < tasks.length && selected.length < limit; i++) {
      if (tasks[i].status != SemanticChunkStatus.pending) continue;
      selected.add(index.chunks[i]);
      positions.add(i);
    }
    final request = SemanticExtractionRequest(
      index: index, chunks: selected, categories: _categories,
    );
    final result = await SemanticProviderGate.run(provider, request);
    if (candidates.length + result.candidates.length > maxStoredCandidates) {
      throw const FormatException('Слишком много семантических кандидатов');
    }
    final ids = {for (final item in candidates) item.id};
    for (final item in result.candidates) {
      if (!ids.add(item.id)) {
        throw const FormatException('Повторное семантическое доказательство');
      }
    }
    final next = List<SemanticChunkTask>.from(tasks);
    for (final position in positions) {
      next[position] = next[position].complete();
    }
    return SemanticReviewSession._(
      sourceFingerprint: sourceFingerprint,
      providerId: providerId,
      providerVersion: providerVersion,
      tasks: next,
      candidates: [...candidates, ...result.candidates],
      decisions: decisions,
    );
  }

  SemanticReviewSession decide(String candidateId,
      SemanticReviewDecision? verdict) {
    if (!candidates.any((c) => c.id == candidateId)) {
      throw ArgumentError.value(candidateId, 'candidateId');
    }
    final next = Map<String, SemanticReviewDecision>.from(decisions);
    if (verdict == null) {
      next.remove(candidateId);
    } else {
      next[candidateId] = verdict;
    }
    return SemanticReviewSession._(
      sourceFingerprint: sourceFingerprint,
      providerId: providerId,
      providerVersion: providerVersion,
      tasks: tasks,
      candidates: candidates,
      decisions: next,
    );
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': sourceFingerprint,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'stage': 'SEMANTIC_PROPOSALS_ONLY',
    'gameplay_coverage': 0,
    'can_publish_bookworld': false,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    'decisions': {
      for (final entry in decisions.entries)
        entry.key: entry.value.name.toUpperCase(),
    },
  };

  String encode() {
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Семантический checkpoint слишком велик');
    }
    return raw;
  }

  void _verifyTasks(BookSourceIndex index, SourceSemanticProvider provider) {
    if (sourceFingerprint != index.sourceFingerprint ||
        providerId != provider.id || providerVersion != provider.version ||
        tasks.length != index.chunks.length) {
      throw const FormatException('Checkpoint не соответствует книге или провайдеру');
    }
    for (var i = 0; i < tasks.length; i++) {
      final item = tasks[i];
      final chunk = index.chunks[i];
      if (item.chunkId != chunk.id || item.sha256Text != chunk.sha256Text) {
        throw const FormatException('Изменён исходный фрагмент');
      }
    }
  }

  /// Recompute SHA and validate *every* embedded candidate against the exact
  /// original UTF-16 source before exposing persisted results to the UI.
  static SemanticReviewSession decode(
      BookSourceIndex index, SourceSemanticProvider provider, String raw) {
    _checkProvider(provider);
    if (utf8.encode(raw).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой checkpoint');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root.length != 3 ||
          root.keys.toSet().difference({'format', 'payload', 'sha256'}).isNotEmpty ||
          root['format'] != format) {
        throw const FormatException('Неизвестная версия semantic checkpoint');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (payload.length != 9 ||
          payload.keys.toSet().difference({
            'source_fingerprint', 'provider_id', 'provider_version', 'stage',
            'gameplay_coverage', 'can_publish_bookworld', 'tasks',
            'candidates', 'decisions',
          }).isNotEmpty ||
          root['sha256'] != _sha(jsonEncode(payload)) ||
          payload['stage'] != 'SEMANTIC_PROPOSALS_ONLY' ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Повреждён semantic checkpoint');
      }
      final rawTasks = payload['tasks'] as List;
      final rawCandidates = payload['candidates'] as List;
      if (rawTasks.length != index.chunks.length ||
          rawCandidates.length > maxStoredCandidates) {
        throw const FormatException('Неверное количество записей');
      }
      final tasks = [
        for (final t in rawTasks)
          SemanticChunkTask.fromJson(Map<String, dynamic>.from(t as Map)),
      ];
      final candidates = <SemanticCandidate>[];
      final seen = <String>{};
      final chunks = {for (final c in index.chunks) c.id: c};
      final status = {for (final t in tasks) t.chunkId: t.status};
      for (final value in rawCandidates) {
        final item = SemanticCandidate.fromJson(
            Map<String, dynamic>.from(value as Map));
        if (!seen.add(item.id) ||
            status[item.chunkId] != SemanticChunkStatus.done ||
            chunks[item.chunkId] == null) {
          throw const FormatException('Несогласованная запись semantic');
        }
        SemanticCandidateValidator.validateCandidate(
          index, item,
          allowedChunkIds: {item.chunkId},
          categories: _categories,
          sourceChunk: chunks[item.chunkId],
        );
        candidates.add(item);
      }
      final decisionsRaw = Map<String, dynamic>.from(payload['decisions'] as Map);
      final decisions = <String, SemanticReviewDecision>{};
      if (decisionsRaw.length > candidates.length) {
        throw const FormatException('Лишние решения редактора');
      }
      for (final entry in decisionsRaw.entries) {
        if (!seen.contains(entry.key)) {
          throw const FormatException('Решение относится к чужой цитате');
        }
        decisions[entry.key] = switch (entry.value) {
          'KEPTFORREVIEW' => SemanticReviewDecision.keptForReview,
          'REJECTED' => SemanticReviewDecision.rejected,
          _ => throw const FormatException('Неизвестное решение редактора'),
        };
      }
      final session = SemanticReviewSession._(
        sourceFingerprint: payload['source_fingerprint'] as String,
        providerId: payload['provider_id'] as String,
        providerVersion: payload['provider_version'] as String,
        tasks: tasks,
        candidates: candidates,
        decisions: decisions,
      );
      session._verifyTasks(index, provider);
      if (session.encode() != raw) {
        throw const FormatException('Неправильная сериализация checkpoint');
      }
      return session;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Некорректный semantic checkpoint');
    }
  }
}
