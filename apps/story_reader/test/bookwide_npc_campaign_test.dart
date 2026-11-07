import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/multi_act_trial_page.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_trial_compiler.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/whole_book_npc_campaign_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

class _Fixture {
  _Fixture(this.source, this.base, this.roles, this.candidates);
  final WholeBookNpcSourcePlan source;
  final StoryPlanTrialCompilation base;
  final List<ReviewedHeroRole> roles;
  final List<BookwideNpcConversationCandidate> candidates;

  List<NpcCampaignDialogueDraft> get drafts => [
    for (var i = 0; i < candidates.length; i++)
      NpcCampaignDialogueDraft(
        candidateId: candidates[i].id,
        playerLine: 'Обсудим наш игровой путь через главу ${i + 1}.',
        npcLine: 'Я помню нашу игровую встречу в главе ${i + 1}.',
        requiresCandidateIds: [if (i > 0) candidates[i - 1].id],
      ),
  ];

  ReviewedBookwideNpcCampaign review() => BookwideNpcCampaignAuthoring.review(
    source: source, verifiedBaseArchive: base.archive,
    currentReviewedRoles: roles, selectedDrafts: drafts,
  );
}

StoryDilemmaProposal _proposal(NarrativeBookModel book, int chapter) {
  final events = book.events.where((e) => e.source.chapterIndex == chapter).toList();
  return StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: events.first.id, outcomeEventId: events.last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Принять предложение или продолжить путь самостоятельно',
    acceptIntent: 'Принять предложение', refuseIntent: 'Отказаться от предложения',
    followupGoal: 'Исполнить выбранное условие',
    finishOriginalIntent: 'Исполнить обещание',
    originalEnding: 'Завершить исходный путь',
    alternativeSearchGoal: 'Найти другой путь',
    searchIntent: 'Исследовать другую дорогу',
    alternativeDiscovery: 'Найдена игровая альтернатива',
    useDiscoveryIntent: 'Использовать найденный путь',
    alternativeEnding: 'Завершить альтернативный путь',
  );
}

Future<_Fixture> _prepare() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Три персонажа — синтетическая причинная приёмка',
    author: 'Локальный тест, не оригинальная книга',
    chapters: [
      for (final name in names)
        List.filled(7, 'Начало пути. ').join() +
            '$name встретил путника у ворот и показал дорогу. ' +
            List.filled(12, 'Путник продолжил путешествие. ').join(),
    ],
  ));
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analyzer = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      // Source validation permits at most 180 UTF-16 units per quote.
      // Distinct overlapping 150-unit excerpts keep the reviewed name in
      // both encounters without bypassing any production source checks.
      final candidates = [
        for (var i = 0; i < 4; i++)
          SemanticCandidate.propose(source, chunk,
            category: SemanticCategory.event,
            startUtf16: chunk.startUtf16 + i * 10,
            endUtf16: chunk.startUtf16 + 150 + i * 10,
            label: 'Проверяемый отрывок',
            uncertainty: 'Игровая интерпретация не подтверждает канон.'),
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
        rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final analyzed = await analyzer.analyze(
    index: index, approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 64,
  );
  expect(analyzed.complete, true);
  final book = NarrativeBookModel.fromExisting(
      index: index, outline: ZaiWholeBookEventOutline.build(analyzed));
  expect(book.events.length, 12);
  final map = BookwideActPlanner.build(index: index, book: book);
  final draft = BookwideStoryPlanComposer.compose(
    index: index, book: book, bookMap: map,
    actProposals: [for (var i = 0; i < 3; i++) _proposal(book, i)],
  );
  final source = WholeBookNpcSourcePlan.fromBook(
      index: index, book: book, bookMap: map, draft: draft);
  expect(source.coverage.referencedEvents, 12);
  expect(source.coverage.allDetectedEventsReferenced, true);
  var graph = SourceEvidenceGraph.empty(index);
  final mentions = <SourceEvidence>[];
  for (var chapter = 0; chapter < names.length; chapter++) {
    final event = book.events.firstWhere((e) =>
        e.source.chapterIndex == chapter && source.extraEventIds.contains(e.id));
    final offset = event.source.quote.indexOf(names[chapter]);
    expect(offset, greaterThanOrEqualTo(0));
    mentions.add(SourceEvidence.propose(index,
      chunkId: event.source.chunkId, kind: EvidenceKind.character,
      startUtf16: event.source.startUtf16 + offset,
      endUtf16: event.source.startUtf16 + offset + names[chapter].length,
    ));
  }
  graph = graph.addAll(index, mentions);
  for (final mention in mentions) {
    graph = graph.review(index, mention.id, EvidenceStatus.confirmed);
  }
  final relations = SourceRelationReviewSession.create(index, graph);
  final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
  final editorial = SemanticEditorialReviewSession.create(index, catalog);
  final dossiers = SourceCharacterDossierIndex.build(
      index, graph, relations, catalog, editorial);
  var notebook = NpcEditorialNotebook.empty(index);
  for (final name in names) {
    notebook = notebook.putProfile(NpcEditorialNotebook.freshProfile(
        dossiers.dossiers.singleWhere((d) => d.labels.contains(name))));
  }
  final roles = ReviewedHeroRole.fromReviewedSources(
    index: index, dossiers: dossiers, graph: graph,
    catalog: catalog, editorial: editorial, notebook: notebook,
  );
  final candidates = BookwideNpcCampaignAuthoring.discover(
      source: source, currentReviewedRoles: roles);
  expect(candidates.length, 3);
  expect(candidates.map((c) => c.role.characterId).toSet().length, 3);
  final base = await source.compileBase(
    approvedPlanDigest: source.planDigest,
    allShownQuotesReviewed: true, privateFictionConfirmed: true,
  );
  return _Fixture(source, base, roles, candidates);
}

class _UnusedGateway implements WorldLibraryGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No installation is authorized while opening the editor');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUpAll(() async { fixture = await _prepare(); });

  test('all source events and three independent NPCs form one causally '
      'connected offline campaign, with isolated knowledge and SQLite replay',
      () async {
    final approval = fixture.review();
    expect(approval.actorCount, 3);
    expect(approval.episodeCount, 3);
    final built = await BookwideNpcCampaignAuthoring.compile(
      source: fixture.source, approval: approval,
      freshReviewedRoles: fixture.roles,
      approvedDigest: approval.approvalDigest,
      explicitlyConfirmedPrivateFiction: true,
    );
    expect(built.sourceEventsRepresented, 12);
    expect(built.requiresNetworkToPlay, false);
    expect(built.canonicalAdaptationVerified, false);
    final game = const RichPrivateBookworldImporter().inspect(built.archive);
    expect(game.blueprint.actors.length, 4);
    expect(game.blueprint.facts.length, 3);
    expect(game.npcSocialRulebook!.rules.length, 3);
    final candidates = fixture.candidates;
    final first = candidates.first;
    String meet(String id) => ReviewedNpcCampaignBookworldWriter.meetChoiceId(id);
    String reply(String id) => ReviewedNpcCampaignBookworldWriter.replyChoiceId(id);
    StoryWorld world() => StoryWorld(game.blueprint,
        socialRulebook: game.npcSocialRulebook);
    void act(StoryWorld story, String id) {
      expect(story.apply(actionId: 'step_${story.state.revision}',
          choiceId: id, expectedRevision: story.state.revision).applied,
          true, reason: id);
    }
    final skipped = world();
    act(skipped, first.firstExitChoiceId);
    expect(skipped.apply(actionId: 'unearned_reply',
        choiceId: reply(first.id)).applied, false);
    final rawTurns = RichSceneDialogue.verify(
        (game.presentation['scene_dialogues'] as Map)[first.responseSceneId],
        game.blueprint.scenes[first.responseSceneId]!.text);
    final turnReview = (game.presentation['scene_dialogue_knowledge'] as Map)
        [first.responseSceneId] as List;
    final hidden = RichNpcDialogueKnowledge.redact(
      rawTurns, turnReview, skipped.state.knowledge,
      social: NpcSocialLedger.inspect(skipped, game.npcSocialRulebook!),
      committedEvents: skipped.events, sceneId: first.responseSceneId,
    );
    expect(hidden.any((t) => t.text == fixture.drafts.first.npcLine), false);
    expect(hidden.any((t) => t.text == RichNpcDialogueKnowledge.unavailableLine), true);
    act(skipped, first.responseExitChoiceId);
    act(skipped, 'act_1_accept_offer');
    act(skipped, 'act_1_honor_condition');
    act(skipped, 'act_1_continue_original');
    expect(skipped.state.sceneId, candidates[1].firstSceneId);
    expect(skipped.apply(actionId: 'missing_first_npc',
        choiceId: meet(candidates[1].id)).applied, false);

    final successful = world();
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      act(successful, meet(candidate.id));
      expect(successful.state.knowledge[candidate.role.characterId],
          {ReviewedNpcCampaignBookworldWriter.factId(candidate.id)});
      expect(successful.state.knowledge['player'], isEmpty);
      act(successful, reply(candidate.id));
      act(successful, 'act_${i + 1}_accept_offer');
      act(successful, 'act_${i + 1}_honor_condition');
      if (i < candidates.length - 1) {
        act(successful, 'act_${i + 1}_continue_original');
      }
    }
    expect(game.blueprint.scenes[successful.state.sceneId]!.terminal, true);
    final replayed = StoryWorld.replay(game.blueprint,
      successful.events.map((e) => e.toJson()),
      expectedSequence: successful.state.revision,
      expectedStateHash: successful.state.stateHash,
      socialRulebook: game.npcSocialRulebook,
    );
    expect(replayed.state.stateHash, successful.state.stateHash);
    for (final candidate in candidates) {
      final social = NpcSocialLedger.inspect(replayed, game.npcSocialRulebook!);
      expect(social.hasMemory(candidate.role.characterId,
          ReviewedNpcCampaignBookworldWriter.memoryId(candidate.id)), true);
      expect(social.directedScore(candidate.role.characterId, 'player'), 1);
    }

    final dir = await Directory.systemTemp.createTemp('three_npc_campaign_');
    late String id;
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        final installed = db.installBookworld(built.archive);
        id = db.createCampaign(installed.archiveHash);
        expect(db.commitChoice(id, actionId: 'sqlite_meet',
          choiceId: meet(first.id), expectedRevision: 0).applied, true);
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        final saved = db.loadCampaign(id);
        expect(saved.metadata.revision, 1);
        expect(saved.coordinator.state.knowledge[first.role.characterId],
            {ReviewedNpcCampaignBookworldWriter.factId(first.id)});
        expect(saved.coordinator.state.knowledge[candidates[1].role.characterId], isEmpty);
        expect(db.commitChoice(id, actionId: 'sqlite_reply',
          choiceId: reply(first.id), expectedRevision: 1).applied, true);
        expect(db.exportPortable(id), isNotEmpty);
      } finally { db.close(); }
    } finally { await dir.delete(recursive: true); }
  });

  test('approval binds every actor, line, dependency and exact base bytes', () async {
    final accepted = fixture.review();
    final reverse = BookwideNpcCampaignAuthoring.review(
      source: fixture.source, verifiedBaseArchive: fixture.base.archive,
      currentReviewedRoles: fixture.roles.reversed.toList(),
      selectedDrafts: fixture.drafts.reversed.toList(),
    );
    expect(reverse.approvalDigest, accepted.approvalDigest);
    await expectLater(BookwideNpcCampaignAuthoring.compile(
      source: fixture.source, approval: accepted, freshReviewedRoles: const [],
      approvedDigest: accepted.approvalDigest,
      explicitlyConfirmedPrivateFiction: true,
    ), throwsFormatException);
    await expectLater(BookwideNpcCampaignAuthoring.compile(
      source: fixture.source, approval: accepted, freshReviewedRoles: fixture.roles,
      approvedDigest: 'not-the-shown-review',
      explicitlyConfirmedPrivateFiction: true,
    ), throwsFormatException);
    await expectLater(BookwideNpcCampaignAuthoring.compile(
      source: fixture.source, approval: accepted, freshReviewedRoles: fixture.roles,
      approvedDigest: accepted.approvalDigest,
      explicitlyConfirmedPrivateFiction: false,
    ), throwsFormatException);
    expect(() => fixture.source.compileBase(
      approvedPlanDigest: fixture.source.planDigest,
      allShownQuotesReviewed: false, privateFictionConfirmed: true,
    ), throwsFormatException);
  });

  test('rehashed forged citations, unknown fields and circular dependencies '
      'still fail before installing any campaign', () {
    final accepted = fixture.review();
    void refused(void Function(Map<String, dynamic>) corrupt) {
      final raw = accepted.shownReview;
      corrupt(raw);
      final changed = jsonEncode(raw);
      expect(() => const ReviewedNpcCampaignBookworldWriter().build(
        verifiedBaseArchive: fixture.base.archive,
        sourceIndex: Map<String, dynamic>.from(fixture.source.index.toJson()),
        reviewJson: changed,
        approvedDigest: ReviewedNpcCampaignBookworldWriter.digest(changed),
        userConfirmed: true,
      ), throwsFormatException);
    }
    refused((raw) => raw['unexpected_auto_approval'] = true);
    refused((raw) => (raw['episodes'] as List).first['first_quote_sha256'] =
        List.filled(64, 'f').join());
    refused((raw) {
      final rows = raw['episodes'] as List;
      rows[0]['requires_episodes'] = [rows[1]['id']];
      rows[1]['requires_episodes'] = [rows[0]['id']];
    });
    refused((raw) => (raw['episodes'] as List).last['actor_id'] = 'npc_fake');
  });

  testWidgets('campaign-wide editor is reachable without an API request or '
      'installation, and preserves the existing advanced editor', (tester) async {
    final source = fixture.source;
    await tester.pumpWidget(MaterialApp(home: MultiActTrialPage(
      index: source.index, book: source.book, bookMap: source.bookMap,
      draft: source.draft, gateway: _UnusedGateway(),
    )));
    expect(find.byKey(const Key('multiact-open-whole-npc-campaign')), findsOneWidget);
    await tester.tap(find.byKey(const Key('multiact-open-whole-npc-campaign')));
    await tester.pumpAndSettle();
    expect(find.byType(WholeBookNpcCampaignPage), findsOneWidget);
    expect(find.byKey(const Key('whole-npc-source-quotes')), findsOneWidget);
    final prepare = find.byKey(const Key('whole-npc-prepare'));
    await tester.scrollUntilVisible(prepare, 140,
        scrollable: find.byType(Scrollable).last);
    expect(tester.widget<OutlinedButton>(prepare).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
