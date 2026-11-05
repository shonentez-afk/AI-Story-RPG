import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index({String suffix = ''}) {
  const first = 'Путешественник увидел старый мост и услышал вопрос '
      'прохожего о его намерениях. ';
  const ending = 'Спутник рассказал о другом пути и не подтвердил '
      'никаких обещаний от лица путника. ';
  return BookSourceIndexer.index(ImportedBook(
    title: 'Путешествие без выдуманного канона',
    author: 'Тестовый текст',
    chapters: [
      List.filled(9, first).join(' '),
      'Второй раздел ещё не содержит убедительных предложений событий. '
          'Отсутствие ответа модели не означает отсутствие настоящих событий.',
      List.filled(8, ending).join(' ') + suffix,
    ],
  ));
}

Future<NarrativeBookModel> _book(BookSourceIndex index,
    {bool partial = false, bool fillGaps = false}) async {
  final preview = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final count = window.chapterIndex == 1 && !fillGaps ? 0 : 4;
      final candidates = <SemanticCandidate>[];
      for (var i = 0; i < count; i++) {
        final start = chunk.startUtf16 + i * 75;
        if (start + 60 > chunk.endUtf16) break;
        candidates.add(SemanticCandidate.propose(
          source, chunk,
          category: SemanticCategory.event,
          startUtf16: start,
          endUtf16: start + 60,
          label: 'Непроверенное смысловое событие в тексте',
          uncertainty: 'Цитата есть, но её литературный смысл неизвестен.',
        ));
      }
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: candidates,
        ),
        totalSuggestions: candidates.length,
        rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await preview.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: partial ? 1 : 64,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(review),
    permitIncompleteAnalysisForReview: partial,
  );
}

StoryDilemmaProposal _dilemma(NarrativeBookModel book) =>
    StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: book.events.first.id,
      outcomeEventId: book.events.last.id,
      kind: StoryDilemmaKind.disclosure,
      dilemma: 'Раскрыть предположение о пути или поискать другую дорогу',
      acceptIntent: 'Согласиться на открытое объяснение условий',
      refuseIntent: 'Отказаться и продолжить поиск без обязательства',
      followupGoal: 'Разобраться с последствиями высказанного решения',
      finishOriginalIntent: 'Завершить действие, на которое согласились',
      originalEnding: 'Один вариант завершения вымышленного сценария',
      alternativeSearchGoal: 'Проверить другой возможный маршрут героя',
      searchIntent: 'Спросить других путников и исследовать тропы',
      alternativeDiscovery: 'Новая информация позволяет сделать выбор',
      useDiscoveryIntent: 'Использовать обнаруженный другой маршрут',
      alternativeEnding: 'Другой вариант завершения вымышленного маршрута',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all exact source events survive per-chapter segmentation; gaps '
      'are explicit and textual adjacency proves no causality', () async {
    final index = _index();
    final book = await _book(index);
    expect(book.analysisComplete, true);
    expect(book.chaptersWithEventProposals, 2);
    expect(book.events, hasLength(8));
    final map = BookwideActPlanner.build(
        index: index, book: book, eventsPerPart: 3);
    expect(map.chapters, 3);
    expect(map.chaptersWithEvents, 2);
    expect(map.chaptersWithoutEvents, [1]);
    expect(map.sourceEvents, 8);
    expect(map.acts.length, 5); // 2 + one gap + 2
    expect(map.acts.map((a) => a.events.length).toList(),
        [3, 1, 0, 3, 1]);
    expect(map.acts.map((a) => a.id).toList(),
        ['act_1_1', 'act_1_2', 'act_2_1', 'act_3_1', 'act_3_2']);
    final preserved = [
      for (final a in map.acts)
        for (final e in a.events) e.id,
    ];
    expect(preserved, [for (final e in book.events) e.id]);
    expect(preserved.toSet().length, book.events.length);
    expect(map.textAdjacency.length, map.acts.length - 1);
    expect(map.textAdjacency.every((a) =>
        !a.provesWorldTime && !a.provesCausation), true);
    expect(map.hasSourceGaps, true);
    expect(map.playableGame, false);
    expect(map.literaryMeaningVerified, false);
    expect(map.causalityVerified, false);
    expect(map.reviewRequirements.join(' '), contains('флешбеков'));

    final dump = jsonEncode(map.toDiagnosticJson());
    expect(dump, contains('SOURCE_MAP_ONLY'));
    expect(dump, isNot(contains(index.title)));
    expect(dump, isNot(contains(book.events.first.source.quote)));
    expect(dump, isNot(contains(book.sourceFingerprint)));
    expect(() => map.acts.clear(), throwsUnsupportedError);
    expect(() => map.chaptersWithoutEvents.clear(), throwsUnsupportedError);
    expect(() => map.acts.first.events.clear(), throwsUnsupportedError);
  });

  test('a two-event GLM StoryPlan covers only those source events '
      'even when every chapter was analyzed', () async {
    final index = _index();
    final book = await _book(index);
    final actMap = BookwideActPlanner.build(index: index, book: book);
    final story = StoryPlanDilemmaGenerator.propose(book, _dilemma(book));
    final coverage = BookwideActPlanner.compareWithStoryPlan(
      bookMap: actMap, book: book, story: story,
    );
    expect(coverage.allEvents, 8);
    expect(coverage.referencedEvents, 2);
    expect(coverage.eventIdsStillUnrepresented, hasLength(6));
    expect(coverage.chaptersWithoutEventProposals, [1]);
    expect(coverage.chaptersReferenced, 2);
    expect(coverage.chaptersNotCovered, [1]);
    expect(coverage.allDetectedEventsReferenced, false);
    expect(coverage.allChaptersCovered, false);
    expect(coverage.verifiesLiterarySemantics, false);
    expect(coverage.fullRpgReady, false);
    expect(coverage.toDiagnosticJson()['events_referenced_in_plan'], 2);
  });

  test('the same title but another edition, incomplete scan and '
      'unsupported limits fail closed', () async {
    final index = _index();
    final book = await _book(index);
    expect(() => BookwideActPlanner.build(
        index: _index(suffix: ' другая редакция'),
        book: book), throwsFormatException);
    expect(() => BookwideActPlanner.build(
        index: index, book: book, eventsPerPart: 0),
        throwsFormatException);
    expect(() => BookwideActPlanner.build(
        index: index, book: book, eventsPerPart: 25),
        throwsFormatException);
    final partial = await _book(index, partial: true);
    expect(partial.analysisComplete, false);
    expect(() => BookwideActPlanner.build(
        index: index, book: partial), throwsFormatException);
    final otherIndex = _index(suffix: ' другая редакция');
    final otherModel = await _book(otherIndex);
    final otherMap = BookwideActPlanner.build(
        index: otherIndex, book: otherModel);
    final story = StoryPlanDilemmaGenerator.propose(book, _dilemma(book));
    expect(() => BookwideActPlanner.compareWithStoryPlan(
        bookMap: otherMap, book: book, story: story),
        throwsFormatException);
  });

  test('no chapter gaps still does NOT mean causal or literary readiness',
      () async {
    final index = _index();
    final book = await _book(index, fillGaps: true);
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(map.chaptersWithEvents, 3);
    expect(map.chaptersWithoutEvents, isEmpty);
    expect(map.hasSourceGaps, false);
    expect(map.worldTimeVerified, false);
    expect(map.causalityVerified, false);
    expect(map.playableGame, false);
    final story = StoryPlanDilemmaGenerator.propose(book, _dilemma(book));
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: map, book: book, story: story);
    expect(coverage.allChaptersCovered, false);
    expect(coverage.allDetectedEventsReferenced, false);
    expect(coverage.fullRpgReady, false);
  });
}
