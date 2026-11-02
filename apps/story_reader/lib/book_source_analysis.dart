import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';

/// M2b1 is an offline extraction work queue, not a compiler or an AI model.
/// All hits are untrusted *mentions* awaiting review; no canonical game facts
/// or playable BookWorld are produced.
enum ChunkAnalysisStatus { pending, running, done, failed, review }

enum MentionDecision { review, accepted, rejected }

class SourceMention {
  const SourceMention({
    required this.id,
    required this.chunkId,
    required this.kind,
    required this.label,
    required this.chapterIndex,
    required this.chapterId,
    required this.blockIndex,
    required this.startUtf16,
    required this.endUtf16,
    required this.evidenceSha256,
    this.decision = MentionDecision.review,
  });

  final String id;
  final String chunkId;
  final String kind;
  final String label;
  final int chapterIndex;
  final String chapterId;
  final int blockIndex;
  final int startUtf16;
  final int endUtf16;
  final String evidenceSha256;
  final MentionDecision decision;

  SourceMention decide(MentionDecision value) => SourceMention(
    id: id,
    chunkId: chunkId,
    kind: kind,
    label: label,
    chapterIndex: chapterIndex,
    chapterId: chapterId,
    blockIndex: blockIndex,
    startUtf16: startUtf16,
    endUtf16: endUtf16,
    evidenceSha256: evidenceSha256,
    decision: value,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'chunk_id': chunkId,
    'kind': kind,
    'label': label,
    'chapter_index': chapterIndex,
    'chapter_id': chapterId,
    'block_index': blockIndex,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'evidence_sha256': evidenceSha256,
    'decision': decision.name.toUpperCase(),
  };

  factory SourceMention.fromJson(Map<String, dynamic> json) => SourceMention(
    id: json['id'] as String,
    chunkId: json['chunk_id'] as String,
    kind: json['kind'] as String,
    label: json['label'] as String,
    chapterIndex: json['chapter_index'] as int,
    chapterId: json['chapter_id'] as String,
    blockIndex: json['block_index'] as int,
    startUtf16: json['start_utf16'] as int,
    endUtf16: json['end_utf16'] as int,
    evidenceSha256: json['evidence_sha256'] as String,
    decision: MentionDecision.values.byName(
      (json['decision'] as String).toLowerCase(),
    ),
  );
}

class ChunkAnalysisTask {
  const ChunkAnalysisTask(this.chunkId, this.textSha256, this.status);

  final String chunkId;
  final String textSha256;
  final ChunkAnalysisStatus status;

  ChunkAnalysisTask withStatus(ChunkAnalysisStatus next) =>
      ChunkAnalysisTask(chunkId, textSha256, next);

  Map<String, Object> toJson() => {
    'chunk_id': chunkId,
    'text_sha256': textSha256,
    'status': status.name.toUpperCase(),
  };

  factory ChunkAnalysisTask.fromJson(Map<String, dynamic> json) =>
      ChunkAnalysisTask(
        json['chunk_id'] as String,
        json['text_sha256'] as String,
        ChunkAnalysisStatus.values.byName(
          (json['status'] as String).toLowerCase(),
        ),
      );
}

class SourceAnalysisSession {
  SourceAnalysisSession._(
    this.sourceFingerprint,
    List<ChunkAnalysisTask> tasks,
    List<SourceMention> mentions,
  ) : tasks = List.unmodifiable(tasks),
      mentions = List.unmodifiable(mentions);

  static const format = 'ai_story_source_analysis_m2b1_v1';
  static const maxCheckpointUtf8Bytes = 12 * 1024 * 1024;
  static const maxMentions = 60000;

  final String sourceFingerprint;
  final List<ChunkAnalysisTask> tasks;
  final List<SourceMention> mentions;

  static String _digest(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  factory SourceAnalysisSession.create(BookSourceIndex index) =>
      SourceAnalysisSession._(
        index.sourceFingerprint,
        [
          for (final chunk in index.chunks)
            ChunkAnalysisTask(
              chunk.id, chunk.sha256Text, ChunkAnalysisStatus.pending,
            ),
        ],
        const [],
      );

  int get processedCount => tasks.where((task) =>
      task.status == ChunkAnalysisStatus.done ||
      task.status == ChunkAnalysisStatus.review).length;

  int get pendingCount => tasks.where((task) =>
      task.status == ChunkAnalysisStatus.pending).length;

  int get failedCount => tasks.where((task) =>
      task.status == ChunkAnalysisStatus.failed).length;

  int get reviewCount => mentions.where((mention) =>
      mention.decision == MentionDecision.review).length;

  bool get canPublishBookworld => false;
  double get gameplayCoverage => 0;

  Map<String, Object> _payload() => {
    'source_fingerprint': sourceFingerprint,
    'stage': 'SOURCE_EXTRACTION_REVIEW_ONLY',
    'gameplay_coverage': 0,
    'can_publish_bookworld': false,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'mentions': mentions.map((mention) => mention.toJson()).toList(),
  };

  /// Persist only source IDs, digests and evidence spans (never a whole book).
  /// SHA-256 detects accidental corruption; it is not a signature/authorship.
  String encode() {
    final payload = _payload();
    final text = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _digest(jsonEncode(payload)),
    });
    if (utf8.encode(text).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой checkpoint анализа');
    }
    return text;
  }

  /// Fail closed on wrong edition, different chunking, corruption, altered
  /// evidence, missing work or injected "confirmed" game content.
  /// An interrupted RUNNING task becomes PENDING, never magically DONE.
  static SourceAnalysisSession decode(BookSourceIndex index, String raw) {
    if (utf8.encode(raw).length > maxCheckpointUtf8Bytes) {
      throw const FormatException('Checkpoint анализа слишком велик');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root['format'] != format) {
        throw const FormatException('Неизвестный формат анализа');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (_digest(jsonEncode(payload)) != root['sha256'] ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['stage'] != 'SOURCE_EXTRACTION_REVIEW_ONLY' ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Checkpoint не соответствует книге');
      }
      final rawTasks = payload['tasks'] as List;
      final rawMentions = payload['mentions'] as List;
      if (rawTasks.length != index.chunks.length ||
          rawMentions.length > maxMentions) {
        throw const FormatException('Неполная очередь анализа');
      }
      final tasks = <ChunkAnalysisTask>[];
      final chunksById = <String, SourceChunk>{};
      for (var i = 0; i < index.chunks.length; i++) {
        final chunk = index.chunks[i];
        if (chunksById.containsKey(chunk.id)) {
          throw const FormatException('Повторный идентификатор фрагмента');
        }
        chunksById[chunk.id] = chunk;
        final task = ChunkAnalysisTask.fromJson(
          Map<String, dynamic>.from(rawTasks[i] as Map),
        );
        if (task.chunkId != chunk.id ||
            task.textSha256 != chunk.sha256Text) {
          throw const FormatException('Изменён текст или порядок фрагментов');
        }
        tasks.add(task.status == ChunkAnalysisStatus.running
            ? task.withStatus(ChunkAnalysisStatus.pending) : task);
      }

      final mentions = <SourceMention>[];
      final ids = <String>{};
      for (final rawMention in rawMentions) {
        final mention = SourceMention.fromJson(
          Map<String, dynamic>.from(rawMention as Map),
        );
        final chunk = chunksById[mention.chunkId];
        final task = tasks[index.chunks.indexWhere(
          (x) => x.id == mention.chunkId,
        )];
        if (chunk == null || !ids.add(mention.id) ||
            (mention.kind != 'CHARACTER_NAME' &&
             mention.kind != 'LOCATION_NAME') ||
            (task.status != ChunkAnalysisStatus.review &&
             task.status != ChunkAnalysisStatus.done) ||
            mention.chapterIndex != chunk.chapterIndex ||
            mention.chapterId != chunk.chapterId ||
            mention.blockIndex != chunk.blockIndex ||
            mention.startUtf16 < chunk.startUtf16 ||
            mention.endUtf16 > chunk.endUtf16 ||
            mention.startUtf16 >= mention.endUtf16) {
          throw const FormatException('Повреждена ссылка на источник');
        }
        final relativeStart = mention.startUtf16 - chunk.startUtf16;
        final relativeEnd = mention.endUtf16 - chunk.startUtf16;
        if (chunk.text.substring(relativeStart, relativeEnd) != mention.label ||
            _digest(mention.label) != mention.evidenceSha256 ||
            mention.id != _mentionId(chunk, mention.kind,
              mention.startUtf16, mention.endUtf16, mention.label)) {
          throw const FormatException('Подмена доказательства в тексте');
        }
        mentions.add(mention);
      }
      for (final task in tasks) {
        final needsReview = mentions.any((m) =>
            m.chunkId == task.chunkId &&
            m.decision == MentionDecision.review);
        if ((task.status == ChunkAnalysisStatus.review) != needsReview) {
          throw const FormatException('Несогласованное состояние проверки');
        }
      }
      return SourceAnalysisSession._(index.sourceFingerprint, tasks, mentions);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённый checkpoint анализа');
    }
  }

  SourceAnalysisSession startNext() {
    if (tasks.any((x) => x.status == ChunkAnalysisStatus.running)) {
      throw StateError('Сначала завершите RUNNING фрагмент');
    }
    final position = tasks.indexWhere(
      (x) => x.status == ChunkAnalysisStatus.pending,
    );
    if (position < 0) return this;
    final updated = List<ChunkAnalysisTask>.from(tasks);
    updated[position] = updated[position].withStatus(
      ChunkAnalysisStatus.running,
    );
    return SourceAnalysisSession._(sourceFingerprint, updated, mentions);
  }

  /// Explicit failed jobs remain FAILED until the user requests retry.
  SourceAnalysisSession failRunning() {
    final position = tasks.indexWhere(
      (x) => x.status == ChunkAnalysisStatus.running,
    );
    if (position < 0) throw StateError('Нет RUNNING фрагмента');
    final updated = List<ChunkAnalysisTask>.from(tasks);
    updated[position] = updated[position].withStatus(ChunkAnalysisStatus.failed);
    return SourceAnalysisSession._(sourceFingerprint, updated, mentions);
  }

  SourceAnalysisSession retryFailed() => SourceAnalysisSession._(
    sourceFingerprint,
    [for (final task in tasks)
      task.status == ChunkAnalysisStatus.failed
        ? task.withStatus(ChunkAnalysisStatus.pending) : task],
    mentions,
  );

  SourceAnalysisSession finishRunning(BookSourceIndex index) {
    if (index.sourceFingerprint != sourceFingerprint ||
        tasks.length != index.chunks.length) {
      throw const FormatException('Не та редакция книги');
    }
    final position = tasks.indexWhere(
      (x) => x.status == ChunkAnalysisStatus.running,
    );
    if (position < 0) throw StateError('Нет RUNNING фрагмента');
    final chunk = index.chunks[position];
    if (tasks[position].chunkId != chunk.id ||
        tasks[position].textSha256 != chunk.sha256Text ||
        _digest(chunk.text) != chunk.sha256Text) {
      throw const FormatException('Изменён фрагмент исходного текста');
    }
    final found = _scan(chunk);
    if (mentions.length + found.length > maxMentions) {
      throw const FormatException('Слишком много кандидатов анализа');
    }
    final updated = List<ChunkAnalysisTask>.from(tasks);
    updated[position] = updated[position].withStatus(
      found.isEmpty ? ChunkAnalysisStatus.done : ChunkAnalysisStatus.review,
    );
    return SourceAnalysisSession._(
      sourceFingerprint, updated, [...mentions, ...found],
    );
  }

  SourceAnalysisSession processBatch(
    BookSourceIndex index, {int limit = 24}
  ) {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    var current = this;
    for (var i = 0; i < limit && current.pendingCount > 0; i++) {
      current = current.startNext().finishRunning(index);
    }
    return current;
  }

  /// ACCEPTED means "this text mention was reviewed", NOT an accepted canon
  /// fact, character identity, spoiler permission, or game world effect.
  SourceAnalysisSession decide(String id, MentionDecision decision) {
    if (decision == MentionDecision.review) {
      throw ArgumentError.value(decision, 'decision');
    }
    final pos = mentions.indexWhere((mention) => mention.id == id);
    if (pos < 0) throw ArgumentError.value(id, 'id', 'Неизвестный кандидат');
    final updatedMentions = List<SourceMention>.from(mentions);
    updatedMentions[pos] = updatedMentions[pos].decide(decision);
    final chunkId = updatedMentions[pos].chunkId;
    final stillPending = updatedMentions.any((mention) =>
        mention.chunkId == chunkId &&
        mention.decision == MentionDecision.review);
    final updatedTasks = List<ChunkAnalysisTask>.from(tasks);
    final taskIndex = updatedTasks.indexWhere(
      (task) => task.chunkId == chunkId,
    );
    updatedTasks[taskIndex] = updatedTasks[taskIndex].withStatus(
      stillPending ? ChunkAnalysisStatus.review : ChunkAnalysisStatus.done,
    );
    return SourceAnalysisSession._(
      sourceFingerprint, updatedTasks, updatedMentions,
    );
  }

  static String _mentionId(SourceChunk chunk, String kind,
      int start, int end, String label) =>
      _digest(chunk.id + '|' + kind + '|' + start.toString() + '|' +
          end.toString() + '|' + label).substring(0, 24);

  static final _patterns = <(String, RegExp)>[
    ('CHARACTER_NAME', RegExp(
      r'(?:[Пп]о имени|[Зз]вали|[Nn]amed)\s+([А-ЯЁ][а-яё-]{1,40}|[A-Z][a-z-]{1,40})',
      unicode: true,
    )),
    ('LOCATION_NAME', RegExp(
      r'(?:[Вв] городе|[Вв] деревне|[Гг]ород|[Дд]еревня|[Ii]n the city of)\s+([А-ЯЁ][а-яё-]{1,40}|[A-Z][a-z-]{1,40})',
      unicode: true,
    )),
  ];

  static List<SourceMention> _scan(SourceChunk chunk) {
    final hits = <SourceMention>[];
    final unique = <String>{};
    for (final pattern in _patterns) {
      for (final match in pattern.$2.allMatches(chunk.text)) {
        final label = match.group(1)!;
        final relativeStart = match.start + match.group(0)!.lastIndexOf(label);
        final start = chunk.startUtf16 + relativeStart;
        final end = start + label.length;
        final id = _mentionId(chunk, pattern.$1, start, end, label);
        if (!unique.add(id)) continue;
        hits.add(SourceMention(
          id: id,
          chunkId: chunk.id,
          kind: pattern.$1,
          label: label,
          chapterIndex: chunk.chapterIndex,
          chapterId: chunk.chapterId,
          blockIndex: chunk.blockIndex,
          startUtf16: start,
          endUtf16: end,
          evidenceSha256: _digest(label),
        ));
      }
    }
    hits.sort((a, b) => a.startUtf16.compareTo(b.startUtf16));
    return hits;
  }
}
