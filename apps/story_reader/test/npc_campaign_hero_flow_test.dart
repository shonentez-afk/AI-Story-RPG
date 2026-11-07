import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/npc_campaign_hero_selection.dart';
import 'package:ai_story_reader/npc_campaign_writing_session.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/reviewed_hero_source_action.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/whole_book_npc_campaign_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_npc_campaign_writing.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

class _Fixture {
  _Fixture(this.free, this.roles);
  final WholeBookNpcSourcePlan free;
  final List<ReviewedHeroRole> roles;
  ReviewedHeroRole get hero => roles.singleWhere((r) => r.displayName == 'Артем');
  WholeBookNpcSourcePlan select(ReviewedHeroRole? role, {bool actions = false}) =>
      NpcCampaignHeroSelection(role, actions, 0).bind(free);
  List<BookwideNpcConversationCandidate> candidates(WholeBookNpcSourcePlan source) =>
      BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: roles);
  NpcWritingCatalog catalog(WholeBookNpcSourcePlan source) =>
      NpcWritingCatalog(source: source, candidates: candidates(source));
}

Future<_Fixture> _fixture() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Герой, две встречи и сохранённая память', author: 'Синтетическая приёмка',
    chapters: [for (final name in names)
      List.filled(7, 'Начало пути. ').join() + '$name встретил путника у ворот и показал дорогу. ' +
          List.filled(12, 'Путник продолжил путешествие. ').join()],
  ));
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analyzed = await ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final rows = [for (var i = 0; i < 4; i++) SemanticCandidate.propose(source, chunk,
        category: SemanticCategory.event, startUtf16: chunk.startUtf16 + i * 10,
        endUtf16: chunk.startUtf16 + 150 + i * 10,
        label: 'Проверяемое событие', uncertainty: 'Смысл требует проверки.')];
      return ZaiSemanticPreviewResult(batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: source.sourceFingerprint,
        chunkIds: [for (final c in window.chunks) c.id], candidates: rows),
        totalSuggestions: rows.length, rejectedCount: 0, rejectedNonRussian: 0);
    },
  ).analyze(index: index, approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true, maxWindowsPerRun: 64);
  final book = NarrativeBookModel.fromExisting(index: index, outline: ZaiWholeBookEventOutline.build(analyzed));
  final map = BookwideActPlanner.build(index: index, book: book);
  final proposals = [for (var i = 0; i < 3; i++) StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: book.events.where((e) => e.source.chapterIndex == i).first.id,
    outcomeEventId: book.events.where((e) => e.source.chapterIndex == i).last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Принять предложение или продолжить путь самому',
    acceptIntent: 'Принять предложение', refuseIntent: 'Отказаться',
    followupGoal: 'Выполнить выбранное условие', finishOriginalIntent: 'Исполнить обещание',
    originalEnding: 'Завершить исходный путь', alternativeSearchGoal: 'Найти другой путь',
    searchIntent: 'Исследовать дорогу', alternativeDiscovery: 'Найдена другая дорога',
    useDiscoveryIntent: 'Выбрать найденный путь', alternativeEnding: 'Завершить иной путь')];
  final draft = BookwideStoryPlanComposer.compose(index: index, book: book, bookMap: map, actProposals: proposals);
  final free = WholeBookNpcSourcePlan.fromBook(index: index, book: book, bookMap: map, draft: draft);
  var graph = SourceEvidenceGraph.empty(index);
  for (var i = 0; i < names.length; i++) {
    final event = book.events.firstWhere((e) => e.source.chapterIndex == i && free.extraEventIds.contains(e.id));
    final offset = event.source.quote.indexOf(names[i]);
    expect(offset, greaterThanOrEqualTo(0));
    final mention = SourceEvidence.propose(index, chunkId: event.source.chunkId,
      kind: EvidenceKind.character, startUtf16: event.source.startUtf16 + offset,
      endUtf16: event.source.startUtf16 + offset + names[i].length);
    graph = graph.addAll(index, [mention]).review(index, mention.id, EvidenceStatus.confirmed);
  }
  final relations = SourceRelationReviewSession.create(index, graph);
  final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
  final editorial = SemanticEditorialReviewSession.create(index, catalog);
  final dossiers = SourceCharacterDossierIndex.build(index, graph, relations, catalog, editorial);
  var notebook = NpcEditorialNotebook.empty(index);
  for (final name in names) { notebook = notebook.putProfile(NpcEditorialNotebook.freshProfile(
      dossiers.dossiers.singleWhere((d) => d.labels.contains(name)))); }
  final roles = ReviewedHeroRole.fromReviewedSources(index: index, dossiers: dossiers,
      graph: graph, catalog: catalog, editorial: editorial, notebook: notebook);
  return _Fixture(free, roles);
}

class _Preferences extends AiCloudPreferences {
  @override Future<bool> isEnabled() async => true;
}
class _Vault implements AiApiKeyVault {
  @override Future<String?> read() async => 'fake-unit-key';
  @override Future<void> write(String value) async {}
  @override Future<void> delete() async {}
  @override Future<bool> hasKey() async => true;
}
class _Transport implements AiHttpTransport {
  final sent = <Map<String, dynamic>>[];
  @override Future<AiHttpResponse> send({required Uri uri,
      required Map<String, String> headers, required String body}) async {
    final outer = jsonDecode(body) as Map;
    final batch = jsonDecode((outer['messages'] as List).last['content'] as String) as Map<String, dynamic>;
    sent.add(batch);
    return AiHttpResponse(200, jsonEncode({'choices': [{'finish_reason': 'stop', 'message': {
      'content': jsonEncode({'batch_id': batch['batch_id'],
        'proposals': [for (final row in batch['conversations'] as List) {
          'candidate_id': row['candidate_id'], 'actor_id': row['actor_id'],
          'player_line': 'Я хочу поговорить о дороге у ворот.',
          'npc_line': 'Я помню нашу встречу у ворот и дорогу.',
          'uncertainty': 'Это частная игровая версия, проверьте смысл.',
        }], 'skipped': <Object>[]}),
    }}]}));
  }
}
class _Roles extends ReviewedHeroRoleCatalog {
  _Roles(this.roles);
  final List<ReviewedHeroRole> roles;
  @override Future<List<ReviewedHeroRole>> load(BookSourceIndex index) async => roles;
}
class _UnusedGateway implements WorldLibraryGateway {
  int calls = 0;
  @override dynamic noSuchMethod(Invocation invocation) {
    calls++; throw StateError('Opening or changing hero must not install a game');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUpAll(() async { f = await _fixture(); });

  test('selected hero -> shown AI role -> two distinct NPCs -> source action, '
      'memory, terminal replay and SQLite reopen in ONE offline game', () async {
    final folder = await Directory.systemTemp.createTemp('hero_npc_e2e_');
    try {
      final repo = FileSourceAnalysisCheckpointRepository(rootDirectory: () async => folder);
      final choices = NpcCampaignHeroStore(repository: repo);
      await choices.save(f.free, currentRoles: f.roles, role: f.hero,
          sourceAction: true, expectedRevision: 0);
      final restored = await NpcCampaignHeroStore(repository: repo).load(f.free, f.roles);
      expect(restored.cloudConsent, false); expect(restored.installConsent, false);
      final source = restored.bind(f.free);
      final catalog = f.catalog(source);
      expect(catalog.candidates.length, 2);
      expect(catalog.candidates.values.any((c) => c.role.characterId == f.hero.characterId), false);
      final candidates = f.candidates(source);
      final store = NpcWritingStore(repository: repo);
      final empty = await store.save(catalog, expectedRevision: 0, edits: [
        for (var i = 0; i < candidates.length; i++) NpcWritingEdit(id: candidates[i].id,
            dependencies: [if (i > 0) candidates[i - 1].id]),
      ]);
      final request = NpcWritingRequest.prepare(catalog, empty);
      final transport = _Transport();
      final writer = ZaiNpcCampaignWriting(preferences: _Preferences(), vault: _Vault(),
          transport: transport, retryWait: (_) async {});
      await writer.generate(catalog: catalog, store: store, request: request,
          approvedDigest: request.approvalDigest, explicitCloudConsent: true);
      expect(transport.sent.single['player_role'], containsPair('character_id', f.hero.characterId));
      expect(transport.sent.single['player_role'], containsPair('display_name', f.hero.displayName));
      expect(transport.sent.single['player_role'], containsPair('imports_npc_knowledge', false));
      final writings = await NpcWritingStore(repository: repo).load(catalog);
      expect(writings.canInstallDirectly, false);
      final base = await source.compileBase(approvedPlanDigest: source.planDigest,
          approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
      final approval = BookwideNpcCampaignAuthoring.review(source: source,
          verifiedBaseArchive: base.archive, currentReviewedRoles: f.roles,
          selectedDrafts: writings.edits.values.map((e) => e.toDraft()).toList());
      final built = await BookwideNpcCampaignAuthoring.compile(source: source, approval: approval,
          freshReviewedRoles: f.roles, approvedDigest: approval.approvalDigest,
          explicitlyConfirmedPrivateFiction: true);
      final game = const RichPrivateBookworldImporter().inspect(built.archive);
      expect(game.requiresNetwork, false);
      expect(game.presentation['hero'], containsPair('name', f.hero.displayName));
      expect(game.blueprint.actors, isNot(contains(f.hero.characterId)));
      expect(game.blueprint.actors.length, 3);
      expect(game.blueprint.initial.flags[f.hero.playerIdentityFlag], true);
      expect(game.blueprint.initial.knowledge['player'], isEmpty);
      final opportunity = ReviewedHeroSourceAction.find(index: source.index, book: source.book,
          plan: source.plan, role: f.hero)!;
      final observe = '${opportunity.observeSceneId}_hero_observe';
      final recall = '${opportunity.recallSceneId}_hero_recall';
      final skipped = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      expect(skipped.apply(actionId: 'skip_observation', choiceId: opportunity.observeBaseChoiceId).applied, true);
      expect(skipped.apply(actionId: 'unearned_recall', choiceId: recall).applied, false);

      final world = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      final path = <String>[observe, recall, 'act_1_accept_offer', 'act_1_honor_condition', 'act_1_continue_original'];
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        path.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(c.id),
          ReviewedNpcCampaignBookworldWriter.replyChoiceId(c.id),
          'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
        if (i < candidates.length - 1) path.add('act_${i + 2}_continue_original');
      }
      for (var i = 0; i < path.length; i++) {
        expect(world.apply(actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true, reason: path[i]);
        expect(world.state.knowledge['player'], isEmpty);
      }
      expect(game.blueprint.scenes[world.state.sceneId]!.terminal, true);
      final replay = StoryWorld.replay(game.blueprint, world.events.map((e) => e.toJson()),
          expectedSequence: world.state.revision, expectedStateHash: world.state.stateHash,
          socialRulebook: game.npcSocialRulebook);
      expect(replay.state.stateHash, world.state.stateHash);
      for (final c in candidates) {
        expect(world.state.knowledge[c.role.characterId], {ReviewedNpcCampaignBookworldWriter.factId(c.id)});
        expect(NpcSocialLedger.inspect(replay, game.npcSocialRulebook!).hasMemory(
            c.role.characterId, ReviewedNpcCampaignBookworldWriter.memoryId(c.id)), true);
      }
      var db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/campaign');
      late String campaign;
      try {
        final installed = db.installBookworld(built.archive);
        campaign = db.createCampaign(installed.archiveHash);
        expect(db.commitChoice(campaign, actionId: 'observe', choiceId: observe, expectedRevision: 0).applied, true);
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/campaign');
      try {
        final state = db.loadCampaign(campaign).coordinator.state;
        expect(state.flags[f.hero.playerIdentityFlag], true);
        expect(state.flags[ReviewedHeroSourceAction.observedFlag], true);
        expect(state.knowledge['player'], isEmpty);
        for (var i = 1; i < path.length; i++) {
          expect(db.commitChoice(campaign, actionId: 'reopened_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).metadata.revision, path.length);
        expect(db.exportPortable(campaign), isNotEmpty);
      } finally { db.close(); }
    } finally { await folder.delete(recursive: true); }
  });

  test('hero change isolates writings and revokes cloud/base/install review; '
      'self-conversation and revoked hero card fail closed', () async {
    final source = f.select(f.hero);
    final other = f.select(f.roles.singleWhere((r) => r.displayName == 'Мария'));
    expect(source.planDigest, isNot(other.planDigest));
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcWritingStore(repository: repo);
    final freeCatalog = f.catalog(f.free), heroCatalog = f.catalog(source), otherCatalog = f.catalog(other);
    final freeSaved = await store.save(freeCatalog, expectedRevision: 0,
        edits: [NpcWritingEdit(id: freeCatalog.candidates.keys.last, playerLine: 'Ручная реплика свободного героя')]);
    final heroSaved = await store.save(heroCatalog, expectedRevision: 0,
        edits: [for (final id in heroCatalog.candidates.keys) NpcWritingEdit(id: id)]);
    expect((await store.load(otherCatalog)).edits, isEmpty);
    expect((await store.load(freeCatalog)).revision, freeSaved.revision);
    final request = NpcWritingRequest.prepare(heroCatalog, heroSaved);
    expect(() => NpcWritingRequest.prepare(otherCatalog, heroSaved), throwsFormatException);
    final transport = _Transport();
    await expectLater(ZaiNpcCampaignWriting(preferences: _Preferences(), vault: _Vault(),
        transport: transport).generate(catalog: otherCatalog, store: store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true), throwsA(isA<AiSetupException>()));
    expect(transport.sent, isEmpty);
    expect(() => source.compileBase(approvedPlanDigest: source.planDigest,
        allShownQuotesReviewed: true, privateFictionConfirmed: true), throwsFormatException);
    expect(() => BookwideNpcCampaignAuthoring.discover(source: source,
        currentReviewedRoles: f.roles.where((r) => r.characterId != f.hero.characterId).toList()), throwsFormatException);
    expect(() => NpcWritingCatalog(source: source, candidates: f.candidates(f.free)), throwsFormatException);
    final base = await f.free.compileBase(approvedPlanDigest: f.free.planDigest,
        allShownQuotesReviewed: true, privateFictionConfirmed: true);
    final drafts = [for (final c in f.candidates(f.free)) NpcCampaignDialogueDraft(candidateId: c.id,
        playerLine: 'Расскажи о дороге у ворот.', npcLine: 'Я помню эту дорогу и нашу встречу.')];
    final freeApproval = BookwideNpcCampaignAuthoring.review(source: f.free,
        verifiedBaseArchive: base.archive, currentReviewedRoles: f.roles, selectedDrafts: drafts);
    expect(() => BookwideNpcCampaignAuthoring.review(source: source,
        verifiedBaseArchive: base.archive, currentReviewedRoles: f.roles, selectedDrafts: drafts), throwsFormatException);
    await expectLater(BookwideNpcCampaignAuthoring.compile(source: source, approval: freeApproval,
        freshReviewedRoles: f.roles, approvedDigest: freeApproval.approvalDigest,
        explicitlyConfirmedPrivateFiction: true), throwsFormatException);
  });

  test('remembered role is source-bound, revision-checked, non-authorizing and '
      'cannot erase separate drafts on corruption or failed write', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final heroes = NpcCampaignHeroStore(repository: repo);
    final first = await heroes.save(f.free, currentRoles: f.roles, role: f.hero,
        sourceAction: false, expectedRevision: 0);
    final key = NpcCampaignHeroStore.storageKey(f.free);
    final before = await repo.read(key);
    repo.failNextWrite = true;
    await expectLater(heroes.save(f.free, currentRoles: f.roles, role: null,
        sourceAction: false, expectedRevision: first.revision), throwsA(isA<FileSystemException>()));
    expect(await repo.read(key), before);
    await expectLater(heroes.save(f.free, currentRoles: f.roles, role: null,
        sourceAction: false, expectedRevision: 0), throwsFormatException);
    await expectLater(heroes.load(f.free, const []), throwsFormatException);
    expect(await repo.read(key), before);
    final store = NpcWritingStore(repository: repo), catalog = f.catalog(first.bind(f.free));
    await store.save(catalog, expectedRevision: 0, edits: [NpcWritingEdit(
        id: catalog.candidates.keys.first, playerLine: 'Незавершённый вопрос выбранного героя')]);
    final writing = await repo.read(catalog.storageKey);
    final forged = jsonDecode(before!) as Map<String, dynamic>;
    (forged['payload'] as Map)['install_consent'] = true;
    forged['sha256'] = npcWritingHash(forged['payload']);
    await repo.write(key, jsonEncode(forged));
    await expectLater(heroes.load(f.free, f.roles), throwsFormatException);
    expect(() => heroes.reset(f.free, confirmed: false), throwsFormatException);
    await heroes.reset(f.free, confirmed: true);
    expect((await heroes.load(f.free, f.roles)).role, isNull);
    expect(await repo.read(catalog.storageKey), writing);
  });

  testWidgets('same editor restores and changes hero locally without network, '
      'installation or inherited consent at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemorySourceAnalysisCheckpointRepository();
    final heroStore = NpcCampaignHeroStore(repository: repo);
    await heroStore.save(f.free, currentRoles: f.roles, role: f.hero, sourceAction: false, expectedRevision: 0);
    final gateway = _UnusedGateway(), transport = _Transport();
    await tester.pumpWidget(MaterialApp(home: WholeBookNpcCampaignPage(
      index: f.free.index, book: f.free.book, bookMap: f.free.bookMap, draft: f.free.draft,
      gateway: gateway, roleCatalog: _Roles(f.roles), draftStore: NpcWritingStore(repository: repo),
      aiWriter: ZaiNpcCampaignWriting(preferences: _Preferences(), vault: _Vault(), transport: transport),
    )));
    expect(transport.sent, isEmpty); expect(gateway.calls, 0);
    await tester.tap(find.byKey(const Key('whole-npc-load-heroes')));
    await tester.pumpAndSettle();
    expect(find.text('Герой: Артем'), findsOneWidget);
    final selector = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(selector);
    await tester.tap(selector); await tester.pumpAndSettle();
    await tester.tap(find.text('Мария').last); await tester.pumpAndSettle();
    expect(find.text('Герой: Мария'), findsOneWidget);
    expect((await heroStore.load(f.free, f.roles)).role!.displayName, 'Мария');
    final consent = find.byKey(const Key('whole-npc-quotes-reviewed'));
    await tester.scrollUntilVisible(consent, 160, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    expect(transport.sent, isEmpty); expect(gateway.calls, 0);
    expect(tester.takeException(), isNull);
  });
}
