import 'source_semantic_provider.dart';
import 'zai_auto_whole_book_analysis.dart';

/// One EXACT quote with a proposed (unverified) event label.
/// Position in the book is NOT proof of in-world chronological order.
class ZaiSourceEventProposal {
  const ZaiSourceEventProposal({
    required this.id,
    required this.chapterIndex,
    required this.blockIndex,
    required this.startUtf16,
    required this.label,
    required this.quote,
    required this.chunkId,
    required this.windowPosition,
  });

  final String id;
  final int chapterIndex;
  final int blockIndex;
  final int startUtf16;
  final String label;
  final String quote;
  final String chunkId;
  final int windowPosition;

  bool get hasExactSourceQuote => true;
  bool get isEventMeaningVerified => false;
  bool get isChronologyVerified => false;
  bool get hasCausalDependencies => false;
}

/// Read-only story coverage report over the existing Z.ai result checkpoint.
/// No LLM output is allowed to assert an identity, chronology, event truth,
/// ending, gameplay state or causal edge through this projection.
class ZaiWholeBookEventOutline {
  ZaiWholeBookEventOutline._({
    required this.sourceFingerprint,
    required this.totalChapters,
    required this.plannedWindows,
    required this.processedWindows,
    required this.chaptersWithAnalyzedText,
    required this.chaptersWithEventProposals,
    required this.events,
  });

  final String sourceFingerprint;
  final int totalChapters;
  final int plannedWindows;
  final int processedWindows;
  final int chaptersWithAnalyzedText;
  final int chaptersWithEventProposals;
  final List<ZaiSourceEventProposal> events;

  bool get analysisComplete => plannedWindows == processedWindows;
  bool get allChaptersHaveEventProposals =>
      chaptersWithEventProposals == totalChapters;
  bool get isPlayableScenario => false;
  bool get canInferCausality => false;
  bool get canPublishPublicly => false;

  List<String> get warnings => List.unmodifiable([
    if (!analysisComplete)
      'Не все части книги обработаны. Пропущены '
          '${plannedWindows - processedWindows} из $plannedWindows.',
    if (chaptersWithEventProposals < totalChapters)
      'У ${totalChapters - chaptersWithEventProposals} глав '
          'ещё нет предложений событий. Это не означает, '
          'что событий в них действительно нет.',
    if (events.isEmpty)
      'ИИ не выделил ни одного проверяемого события.',
    'Цитаты проверены, но правильность понимания событий '
        'и хронология ещё не утверждены.',
    'Причины, последствия и альтернативные развязки '
        'ещё не проверены как игровые правила.',
  ]);

  static ZaiWholeBookEventOutline build(
      ZaiWholeBookReviewResult review) {
    final index = review.queue.index;
    final manifest = review.manifest;
    if (manifest.sourceFingerprint != index.sourceFingerprint ||
        review.queue.windows.length < manifest.windows.length) {
      throw const FormatException('Сводка относится к другой редакции книги.');
    }
    final sourceById = {for (final c in index.chunks) c.id: c};
    final items = <ZaiSourceEventProposal>[];
    final allIds = <String>{};
    final chaptersProcessed = <int>{};
    final chaptersWithEvents = <int>{};
    var processed = 0;
    for (final part in manifest.windows.entries) {
      final window = part.value;
      final stored = review.queue.results[part.key];
      if (stored == null) continue;
      processed++;
      chaptersProcessed.add(window.chapterIndex);
      final permitted = {for (final chunk in window.chunks) chunk.id};
      for (final candidate in stored.candidates) {
        if (candidate.category != SemanticCategory.event) continue;
        if (!allIds.add(candidate.id)) {
          throw const FormatException('Дублированное событие в разных окнах.');
        }
        final chunk = sourceById[candidate.chunkId];
        if (chunk == null || !permitted.contains(chunk.id) ||
            chunk.chapterIndex != window.chapterIndex) {
          throw const FormatException('Событие ссылается на чужую главу.');
        }
        SemanticCandidateValidator.validateCandidate(
          index, candidate,
          allowedChunkIds: permitted,
          categories: const {SemanticCategory.event},
          sourceChunk: chunk,
        );
        chaptersWithEvents.add(chunk.chapterIndex);
        items.add(ZaiSourceEventProposal(
          id: candidate.id,
          chapterIndex: chunk.chapterIndex,
          blockIndex: chunk.blockIndex,
          startUtf16: candidate.startUtf16,
          label: candidate.label,
          quote: candidate.quote,
          chunkId: candidate.chunkId,
          windowPosition: part.key,
        ));
      }
    }
    items.sort((a, b) {
      var v = a.chapterIndex.compareTo(b.chapterIndex);
      if (v != 0) return v;
      v = a.blockIndex.compareTo(b.blockIndex);
      if (v != 0) return v;
      v = a.startUtf16.compareTo(b.startUtf16);
      if (v != 0) return v;
      return a.id.compareTo(b.id);
    });
    // Preserves provenance; does not grant semantic/causal correctness.
    return ZaiWholeBookEventOutline._(
      sourceFingerprint: index.sourceFingerprint,
      totalChapters: index.chapterCount,
      plannedWindows: manifest.plannedRequests,
      processedWindows: processed,
      chaptersWithAnalyzedText: chaptersProcessed.length,
      chaptersWithEventProposals: chaptersWithEvents.length,
      events: List<ZaiSourceEventProposal>.unmodifiable(items),
    );
  }
}
