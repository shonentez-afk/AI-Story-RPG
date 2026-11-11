import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// M2h1: map ALL indexed events; do not confuse text order with world time,
/// source-verified quotations with literary truth or a draft with a game.
class BookActSegment {
  BookActSegment({
    required this.id,
    required this.chapterIndex,
    required this.partIndex,
    required List<NarrativeEvent> events,
  }) : events = List.unmodifiable(events);

  final String id;
  final int chapterIndex, partIndex;
  final List<NarrativeEvent> events;
  bool get isCoverageGap => events.isEmpty;
  bool get provesCausality => false;
  bool get provesWorldTime => false;
  bool get playable => false;

  Map<String, Object> toDiagnosticJson() => {
    'id': id, 'chapter_index': chapterIndex,
    'part_index': partIndex, 'events_count': events.length,
    'event_ids': [for (final e in events) e.id],
    'is_coverage_gap': isCoverageGap, 'gameplay_ready': false,
  };
}

/// Text adjacency is NOT a chronological or causal assertion.
class BookActTextAdjacency {
  const BookActTextAdjacency(this.before, this.after);
  final String before, after;
  bool get provesWorldTime => false;
  bool get provesCausation => false;
}

class BookwideActPlan {
  BookwideActPlan._({
    required this.sourceFingerprint,
    required this.chapters,
    required this.sourceEvents,
    required List<BookActSegment> acts,
    required List<int> chaptersWithoutEvents,
  }) : acts = List.unmodifiable(acts),
       chaptersWithoutEvents = List.unmodifiable(chaptersWithoutEvents),
       textAdjacency = List.unmodifiable([
         for (var i = 1; i < acts.length; i++)
           BookActTextAdjacency(acts[i - 1].id, acts[i].id),
       ]);

  final String sourceFingerprint;
  final int chapters, sourceEvents;
  final List<BookActSegment> acts;
  final List<int> chaptersWithoutEvents;
  final List<BookActTextAdjacency> textAdjacency;

  int get chaptersWithEvents => chapters - chaptersWithoutEvents.length;
  bool get hasSourceGaps => chaptersWithoutEvents.isNotEmpty;
  bool get literaryMeaningVerified => false;
  bool get worldTimeVerified => false;
  bool get causalityVerified => false;
  bool get playableGame => false;

  List<String> get reviewRequirements => List.unmodifiable([
    if (sourceEvents == 0)
      'Нет событий, предложенных при анализе книги.',
    if (hasSourceGaps)
      'Есть главы без предложений событий. '
          'Это пробел анализа, а не подтверждение отсутствия событий.',
    'Проверить смысл и участников событий по исходным отрывкам.',
    'Установить хронологию мира независимо от порядка глав и флешбеков.',
    'Построить причинные переходы, учёт знаний NPC и альтернативные пути.',
    'Написать сцены, сверить последствия и испытать полную игру.',
  ]);

  /// No user text, book title, key or quote enters this diagnostics snapshot.
  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_bookwide_act_map_m2h1_v1',
    'status': 'SOURCE_MAP_ONLY',
    'chapters_total': chapters,
    'chapters_with_event_proposals': chaptersWithEvents,
    'source_events': sourceEvents,
    'parts': [for (final a in acts) a.toDiagnosticJson()],
    'chapters_without_event_proposals': chaptersWithoutEvents,
    'is_playable': false,
    'is_world_causality_verified': false,
  };
}

class BookwideStoryCoverage {
  BookwideStoryCoverage._({
    required this.allEvents,
    required this.referencedEvents,
    required this.chapters,
    required this.chaptersReferenced,
    required List<String> eventIdsStillUnrepresented,
    required List<int> chaptersWithoutEventProposals,
    required List<int> chaptersNotCovered,
  }) : eventIdsStillUnrepresented =
           List.unmodifiable(eventIdsStillUnrepresented),
       chaptersWithoutEventProposals =
           List.unmodifiable(chaptersWithoutEventProposals),
       chaptersNotCovered = List.unmodifiable(chaptersNotCovered);

  final int allEvents, referencedEvents;
  final int chapters, chaptersReferenced;
  final List<String> eventIdsStillUnrepresented;
  final List<int> chaptersWithoutEventProposals, chaptersNotCovered;

  bool get allDetectedEventsReferenced =>
      allEvents > 0 && eventIdsStillUnrepresented.isEmpty;
  bool get allChaptersCovered =>
      chapters > 0 && chaptersNotCovered.isEmpty &&
      chaptersWithoutEventProposals.isEmpty;
  bool get verifiesLiterarySemantics => false;
  bool get fullRpgReady => false;

  Map<String, Object> toDiagnosticJson() => {
    'events_found': allEvents,
    'events_referenced_in_plan': referencedEvents,
    'chapters_total': chapters,
    'chapters_referenced_in_plan': chaptersReferenced,
    'unrepresented_event_ids': eventIdsStillUnrepresented,
    'chapters_with_no_event_proposal': chaptersWithoutEventProposals,
    'chapters_not_covered': chaptersNotCovered,
    'full_rpg_ready': false,
  };
}

class BookwideActPlanner {
  const BookwideActPlanner._();

  static const defaultEventsPerPart = 12;
  static const maxParts = 4096;

  /// Prefer the existing default boundaries. Only when that produces fewer
  /// than two usable acts, split one sufficiently event-rich source segment
  /// into two chronological text ranges. A one-chapter fairy tale is still
  /// eligible for a source-locked multi-act DRAFT without a special title case.
  ///
  /// This operation neither invents events nor proves temporal/causal links.
  /// A chapter with fewer than FOUR candidates cannot be split into two
  /// independent two-event dilemmas and remains an explicit blocker.
  static BookwideActPlan buildForMultiActDraft({
    required BookSourceIndex index,
    required NarrativeBookModel book,
  }) {
    final regular = build(index: index, book: book);
    final eligible = regular.acts.where((a) => a.events.length >= 2).length;
    if (eligible >= 2) return regular;
    var largest = 0;
    for (final act in regular.acts) {
      if (act.events.length > largest) largest = act.events.length;
    }
    if (largest < 4) return regular;
    // With fewer than two eligible default acts, the largest part has
    // at most 12 events. Ceiling-half preserves two >=2 event segments.
    final reducedPerPart = (largest + 1) ~/ 2;
    final split = build(
        index: index, book: book, eventsPerPart: reducedPerPart);
    return split.acts.where((a) => a.events.length >= 2).length >= 2
        ? split : regular;
  }

  /// Assign EVERY source event to exactly one bounded act segment.
  /// Chapters with no suggestions are retained as explicit gaps.
  static BookwideActPlan build({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    int eventsPerPart = defaultEventsPerPart,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        index.chapterCount != book.chapterCount ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        eventsPerPart < 1 || eventsPerPart > 24) {
      throw const FormatException(
          'Нужен законченный анализ этой редакции книги.');
    }
    final byChapter = <int, List<NarrativeEvent>>{};
    final ids = <String>{};
    NarrativeCitation? last;
    for (var i = 0; i < book.events.length; i++) {
      final event = book.events[i];
      final cite = event.source;
      // Validate offsets, Unicode boundaries and actual source text again.
      cite.validate(index);
      var outOfTextOrder = false;
      if (last != null) {
        if (cite.chapterIndex < last.chapterIndex) {
          outOfTextOrder = true;
        } else if (cite.chapterIndex == last.chapterIndex) {
          if (cite.blockIndex < last.blockIndex) {
            outOfTextOrder = true;
          } else if (cite.blockIndex == last.blockIndex &&
              cite.startUtf16 < last.startUtf16) {
            outOfTextOrder = true;
          }
        }
      }
      if (!ids.add(event.id) || event.narrativePosition != i ||
          cite.chapterIndex < 0 || cite.chapterIndex >= index.chapterCount ||
          outOfTextOrder) {
        throw const FormatException(
            'Неверный порядок или идентификаторы событий книги.');
      }
      last = cite;
      byChapter.putIfAbsent(cite.chapterIndex, () => []).add(event);
    }
    if (byChapter.length != book.chaptersWithEventProposals) {
      throw const FormatException(
          'Число глав с событиями отличается от исходного анализа.');
    }
    final result = <BookActSegment>[];
    final gaps = <int>[];
    for (var chapter = 0; chapter < book.chapterCount; chapter++) {
      final events = byChapter[chapter] ?? const <NarrativeEvent>[];
      if (events.isEmpty) gaps.add(chapter);
      final parts = events.isEmpty
          ? 1 : (events.length + eventsPerPart - 1) ~/ eventsPerPart;
      if (result.length + parts > maxParts) {
        throw const FormatException(
            'Нужна поактовая обработка без потери событий: '
            'слишком много глав или частей для одного отчёта.');
      }
      for (var part = 0; part < parts; part++) {
        final start = part * eventsPerPart;
        final end = start + eventsPerPart > events.length
            ? events.length : start + eventsPerPart;
        result.add(BookActSegment(
          id: 'act_' + (chapter + 1).toString() +
              '_' + (part + 1).toString(),
          chapterIndex: chapter,
          partIndex: part,
          events: events.sublist(start, end),
        ));
      }
    }
    if (result.fold<int>(0, (sum, a) => sum + a.events.length) !=
        book.events.length) {
      throw const FormatException('При разбиении потеряны события книги.');
    }
    return BookwideActPlan._(
      sourceFingerprint: book.sourceFingerprint,
      chapters: book.chapterCount,
      sourceEvents: book.events.length,
      acts: result,
      chaptersWithoutEvents: gaps,
    );
  }

  /// Only canonical-PROPOSAL situations anchored to actual source event IDs
  /// count. AI-only branches or decision labels never establish coverage.
  static BookwideStoryCoverage compareWithStoryPlan({
    required BookwideActPlan bookMap,
    required NarrativeBookModel book,
    required StoryPlan story,
    bool expanded = false,
  }) {
    if (bookMap.sourceFingerprint != book.sourceFingerprint ||
        story.sourceFingerprint != book.sourceFingerprint ||
        story.title != book.title || !book.analysisComplete) {
      throw const FormatException('План относится к другой книге.');
    }
    story.validate(book, expanded: expanded);
    final anchors = [
      for (final act in bookMap.acts)
        for (final e in act.events) e,
    ];
    final ids = {for (final event in anchors) event.id};
    final referenced = <String>{
      for (final s in story.situations)
        if (s.route == StoryRoute.canonicalProposal &&
            s.sourceEventId != null)
          s.sourceEventId!,
    };
    if (!ids.containsAll(referenced)) {
      throw const FormatException(
          'Сценарий использует события вне карты оригинала.');
    }
    final chapters = <int>{
      for (final e in anchors)
        if (referenced.contains(e.id)) e.source.chapterIndex,
    };
    return BookwideStoryCoverage._(
      allEvents: anchors.length,
      referencedEvents: referenced.length,
      chapters: bookMap.chapters,
      chaptersReferenced: chapters.length,
      eventIdsStillUnrepresented: [
        for (final e in anchors)
          if (!referenced.contains(e.id)) e.id,
      ],
      chaptersWithoutEventProposals: bookMap.chaptersWithoutEvents,
      chaptersNotCovered: [
        for (var i = 0; i < bookMap.chapters; i++)
          if (!chapters.contains(i)) i,
      ],
    );
  }
}
