import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_analysis.dart';
import 'book_source_index.dart';

/// M2b3a: source-backed, untrusted compiler proposals.
/// Neither an accepted text mention nor a model proposal becomes canon until
/// explicit human verification. This module does not change story_core.
enum EvidenceKind { character, location, fact, event }
enum EvidenceStatus { inferred, confirmed, conflicted, rejected }
enum EvidenceSpoilerGate { chapter, afterEvent, hidden }

class SourceEvidence {
  const SourceEvidence._({
    required this.id,
    required this.sourceFingerprint,
    required this.chunkId,
    required this.kind,
    required this.label,
    required this.evidenceSha256,
    required this.chapterIndex,
    required this.chapterId,
    required this.blockIndex,
    required this.startUtf16,
    required this.endUtf16,
    required this.status,
    required this.spoilerGate,
    required this.visibleAfterChapter,
    this.revealEventId,
  });

  final String id;
  final String sourceFingerprint;
  final String chunkId;
  final EvidenceKind kind;
  final String label;
  final String evidenceSha256;
  final int chapterIndex;
  final String chapterId;
  final int blockIndex;
  final int startUtf16;
  final int endUtf16;
  final EvidenceStatus status;
  final EvidenceSpoilerGate spoilerGate;
  final int visibleAfterChapter;
  final String? revealEventId;

  static String _sha(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static SourceChunk _chunk(BookSourceIndex index, String chunkId) {
    for (final chunk in index.chunks) {
      if (chunk.id == chunkId) return chunk;
    }
    throw const FormatException('Источник доказательства не найден');
  }

  static String _id(String fingerprint, String chunkId, EvidenceKind kind,
      int start, int end, String textDigest) =>
      _sha('$fingerprint|$chunkId|${kind.name}|$start|$end|$textDigest')
          .substring(0, 32);

  /// Extraction is *only a proposal*. The quoted evidence is an exact slice
  /// of an M2a chunk. It must not be treated as authoritative fact or event.
  factory SourceEvidence.propose(
    BookSourceIndex index, {
    required String chunkId,
    required EvidenceKind kind,
    required int startUtf16,
    required int endUtf16,
    EvidenceSpoilerGate spoilerGate = EvidenceSpoilerGate.chapter,
    int? visibleAfterChapter,
    String? revealEventId,
  }) {
    final chunk = _chunk(index, chunkId);
    if (startUtf16 < chunk.startUtf16 ||
        endUtf16 > chunk.endUtf16 ||
        endUtf16 <= startUtf16 ||
        endUtf16 - startUtf16 > 180) {
      throw const FormatException('Некорректный диапазон доказательства');
    }
    final start = startUtf16 - chunk.startUtf16;
    final end = endUtf16 - chunk.startUtf16;
    final text = chunk.text.substring(start, end);
    if (text.trim().isEmpty) {
      throw const FormatException('Пустое доказательство');
    }
    if (start > 0 && _isLow(chunk.text.codeUnitAt(start))) {
      throw const FormatException('Диапазон разрезает символ Unicode');
    }
    if (end < chunk.text.length && _isLow(chunk.text.codeUnitAt(end))) {
      throw const FormatException('Диапазон разрезает символ Unicode');
    }
    final gateChapter = visibleAfterChapter ?? chunk.chapterIndex;
    if (gateChapter < chunk.chapterIndex ||
        gateChapter >= index.chapters.length ||
        (spoilerGate == EvidenceSpoilerGate.afterEvent &&
            (revealEventId == null || revealEventId.isEmpty)) ||
        (spoilerGate != EvidenceSpoilerGate.afterEvent &&
            revealEventId != null)) {
      throw const FormatException('Небезопасное правило раскрытия');
    }
    final digest = _sha(text);
    return SourceEvidence._(
      id: _id(index.sourceFingerprint, chunkId, kind,
          startUtf16, endUtf16, digest),
      sourceFingerprint: index.sourceFingerprint,
      chunkId: chunkId,
      kind: kind,
      label: text,
      evidenceSha256: digest,
      chapterIndex: chunk.chapterIndex,
      chapterId: chunk.chapterId,
      blockIndex: chunk.blockIndex,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      status: EvidenceStatus.inferred,
      spoilerGate: spoilerGate,
      visibleAfterChapter: gateChapter,
      revealEventId: revealEventId,
    );
  }

  static bool _isLow(int value) => value >= 0xdc00 && value <= 0xdfff;

  SourceEvidence _copy({
    EvidenceStatus? status,
    EvidenceSpoilerGate? spoilerGate,
    int? visibleAfterChapter,
    String? revealEventId,
    bool replaceReveal = false,
  }) => SourceEvidence._(
    id: id,
    sourceFingerprint: sourceFingerprint,
    chunkId: chunkId,
    kind: kind,
    label: label,
    evidenceSha256: evidenceSha256,
    chapterIndex: chapterIndex,
    chapterId: chapterId,
    blockIndex: blockIndex,
    startUtf16: startUtf16,
    endUtf16: endUtf16,
    status: status ?? this.status,
    spoilerGate: spoilerGate ?? this.spoilerGate,
    visibleAfterChapter: visibleAfterChapter ?? this.visibleAfterChapter,
    revealEventId: replaceReveal ? revealEventId : this.revealEventId,
  );

  /// A human's explicit review is the only path to CONFIRMED.
  SourceEvidence reviewed(EvidenceStatus next) {
    if (next == EvidenceStatus.inferred) {
      throw ArgumentError.value(next, 'next', 'Не является решением');
    }
    return _copy(status: next);
  }

  SourceEvidence withGate(BookSourceIndex index, EvidenceSpoilerGate gate, {
    int? chapter,
    String? eventId,
  }) {
    final verified = SourceEvidence.propose(index,
      chunkId: chunkId, kind: kind, startUtf16: startUtf16,
      endUtf16: endUtf16, spoilerGate: gate,
      visibleAfterChapter: chapter, revealEventId: eventId,
    );
    return _copy(
      spoilerGate: verified.spoilerGate,
      visibleAfterChapter: verified.visibleAfterChapter,
      revealEventId: verified.revealEventId,
      replaceReveal: true,
    );
  }

  bool playerCanSee({
    required int currentChapter,
    Set<String> knownEvents = const {},
  }) {
    if (status != EvidenceStatus.confirmed ||
        currentChapter < visibleAfterChapter ||
        spoilerGate == EvidenceSpoilerGate.hidden) return false;
    if (spoilerGate == EvidenceSpoilerGate.afterEvent) {
      return knownEvents.contains(revealEventId);
    }
    return true;
  }

  void validate(BookSourceIndex index) {
    if (sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Другая редакция книги');
    }
    final correct = SourceEvidence.propose(index,
      chunkId: chunkId, kind: kind,
      startUtf16: startUtf16, endUtf16: endUtf16,
      spoilerGate: spoilerGate,
      visibleAfterChapter: visibleAfterChapter,
      revealEventId: revealEventId,
    );
    if (id != correct.id || label != correct.label ||
        evidenceSha256 != correct.evidenceSha256 ||
        chapterIndex != correct.chapterIndex ||
        chapterId != correct.chapterId ||
        blockIndex != correct.blockIndex) {
      throw const FormatException('Подмена источника или доказательства');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'source_fingerprint': sourceFingerprint,
    'chunk_id': chunkId,
    'kind': kind.name.toUpperCase(),
    'label': label,
    'evidence_sha256': evidenceSha256,
    'chapter_index': chapterIndex,
    'chapter_id': chapterId,
    'block_index': blockIndex,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'status': status.name.toUpperCase(),
    'spoiler_gate': spoilerGate.name.toUpperCase(),
    'visible_after_chapter': visibleAfterChapter,
    'reveal_event_id': revealEventId,
  };

  factory SourceEvidence.fromJson(BookSourceIndex index,
      Map<String, dynamic> json) {
    try {
      final kind = EvidenceKind.values.byName(
          (json['kind'] as String).toLowerCase());
      final gate = EvidenceSpoilerGate.values.byName(
          (json['spoiler_gate'] as String).toLowerCase());
      final base = SourceEvidence.propose(index,
        chunkId: json['chunk_id'] as String,
        kind: kind,
        startUtf16: json['start_utf16'] as int,
        endUtf16: json['end_utf16'] as int,
        spoilerGate: gate,
        visibleAfterChapter: json['visible_after_chapter'] as int,
        revealEventId: json['reveal_event_id'] as String?,
      );
      final status = EvidenceStatus.values.byName(
          (json['status'] as String).toLowerCase());
      final verified = base._copy(status: status);
      if (jsonEncode(verified.toJson()) != jsonEncode(json)) {
        throw const FormatException('Доказательство повреждено');
      }
      verified.validate(index);
      return verified;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Недопустимые поля доказательства');
    }
  }
}

class PossibleEntityMatch {
  const PossibleEntityMatch({
    required this.normalizedName,
    required this.kind,
    required this.evidenceIds,
  });

  final String normalizedName;
  final EvidenceKind kind;
  final List<String> evidenceIds;

  /// Identical spelling across chapters never proves identical identity.
  bool get identityConfirmed => false;
  bool get requiresReview => true;
}

class SourceEvidenceGraph {
  SourceEvidenceGraph._(this.sourceFingerprint, List<SourceEvidence> records)
      : records = List.unmodifiable(records);

  static const format = 'ai_story_source_evidence_m2b3a_v1';
  static const maxRecords = 60000;
  static const maxBytes = 12 * 1024 * 1024;

  final String sourceFingerprint;
  final List<SourceEvidence> records;

  factory SourceEvidenceGraph.empty(BookSourceIndex index) =>
      SourceEvidenceGraph._(index.sourceFingerprint, const []);

  /// Only accepted *mentions* from M2b1 are imported. They start INFERRED,
  /// and a repeated name is not automatically fused into one character.
  factory SourceEvidenceGraph.fromReviewedMentions(
      BookSourceIndex index, SourceAnalysisSession session) {
    if (index.sourceFingerprint != session.sourceFingerprint) {
      throw const FormatException('Анализ относится к другой книге');
    }
    final items = <SourceEvidence>[];
    for (final mention in session.mentions) {
      if (mention.decision != MentionDecision.accepted) continue;
      final kind = switch (mention.kind) {
        'CHARACTER_NAME' => EvidenceKind.character,
        'LOCATION_NAME' => EvidenceKind.location,
        _ => throw const FormatException('Неизвестный тип упоминания'),
      };
      final proposal = SourceEvidence.propose(index,
        chunkId: mention.chunkId,
        kind: kind,
        startUtf16: mention.startUtf16,
        endUtf16: mention.endUtf16,
      );
      if (proposal.label != mention.label ||
          proposal.evidenceSha256 != mention.evidenceSha256 ||
          proposal.chapterIndex != mention.chapterIndex ||
          proposal.chapterId != mention.chapterId ||
          proposal.blockIndex != mention.blockIndex) {
        throw const FormatException('Неверная ссылка M2b1 на источник');
      }
      items.add(proposal);
    }
    return SourceEvidenceGraph.empty(index).addAll(index, items);
  }

  SourceEvidenceGraph addAll(BookSourceIndex index,
      Iterable<SourceEvidence> proposed) {
    if (index.sourceFingerprint != sourceFingerprint) {
      throw const FormatException('Другая редакция книги');
    }
    final all = [...records];
    final ids = {for (final record in records) record.id};
    for (final evidence in proposed) {
      evidence.validate(index);
      if (!ids.add(evidence.id) || all.length >= maxRecords) {
        throw const FormatException('Дубликат или превышение лимита доказательств');
      }
      all.add(evidence);
    }
    return SourceEvidenceGraph._(sourceFingerprint, all);
  }

  SourceEvidenceGraph review(BookSourceIndex index, String id,
      EvidenceStatus verdict) {
    if (index.sourceFingerprint != sourceFingerprint) {
      throw const FormatException('Другая редакция книги');
    }
    final pos = records.indexWhere((entry) => entry.id == id);
    if (pos < 0) throw ArgumentError.value(id, 'id');
    records[pos].validate(index);
    final updated = [...records];
    updated[pos] = updated[pos].reviewed(verdict);
    return SourceEvidenceGraph._(sourceFingerprint, updated);
  }

  List<PossibleEntityMatch> get possibleCrossChapterMatches {
    final groups = <String, List<SourceEvidence>>{};
    for (final e in records) {
      if (e.kind != EvidenceKind.character &&
          e.kind != EvidenceKind.location) continue;
      if (e.status == EvidenceStatus.rejected) continue;
      final label = e.label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final key = '${e.kind.name}|$label';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final result = <PossibleEntityMatch>[];
    for (final entries in groups.values) {
      if (entries.map((e) => e.chapterIndex).toSet().length < 2) continue;
      result.add(PossibleEntityMatch(
        normalizedName: entries.first.label.trim().toLowerCase(),
        kind: entries.first.kind,
        evidenceIds: List.unmodifiable(entries.map((e) => e.id)),
      ));
    }
    result.sort((a, b) => a.normalizedName.compareTo(b.normalizedName));
    return List.unmodifiable(result);
  }

  List<SourceEvidence> visibleToPlayer({
    required int currentChapter,
    Set<String> knownEvents = const {},
  }) => List.unmodifiable(records.where((e) =>
      e.playerCanSee(
        currentChapter: currentChapter,
        knownEvents: knownEvents,
      )));

  /// Store only candidate snippets and source spans, not the full book.
  String encode() {
    final payload = {
      'source_fingerprint': sourceFingerprint,
      'gameplay_coverage': 0,
      'can_publish_bookworld': false,
      'evidence': records.map((r) => r.toJson()).toList(),
    };
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': SourceEvidence._sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой набор доказательств');
    }
    return raw;
  }

  static SourceEvidenceGraph decode(BookSourceIndex index, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой набор доказательств');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root['format'] != format) {
        throw const FormatException('Неизвестная версия evidence');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (root['sha256'] != SourceEvidence._sha(jsonEncode(payload)) ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Повреждённый или чужой набор evidence');
      }
      final items = payload['evidence'] as List<dynamic>;
      if (items.length > maxRecords) {
        throw const FormatException('Слишком много доказательств');
      }
      final result = SourceEvidenceGraph.empty(index);
      return result.addAll(index, [
        for (final item in items)
          SourceEvidence.fromJson(index,
              Map<String, dynamic>.from(item as Map)),
      ]);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неверная структура evidence');
    }
  }
}
