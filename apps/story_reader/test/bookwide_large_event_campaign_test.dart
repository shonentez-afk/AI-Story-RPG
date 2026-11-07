import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_campaign_contract.dart';
import 'package:ai_story_reader/bookwide_source_encounters.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/multi_act_trial_compiler.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

/// Synthetic source: six acts, three distinct source windows per chapter,
/// four independently source-verified proposals per window. No private FB2,
/// API calls, model inference, or claims of literary truth.
BookSourceIndex _longIndex({int chapters = 6}) =>
    BookSourceIndexer.index(ImportedBook(
  title: 'Шесть актов — нагрузочная проверка причинных событий',
  author: 'Синтетический стенд',
  chapters: [
    for (var chapter = 0; chapter < chapters; chapter++)
      List.filled(350, 'Путник нашёл ключ у ворот. ').join(),
  ],
));

Future<NarrativeBookModel> _longBook(BookSourceIndex index) async {
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  expect(manifest.plannedRequests, index.chapterCount * 3);
  final analysis = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      // Four candidates in every independently reviewed window: under the
      // real eight-per-window bound. All quote offsets point into its actual
      // first source chunk, never into flattened concatenated window text.
      final chunk = window.chunks.first;
      final candidates = [
        for (var i = 0; i < 4; i++)
          SemanticCandidate.propose(
            source, chunk,
            category: SemanticCategory.event,
            startUtf16: chunk.startUtf16 + i * 86,
            endUtf16: chunk.startUtf16 + i * 86 + 60,
            label: 'Предложенное событие',
            uncertainty: 'Смысл и время внутри мира не подтверждены.',
          ),
      ];
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: candidates,
        ),
        totalSuggestions: candidates.length,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final review = await analysis.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  expect(review.complete, isTrue);
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(review),
  );
}

StoryDilemmaProposal _actProposal(NarrativeBookModel book, int chapter) {
  final events = book.events.where(
      (event) => event.source.chapterIndex == chapter).toList();
  return StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: events.first.id,
    outcomeEventId: events.last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Выбрать самостоятельный путь или согласиться на условие',
    acceptIntent: 'Принять условие добровольно',
    refuseIntent: 'Отказаться от условия',
    followupGoal: 'Проверить последствия принятого решения',
    finishOriginalIntent: 'Исполнить обещание и продолжить путь',
    originalEnding: 'Завершить исходный путь после согласия',
    alternativeSearchGoal: 'Проверить другую дорогу',
    searchIntent: 'Исследовать безопасную альтернативу',
    alternativeDiscovery: 'Обнаружена иная вымышленная возможность',
    useDiscoveryIntent: 'Использовать найденную возможность',
    alternativeEnding: 'Завершить выбранный альтернативный путь',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('60 reviewed interactive events across six acts compile, each choice '
      'is playable, and a 77-step SQLite campaign survives reopening',
      () async {
    final index = _longIndex();
    final book = await _longBook(index);
    expect(book.events, hasLength(72));
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(map.acts, hasLength(6));
    for (final act in map.acts) {
      expect(act.events, hasLength(12));
    }
    final draft = BookwideStoryPlanComposer.compose(
      index: index,
      book: book,
      bookMap: map,
      actProposals: [for (var i = 0; i < 6; i++) _actProposal(book, i)],
    );
    expect(draft.parts, hasLength(6));
    final extras = <String>{};
    for (var act = 0; act < 6; act++) {
      final eligible = BookwideSourceEncounters.eligibleForAct(
        index: index, bookMap: map, draft: draft, partIndex: act,
      );
      expect(eligible, hasLength(10));
      extras.addAll(eligible.map((e) => e.id));
    }
    expect(extras.length, 60);
    expect(extras.length, greaterThan(48));

    final plan = BookwideSourceEncounters.attach(
      index: index, book: book, bookMap: map, draft: draft,
      plan: draft.plan, reviewedEventIds: extras,
      userConfirmedPrivateAdaptation: true,
    );
    expect(plan.situations.length, draft.plan.situations.length + 60);
    final coverage = BookwideActPlanner.compareWithStoryPlan(
      bookMap: map, book: book, story: plan,
    );
    expect(coverage.referencedEvents, 72);
    expect(coverage.allDetectedEventsReferenced, isTrue);
    expect(coverage.allChaptersCovered, isTrue);
    final requiredActions =
        BookwideSourceEncounters.executableChoicesForReviewedEvents(
      plan: plan, reviewedEventIds: extras,
    );
    expect(requiredActions.length, 60);
    expect(requiredActions.values.toSet().length, 60);
    final contract = BookwideCampaignContract.fromPlan(
      book: book, draft: draft, plan: plan,
      reviewedInteractiveEventIds: extras,
    );
    expect(contract.sourceDecisions.length, 72);
    expect(contract.bridgeDecisions.length, 10);
    expect(contract.actEntryScenes, hasLength(6));

    final reviewedQuotes = <String>{
      for (final part in draft.parts) ...[
        part.setupEventId, part.outcomeEventId,
      ],
      ...extras,
    };
    expect(reviewedQuotes.length, 72);
    final compiled = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: map, draft: draft,
      reviewedInteractiveEventIds: extras,
      sourceEventIdsReviewedByUser: reviewedQuotes,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    );
    expect(compiled.sourceEventsRepresented, 72);
    expect(compiled.sourceQuoteCount, 72);
    expect(compiled.verifiedSourceChoices, 72);
    expect(compiled.verifiedActBridges, 10);
    expect(compiled.isFullBookAdaptation, isFalse);
    expect(compiled.requiresCloudToPlay, isFalse);
    final imported = const RichPrivateBookworldImporter()
        .inspect(compiled.archive);
    final causal = StoryCampaignCausalAudit.inspect(
      blueprint: imported.blueprint,
      requiredChoiceIds: contract.requiredChoiceIds,
    );
    expect(causal.status, CampaignCausalStatus.playable);
    contract.verifyWitnesses(causal);
    expect(causal.choiceWitnesses.keys,
        containsAll(contract.requiredChoiceIds));
    expect(causal.cycleCount, 0);
    expect(causal.unprovenRequiredChoiceIds, isEmpty);
    for (final action in requiredActions.values) {
      expect(causal.choiceWitnesses[action], isNotEmpty,
          reason: 'No real StoryWorld.apply path for $action');
      expect(causal.choiceWitnesses[action]!.last.choiceId, action);
    }

    final temp = await Directory.systemTemp.createTemp(
        'ai-rpg-many-events-');
    late String campaign;
    var revision = 0;
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        final installed = store.installBookworld(compiled.archive);
        campaign = store.createCampaign(installed.archiveHash);
        // Visit all 60 events, then take the positive branch of each act.
        // Every transition is committed by the same production SQLite engine.
        for (var act = 1; act <= 6; act++) {
          for (var i = 0; i < 10; i++) {
            final suffix = i == 0 ? '' : '_${i + 1}';
            final choice = 'act_${act}_examine_source$suffix';
            final available = store.loadCampaign(campaign).coordinator
                .choices.any((c) => c.id == choice && c.enabled);
            expect(available, isTrue, reason: choice);
            final result = store.commitChoice(campaign,
              actionId: 'long_step_$revision',
              choiceId: choice, expectedRevision: revision);
            expect(result.applied, isTrue, reason: choice);
            revision++;
          }
          final decisions = <String>[
            'act_${act}_accept_offer',
            'act_${act}_honor_condition',
            if (act != 6) 'act_${act}_continue_original',
          ];
          for (final choice in decisions) {
            final result = store.commitChoice(campaign,
              actionId: 'long_step_$revision',
              choiceId: choice, expectedRevision: revision);
            expect(result.applied, isTrue, reason: choice);
            revision++;
          }
        }
        expect(revision, 77);
        expect(store.loadCampaign(campaign).coordinator.isTerminal, isTrue);
        expect(store.loadCampaign(campaign).metadata.revision, revision);
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        expect(store.installedWorlds(), hasLength(1));
        expect(store.loadCampaign(campaign).coordinator.isTerminal, isTrue);
        expect(store.loadCampaign(campaign).metadata.revision, 77);
      } finally {
        store.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('eight source-locked acts keep durable outcomes, reuse only local '
      'flags, prove anchors and both bridges, and resume after SQLite restart',
      () async {
    final index = _longIndex(chapters: 8);
    final book = await _longBook(index);
    expect(book.events, hasLength(96));
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(map.acts, hasLength(8));
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 8; i++) _actProposal(book, i)],
    );
    expect(draft.parts, hasLength(8));
    expect(draft.plan.flags, hasLength(19)); // 16 durable + 3 rolling.
    expect(draft.plan.flags,
        containsAll(BookwideStoryPlanComposer.rollingFlags));
    expect(draft.plan.flags, contains('act_1_original_outcome'));
    expect(draft.plan.flags, contains('act_8_alternate_outcome'));
    final extras = <String>{};
    for (var i = 0; i < 8; i++) {
      extras.add(BookwideSourceEncounters.eligibleForAct(
        index: index, bookMap: map, draft: draft, partIndex: i,
      ).first.id);
    }
    final plan = BookwideSourceEncounters.attach(
      index: index, book: book, bookMap: map, draft: draft,
      plan: draft.plan, reviewedEventIds: extras,
      userConfirmedPrivateAdaptation: true,
    );
    final contract = BookwideCampaignContract.fromPlan(
      book: book, draft: draft, plan: plan,
      reviewedInteractiveEventIds: extras,
    );
    expect(contract.sourceDecisions.length, 24); // 16 anchors + 8 extras.
    expect(contract.bridgeDecisions.length, 14);
    expect(contract.requiredChoiceIds.length, 38);
    expect(plan.situations.length, 64);
    for (var act = 1; act < 8; act++) {
      for (final kind in ['original', 'alternate']) {
        final scene = plan.situations.singleWhere(
            (s) => s.id == 'act_${act}_${kind}_ending');
        final bridge = scene.decisions.single;
        expect(bridge.removes,
            containsAll(BookwideStoryPlanComposer.rollingFlags));
        expect(bridge.nextSituationId,
            'act_${act + 1}_source_encounter');
      }
    }

    // A forged source anchor or diverted act-boundary must FAIL CLOSED before
    // any ZIP is built or the user's installed campaigns are modified.
    StoryPlan alter(String sceneId,
        StorySituation Function(StorySituation) change) => StoryPlan(
      sourceFingerprint: plan.sourceFingerprint,
      title: plan.title, entrySituationId: plan.entrySituationId,
      flags: plan.flags, initialFlags: plan.initialFlags,
      situations: [
        for (final s in plan.situations)
          if (s.id == sceneId) change(s) else s,
      ],
    );
    final wrongQuote = alter('act_1_turning_point', (s) =>
        StorySituation(
          id: s.id, goal: s.goal, conflict: s.conflict,
          chapterIndex: s.chapterIndex, sourceEventId: extras.first,
          route: s.route, terminal: s.terminal, decisions: s.decisions,
        ));
    expect(() => BookwideCampaignContract.fromPlan(
      book: book, draft: draft, plan: wrongQuote,
      reviewedInteractiveEventIds: extras,
    ), throwsFormatException);
    final wrongBridge = alter('act_1_original_ending', (s) =>
        StorySituation(
          id: s.id, goal: s.goal, conflict: s.conflict,
          chapterIndex: s.chapterIndex, sourceEventId: s.sourceEventId,
          route: s.route, terminal: s.terminal, decisions: [
            for (final d in s.decisions)
              StoryDecision(
                id: d.id, intent: d.intent,
                nextSituationId: 'act_1_turning_point',
                sourceEventId: d.sourceEventId, route: d.route,
                requires: d.requires, forbids: d.forbids,
                adds: d.adds, removes: d.removes,
              ),
          ],
        ));
    expect(() => BookwideCampaignContract.fromPlan(
      book: book, draft: draft, plan: wrongBridge,
      reviewedInteractiveEventIds: extras,
    ), throwsFormatException);

    final reviewedIds = <String>{
      for (final part in draft.parts) ...[
        part.setupEventId, part.outcomeEventId,
      ],
      ...extras,
    };
    final compiled = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: map, draft: draft,
      sourceEventIdsReviewedByUser: reviewedIds,
      reviewedInteractiveEventIds: extras,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    expect(compiled.sourceQuoteCount, 24);
    expect(compiled.verifiedSourceChoices, 24);
    expect(compiled.verifiedActBridges, 14);
    expect(compiled.requiresCloudToPlay, isFalse);
    final imported = const RichPrivateBookworldImporter()
        .inspect(compiled.archive);
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: imported.blueprint,
      requiredChoiceIds: contract.requiredChoiceIds,
    );
    expect(report.status, CampaignCausalStatus.playable);
    contract.verifyWitnesses(report);

    final dir = await Directory.systemTemp.createTemp('rpg-eight-acts-');
    var revision = 0;
    late String campaign;
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        final installed = db.installBookworld(compiled.archive);
        campaign = db.createCampaign(installed.archiveHash);
        for (var act = 1; act <= 4; act++) {
          for (final id in [
            'act_${act}_examine_source',
            'act_${act}_accept_offer',
            'act_${act}_honor_condition',
            'act_${act}_continue_original',
          ]) {
            expect(db.commitChoice(campaign,
              actionId: 'eight_$revision', choiceId: id,
              expectedRevision: revision).applied, isTrue, reason: id);
            revision++;
          }
        }
        expect(db.loadCampaign(campaign).coordinator.sceneId,
            'act_5_source_encounter');
        expect(db.loadCampaign(campaign).metadata.revision, 16);
      } finally {
        db.close();
      }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        expect(db.loadCampaign(campaign).coordinator.sceneId,
            'act_5_source_encounter');
        for (var act = 5; act <= 8; act++) {
          for (final id in [
            'act_${act}_examine_source',
            'act_${act}_accept_offer',
            'act_${act}_honor_condition',
            if (act < 8) 'act_${act}_continue_original',
          ]) {
            expect(db.commitChoice(campaign,
              actionId: 'eight_$revision', choiceId: id,
              expectedRevision: revision).applied, isTrue, reason: id);
            revision++;
          }
        }
        expect(revision, 31);
        expect(db.loadCampaign(campaign).metadata.revision, 31);
        expect(db.loadCampaign(campaign).coordinator.isTerminal, isTrue);
      } finally {
        db.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
