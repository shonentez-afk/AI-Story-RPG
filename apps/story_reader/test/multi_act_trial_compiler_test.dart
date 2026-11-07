import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/bookwide_source_encounters.dart';
import 'package:ai_story_reader/cross_act_consequence_gate.dart';
import 'package:ai_story_reader/cross_act_source_evidence_packet.dart';
import 'package:ai_story_reader/multi_act_trial_compiler.dart';
import 'package:ai_story_reader/story_plan_causal_audit.dart';
import 'package:ai_story_reader/whole_story_literary_evidence_manifest.dart';
import 'package:ai_story_reader/whole_story_literary_review.dart';
import 'package:ai_story_reader/whole_story_literary_summary.dart';
import 'package:ai_story_reader/whole_story_literary_bounded_repair.dart';
import 'package:ai_story_reader/whole_story_literary_unchanged_approval.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
import 'package:ai_story_reader/gameplay_candidate_reachability.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
import 'package:ai_story_reader/whole_plan_gameplay_batch_page.dart';
import 'package:ai_story_reader/source_locked_gameplay_review_page.dart';
import 'package:ai_story_reader/reviewed_prose_scene_overlay.dart';
import 'package:ai_story_reader/zai_source_locked_prose_preview.dart';
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
import 'package:flutter/material.dart';
import 'package:ai_story_reader/multi_act_trial_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';

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

Future<NarrativeBookModel> _analyze(BookSourceIndex index,
    {int eventsPerChapter = 2}) async {
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
            for (var i = 0; i < eventsPerChapter; i++)
              SemanticCandidate.propose(
                source, chunk, category: SemanticCategory.event,
                startUtf16: chunk.startUtf16 + i * 86,
                endUtf16: chunk.startUtf16 + i * 86 + 60,
                label: 'Предположенное событие',
                uncertainty: 'Смысл и хронология мира не проверены.',
              ),
          ],
        ),
        totalSuggestions: eventsPerChapter,
        rejectedCount: 0, rejectedNonRussian: 0,
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
    expect(compilation.sourceEventsTotal, book.events.length);
    expect(compilation.sourceEventsRepresented, input.draft.coverage.referencedEvents);
    expect(compilation.unrepresentedSourceEventIds,
        input.draft.coverage.eventIdsStillUnrepresented);
    expect(compilation.chaptersWithoutSourceEvents,
        input.draft.coverage.chaptersWithoutEventProposals);
    expect(compilation.hasAllSourceEventsRepresented,
        input.draft.coverage.allDetectedEventsReferenced &&
            input.draft.coverage.allChaptersCovered);
    expect(compilation.selectedHeroLabel, 'Игрок');
    expect(compilation.isFullBookAdaptation, false);
    final inspected = const RichPrivateBookworldImporter().inspect(
        compilation.archive);
    expect(inspected.sourceFingerprint, index.sourceFingerprint);
    expect(inspected.requiresNetwork, false);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.blueprint.scenes.length, 14);
    expect(inspected.presentation['hero'], containsPair('name', 'Игрок'));
    expect(inspected.presentation['item_names'], isEmpty);
    expect(inspected.presentation['fact_names'], isEmpty);
    expect(inspected.blueprint.initial.stats, isEmpty);
    expect(() => const PrivateBookworldImporter().inspect(compilation.archive),
        throwsFormatException);

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

  test('selected player label is written to rich v3 and rejects invalid '
      'names without changing the story actor', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final named = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map, draft: input.draft,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
      heroName: 'Путешественник',
    );
    final rich = const RichPrivateBookworldImporter().inspect(named.archive);
    expect(rich.presentation['hero'], containsPair('name', 'Путешественник'));
    expect(rich.blueprint.actors, contains('player'));
    expect(named.selectedHeroLabel, 'Путешественник');
    expect(named.sourceEventsTotal, book.events.length);
    expect(named.isFullBookAdaptation, false);
    for (final bad in ['', ' Неверное имя', 'x' * 91, 'Имя\nчужое']) {
      await expectLater(MultiActTrialCompiler.compile(
        index: index, book: book, bookMap: input.map, draft: input.draft,
        sourceEventIdsReviewedByUser: input.eventIds,
        privateUseConfirmed: true, fictionalTrialAcknowledged: true,
        heroName: bad,
      ), throwsFormatException);
    }
  });

  test('g2b real integration: criticized cross-act decision is repaired, '
      'independently re-reviewed, then built as offline v3 with two routes',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final original = input.draft.plan;
    final evidence = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: original);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: original, evidence: evidence);
    const target = 'act_2_accept_offer';
    final firstReports = [
      for (final window in manifest.windows)
        WholeLiteraryReviewReport.fromJson(window, {
          'window_digest': window.approvalDigest,
          'verdict': window.transitions.any(
                  (step) => step['choice_id'] == target)
              ? 'needsRevision' : 'insufficientEvidence',
          'uncertainty': 'Независимый тест: решение следующего акта '
              'зависит от не подтверждённого игрового исхода.',
          'findings': [
            if (window.transitions.any(
                (step) => step['choice_id'] == target))
              {
                'kind': 'causalLink', 'severity': 'high',
                'scene_id': 'act_2_turning_point',
                'choice_id': target, 'source_event_id': null,
                'problem': 'Второе согласие не должно быть доступно '
                    'после альтернативного окончания первого акта.',
              },
          ],
          'status': 'UNVERIFIED_AI_REVIEW',
        }),
    ];
    final digest = WholeStoryLiterarySummary.compile(
        manifest: manifest, reports: firstReports).reportDigest;
    final repair = WholeStoryLiteraryBoundedRepair.propose(
      manifest: manifest, reports: firstReports,
      expectedReportDigest: digest,
      explicitRuleReview: true,
      approvedRules: StoryCausalContract(decisionInvariants: [
        StoryDecisionInvariant(id: 'cross_act_consented',
          decisionId: target,
          requires: ['act_1_original_outcome'],
          forbids: ['act_1_alternate_outcome']),
      ]),
    );
    expect(repair.changed, true);
    expect(repair.formal.after.counterexamples, isEmpty);
    expect(repair.draft.validate(book).terminalSituations, 2);
    final fresh = repair.newReviewManifest!;
    final cleanReports = [
      for (final window in fresh.windows)
        WholeLiteraryReviewReport.fromJson(window, {
          'window_digest': window.approvalDigest,
          'verdict': window.sourceQuotes.isEmpty
              ? 'insufficientEvidence' : 'possibleConsistency',
          'uncertainty': 'Неопределённость исходного текста сохраняется. '
              'Проверены только игровые условия этой частной версии.',
          'findings': <Map<String, Object?>>[],
          'status': 'UNVERIFIED_AI_REVIEW',
        }),
    ];
    final accepted = WholeStoryLiteraryRecheckApproval.accept(
      repair: repair, newReports: cleanReports,
      userReviewedNewResults: true, confirmedPrivateGameFiction: true,
    );
    expect(accepted.provesBookCanon, false);
    accepted.verifyForCompiler(
        index: index, book: book, originalPlan: original);
    final archive = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, recheckedRepair: accepted,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    );
    final inspected = const RichPrivateBookworldImporter()
        .inspect(archive.archive);
    expect(inspected.blueprint.scenes.length, 14);
    expect(inspected.requiresNetwork, false);
    expect(inspected.canDistributePublicly, false);
    final dir = await Directory.systemTemp.createTemp('g2b-e2e-v3-');
    try {
      final db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        final world = db.installBookworld(archive.archive);
        final rejected = db.createCampaign(world.archiveHash);
        final originalRoute = db.createCampaign(world.archiveHash);
        var rev = 0;
        for (final action in [
          'act_1_refuse_offer', 'act_1_explore',
          'act_1_use_discovery', 'act_1_end_alternative',
          'act_1_continue_alternative',
        ]) {
          final result = db.commitChoice(rejected,
            actionId: 'alt_' + rev.toString(), choiceId: action,
            expectedRevision: rev);
          expect(result.applied, true);
          rev++;
        }
        expect(db.loadCampaign(rejected).coordinator.choices.any((c) =>
            c.id == target && c.enabled), false);
        expect(db.loadCampaign(rejected).coordinator.choices.any((c) =>
            c.id == 'act_2_refuse_offer' && c.enabled), true);
        rev = 0;
        for (final action in [
          'act_1_accept_offer', 'act_1_honor_condition',
          'act_1_continue_original',
        ]) {
          final result = db.commitChoice(originalRoute,
            actionId: 'original_' + rev.toString(),
            choiceId: action, expectedRevision: rev);
          expect(result.applied, true);
          rev++;
        }
        expect(db.loadCampaign(originalRoute).coordinator.choices.any(
            (c) => c.id == target && c.enabled), true);
      } finally {
        db.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
    await expectLater(MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, recheckedRepair: accepted,
      continuity: input.continuity,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    ), throwsFormatException);
  });

  test('g2f2b unchanged complete literary review has a typed source-SHA '
      'receipt and compiles only the exact PRIVATE v3 graph', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final evidence = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: input.draft.plan);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: input.draft.plan,
        evidence: evidence);
    expect(manifest.totalWindows, greaterThan(0));
    // This is a private, source-locked test review, NOT a claim that
    // the model correctly understood the actual original book.
    final reports = [
      for (final window in manifest.windows)
        WholeLiteraryReviewReport.fromJson(window, {
          'window_digest': window.approvalDigest,
          'verdict': window.sourceQuotes.isEmpty
              ? 'insufficientEvidence' : 'possibleConsistency',
          'uncertainty': 'Цитаты доказывают слова, но не всю литературную '
              'причинность, смысл или знания персонажей книги.',
          'findings': <Map<String, Object?>>[],
          'status': 'UNVERIFIED_AI_REVIEW',
        }),
    ];
    final summary = WholeStoryLiterarySummary.compile(
        manifest: manifest, reports: reports);
    expect(summary.totalFindings, 0);
    expect(() => WholeStoryLiteraryUnchangedApproval.accept(
      manifest: manifest, reports: reports,
      userReviewedAllReports: false,
      explicitlyAcceptedPrivateFiction: true,
    ), throwsFormatException);
    expect(() => WholeStoryLiteraryUnchangedApproval.accept(
      manifest: manifest, reports: reports,
      userReviewedAllReports: true,
      explicitlyAcceptedPrivateFiction: false,
    ), throwsFormatException);
    expect(() => WholeStoryLiteraryUnchangedApproval.accept(
      manifest: manifest, reports: reports.take(reports.length - 1).toList(),
      userReviewedAllReports: true,
      explicitlyAcceptedPrivateFiction: true,
    ), throwsFormatException);

    final accepted = WholeStoryLiteraryUnchangedApproval.accept(
      manifest: manifest, reports: reports,
      userReviewedAllReports: true,
      explicitlyAcceptedPrivateFiction: true,
    );
    expect(accepted.provesBookCanon, false);
    expect(accepted.canDistributePublicly, false);
    expect(accepted.unresolvedWindows, summary.insufficient);
    expect(accepted.uncoveredSourceEvents, summary.uncoveredEvents);
    accepted.verifyForCompiler(
        index: index, book: book, plan: input.draft.plan);
    final compiled = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, unchangedReview: accepted,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    );
    final rich = const RichPrivateBookworldImporter().inspect(
        compiled.archive);
    expect(rich.sourceFingerprint, index.sourceFingerprint);
    expect(rich.requiresNetwork, false);
    expect(rich.canDistributePublicly, false);
    expect(rich.blueprint.scenes.length, 14);

    // Any additional causal rule after the independent verdict MUST
    // invalidate the same original-plan receipt before game installation.
    await expectLater(MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, unchangedReview: accepted,
      continuity: input.continuity,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    ), throwsFormatException);
    final editedIndex = _index(suffix: ' Другая редакция');
    final editedBook = await _analyze(editedIndex);
    expect(() => accepted.verifyForCompiler(
      index: editedIndex, book: editedBook,
      plan: input.draft.plan,
    ), throwsFormatException);
    final markedForRevision = [
      for (final window in manifest.windows)
        WholeLiteraryReviewReport.fromJson(window, {
          'window_digest': window.approvalDigest,
          'verdict': 'needsRevision',
          'uncertainty': 'Необходимо отдельно прояснить литературные '
              'причины и последствия этого решения персонажа.',
          'findings': <Map<String, Object?>>[],
          'status': 'UNVERIFIED_AI_REVIEW',
        }),
    ];
    expect(() => WholeStoryLiteraryUnchangedApproval.accept(
      manifest: manifest, reports: markedForRevision,
      userReviewedAllReports: true,
      explicitlyAcceptedPrivateFiction: true,
    ), throwsFormatException);
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

  test('reviewed Russian prose is embedded in PRIVATE BookWorld while '
      'source quote, game decisions and provenance remain unchanged',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: input.draft.plan,
      situationId: 'act_1_turning_point',
    );
    const prose = 'Путник задержался возле тихого ручья и '
        'посмотрел на следы у старой переправы. '
        'Он слушал собеседника, но ещё не принимал никаких '
        'обязательств. Перед ним оставались разные пути.';
    final draft = SourceLockedProseDraft(
      sourceFingerprint: index.sourceFingerprint,
      situationId: context.situation.id,
      approvalDigest: context.approvalDigest,
      text: prose,
      uncertainty: 'Художественная адаптация; знания и причины не доказаны.',
      route: context.situation.route,
    );
    final approved = ReviewedProseSceneApproval.accept(
      context: context, draft: draft,
      fullTextReviewedByUser: true,
      privateFictionAcknowledged: true,
    );
    expect(approved.establishesBookWorldTruth, false);
    expect(approved.canPublishAsCanon, false);
    expect(approved.changesGameRules, false);

    final baseline = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft,
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    final improved = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, reviewedProse: [approved],
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    final original = const RichPrivateBookworldImporter().inspect(
        baseline.archive);
    final changed = const RichPrivateBookworldImporter().inspect(
        improved.archive);
    final oldScene = original.blueprint.scenes['act_1_turning_point']!;
    final newScene = changed.blueprint.scenes['act_1_turning_point']!;
    expect(newScene.text, contains(prose));
    expect(newScene.text, contains(context.sourceEvent!.source.quote));
    expect(newScene.text, contains('НЕ КАНОН'));
    expect(oldScene.text, isNot(contains(prose)));
    expect(newScene.choices.map((e) => e.id).toList(),
        oldScene.choices.map((e) => e.id).toList());
    expect(changed.blueprint.scenes.length,
        original.blueprint.scenes.length);
    expect(changed.sourceFingerprint, index.sourceFingerprint);
    expect(changed.requiresNetwork, false);
    expect(changed.canDistributePublicly, false);
  });

  test('unapproved, stale and cross-plan prose are never installed',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: input.draft.plan,
      situationId: 'act_1_turning_point',
    );
    const prose = 'Дорога вилась между деревьями, когда путник '
        'вспомнил о нерешённом предложении и остановился '
        'у реки. Он прислушался к шагам вдали, не принимая '
        'обещаний и не выдавая догадки за знание.';
    SourceLockedProseDraft draftFor(String fingerprint, String digest) =>
        SourceLockedProseDraft(
          sourceFingerprint: fingerprint,
          situationId: context.situation.id,
          approvalDigest: digest,
          text: prose,
          uncertainty: 'События и факты не подтверждены исходной книгой.',
          route: context.situation.route,
        );
    final draft = draftFor(index.sourceFingerprint, context.approvalDigest);
    expect(() => ReviewedProseSceneApproval.accept(
      context: context, draft: draft,
      fullTextReviewedByUser: false,
      privateFictionAcknowledged: true,
    ), throwsFormatException);
    expect(() => ReviewedProseSceneApproval.accept(
      context: context, draft: draft,
      fullTextReviewedByUser: true,
      privateFictionAcknowledged: false,
    ), throwsFormatException);
    expect(() => ReviewedProseSceneApproval.accept(
      context: context,
      draft: draftFor('foreign-edition', context.approvalDigest),
      fullTextReviewedByUser: true,
      privateFictionAcknowledged: true,
    ), throwsFormatException);
    expect(() => ReviewedProseSceneApproval.accept(
      context: context, draft: draftFor(index.sourceFingerprint, 'stale'),
      fullTextReviewedByUser: true,
      privateFictionAcknowledged: true,
    ), throwsFormatException);

    final approved = ReviewedProseSceneApproval.accept(
      context: context, draft: draft,
      fullTextReviewedByUser: true,
      privateFictionAcknowledged: true,
    );
    await expectLater(MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, continuity: input.continuity,
      reviewedProse: [approved],
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    ), throwsFormatException);
    await expectLater(MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: input.map,
      draft: input.draft, reviewedProse: [approved, approved],
      sourceEventIdsReviewedByUser: input.eventIds,
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    ), throwsFormatException);
  });


  test('M2h7c6a: TWO complete real branches expose exact source words '
      'and BEFORE/AFTER gameplay states across two chapters', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final accepted = [
      'act_1_accept_offer', 'act_1_honor_condition',
      'act_1_continue_original',
      'act_2_accept_offer', 'act_2_honor_condition',
    ];
    final refused = [
      'act_1_refuse_offer', 'act_1_explore',
      'act_1_use_discovery', 'act_1_end_alternative',
      'act_1_continue_alternative',
      'act_2_refuse_offer', 'act_2_explore',
      'act_2_use_discovery', 'act_2_end_alternative',
    ];
    final packet = CrossActSourceEvidencePacket.fromCompletePaths(
      index: index, book: book, plan: input.draft.plan,
      choicePaths: [accepted, refused],
    );
    expect(packet.referencedSourceEvents, greaterThanOrEqualTo(2));
    expect(packet.crossedChapters, 2);
    expect(packet.inputBytes,
        lessThanOrEqualTo(CrossActSourceEvidencePacket.maxUserBytes));
    expect(packet.sourceQuotesVerified, true);
    expect(packet.establishesWorldTime, false);
    expect(packet.provesBookCausation, false);
    expect(packet.provesActorKnowledge, false);
    expect(packet.establishesLiteraryCanon, false);
    expect(packet.mayAutomaticallyModifyGame, false);
    final paths = packet.sentContext['complete_game_paths'] as List;
    expect(paths, hasLength(2));
    final yes = (paths.first as Map)['steps'] as List;
    final no = (paths.last as Map)['steps'] as List;
    final firstAccepted = yes.first as Map;
    final firstRefused = no.first as Map;
    expect(firstAccepted['choice_id'], 'act_1_accept_offer');
    expect(firstAccepted['flags_before'], isNot(contains('act_1_disclosure_accepted')));
    expect(firstAccepted['flags_after'], contains('act_1_disclosure_accepted'));
    expect(firstRefused['choice_id'], 'act_1_refuse_offer');
    expect(firstRefused['flags_after'], isNot(contains('act_1_disclosure_accepted')));
    expect((paths.first as Map)['terminal_scene_id'],
        isNot((paths.last as Map)['terminal_scene_id']));
    final evidence = packet.sentContext['source_evidence'] as List;
    expect(evidence, isNotEmpty);
    for (final item in evidence) {
      final excerpt = item as Map;
      final event = book.events.singleWhere(
          (e) => e.id == excerpt['event_id']);
      event.source.validate(index);
      expect(excerpt['quote'], event.source.quote);
      expect(excerpt['evidence_status'],
          'EXACT_WORDS_ONLY_NOT_CAUSAL_PROOF');
    }
    final sent = jsonEncode(packet.sentContext);
    expect(sent, isNot(contains(index.title)));
    expect(sent, isNot(contains(index.author)));
    expect(sent, isNot(contains(index.sourceFingerprint)));
    expect(packet.approvalDigest, hasLength(64));
  });

  test('M2h7c6a: refuses invented, illegal or incomplete histories '
      'and unrelated editions without sending anything', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final accepted = [
      'act_1_accept_offer', 'act_1_honor_condition',
      'act_1_continue_original',
      'act_2_accept_offer', 'act_2_honor_condition',
    ];
    final refused = [
      'act_1_refuse_offer', 'act_1_explore',
      'act_1_use_discovery', 'act_1_end_alternative',
      'act_1_continue_alternative',
      'act_2_refuse_offer', 'act_2_explore',
      'act_2_use_discovery', 'act_2_end_alternative',
    ];
    void build(List<List<String>> paths, {BookSourceIndex? from}) {
      CrossActSourceEvidencePacket.fromCompletePaths(
        index: from ?? index,
        book: book,
        plan: input.draft.plan,
        choicePaths: paths,
      );
    }
    expect(() => build([accepted, accepted]), throwsFormatException);
    expect(() => build([accepted.sublist(0, 2), refused]),
        throwsFormatException);
    expect(() => build([
      ['act_1_refuse_offer', 'act_1_honor_condition'], accepted,
    ]), throwsFormatException);
    expect(() => build([
      ['act_1_accept_offer', 'foreign_model_choice'], refused,
    ]), throwsFormatException);
    expect(() => build([accepted, refused],
        from: _index(suffix: ' другой перевод')),
        throwsFormatException);
    expect(() => build([accepted, []]), throwsFormatException);
  });


  testWidgets('cross-act gameplay proposal stays tied to the '
      'source-reviewed effective plan with no automatic API call',
      (tester) async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    await tester.pumpWidget(MaterialApp(
      home: MultiActTrialPage(
        index: index, book: book, bookMap: input.map, draft: input.draft,
        gateway: const DeviceWorldLibraryGateway(background: false),
      ),
    ));

    expect(find.byKey(const Key('multiact-source-coverage')), findsOneWidget);
    expect(find.byKey(const Key('multiact-available-mode')), findsOneWidget);
    expect(find.byKey(const Key('multiact-hero-label')), findsOneWidget);
    // Scroll the PRIMARY page ListView, not an ExpansionTile or nested
    // ListTile scrollable. Controls below the viewport are lazily built.
    final scrollable = find.byType(Scrollable).first;
    final quotes = find.byKey(const Key('multiact-trial-source-reviewed'));
    await tester.scrollUntilVisible(quotes, 110, scrollable: scrollable);
    await tester.tap(quotes);
    await tester.pumpAndSettle();
    final fiction = find.byKey(const Key('multiact-trial-private-fiction'));
    await tester.scrollUntilVisible(fiction, 110, scrollable: scrollable);
    await tester.tap(fiction);
    await tester.pumpAndSettle();

    final crossAct = find.byKey(const Key('multiact-trial-consequence'));
    await tester.scrollUntilVisible(crossAct, 110, scrollable: scrollable);
    await tester.tap(crossAct);
    await tester.pumpAndSettle();
    final itemButton = find.byKey(
        const Key('multiact-trial-optional-gameplay'));
    await tester.scrollUntilVisible(itemButton, 110, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(itemButton).onPressed, isNotNull);
    final batchButton =
        find.byKey(const Key('multiact-trial-whole-gameplay-batch'));
    await tester.scrollUntilVisible(batchButton, 110,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(batchButton).onPressed, isNotNull);
    final literaryButton =
        find.byKey(const Key('multiact-trial-whole-literary-review'));
    await tester.scrollUntilVisible(literaryButton, 110,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(literaryButton).onPressed, isNull);

    await tester.scrollUntilVisible(itemButton, -110,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(itemButton);
    await tester.pumpAndSettle();
    final candidatePage = tester.widget<SourceLockedGameplayReviewPage>(
        find.byType(SourceLockedGameplayReviewPage));
    final second = candidatePage.plan.situations.singleWhere(
        (scene) => scene.id == 'act_2_turning_point');
    final accept = second.decisions.singleWhere(
        (choice) => choice.id == 'act_2_accept_offer');
    expect(accept.requires, contains('act_1_original_outcome'));
    expect(find.text('Предметы и знания из книги'), findsOneWidget);
    final request = find.byKey(const Key('gameplay-source-request'));
    await tester.scrollUntilVisible(request, 110,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(request).onPressed, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('multiact-trial-start'));
    await tester.scrollUntilVisible(start, 110,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(start, findsOneWidget);
    expect(find.byKey(const Key('multiact-trial-clear-gameplay')),
        findsNothing);
  });

  test('whole-plan gameplay batching covers anchored acts with exact consent, '
      'bounded requests and recoverable proposal-only checkpoints', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: input.draft.plan,
      maxNewRequestsPerRun: 1,
    );
    expect(manifest.totalBatches, greaterThanOrEqualTo(1));
    expect(manifest.totalReferencedSourceEvents,
        greaterThanOrEqualTo(1));
    expect(manifest.totalReferencedSourceEvents + manifest.unanchoredBookEvents,
        book.events.length);
    expect(manifest.sentContextBytes, greaterThan(0));
    expect(manifest.literaryCanonVerified, false);
    expect(manifest.mayInstallGame, false);
    expect(manifest.coversUnanchoredEvents, false);
    expect(manifest.maxHttpAttempts,
        ZaiSourceLockedGameplayCandidateService.maxAttempts);
    expect(manifest.sentContexts.length, manifest.totalBatches);
    manifest.verifyUnchanged();

    var networkCalls = 0;
    final memory = MemorySourceAnalysisCheckpointRepository();
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        networkCalls++;
        token.check();
        expect(ctx.payloadJson, isNot(contains('Два акта с разными')));
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: const [],
        );
      },
    );
    final before = await service.inspect(manifest);
    expect(before.completed, 0);
    expect(networkCalls, 0);
    await expectLater(service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: false,
    ), throwsFormatException);
    await expectLater(service.generate(
      manifest: manifest, approvedManifestDigest: 'f' * 64,
      explicitBatchConsent: true,
    ), throwsFormatException);
    expect(networkCalls, 0);

    var report = await service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(report.completed, 1);
    expect(report.newRequests, 1);
    expect(networkCalls, 1);
    // Reopening must NOT pay for the already saved first batch again.
    final reloaded = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        networkCalls++;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: const [],
        );
      },
    );
    for (var i = 1; i < manifest.totalBatches; i++) {
      report = await reloaded.generate(
        manifest: manifest,
        approvedManifestDigest: manifest.approvalDigest,
        explicitBatchConsent: true,
      );
      expect(report.newRequests, lessThanOrEqualTo(1));
    }
    report = await reloaded.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(report.allProposalsCollected, true);
    expect(report.newRequests, 0);
    expect(report.recovered, manifest.totalBatches);
    expect(networkCalls, manifest.totalBatches);
    final saved = await reloaded.readUnreviewedProposals(manifest);
    expect(saved, hasLength(manifest.totalBatches));
    for (var i = 0; i < saved.length; i++) {
      expect(saved[i].approvalDigest, manifest.contexts[i].approvalDigest);
      expect(saved[i].candidates, isEmpty);
      expect(saved[i].provesLiteraryMeaning, false);
      expect(saved[i].mayChangeGameState, false);
    }

    // Reinterpreting the SAME book with a different authorized request
    // budget invalidates old consent and cannot silently reuse checkpoints.
    final different = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: input.draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(different.approvalDigest, isNot(manifest.approvalDigest));
    await expectLater(reloaded.inspect(different), throwsFormatException);
    expect(networkCalls, manifest.totalBatches);
  });

  test('gameplay batches reject corrupted checkpoint and failed atomic write '
      'without silently scheduling another API call', () async {
    final index = _index();
    final book = await _analyze(index);
    final input = _draft(index, book);
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: input.draft.plan,
      maxNewRequestsPerRun: 1,
    );
    final memory = MemorySourceAnalysisCheckpointRepository();
    var calls = 0;
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        calls++;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest, candidates: const [],
        );
      },
    );
    memory.failNextWrite = true;
    await expectLater(service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    ), throwsA(isA<FileSystemException>()));
    expect(calls, 1);
    expect((await service.inspect(manifest)).completed, 0);
    await memory.write(index.sourceFingerprint, '{"corrupt":true}');
    await expectLater(service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    ), throwsFormatException);
    expect(calls, 1); // Never retry a paid call over damaged checkpoint.
    await memory.delete(index.sourceFingerprint);
    expect((await service.inspect(manifest)).completed, 0);
    final after = await service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(after.completed, 1);
    expect(calls, 2);
  });


  test('parallel screens may not send two billable batches for same edition',
      () async {
    final index = _index();
    final book = await _analyze(index);
    final plan = _draft(index, book).draft.plan;
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: plan,
      maxNewRequestsPerRun: 1,
    );
    final gate = Completer<void>();
    final memory = MemorySourceAnalysisCheckpointRepository();
    var calls = 0;
    final first = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        calls++;
        await gate.future;
        token.check();
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest, candidates: const [],
        );
      },
    );
    final second = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        calls++;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest, candidates: const [],
        );
      },
    );
    final running = first.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    // The first continuation reaches its awaited model after reading the
    // source checkpoint. The second runner shares the same in-process lock.
    for (var i = 0; i < 10 && calls == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls, 1);
    await expectLater(second.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    ), throwsFormatException);
    expect(calls, 1);
    gate.complete();
    expect((await running).completed, 1);
    expect((await second.inspect(manifest)).completed, 1);
    expect(calls, 1);
  });


  test('all FOUR acts share reviewed gameplay consequences in real '
      'BookWorld with SQLite replay and no retroactive permissions', () async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре связанных игровых акта',
      author: 'Тест игрового решения и его последствий',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Путник увидел старинное кольцо '
              'рядом с воротами и услышал просьбу. '
              'После дороги ему предложили новое условие. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 4; i++) _proposal(book, i)],
    );
    expect(() => CrossActConsequenceGate.applyReviewedActChain(
      index: index, book: book, bookMap: map, draft: draft,
      userConfirmedFictionalContinuity: false,
    ), throwsFormatException);
    final continuity = CrossActConsequenceGate.applyReviewedActChain(
      index: index, book: book, bookMap: map, draft: draft,
      userConfirmedFictionalContinuity: true,
    );
    expect(continuity.hasEnforcedContinuity, true);
    expect(continuity.impacts, hasLength(3));
    expect(continuity.impacts.every((rule) =>
        rule.allowedEarlierOutcomeStates > 0 &&
        rule.blockedOppositeOutcomeStates > 0), true);
    expect(continuity.audit.counterexamples, isEmpty);
    for (var i = 2; i <= 4; i++) {
      final entry = continuity.plan.situations.singleWhere(
          (scene) => scene.id == 'act_${i}_turning_point');
      final accept = entry.decisions.singleWhere(
          (choice) => choice.id == 'act_${i}_accept_offer');
      expect(accept.requires,
          contains('act_${i - 1}_original_outcome'));
      expect(entry.decisions.singleWhere(
          (choice) => choice.id == 'act_${i}_refuse_offer')
          .requires, isNot(contains('act_${i - 1}_original_outcome')));
    }
    expect(continuity.coverage.referencedEvents, 8);
    final compilation = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: map, draft: draft,
      continuity: continuity,
      sourceEventIdsReviewedByUser: {
        for (final part in draft.parts)
          ...[part.setupEventId, part.outcomeEventId],
      },
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
      heroName: 'Путник',
    );
    final verified = const RichPrivateBookworldImporter()
        .inspect(compilation.archive);
    expect(verified.presentation['hero'], containsPair('name', 'Путник'));
    expect(compilation.sceneCount, 28);
    expect(compilation.sourceQuoteCount, 8);
    expect(compilation.isFullBookAdaptation, false);
    final folder = await Directory.systemTemp.createTemp(
        'bookwide-continuity-');
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(folder.path);
      late String refusalId;
      try {
        final installed = db.installBookworld(compilation.archive);
        refusalId = db.createCampaign(installed.archiveHash);
        var revision = 0;
        void step(String choiceId) {
          final before = db.loadCampaign(refusalId).coordinator;
          expect(before.choices.any((c) =>
              c.id == choiceId && c.enabled), true,
              reason: 'choice $choiceId at revision $revision');
          final result = db.commitChoice(refusalId,
              actionId: 'linked_' + revision.toString(),
              choiceId: choiceId,
              expectedRevision: revision);
          expect(result.applied, true);
          revision++;
        }
        for (var act = 1; act <= 3; act++) {
          for (final choice in [
            'act_${act}_refuse_offer',
            'act_${act}_explore',
            'act_${act}_use_discovery',
            'act_${act}_end_alternative',
            'act_${act}_continue_alternative',
          ]) {
            step(choice);
          }
          final next = act + 1;
          final nextScene = db.loadCampaign(refusalId).coordinator;
          expect(nextScene.sceneId, 'act_${next}_turning_point');
          expect(nextScene.choices.singleWhere(
              (c) => c.id == 'act_${next}_accept_offer')
              .enabled, false);
          expect(nextScene.choices.singleWhere(
              (c) => c.id == 'act_${next}_refuse_offer')
              .enabled, true);
        }
        // Last-act original ending cannot be taken after three refusals.
        for (final choice in [
          'act_4_refuse_offer', 'act_4_explore',
          'act_4_use_discovery', 'act_4_end_alternative',
        ]) {
          step(choice);
        }
        expect(db.loadCampaign(refusalId).coordinator.isTerminal, true);
        expect(db.loadCampaign(refusalId).metadata.revision, revision);
      } finally {
        db.close();
      }
      db = BookworldCampaignStore.openPrivateDirectory(folder.path);
      try {
        expect(db.loadCampaign(refusalId).coordinator.isTerminal, true);
        expect(db.loadCampaign(refusalId).metadata.revision, 19);
        // A replayed campaign does NOT regain restricted choices.
        final newId = db.createCampaign(verified.archiveSha256);
        var revision = 0;
        for (var act = 1; act <= 3; act++) {
          for (final choice in [
            'act_${act}_accept_offer', 'act_${act}_honor_condition',
            'act_${act}_continue_original',
          ]) {
            final result = db.commitChoice(newId,
                actionId: 'original_' + revision.toString(),
                choiceId: choice, expectedRevision: revision);
            expect(result.applied, true);
            revision++;
          }
          expect(db.loadCampaign(newId).coordinator.choices.any((c) =>
              c.id == 'act_${act + 1}_accept_offer' && c.enabled), true);
        }
        expect(db.commitChoice(newId, actionId: 'fourth_accept',
            choiceId: 'act_4_accept_offer',
            expectedRevision: revision).applied, true);
        expect(db.commitChoice(newId, actionId: 'fourth_finish',
            choiceId: 'act_4_honor_condition',
            expectedRevision: revision + 1).applied, true);
        expect(db.loadCampaign(newId).coordinator.isTerminal, true);
      } finally {
        db.close();
      }
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('reviewed gameplay item and cross-act choice restriction compile '
      'together, reject stale consent and survive SQLite replay', () async {
    final index = _index();
    final book = await _analyze(index);
    final setup = _draft(index, book);
    final continuity = CrossActConsequenceGate.applyReviewedActChain(
      index: index, book: book, bookMap: setup.map, draft: setup.draft,
      userConfirmedFictionalContinuity: true,
    );
    final context = SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: continuity.plan,
      exactEventIds: setup.eventIds.toList(),
    );
    final first = context.choices.singleWhere(
        (choice) => choice.choiceId == 'act_1_accept_offer');
    final ring = GameplayCandidate(
      kind: 'item', id: 'source_ring', label: 'кольцо',
      op: 'grant_item', sceneId: first.sceneId, choiceId: first.choiceId,
      sourceEventId: first.sourceEventId,
      uncertainty: 'Это только вымышленная игровая награда по цитате.',
    );
    final proposals = GameplayCandidateDraft(
      sourceFingerprint: context.sourceFingerprint,
      approvalDigest: context.approvalDigest,
      candidates: [ring],
    );
    final notes = {
      ReviewedGameplayCompiler.signature(ring):
          'Разрешаю выдачу игрового кольца в частной версии, '
          'но не объявляю владение оригинальным каноном.',
    };
    final base = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: setup.map, draft: setup.draft,
      continuity: continuity,
      sourceEventIdsReviewedByUser: setup.eventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    expect(() => ReviewedGameplayCompiler.preview(
      currentRichBookworld: base.archive,
      index: index, book: book, plan: setup.draft.plan,
      context: context, proposals: proposals,
      selectedUserReviewNotes: notes,
    ), throwsFormatException); // The pre-continuity plan is NOT consented.
    final approval = ReviewedGameplayCompiler.preview(
      currentRichBookworld: base.archive,
      index: index, book: book, plan: continuity.plan,
      context: context, proposals: proposals,
      selectedUserReviewNotes: notes,
    );
    expect((approval.shownReview['effects'] as List), hasLength(1));
    final archive = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approval, currentRichBookworld: base.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: approval.approvalDigest,
    );
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    expect(inspected.presentation['item_names'],
        containsPair('source_ring', 'кольцо'));
    final folder = await Directory.systemTemp.createTemp('linked-item-');
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(folder.path);
      late String accepted, rejected;
      try {
        final installed = store.installBookworld(archive);
        accepted = store.createCampaign(installed.archiveHash);
        rejected = store.createCampaign(installed.archiveHash);
        expect(store.commitChoice(accepted, actionId: 'pick_ring',
            choiceId: 'act_1_accept_offer',
            expectedRevision: 0).applied, true);
        expect(store.loadCampaign(accepted).coordinator.state.inventory,
            contains('source_ring'));
        expect(store.commitChoice(accepted, actionId: 'finish_first',
            choiceId: 'act_1_honor_condition',
            expectedRevision: 1).applied, true);
        expect(store.commitChoice(accepted, actionId: 'next_original',
            choiceId: 'act_1_continue_original',
            expectedRevision: 2).applied, true);
        expect(store.loadCampaign(accepted).coordinator.choices.any((c) =>
            c.id == 'act_2_accept_offer' && c.enabled), true);
        for (final (n, choice) in [
          'act_1_refuse_offer', 'act_1_explore',
          'act_1_use_discovery', 'act_1_end_alternative',
          'act_1_continue_alternative',
        ].indexed) {
          expect(store.commitChoice(rejected,
              actionId: 'reject_' + n.toString(), choiceId: choice,
              expectedRevision: n).applied, true);
        }
        expect(store.loadCampaign(rejected).coordinator.choices.any((c) =>
            c.id == 'act_2_accept_offer' && c.enabled), false);
        expect(store.loadCampaign(rejected).coordinator.state.inventory,
            isNot(contains('source_ring')));
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(folder.path);
      try {
        expect(store.loadCampaign(accepted).coordinator.state.inventory,
            contains('source_ring'));
        expect(store.loadCampaign(accepted).coordinator.choices.any((c) =>
            c.id == 'act_2_accept_offer' && c.enabled), true);
        expect(store.loadCampaign(rejected).coordinator.choices.any((c) =>
            c.id == 'act_2_accept_offer' && c.enabled), false);
      } finally {
        store.close();
      }
    } finally {
      await folder.delete(recursive: true);
    }
  });

  testWidgets('extra source event requires new quote review '
      'and enters the existing multi-act editor, never a new page',
      (tester) async {
    final index = _index();
    final book = await _analyze(index, eventsPerChapter: 3);
    final input = _draft(index, book);
    final event = book.events.where((e) =>
        e.source.chapterIndex == 0).toList()[1];
    await tester.pumpWidget(MaterialApp(home: MultiActTrialPage(
      index: index, book: book, bookMap: input.map,
      draft: input.draft,
      gateway: const DeviceWorldLibraryGateway(background: false),
    )));
    final scroll = find.byType(Scrollable).first;
    final reviewed = find.byKey(const Key('multiact-trial-source-reviewed'));
    await tester.scrollUntilVisible(reviewed, 100, scrollable: scroll);
    await tester.tap(reviewed);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(reviewed).value, true);
    final expand = find.byKey(const Key('multiact-source-encounters'));
    await tester.scrollUntilVisible(expand, -120, scrollable: scroll);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final choice = find.byKey(Key('multiact-extra-' + event.id));
    await tester.scrollUntilVisible(choice, 95, scrollable: scroll);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(reviewed, 110, scrollable: scroll);
    expect(tester.widget<CheckboxListTile>(reviewed).value, false);
    final coverage = find.byKey(const Key('multiact-source-coverage'));
    await tester.scrollUntilVisible(coverage, -100, scrollable: scroll);
    expect(tester.widget<Text>(coverage).data, contains('не представлено 1'));
    expect(find.byType(MultiActTrialPage), findsOneWidget);
  });

  test('two additional source events become real investigate/skip '
      'choices in rich-v3, locked to human review and saved in SQLite',
      () async {
    final index = _index();
    final book = await _analyze(index, eventsPerChapter: 3);
    expect(book.events, hasLength(6));
    final ready = _draft(index, book);
    final extras = <String>{
      for (var chapter = 0; chapter < 2; chapter++)
        book.events.where((e) => e.source.chapterIndex == chapter)
            .toList()[1].id,
    };
    expect(ready.draft.coverage.eventIdsStillUnrepresented, hasLength(2));
    for (var i = 0; i < 2; i++) {
      expect(BookwideSourceEncounters.eligibleForAct(
        index: index, bookMap: ready.map, draft: ready.draft,
        partIndex: i), hasLength(1));
    }
    StoryPlan attach(Set<String> ids, {bool approved = true}) =>
        BookwideSourceEncounters.attach(
          index: index, book: book, bookMap: ready.map,
          draft: ready.draft, plan: ready.continuity.plan,
          reviewedEventIds: ids,
          userConfirmedPrivateAdaptation: approved,
        );
    expect(() => attach(extras, approved: false), throwsFormatException);
    expect(() => attach({'not_an_actual_event'}), throwsFormatException);
    expect(() => attach({ready.draft.parts.first.setupEventId}),
        throwsFormatException);
    final augmented = attach(extras);
    expect(augmented.entrySituationId, 'act_1_source_encounter');
    expect(augmented.situations.length,
        ready.draft.plan.situations.length + 2);
    expect(augmented.validate(book).isStructurallySound, true);
    final sourceChoices = augmented.situations
        .singleWhere((s) => s.id == 'act_1_source_encounter').decisions;
    expect(sourceChoices.map((d) => d.id), [
      'act_1_examine_source', 'act_1_pass_source',
    ]);
    final fromOriginal = augmented.situations
        .singleWhere((s) => s.id == 'act_1_original_ending');
    final fromOther = augmented.situations
        .singleWhere((s) => s.id == 'act_1_alternate_ending');
    expect(fromOriginal.decisions.single.nextSituationId,
        'act_2_source_encounter');
    expect(fromOther.decisions.single.nextSituationId,
        'act_2_source_encounter');
    expect(BookwideActPlanner.compareWithStoryPlan(
        bookMap: ready.map, book: book, story: augmented)
        .allDetectedEventsReferenced, true);
    expect(() => SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: ready.draft.plan,
      exactEventIds: extras.toList(),
    ), throwsFormatException);
    final sourceContext = SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: augmented,
      exactEventIds: extras.toList(),
    );
    expect(sourceContext.choices.map((c) => c.choiceId),
        contains('act_1_examine_source'));

    await expectLater(MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: ready.map, draft: ready.draft,
      continuity: ready.continuity,
      reviewedInteractiveEventIds: extras,
      sourceEventIdsReviewedByUser: ready.eventIds, // not both new quotes!
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    ), throwsFormatException);
    final compiled = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: ready.map, draft: ready.draft,
      continuity: ready.continuity,
      reviewedInteractiveEventIds: extras,
      sourceEventIdsReviewedByUser: {...ready.eventIds, ...extras},
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    expect(compiled.sceneCount, ready.draft.plan.situations.length + 2);
    expect(compiled.sourceQuoteCount, 6);
    expect(compiled.sourceEventsRepresented, 6);
    expect(compiled.isFullBookAdaptation, false);
    final verified = const RichPrivateBookworldImporter()
        .inspect(compiled.archive);
    expect(verified.canDistributePublicly, false);
    for (var i = 0; i < 2; i++) {
      final scene = verified.blueprint.scenes[
          'act_${i + 1}_source_encounter']!;
      final quote = book.events.firstWhere((e) => extras.contains(e.id) &&
          e.source.chapterIndex == i).source.quote;
      expect(scene.text, contains(quote));
    }
    final temp = await Directory.systemTemp.createTemp('source-encounter-');
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      late String id;
      try {
        final installed = store.installBookworld(compiled.archive);
        id = store.createCampaign(installed.archiveHash);
        expect(store.loadCampaign(id).coordinator.sceneId,
            'act_1_source_encounter');
        var revision = 0;
        for (final decision in [
          'act_1_examine_source',
          'act_1_accept_offer', 'act_1_honor_condition',
          'act_1_continue_original',
          'act_2_pass_source',
          'act_2_accept_offer', 'act_2_honor_condition',
        ]) {
          final result = store.commitChoice(id,
              actionId: 'source_${revision}',
              choiceId: decision, expectedRevision: revision);
          expect(result.applied, isTrue, reason: decision);
          revision++;
        }
        expect(store.loadCampaign(id).coordinator.isTerminal, true);
        expect(store.loadCampaign(id).metadata.revision, 7);
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        final restored = store.loadCampaign(id);
        expect(restored.metadata.revision, 7);
        expect(restored.coordinator.isTerminal, true);
        expect(restored.coordinator.events.map((e) => e.choiceId), containsAll([
          'act_1_examine_source', 'act_2_pass_source',
        ]));
      } finally {
        store.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('four source-anchored acts create MORE THAN one six-citation GLM '
      'window with no loss of late-book references', () async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре части одной синтетической книги',
      author: 'Сценарий для проверки охвата',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Участник нашёл ключ около '
              'известной дороги, а затем услышал новое условие. '
              'Решение пока ещё не принято. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    expect(map.acts, hasLength(4));
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [
        for (var i = 0; i < 4; i++) _proposal(book, i),
      ],
    );
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(manifest.totalReferencedSourceEvents, 8);
    expect(manifest.totalBatches, greaterThan(1));
    expect(manifest.maxHttpAttempts,
        2 * ZaiSourceLockedGameplayCandidateService.maxAttempts);
    final requested = <String>{};
    for (final batch in manifest.contexts) {
      expect(batch.excerpts.length, lessThanOrEqualTo(6));
      expect(batch.choices.length, lessThanOrEqualTo(16));
      expect(batch.payloadJson.length, lessThanOrEqualTo(8192));
      requested.addAll(batch.excerpts.map((e) => e.id));
    }
    expect(requested, {for (final e in book.events) e.id});
    expect(manifest.unanchoredBookEvents, 0);
    // Manifest approval displays exact request payloads for BOTH windows.
    expect(manifest.sentContexts, hasLength(manifest.totalBatches));
    expect(manifest.sentContextBytes, greaterThan(0));
    final memory = MemorySourceAnalysisCheckpointRepository();
    var requests = 0;
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, token) async {
        requests++;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest, candidates: const [],
        );
      },
    );
    final progress = await service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(progress.newRequests, lessThanOrEqualTo(2));
    expect(requests, progress.newRequests);
    expect(requests, lessThanOrEqualTo(2));
    expect((await service.inspect(manifest)).completed, progress.completed);
  });


  testWidgets('whole-book consent UI sends nothing on opening, sends '
      'only after two checks and resumes without re-paying', (tester) async {
    final index = _index();
    final book = await _analyze(index);
    final plan = _draft(index, book).draft.plan;
    final memory = MemorySourceAnalysisCheckpointRepository();
    var sent = 0;
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, cancellation) async {
        sent++;
        cancellation.check();
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: const [],
        );
      },
    );
    Widget page() => MaterialApp(
      home: WholePlanGameplayBatchPage(
        index: index, book: book, plan: plan, service: service,
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(sent, 0);
    expect(find.text('Предметы: весь игровой план'), findsOneWidget);
    final scroll = find.byType(Scrollable).first;
    final run = find.byKey(const Key('whole-gameplay-batch-run'));
    await tester.scrollUntilVisible(run, 130, scrollable: scroll);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(run).onPressed, isNull);

    final reviewed = find.byKey(const Key('whole-gameplay-batch-reviewed'));
    await tester.scrollUntilVisible(reviewed, -130, scrollable: scroll);
    await tester.tap(reviewed);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(run).onPressed, isNull);
    final cloud = find.byKey(const Key('whole-gameplay-batch-consent'));
    await tester.scrollUntilVisible(cloud, 100, scrollable: scroll);
    await tester.tap(cloud);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(run, 100, scrollable: scroll);
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(find.textContaining('Сохранено пакетов: 1'), findsOneWidget);

    // A successful run resets BOTH permissions; nothing is sent again just
    // because the result arrived or the user reopened this page.
    if (find.byKey(const Key('whole-gameplay-batch-run')).evaluate().isNotEmpty) {
      expect(tester.widget<FilledButton>(run).onPressed, isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(sent, 1);
    final checkpoint = await memory.read(index.sourceFingerprint);
    expect(checkpoint, isNotNull);
    expect(checkpoint, isNot(contains(index.chunks.first.text)));
    final finished = find.byKey(
        const Key('whole-gameplay-batch-finished'));
    await tester.scrollUntilVisible(finished, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(finished, findsOneWidget);
    final auditResult = find.byKey(
        const Key('whole-gameplay-batch-audit-ok'));
    await tester.scrollUntilVisible(auditResult, 110,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(auditResult, findsOneWidget);
  });


  test('cross-batch audit joins item/fact IDs across every source-locked '
      'act, rejecting conflicting names and altered consent', () async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре главы для совместной проверки персонажей',
      author: 'Синтетическая книга',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Путник увидел старый ключ возле '
              'ворот и услышал условие помощи. Он решил подумать. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 4; i++) _proposal(book, i)],
    );
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(manifest.contexts.length, greaterThan(1));
    GameplayCandidate suggestion(
        SourceLockedGameplayContext ctx, String label) {
      final choice = ctx.choices.first;
      return GameplayCandidate(
        kind: 'fact', id: 'remembered_promise',
        label: label, op: 'learn_fact',
        sceneId: choice.sceneId, choiceId: choice.choiceId,
        sourceEventId: choice.sourceEventId,
        uncertainty: 'Знание героя является только игровой гипотезой.',
      );
    }
    final proposals = [
      for (final ctx in manifest.contexts)
        GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: [suggestion(ctx, 'Помнит об условии')],
        ),
    ];
    const auditor = GameplayCandidateReachabilityAuditor();
    final whole = auditor.auditAcrossBatches(
      plan: draft.plan, manifest: manifest, drafts: proposals,
    );
    expect(whole.issues, isEmpty);
    expect(whole.checkedCandidateOperations, manifest.totalBatches);
    expect(whole.reachedEndingIds.length, greaterThanOrEqualTo(2));
    expect(whole.verifiesLiteraryCanon, false);
    expect(whole.verifiesLiteraryOwnership, false);
    expect(whole.mayAutomaticallyChangeBookworld, false);

    await expectLater(() => auditor.auditAcrossBatches(
      plan: draft.plan, manifest: manifest,
      drafts: proposals.take(1).toList(),
    ), throwsFormatException);
    final second = manifest.contexts[1];
    final conflicting = [
      proposals.first,
      GameplayCandidateDraft(
        sourceFingerprint: second.sourceFingerprint,
        approvalDigest: second.approvalDigest,
        candidates: [suggestion(second, 'Другое непроверенное знание')],
      ),
      ...proposals.skip(2),
    ];
    expect(() => auditor.auditAcrossBatches(
      plan: draft.plan, manifest: manifest, drafts: conflicting,
    ), throwsFormatException);
    final forgery = [
      proposals.first,
      GameplayCandidateDraft(
        sourceFingerprint: second.sourceFingerprint,
        approvalDigest: 'f' * 64, candidates: proposals[1].candidates,
      ),
      ...proposals.skip(2),
    ];
    expect(() => auditor.auditAcrossBatches(
      plan: draft.plan, manifest: manifest, drafts: forgery,
    ), throwsFormatException);
  });

  test('cross-batch route audit finds spend without prior pickup '
      'even when both isolated proposals are source-bound', () async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре части: ключ и отказ',
      author: 'Синтетический источник',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Путник нашёл ключ около ворот '
              'и задумался о предложении помощника. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 4; i++) _proposal(book, i)],
    );
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(manifest.totalBatches, greaterThan(1));
    GameplayCandidate item(SourceLockedGameplayContext ctx, String op) {
      final choices = ctx.choices.where((anchor) =>
        ctx.excerpts.any((event) =>
          event.id == anchor.sourceEventId &&
          event.source.quote.toLowerCase().contains('ключ'))).toList();
      expect(choices, isNotEmpty);
      final a = choices.first;
      return GameplayCandidate(
        kind: 'item', id: 'old_key', label: 'ключ', op: op,
        sceneId: a.sceneId, choiceId: a.choiceId,
        sourceEventId: a.sourceEventId,
        uncertainty: 'В исходной книге упоминание не доказывает владение.',
      );
    }
    final data = [
      for (var n = 0; n < manifest.totalBatches; n++)
        GameplayCandidateDraft(
          sourceFingerprint: manifest.contexts[n].sourceFingerprint,
          approvalDigest: manifest.contexts[n].approvalDigest,
          candidates: [
            if (n == 0) item(manifest.contexts[n], 'grant_item'),
            if (n == 1) item(manifest.contexts[n], 'consume_item'),
          ],
        ),
    ];
    final report = const GameplayCandidateReachabilityAuditor()
        .auditAcrossBatches(
      plan: draft.plan, manifest: manifest, drafts: data,
    );
    expect(report.issues.map((i) => i.code),
        contains('CONSUME_UNOWNED'));
    final failure = report.issues.firstWhere(
        (issue) => issue.code == 'CONSUME_UNOWNED');
    expect(failure.pathChoiceIds, isNotEmpty);
    expect(report.mayAutomaticallyChangeBookworld, false);
  });


  test('approved effects from DIFFERENT source batches compile into one '
      'new private BookWorld v3 with real item and fact, not canon',
      () async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре части о ключе',
      author: 'Синтетическое произведение',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Путник нашёл ключ возле ворот, '
              'услышал правило и задумался о будущем. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 4; i++) _proposal(book, i)],
    );
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(manifest.totalBatches, greaterThan(1));
    GameplayCandidate candidate(SourceLockedGameplayContext ctx, bool item) {
      final choice = ctx.choices.first;
      return GameplayCandidate(
        kind: item ? 'item' : 'fact',
        id: item ? 'book_key' : 'knows_promise',
        label: item ? 'ключ' : 'знает обещание',
        op: item ? 'grant_item' : 'learn_fact',
        sceneId: choice.sceneId, choiceId: choice.choiceId,
        sourceEventId: choice.sourceEventId,
        uncertainty: 'Игровая гипотеза, отдельного канона не проверяли.',
      );
    }
    final last = manifest.totalBatches - 1;
    final selected = <GameplayCandidate>[];
    final proposals = [
      for (var i = 0; i < manifest.totalBatches; i++)
        GameplayCandidateDraft(
          sourceFingerprint: manifest.contexts[i].sourceFingerprint,
          approvalDigest: manifest.contexts[i].approvalDigest,
          candidates: [
            if (i == 0 || i == last)
              candidate(manifest.contexts[i], i == 0),
          ],
        ),
    ];
    selected.add(proposals.first.candidates.single);
    selected.add(proposals.last.candidates.single);
    final notes = {
      for (final effect in selected)
        ReviewedGameplayCompiler.signature(effect):
          'Пользователь разрешил только частный вымышленный эффект, не канон.',
    };
    final base = await MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: map, draft: draft,
      sourceEventIdsReviewedByUser: {
        for (final part in draft.parts)
          ...[part.setupEventId, part.outcomeEventId],
      },
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    final approved = ReviewedGameplayCompiler.previewAcrossBatches(
      currentRichBookworld: base.archive,
      index: index, book: book, plan: draft.plan,
      manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: notes,
    );
    expect(approved.verifiedRoutes, 2);
    expect(approved.literaryCanonVerified, false);
    expect((approved.shownReview['effects'] as List), hasLength(2));
    expect(approved.shownReview['source_payload_digest'],
        manifest.approvalDigest);

    await expectLater(ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved, currentRichBookworld: base.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: false,
      approvedReviewDigest: approved.approvalDigest,
    ), throwsFormatException);
    await expectLater(ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved, currentRichBookworld: base.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: 'not_the_review',
    ), throwsFormatException);
    final archive = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved, currentRichBookworld: base.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: approved.approvalDigest,
    );
    final imported = const RichPrivateBookworldImporter().inspect(archive);
    expect(imported.sourceFingerprint, index.sourceFingerprint);
    expect(imported.bookworldId, isNot(base.bookworldId));
    expect(imported.presentation['item_names'],
        containsPair('book_key', 'ключ'));
    expect(imported.presentation['fact_names'],
        containsPair('knows_promise', 'знает обещание'));
    expect(imported.canDistributePublicly, false);
    expect(imported.requiresNetwork, false);

    expect(() => ReviewedGameplayCompiler.previewAcrossBatches(
      currentRichBookworld: archive,
      index: index, book: book, plan: draft.plan,
      manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: notes,
    ), throwsFormatException);

    final folder = await Directory.systemTemp.createTemp(
        'ai_story_multi_batch_author_');
    try {
      final store = BookworldCampaignStore.openPrivateDirectory(folder.path);
      try {
        final installed = store.installBookworld(archive);
        final campaign = store.createCampaign(installed.archiveHash);
        expect(store.loadCampaign(campaign).metadata.revision, 0);
        expect(store.installedWorlds(), hasLength(1));
      } finally {
        store.close();
      }
    } finally {
      await folder.delete(recursive: true);
    }

    // Distinct, book-bound notes are mandatory; a fake or missing human
    // approval cannot sneak into an otherwise complete batch manifest.
    expect(() => ReviewedGameplayCompiler.previewAcrossBatches(
      currentRichBookworld: base.archive,
      index: index, book: book, plan: draft.plan,
      manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: {
        ReviewedGameplayCompiler.signature(selected.first):
          'Only one accepted effect, not all proposals.',
        'made_up_choice/fake_op/fake_id/missing': 'Фальшивая подпись.',
      },
    ), throwsFormatException);
  });


  testWidgets('completed whole-book GLM drafts can be selected and '
      'returned with human notes without a second paid request',
      (tester) async {
    final index = _index();
    final book = await _analyze(index);
    final plan = _draft(index, book).draft.plan;
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: plan,
      maxNewRequestsPerRun: 2,
    );
    final memory = MemorySourceAnalysisCheckpointRepository();
    var calls = 0;
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, cancellation) async {
        calls++;
        final choice = ctx.choices.first;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: [
            GameplayCandidate(
              kind: 'fact', id: 'remembered_offer',
              label: 'знает о предложении',
              op: 'learn_fact', sceneId: choice.sceneId,
              choiceId: choice.choiceId,
              sourceEventId: choice.sourceEventId,
              uncertainty: 'Знание является только игровой гипотезой.',
            ),
          ],
        );
      },
    );
    final first = await service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(first.allProposalsCollected, true);
    expect(calls, manifest.totalBatches);

    SelectedWholePlanGameplayCandidates? returned;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(
          onPressed: () async {
            returned = await Navigator.of(context)
                .push<SelectedWholePlanGameplayCandidates>(
              MaterialPageRoute(builder: (_) => WholePlanGameplayBatchPage(
                index: index, book: book, plan: plan, service: service,
              )),
            );
          },
          child: const Text('Открыть пакетный редактор'),
        )),
      ),
    ));
    await tester.tap(find.text('Открыть пакетный редактор'));
    await tester.pumpAndSettle();
    expect(calls, manifest.totalBatches);
    final scroll = find.byType(Scrollable).first;
    final item = find.byKey(const Key('whole-gameplay-select-0'));
    await tester.scrollUntilVisible(item, 160, scrollable: scroll);
    await tester.tap(item);
    await tester.pumpAndSettle();
    final note = find.byKey(const Key('whole-gameplay-note-0'));
    await tester.scrollUntilVisible(note, 120, scrollable: scroll);
    await tester.enterText(note,
        'Читатель разрешает игровое знание, но не подтверждает канон.');
    await tester.pumpAndSettle();
    final confirmation = find.byKey(
        const Key('whole-gameplay-private-fiction'));
    await tester.scrollUntilVisible(confirmation, 120, scrollable: scroll);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    final button = find.byKey(
        const Key('whole-gameplay-return-selection'));
    await tester.scrollUntilVisible(button, 120, scrollable: scroll);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(returned, isNotNull);
    expect(returned!.drafts, hasLength(manifest.totalBatches));
    expect(returned!.selectedUserReviewNotes, hasLength(1));
    expect(returned!.manifest.approvalDigest, manifest.approvalDigest);
    expect(calls, manifest.totalBatches);
    expect(find.text('Открыть пакетный редактор'), findsOneWidget);
  });


  testWidgets('conflicting model labels across GLM windows show warning '
      'but allow a reviewed conflict-free subset', (tester) async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Четыре главы: спорные знания',
      author: 'Тест без настоящей книги',
      chapters: [
        for (var n = 1; n <= 4; n++)
          List.filled(5, 'Часть $n. Путник увидел старый ключ '
              'около ворот и задумался об обещании. ').join(' '),
      ],
    ));
    final book = await _analyze(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [for (var i = 0; i < 4; i++) _proposal(book, i)],
    );
    final manifest = WholePlanGameplayBatchManifest.fromPlan(
      index: index, book: book, plan: draft.plan,
      maxNewRequestsPerRun: 2,
    );
    expect(manifest.totalBatches, 2);
    final memory = MemorySourceAnalysisCheckpointRepository();
    var requests = 0;
    final service = WholePlanGameplayBatchService(
      repository: memory,
      previewOverride: (ctx, cancel) async {
        requests++;
        final a = ctx.choices.first;
        return GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: [
            GameplayCandidate(
              kind: 'fact', id: 'promise_note',
              label: requests == 1 ? 'помнит обещание' : 'знает иной договор',
              op: 'learn_fact', sceneId: a.sceneId,
              choiceId: a.choiceId,
              sourceEventId: a.sourceEventId,
              uncertainty: 'Это только непроверенное игровое предположение.',
            ),
          ],
        );
      },
    );
    final complete = await service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(complete.allProposalsCollected, true);
    expect(requests, 2);
    SelectedWholePlanGameplayCandidates? picked;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (ctx) => ElevatedButton(
        onPressed: () async {
          picked = await Navigator.of(ctx)
              .push<SelectedWholePlanGameplayCandidates>(
            MaterialPageRoute(builder: (_) => WholePlanGameplayBatchPage(
              index: index, book: book, plan: draft.plan, service: service,
            )),
          );
        },
        child: const Text('Проверить спорные предложения'),
      )),
    )));
    await tester.tap(find.text('Проверить спорные предложения'));
    await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    final warning = find.byKey(
        const Key('whole-gameplay-batch-audit-warning'));
    await tester.scrollUntilVisible(warning, 130, scrollable: scroll);
    await tester.pumpAndSettle();
    expect(warning, findsOneWidget);
    final first = find.byKey(const Key('whole-gameplay-select-0'));
    await tester.scrollUntilVisible(first, 130, scrollable: scroll);
    await tester.tap(first);
    await tester.pumpAndSettle();
    final note = find.byKey(const Key('whole-gameplay-note-0'));
    await tester.scrollUntilVisible(note, 130, scrollable: scroll);
    await tester.enterText(note,
        'Разрешаю только игровое знание в частной адаптации, не канон.');
    await tester.pumpAndSettle();
    final privateFiction = find.byKey(
        const Key('whole-gameplay-private-fiction'));
    await tester.scrollUntilVisible(privateFiction, 130, scrollable: scroll);
    await tester.tap(privateFiction);
    await tester.pumpAndSettle();
    final save = find.byKey(
        const Key('whole-gameplay-return-selection'));
    await tester.scrollUntilVisible(save, 130, scrollable: scroll);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.selectedUserReviewNotes, hasLength(1));
    expect(requests, 2);
    expect(find.text('Проверить спорные предложения'), findsOneWidget);
  });

}
