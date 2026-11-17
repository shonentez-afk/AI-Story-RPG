import 'book_event_outline.dart';
import 'book_source_index.dart';
import 'narrative_book_model.dart';

/// An UNTRUSTED model/manual list of event interpretations. Only its literal
/// UTF-16 excerpts and complete per-chunk inventory are checked here.
/// A complete scan does NOT mean literary meaning or causality is verified.
class SourceLockedEventCandidate implements BookEventProposal {
  const SourceLockedEventCandidate({
    required this.id,
    required this.chunkId,
    required this.chapterIndex,
    required this.blockIndex,
    required this.startUtf16,
    required this.quote,
    required this.label,
  });

  @override final String id;
  @override final String chunkId;
  @override final int chapterIndex;
  @override final int blockIndex;
  @override final int startUtf16;
  @override final String quote;
  @override final String label;

  Map<String, Object> toJson() => {
    'id': id, 'chunk_id': chunkId,
    'chapter_index': chapterIndex, 'block_index': blockIndex,
    'start_utf16': startUtf16, 'quote': quote, 'label': label,
  };
}

class SourceLockedEventOutline implements BookEventOutline {
  SourceLockedEventOutline._(
      this.sourceFingerprint, this.totalChapters,
      this.events, this.chaptersWithEventProposals);

  static const format = 'ai_story_external_source_events_v1';
  final String sourceFingerprint;
  final int totalChapters;
  final List<SourceLockedEventCandidate> events;
  final int chaptersWithEventProposals;

  /// Means all original text fragments were enumerated in this edition.
  /// Does NOT attest that the provider actually understood every chapter.
  @override
  bool get analysisComplete => true;
  bool get literaryMeaningVerified => false;
  bool get causalLinksVerified => false;
  bool get worldReady => false;

  /// The only accepted envelope has exact fingerprint, every indexed chunk
  /// and exact text-bound event excerpts; unknown fields fail closed.
  factory SourceLockedEventOutline.fromJson(
      BookSourceIndex index, Map<String, dynamic> json) {
    const fields = {'format', 'stage', 'source_fingerprint',
      'scanned_chunks', 'events'};
    if (json.keys.toSet().length != fields.length ||
        !json.keys.toSet().containsAll(fields) ||
        json['format'] != format ||
        json['stage'] != 'UNREVIEWED_EVENTS' ||
        json['source_fingerprint'] != index.sourceFingerprint ||
        index.chapterCount < 1 ||
        index.indexedChapterCount != index.chapterCount ||
        json['scanned_chunks'] is! List ||
        json['events'] is! List) {
      throw const FormatException(
          'Не подтверждён полный набор исходных отрывков книги');
    }
    final scanned = json['scanned_chunks'] as List;
    if (scanned.length != index.chunks.length) {
      throw const FormatException('Не все части книги представлены в анализе');
    }
    for (var i = 0; i < scanned.length; i++) {
      final raw = scanned[i];
      if (raw is! Map ||
          raw.keys.toSet().difference({'chunk_id', 'sha256_text'}).isNotEmpty ||
          raw.length != 2 ||
          raw['chunk_id'] != index.chunks[i].id ||
          raw['sha256_text'] != index.chunks[i].sha256Text) {
        throw const FormatException(
            'Порядок или исходные SHA-256 фрагментов не совпадают');
      }
    }
    final byId = {for (final c in index.chunks) c.id: c};
    final ids = <String>{};
    final events = <SourceLockedEventCandidate>[];
    final chapterIds = <int>{};
    final inputs = json['events'] as List;
    if (inputs.length > NarrativeBookModel.maxEvents) {
      throw const FormatException('Слишком много предложенных событий');
    }
    var previousChapter = -1;
    var previousBlock = -1;
    var previousPosition = -1;
    for (final input in inputs) {
      if (input is! Map) {
        throw const FormatException('Некорректный кандидат события');
      }
      const keys = {'id', 'chunk_id', 'chapter_index', 'block_index',
        'start_utf16', 'quote', 'label'};
      if (input.length != keys.length ||
          !input.keys.toSet().containsAll(keys) ||
          input['id'] is! String || input['chunk_id'] is! String ||
          input['chapter_index'] is! int || input['block_index'] is! int ||
          input['start_utf16'] is! int || input['quote'] is! String ||
          input['label'] is! String) {
        throw const FormatException('Неверные поля кандидата события');
      }
      final id = input['id'] as String;
      final chunkId = input['chunk_id'] as String;
      final chapter = input['chapter_index'] as int;
      final block = input['block_index'] as int;
      final position = input['start_utf16'] as int;
      final quote = input['quote'] as String;
      final label = input['label'] as String;
      final chunk = byId[chunkId];
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,79}$').hasMatch(id) ||
          !ids.add(id) || chunk == null ||
          quote.length < 3 || quote.length > 180 ||
          label.trim().isEmpty || label.length > 240 ||
          label.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')) ||
          chapter != chunk.chapterIndex || block != chunk.blockIndex ||
          position < chunk.startUtf16 ||
          position + quote.length > chunk.endUtf16 ||
          chapter < previousChapter ||
          chapter == previousChapter && block < previousBlock ||
          chapter == previousChapter && block == previousBlock &&
              position < previousPosition) {
        throw const FormatException(
            'Чужое, дублированное или переставленное событие');
      }
      // Reuse the SAME exact UTF-16 + surrogate split validator as the book
      // narrative model. No independent approximation or model assertions.
      NarrativeCitation(
        chunkId: chunkId, chapterIndex: chapter, blockIndex: block,
        startUtf16: position, endUtf16: position + quote.length,
        quote: quote,
      ).validate(index);
      events.add(SourceLockedEventCandidate(
        id: id, chunkId: chunkId, chapterIndex: chapter,
        blockIndex: block, startUtf16: position, quote: quote,
        label: label,
      ));
      chapterIds.add(chapter);
      previousChapter = chapter;
      previousBlock = block;
      previousPosition = position;
    }
    return SourceLockedEventOutline._(
        index.sourceFingerprint, index.chapterCount,
        List.unmodifiable(events), chapterIds.length);
  }

  Map<String, Object> toJson(BookSourceIndex index) {
    if (sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Изменена исходная редакция');
    }
    return {
      'format': format, 'stage': 'UNREVIEWED_EVENTS',
      'source_fingerprint': sourceFingerprint,
      'scanned_chunks': [
        for (final c in index.chunks)
          {'chunk_id': c.id, 'sha256_text': c.sha256Text},
      ],
      'events': [for (final e in events) e.toJson()],
    };
  }

  /// Convenient construction of the exact, untrusted JSON envelope.
  /// Does not automatically supply a single invented event.
  static Map<String, Object> emptyDraft(BookSourceIndex index) => {
    'format': format, 'stage': 'UNREVIEWED_EVENTS',
    'source_fingerprint': index.sourceFingerprint,
    'scanned_chunks': [
      for (final c in index.chunks)
        {'chunk_id': c.id, 'sha256_text': c.sha256Text},
    ],
    'events': <Object>[],
  };
}
