import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/cross_act_consequence_gate.dart';
import 'package:ai_story_reader/multi_act_trial_compiler.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index({String suffix = ''}) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Два акта с разными последствиями',
      author: 'Синтетический тест',
      chapters: [
        List.filled(4, 'В деревне путник нашёл кольцо возле '
            'старого ручья. Он ещё не согласился на условие, '
            'предложенное знакомым. ').join(' '),
        List.filled(4, 'После долгой дороги путник услышал '
            'второе предложение и увидел лесную развилку. '
            'Никто не знал, что произойдёт. ').join(' ') + suffix,
      ],
    ));

Future<NarrativeBookModel> _analyze(BookSourceIndex index) async {
  final analysis = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, title) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            for (var i = 0; i < 2; i++)
              SemanticCandidate.propose(
                source, chunk, category: SemanticCategory.event,
                startUtf16: chunk.startUtf16 + i * 86,
                endUtf16: chunk.startUtf16 + i * 86 + 60,
                label: 'Предположенное событие',
                uncertainty: 'Смысл и хронология мира не проверены.',
              ),
          ],
        ),
        totalSuggestions: 2, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await analysis.analyze(index: index,
    approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(index: index,
      outline: ZaiWholeBookEventOutline.build(review));
}

StoryDilemmaProposal _proposal(NarrativeBookModel book, int chapter) {
  final events = book.events.where((e) =>
      e.source.chapterIndex == chapter).toList();
  return StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: events.first.id,
    outcomeEventId: events.last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Рассмотреть соглашение или выбрать самостоятельный путь',
    acceptIntent: 'Принять условие только по собственному решению',
    refuseIntent: 'Отказаться и искать возможности без обещаний',
    followupGoal: 'Оценить последствия добровольно принятого условия',
    finishOriginalIntent: 'Исполнить игровое обязательство после согласия',
    originalEnding: 'Завершение условного первого игрового маршрута',
    alternativeSearchGoal: 'Исследовать возможности без прежнего договора',
    searchIntent: 'Проверить дорогу и поговорить с прохожими',
    alternativeDiscovery: 'Появилась отдельная вымышленная возможность',
    useDiscoveryIntent: 'Выбрать альтернативный безопасный маршрут',
    alternativeEnding: 'Завершить другую вымышленную игровую линию',
  );
}

({BookwideActPlan map, MultiActStoryPlanDraft draft,
  CrossActContinuityDraft continuity, Set<String> eventIds})
    _draft(BookSourceIndex index, NarrativeBookModel book) {
  final map = BookwideActPlanner.build(index: index, book: book);
  final draft = BookwideStoryPlanComposer.compose(index: index,
      book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1)]);
  final continuity = CrossActConsequenceGate.apply(
    index: index, book: book, bookMap: map, draft: draft,
    rules: [
      CrossActConsequenceRule(
        id: 'approved_fictional_link',
        earlierActId: draft.parts.first.actId,
        laterActId: draft.parts[1].actId,
        earlierSourceEventId: draft.parts.first.outcomeEventId,
        laterSourceEventId: draft.parts[1].setupEventId,
        laterDecisionId: 'act_2_accept_offer',
        priorOutcome: CrossActPriorOutcome.original,
        mode: CrossActRuleMode.requiresPriorOutcome,
        reviewedAsGameFiction: true,
        privateReviewReason: 'В этой тестовой адаптации '
            'предыдущее согласие позволяет выбрать второе. '
            'Это не установленный факт книги.',
      ),
    ],
  );
  return (
    map: map,
    draft: draft,
    continuity: continuity,
    eventIds: {
      for (final p in draft.parts) ...[
        p.setupEventId, p.outcomeEventId,
      ],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('multi-act trial uses existing PRIVATE BookWorld and SQLite, '
      'real earlier outcome changes act2 choice and two campaigns '
      'remain correct across DB restart', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final compilation = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, continuity: input.continuity,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    );
    expect(compilation.isPrivateTrial, true);
    expect(compilation.isFullBookAdaptation, false);
    expect(compilation.sourceMeaningIsVerified, false);
    expect(compilation.requiresCloudToPlay, false);
    expect(compilation.canDistributePublicly, false);
    expect(compilation.sceneCount, 14);
    expect(compilation.sourceQuoteCount, 4);
    final inspected = const PrivateBookworldImporter().inspect(
        compilation.archive);
    expect(inspected.sourceFingerprint, index.sourceFingerprint);
    expect(inspected.requiresNetwork, false);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.blueprint.scenes.length, 14);

    final dir = await Directory.systemTemp.createTemp('multiact-private-');
    late String acceptedCampaign, refusedCampaign;
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        final installed = db.installBookworld(compilation.archive);
        acceptedCampaign = db.createCampaign(installed.archiveHash);
        refusedCampaign = db.createCampaign(installed.archiveHash);
        var revision = 0;
        for (final choice in [
          'act_1_accept_offer', 'act_1_honor_condition',
          'act_1_continue_original',
          'act_2_accept_offer', 'act_2_honor_condition',
        ]) {
          final state = db.loadCampaign(acceptedCampaign);
          expect(state.coordinator.choices.any((x) => x.id == choice), true);
          final r = db.commitChoice(acceptedCampaign,
            actionId: 'yes_' + revision.toString(),
            choiceId: choice,
            expectedRevision: revision);
          expect(r.applied, true);
          revision++;
        }
        expect(db.loadCampaign(acceptedCampaign).coordinator.isTerminal, true);
        revision = 0;
        for (final choice in [
          'act_1_refuse_offer', 'act_1_explore',
          'act_1_use_discovery', 'act_1_end_alternative',
          'act_1_continue_alternative',
        ]) {
          final state = db.loadCampaign(refusedCampaign);
          expect(state.coordinator.choices.any((x) => x.id == choice), true);
          final r = db.commitChoice(refusedCampaign,
            actionId: 'no_' + revision.toString(),
            choiceId: choice,
            expectedRevision: revision);
          expect(r.applied, true);
          revision++;
        }
        final turn = db.loadCampaign(refusedCampaign).coordinator;
        expect(turn.sceneId, 'act_2_turning_point');
        expect(turn.choices.any((x) =>
            x.id == 'act_2_accept_offer' && x.enabled), false);
        expect(turn.choices.singleWhere((x) =>
            x.id == 'act_2_accept_offer').lockReason, isNotNull);
        expect(turn.choices.any((x) =>
            x.id == 'act_2_refuse_offer' && x.enabled), true);
        for (final choice in [
          'act_2_refuse_offer', 'act_2_explore',
          'act_2_use_discovery', 'act_2_end_alternative',
        ]) {
          final r = db.commitChoice(refusedCampaign,
            actionId: 'no_' + revision.toString(),
            choiceId: choice,
            expectedRevision: revision);
          expect(r.applied, true);
          revision++;
        }
        expect(db.loadCampaign(refusedCampaign).coordinator.isTerminal, true);
        expect(db.loadCampaign(refusedCampaign).metadata.revision, 9);
      } finally {
        db.close();
      }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        expect(db.installedWorlds(), hasLength(1));
        expect(db.campaigns(), hasLength(2));
        expect(db.loadCampaign(acceptedCampaign).coordinator.isTerminal, true);
        expect(db.loadCampaign(refusedCampaign).coordinator.isTerminal, true);
        expect(db.loadCampaign(acceptedCampaign).metadata.revision, 5);
        expect(db.loadCampaign(refusedCampaign).metadata.revision, 9);
      } finally {
        db.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('without explicit PRIVATE fiction consent or review of all quotes, '
      'compiler fails before altering an existing game', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    Future<void> tryCompile({
      required Set<String> ids,
      bool privateUse = true,
      bool fiction = true,
      BookSourceIndex? source,
    }) async {
      await MultiActTrialCompiler.compile(
        index: source ?? index, book: book, bookMap: input.map,
        draft: input.draft,
        continuity: input.continuity,
        sourceEventIdsReviewedByUser: ids,
        privateUseConfirmed: privateUse,
        fictionalTrialAcknowledged: fiction,
      );
    }
    await expectLater(tryCompile(
        ids: input.eventIds.difference({input.eventIds.first})),
        throwsFormatException);
    await expectLater(tryCompile(
        ids: input.eventIds, privateUse: false), throwsFormatException);
    await expectLater(tryCompile(
        ids: input.eventIds, fiction: false), throwsFormatException);
    await expectLater(tryCompile(
        ids: input.eventIds, source: _index(suffix: ' другой перевод')),
        throwsFormatException);
  });
}
