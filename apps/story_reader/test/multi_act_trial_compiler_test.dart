import 'dart:io';
import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/cross_act_consequence_gate.dart';
import 'package:ai_story_reader/cross_act_source_evidence_packet.dart';
import 'package:ai_story_reader/multi_act_trial_compiler.dart';
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


  testWidgets('multi-act item proposal UI sends no request without consent; '
      'extra cross-act rule disables incompatible choice preparation',
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
    final itemButton = find.byKey(
        const Key('multiact-trial-optional-gameplay'));
    expect(itemButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(itemButton).onPressed, isNull);

    final quotes = find.byKey(
        const Key('multiact-trial-source-reviewed'));
    await tester.ensureVisible(quotes);
    await tester.tap(quotes);
    await tester.pumpAndSettle();
    final fiction = find.byKey(
        const Key('multiact-trial-private-fiction'));
    await tester.ensureVisible(fiction);
    await tester.tap(fiction);
    await tester.pumpAndSettle();

    final crossAct = find.byKey(
        const Key('multiact-trial-consequence'));
    await tester.ensureVisible(crossAct);
    await tester.tap(crossAct);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(itemButton).onPressed, isNull);

    await tester.ensureVisible(crossAct);
    await tester.tap(crossAct);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(itemButton).onPressed, isNotNull);
    await tester.ensureVisible(itemButton);
    await tester.tap(itemButton);
    await tester.pumpAndSettle();
    expect(find.text('Предметы и знания из книги'), findsOneWidget);
    final request = find.byKey(
        const Key('gameplay-source-request'));
    expect(request, findsOneWidget);
    expect(tester.widget<FilledButton>(request).onPressed, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('multiact-trial-start')), findsOneWidget);
    expect(find.byKey(const Key('multiact-trial-clear-gameplay')), findsNothing);
  });

}
