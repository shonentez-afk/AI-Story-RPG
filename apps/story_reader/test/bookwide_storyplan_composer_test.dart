import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index({String ending = ''}) {
  const source = 'Путник подошёл к развилке около старого каменного '
      'моста и услышал от прохожего необычное предложение. '
      'Сначала он хотел отказаться от условий, но ничего '
      'не обещал и решил ещё подумать о своих действиях. ';
  return BookSourceIndexer.index(ImportedBook(
    title: 'Четыре части вымышленной книги',
    author: 'Синтетический тестовый текст',
    chapters: [
      List.filled(4, source).join(' '),
      List.filled(4, source).join(' '),
      'В этой главе ИИ не выделил ни одного подходящего '
          'события. Рассказчик оставляет вопросы нерешёнными.',
      List.filled(4, source).join(' ') + ending,
    ],
  ));
}

Future<NarrativeBookModel> _analyze(BookSourceIndex index) async {
  final provider = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, cancel, includeTitle) async {
      final chunk = window.chunks.first;
      final events = <SemanticCandidate>[];
      if (window.chapterIndex != 2) {
        for (var i = 0; i < 2; i++) {
          events.add(SemanticCandidate.propose(
            source, chunk,
            category: SemanticCategory.event,
            startUtf16: chunk.startUtf16 + i * 85,
            endUtf16: chunk.startUtf16 + i * 85 + 60,
            label: 'Возможное событие в главе',
            uncertainty: 'Смысл и причинность не доказаны.',
          ));
        }
      }
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: events,
        ),
        totalSuggestions: events.length,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await provider.analyze(
    index: index,
    approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(review),
  );
}

StoryDilemmaProposal _proposal(
    NarrativeBookModel book, int chapter,
    {StoryDilemmaKind kind = StoryDilemmaKind.agreement}) {
  final events = book.events.where(
      (event) => event.source.chapterIndex == chapter).toList();
  return StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: events[0].id,
    outcomeEventId: events[1].id,
    kind: kind,
    dilemma: 'Рассмотреть возможное решение, '
        'но не считать его доказанным событием книги',
    acceptIntent: 'Согласиться на предложенный игровой вариант',
    refuseIntent: 'Отказаться и попробовать совершенно иной путь',
    followupGoal: 'Проверить последствия принятого игрового условия',
    finishOriginalIntent: 'Исполнить добровольно принятое игровое решение',
    originalEnding: 'Завершить первую предложенную линию этого эпизода',
    alternativeSearchGoal: 'Искать альтернативу игровому решению героя',
    searchIntent: 'Осмотреть окружение и узнать о другой возможности',
    alternativeDiscovery: 'Герой обнаруживает игровое решение без условия',
    useDiscoveryIntent: 'Использовать выбранную новую игровую возможность',
    alternativeEnding: 'Завершить другую вымышленную игровую линию',
  );
}

/// Exercise a real path through the COMPOSED graph, not independent
/// samples. No cloud, BookWorld installation or SQLite mutation.
(List<String>, String) _walk(
    StoryPlan plan, List<String> choiceIds) {
  final byScene = {for (final scene in plan.situations) scene.id: scene};
  final flags = <String>{...plan.initialFlags};
  var sceneId = plan.entrySituationId;
  for (final choiceId in choiceIds) {
    final scene = byScene[sceneId]!;
    expect(scene.terminal, false);
    final choice = scene.decisions.singleWhere(
        (decision) => decision.id == choiceId);
    expect(flags.containsAll(choice.requires), true);
    expect(flags.intersection(choice.forbids.toSet()), isEmpty);
    flags.removeAll(choice.removes);
    flags.addAll(choice.adds);
    sceneId = choice.nextSituationId;
  }
  expect(byScene[sceneId]!.terminal, true);
  return (flags.toList()..sort(), sceneId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compose THREE independent source acts with two choices per act, '
      'explicit fictional links and retained world state', () async {
    final index = _index();
    final book = await _analyze(index);
    expect(book.events, hasLength(6));
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(map.acts.length, 4);
    expect(map.chaptersWithoutEvents, [2]);
    final result = BookwideStoryPlanComposer.compose(
      index: index,
      book: book,
      bookMap: map,
      actProposals: [
        _proposal(book, 0),
        _proposal(book, 1, kind: StoryDilemmaKind.exchange),
        _proposal(book, 3, kind: StoryDilemmaKind.disclosure),
      ],
    );
    expect(result.parts.map((p) => p.actId).toList(),
        ['act_1_1', 'act_2_1', 'act_4_1']);
    expect(result.parts.map((p) => p.entrySituationId).toList(),
        ['act_1_turning_point', 'act_2_turning_point',
         'act_3_turning_point']);
    expect(result.plan.situations, hasLength(21));
    expect(result.plan.flags, hasLength(15));
    expect(result.fictionalBridges, hasLength(4));
    expect(result.fictionalBridges.every((b) =>
        !b.isSupportedByBookCausality &&
        !b.isVerifiedWorldTime && b.isProposedGameFiction), true);
    expect(result.formalRulesPassed, true);
    expect(result.formalAudit.counterexamples, isEmpty);
    expect(result.plan.validate(book).terminalSituations, 2);
    expect(result.coverage.allEvents, 6);
    expect(result.coverage.referencedEvents, 6);
    expect(result.coverage.allDetectedEventsReferenced, true);
    expect(result.coverage.chaptersWithoutEventProposals, [2]);
    expect(result.coverage.allChaptersCovered, false);
    expect(result.blockers.join(' '), contains('Причинность'));
    expect(result.isFullBookRpg, false);
    expect(result.isReadyToInstall, false);
    expect(result.canPublish, false);
    expect(result.hasConfirmedActorKnowledge, false);
    expect(result.hasSourceProvenCausalBridges, false);
    final meta = jsonEncode(result.toDiagnosticJson());
    expect(meta, contains('DRAFT_ONLY'));
    expect(meta, isNot(contains(index.title)));
    expect(meta, isNot(contains(book.events.first.source.quote)));
    expect(meta, isNot(contains(book.sourceFingerprint)));
    expect(() => result.parts.clear(), throwsUnsupportedError);
    expect(() => result.fictionalBridges.clear(), throwsUnsupportedError);
    expect(() => result.blockers.clear(), throwsUnsupportedError);

    final first = _walk(result.plan, [
      'act_1_accept_offer', 'act_1_honor_condition',
      'act_1_continue_original',
      'act_2_accept_offer', 'act_2_honor_condition',
      'act_2_continue_original',
      'act_3_accept_offer', 'act_3_honor_condition',
    ]);
    expect(first.$2, 'act_3_original_ending');
    expect(first.$1, contains('act_1_original_outcome'));
    expect(first.$1, contains('act_2_original_outcome'));
    expect(first.$1, contains('act_3_original_outcome'));

    final second = _walk(result.plan, [
      'act_1_refuse_offer', 'act_1_explore', 'act_1_use_discovery',
      'act_1_end_alternative', 'act_1_continue_alternative',
      'act_2_accept_offer', 'act_2_honor_condition',
      'act_2_continue_original',
      'act_3_refuse_offer', 'act_3_explore', 'act_3_use_discovery',
      'act_3_end_alternative',
    ]);
    expect(second.$2, 'act_3_alternate_ending');
    expect(second.$1, contains('act_1_alternate_outcome'));
    expect(second.$1, contains('act_2_original_outcome'));
    expect(second.$1, contains('act_3_alternate_outcome'));
    expect(second.$1, isNot(contains('act_1_original_outcome')));
  });

  test('only proposed acts are counted; no false full-book coverage',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final draft = BookwideStoryPlanComposer.compose(
      index: index,
      book: book,
      bookMap: BookwideActPlanner.build(index: index, book: book),
      actProposals: [_proposal(book, 0), _proposal(book, 3)],
    );
    expect(draft.parts, hasLength(2));
    expect(draft.plan.situations, hasLength(14));
    expect(draft.coverage.referencedEvents, 4);
    expect(draft.coverage.eventIdsStillUnrepresented, hasLength(2));
    expect(draft.coverage.allDetectedEventsReferenced, false);
    expect(draft.isFullBookRpg, false);
    expect(draft.fictionalBridges, hasLength(2));
  });

  test('out-of-order acts, reused anchors and cross-act source pair '
      'must never be silently joined', () async {
    final index = _index();
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    List<StoryDilemmaProposal> pair(StoryDilemmaProposal a,
        StoryDilemmaProposal b) => [a, b];
    expect(() => BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: pair(_proposal(book, 3), _proposal(book, 0)),
    ), throwsFormatException);
    expect(() => BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: pair(_proposal(book, 0), _proposal(book, 0)),
    ), throwsFormatException);
    final wrong = _proposal(book, 0);
    final cross = StoryDilemmaProposal(
      sourceFingerprint: wrong.sourceFingerprint,
      setupEventId: wrong.setupEventId,
      outcomeEventId: book.events.last.id,
      kind: wrong.kind,
      dilemma: wrong.dilemma,
      acceptIntent: wrong.acceptIntent,
      refuseIntent: wrong.refuseIntent,
      followupGoal: wrong.followupGoal,
      finishOriginalIntent: wrong.finishOriginalIntent,
      originalEnding: wrong.originalEnding,
      alternativeSearchGoal: wrong.alternativeSearchGoal,
      searchIntent: wrong.searchIntent,
      alternativeDiscovery: wrong.alternativeDiscovery,
      useDiscoveryIntent: wrong.useDiscoveryIntent,
      alternativeEnding: wrong.alternativeEnding,
    );
    expect(() => BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: pair(cross, _proposal(book, 1)),
    ), throwsFormatException);
  });

  test('wrong edition and incomplete or single-act plan are rejected',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(() => BookwideStoryPlanComposer.compose(
      index: _index(ending: 'Другой перевод.'),
      book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1)],
    ), throwsFormatException);
    expect(() => BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [_proposal(book, 0)],
    ), throwsFormatException);
    expect(() => BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: List.filled(7, _proposal(book, 0)),
    ), throwsFormatException);
  });
}
