import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/npc_campaign_consequence_store.dart';
import 'package:ai_story_reader/npc_campaign_consequences.dart';
import 'package:ai_story_reader/npc_campaign_hero_selection.dart';
import 'package:ai_story_reader/npc_campaign_writing_session.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
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
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_npc_campaign_writing.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

class _Fixture {
  _Fixture(this.free, this.source, this.roles, this.base);
  final WholeBookNpcSourcePlan free, source;
  final List<ReviewedHeroRole> roles;
  final Uint8List base;
  ReviewedHeroRole get hero => source.selectedHeroRole!;
  List<BookwideNpcConversationCandidate> get conversations =>
    BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: roles);
  NpcWritingCatalog get catalog => NpcWritingCatalog(source: source, candidates: conversations);
  WholePlanGameplayBatchManifest get manifest => WholePlanGameplayBatchManifest.fromPlan(
    index: source.index, book: source.book, plan: source.plan, maxNewRequestsPerRun: 2);
  List<GameplayCandidateDraft> get proposals => [for (final ctx in manifest.contexts)
    GameplayCandidateDraft(sourceFingerprint: ctx.sourceFingerprint, approvalDigest: ctx.approvalDigest,
      candidates: [for (final c in ctx.choices)
        if (c.choiceId == 'act_1_accept_offer' || c.choiceId == 'act_1_honor_condition')
          GameplayCandidate(kind: 'item', id: 'source_key', label: 'ключ',
            op: c.choiceId == 'act_1_accept_offer' ? 'grant_item' : 'consume_item',
            sceneId: c.sceneId, choiceId: c.choiceId, sourceEventId: c.sourceEventId,
            uncertainty: 'Игровое владение требует авторской проверки.')])];
  Map<String, String> get notes => {for (final d in proposals) for (final c in d.candidates)
    ReviewedGameplayCompiler.signature(c): 'Частное игровое решение автора, не утверждение литературного канона.'};
  Future<NpcConsequenceDraft> load(NpcCampaignConsequenceStore store) =>
    store.load(source: source, originalArchive: base, roles: roles);
  Future<NpcConsequenceDraft> save(NpcCampaignConsequenceStore store, NpcConsequenceDraft expected) =>
    store.save(source: source, originalArchive: base, roles: roles, expected: expected,
      manifest: manifest, proposals: proposals, selectedUserReviewNotes: notes);
}

Future<_Fixture> _fixture() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Сохранённая авторская редакция', author: 'Синтетическая приёмка',
    chapters: [for (final name in names)
      List.filled(7, 'Начало пути. ').join() + '$name нашёл ключ у ворот и показал дорогу. ' +
          List.filled(12, 'Путник продолжил путешествие. ').join()]));
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final analyzed = await ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final rows = [for (var i = 0; i < 4; i++) SemanticCandidate.propose(source, chunk,
        category: SemanticCategory.event, startUtf16: chunk.startUtf16 + i * 10,
        endUtf16: chunk.startUtf16 + 150 + i * 10,
        label: 'Проверяемое событие', uncertainty: 'Смысл требует проверки.')];
      return ZaiSemanticPreviewResult(batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId, providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: source.sourceFingerprint, chunkIds: [for (final c in window.chunks) c.id], candidates: rows),
        totalSuggestions: rows.length, rejectedCount: 0, rejectedNonRussian: 0);
    }).analyze(index: index, approvedManifestDigest: consent.approvalDigest,
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
  for (final name in names) {
    notebook = notebook.putProfile(NpcEditorialNotebook.freshProfile(
      dossiers.dossiers.singleWhere((d) => d.labels.contains(name))));
  }
  final roles = ReviewedHeroRole.fromReviewedSources(index: index, dossiers: dossiers,
      graph: graph, catalog: catalog, editorial: editorial, notebook: notebook);
  final hero = roles.singleWhere((r) => r.displayName == 'Артем');
  final source = NpcCampaignHeroSelection(hero, true, 0).bind(free);
  final base = await source.compileBase(approvedPlanDigest: source.planDigest,
      approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
  return _Fixture(free, source, roles, base.archive);
}

Future<NpcConsequenceDraft> _seed(_Fixture f, SourceAnalysisCheckpointRepository repo) async {
  await NpcCampaignHeroStore(repository: repo).save(f.free, currentRoles: f.roles,
    role: f.hero, sourceAction: true, expectedRevision: 0);
  // Discovery order is narrative order; catalog/hash order is NOT chronology.
  final ids = f.conversations.map((c) => c.id).toList();
  await NpcWritingStore(repository: repo).save(f.catalog, expectedRevision: 0,
    edits: [for (var i = 0; i < ids.length; i++) NpcWritingEdit(id: ids[i],
      playerLine: 'Расскажи о дороге у ворот.', npcLine: 'Я помню нашу встречу у ворот.',
      dependencies: [if (i > 0) ids[i - 1]])]);
  final store = NpcCampaignConsequenceStore(repository: repo);
  return f.save(store, await f.load(store));
}

class _Roles extends ReviewedHeroRoleCatalog {
  _Roles(this.roles);
  final List<ReviewedHeroRole> roles;
  @override Future<List<ReviewedHeroRole>> load(BookSourceIndex index) async => roles;
}
class _NoGateway implements WorldLibraryGateway {
  int calls = 0;
  @override dynamic noSuchMethod(Invocation invocation) {
    calls++; throw StateError('No installation is authorized by a restored draft');
  }
}
class _NoTransport implements AiHttpTransport {
  int calls = 0;
  @override Future<AiHttpResponse> send({required Uri uri,
    required Map<String, String> headers, required String body}) async {
    calls++; throw StateError('Restore must be offline');
  }
}

/// A lazy-list child may exist in cache outside the viewport. Re-layout and
/// center the actual target before asserting that a real tap can hit it.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 140,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
  }
  expect(target, findsOneWidget);
  for (var attempt = 0; attempt < 3; attempt++) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 100));
    if (target.hitTestable().evaluate().isNotEmpty) return;
  }
  expect(target.hitTestable(), findsOneWidget,
      reason: 'The intended control must be inside the real phone viewport');
}

/// Let actual file/isolate work run AND advance the widget frame clock.
/// A real-time delay alone does not drive a FakeAsync route animation.
/// Completion requires the intended result; a progress indicator may be
/// offscreen or intentionally animated beneath a confirmation dialog.
Future<void> _tapLocalWork(WidgetTester tester, Finder target,
    {required bool Function() ready}) async {
  await _reveal(tester, target);
  final completed = await tester.runAsync<bool>(() async {
    await tester.tap(target);
    await tester.pump(); // Start any route ticker before advancing its clock.
    for (var i = 0; i < 400; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      if (ready()) return true;
    }
    return false;
  });
  expect(completed, true, reason: 'Local authoring operation did not finish');
  // A confirmation dialog can intentionally keep the editor busy. Avoid an
  // unbounded pumpAndSettle while its background indicator is animated.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUpAll(() async { f = await _fixture(); });

  test('author disk restart restores hero, exact selected effects and NPC writings; '
      'new approval compiles ONE offline world and mid-item SQLite replay', () async {
    final folder = await Directory.systemTemp.createTemp('author_revision_');
    try {
      final repo = FileSourceAnalysisCheckpointRepository(rootDirectory: () async => folder);
      final first = await _seed(f, repo);
      final writingBytes = await repo.read(f.catalog.storageKey);
      final effectBytes = await repo.read(first.storageKey);
      for (final event in f.source.book.events) {
        expect(effectBytes, isNot(contains(event.source.quote)));
      }
      expect(effectBytes, isNot(contains('api_key')));
      expect(effectBytes, isNot(contains('install_consent')));
      final reopenedRepo = FileSourceAnalysisCheckpointRepository(rootDirectory: () async => folder);
      final hero = await NpcCampaignHeroStore(repository: reopenedRepo).load(f.free, f.roles);
      final source = hero.bind(f.free);
      final rebuilt = await source.compileBase(approvedPlanDigest: source.planDigest,
        approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
      final restored = await NpcCampaignConsequenceStore(repository: reopenedRepo).load(
        source: source, originalArchive: rebuilt.archive, roles: f.roles);
      expect(restored.effectCount, 2);
      expect(restored.recordHash, first.recordHash);
      expect(restored.preview!.approvalDigest, first.preview!.approvalDigest);
      expect(restored.cloudConsent, false); expect(restored.installConsent, false);
      expect(restored.effectsAccepted, false);
      await expectLater(NpcCampaignConsequences.accept(source: source, preview: restored.preview!,
        originalArchive: rebuilt.archive, freshReviewedRoles: f.roles,
        approvedDigest: restored.preview!.approvalDigest, explicitlyConfirmedPrivateFiction: false), throwsFormatException);
      final variant = await NpcCampaignConsequences.accept(source: source, preview: restored.preview!,
        originalArchive: rebuilt.archive, freshReviewedRoles: f.roles,
        approvedDigest: restored.preview!.approvalDigest, explicitlyConfirmedPrivateFiction: true);
      final writings = await NpcWritingStore(repository: reopenedRepo).load(f.catalog);
      expect(await reopenedRepo.read(f.catalog.storageKey), writingBytes);
      final review = BookwideNpcCampaignAuthoring.review(source: source,
        verifiedBaseArchive: variant.archiveFor(source: source, originalArchive: rebuilt.archive),
        currentReviewedRoles: f.roles, selectedDrafts: writings.edits.values.map((e) => e.toDraft()).toList());
      final built = await BookwideNpcCampaignAuthoring.compile(source: source, approval: review,
        freshReviewedRoles: f.roles, approvedDigest: review.approvalDigest, explicitlyConfirmedPrivateFiction: true);
      final game = const RichPrivateBookworldImporter().inspect(built.archive);
      expect(game.requiresNetwork, false);
      final opportunity = ReviewedHeroSourceAction.find(index: source.index,
        book: source.book, plan: source.plan, role: f.hero)!;
      final path = <String>['${opportunity.observeSceneId}_hero_observe',
        '${opportunity.recallSceneId}_hero_recall', 'act_1_accept_offer',
        'act_1_honor_condition', 'act_1_continue_original'];
      final candidates = f.conversations;
      for (var i = 0; i < candidates.length; i++) {
        path.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(candidates[i].id),
          ReviewedNpcCampaignBookworldWriter.replyChoiceId(candidates[i].id),
          'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
        if (i < candidates.length - 1) path.add('act_${i + 2}_continue_original');
      }
      final world = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      for (var i = 0; i < path.length; i++) {
        expect(world.apply(actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true);
      }
      expect(world.isTerminal, true); expect(world.state.inventory, isEmpty);
      expect(world.state.knowledge['player'], isEmpty);
      final replay = StoryWorld.replay(game.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: path.length, expectedStateHash: world.state.stateHash,
        socialRulebook: game.npcSocialRulebook);
      expect(replay.state.stateHash, world.state.stateHash);
      var db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/campaign');
      late String id;
      try {
        id = db.createCampaign(db.installBookworld(built.archive).archiveHash);
        for (var i = 0; i < 3; i++) {
          expect(db.commitChoice(id, actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(id).coordinator.state.inventory, {'source_key'});
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/campaign');
      try {
        expect(db.loadCampaign(id).coordinator.state.inventory, {'source_key'});
        for (var i = 3; i < path.length; i++) {
          expect(db.commitChoice(id, actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(id).coordinator.state.stateHash, world.state.stateHash);
      } finally { db.close(); }
    } finally { await folder.delete(recursive: true); }
  });

  test('failed writes, stale editors, concurrent writers and tombstones never lose a newer selection', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcCampaignConsequenceStore(repository: repo);
    final empty = await f.load(store), saved = await _seed(f, repo);
    final raw = await repo.read(saved.storageKey);
    repo.failNextWrite = true;
    await expectLater(store.clear(source: f.source, originalArchive: f.base,
      roles: f.roles, expected: saved, confirmed: true), throwsA(isA<FileSystemException>()));
    expect(await repo.read(saved.storageKey), raw);
    await expectLater(f.save(store, empty), throwsFormatException);
    final results = await Future.wait<Object>([for (var i = 0; i < 2; i++)
      f.save(NpcCampaignConsequenceStore(repository: repo), saved)
          .then<Object>((value) => value, onError: (Object error) => error)]);
    expect(results.whereType<NpcConsequenceDraft>(), hasLength(1));
    expect(results.whereType<FormatException>(), hasLength(1));
    final current = await f.load(store);
    final cleared = await store.clear(source: f.source, originalArchive: f.base,
      roles: f.roles, expected: current, confirmed: true);
    expect(cleared.effectCount, 0); expect(cleared.revision, current.revision + 1);
    expect((await f.load(store)).preview, isNull);
    await expectLater(f.save(store, saved), throwsFormatException);
    await expectLater(f.save(store, empty), throwsFormatException);
    expect((await NpcWritingStore(repository: repo).load(f.catalog)).edits, hasLength(2));
  });

  test('rehashed foreign roles, source bindings, permission fields, labels and truncated selections fail closed', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcCampaignConsequenceStore(repository: repo);
    final saved = await _seed(f, repo), original = (await repo.read(NpcCampaignConsequenceStore.storageKey(f.source)))!;
    Map firstCandidate(Map p) => ((p['selection']['batches'] as List)
        .firstWhere((b) => (b['candidates'] as List).isNotEmpty)['candidates'] as List).first as Map;
    final mutations = <void Function(Map<String, dynamic>)>[
      (p) => p['install_consent'] = true,
      (p) => p['hero'] = '0' * 64,
      (p) => p['plan'] = '0' * 64,
      (p) => p['base'] = '0' * 64,
      (p) => firstCandidate(p)['source_event_id'] = f.source.book.events.last.id,
      (p) => firstCandidate(p)['label'] = 'Несуществующий меч',
      (p) => firstCandidate(p)['op'] = 'teleport',
      (p) => (p['selection']['batches'] as List).removeLast(),
      (p) => p['selection']['cloud_consent'] = true,
    ];
    for (final mutate in mutations) {
      final envelope = jsonDecode(original) as Map<String, dynamic>;
      final payload = envelope['payload'] as Map<String, dynamic>;
      mutate(payload); envelope['sha256'] = npcWritingHash(payload);
      final forged = jsonEncode(envelope);
      await repo.write(saved.storageKey, forged);
      await expectLater(f.load(store), throwsFormatException);
      expect(await repo.read(saved.storageKey), forged);
    }
    await repo.write(saved.storageKey, original);
    await expectLater(store.load(source: f.source, originalArchive: f.base,
      roles: f.roles.where((r) => r.characterId != f.hero.characterId).toList()), throwsFormatException);
    expect(await repo.read(saved.storageKey), original);
  });

  test('corrupt-record reset is explicit and exact-token guarded; other hero and NPC drafts are retained', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcCampaignConsequenceStore(repository: repo);
    final saved = await _seed(f, repo);
    final writing = await repo.read(f.catalog.storageKey);
    final other = NpcCampaignHeroSelection(f.roles.singleWhere((r) => r.displayName == 'Мария'), false, 0).bind(f.free);
    final otherKey = NpcCampaignConsequenceStore.storageKey(other);
    expect(otherKey, isNot(saved.storageKey));
    await repo.write(otherKey, 'unrelated author draft');
    await repo.write(saved.storageKey, '{broken');
    final token = await store.recordHash(f.source);
    expect(() => store.discard(source: f.source, originalArchive: f.base,
      roles: f.roles, expectedRecordHash: token, confirmed: false), throwsFormatException);
    await repo.write(saved.storageKey, '{newer broken');
    await expectLater(store.discard(source: f.source, originalArchive: f.base,
      roles: f.roles, expectedRecordHash: token, confirmed: true), throwsFormatException);
    expect(await repo.read(saved.storageKey), '{newer broken');
    final reset = await store.discard(source: f.source, originalArchive: f.base,
      roles: f.roles, expectedRecordHash: await store.recordHash(f.source), confirmed: true);
    expect(reset.preview, isNull);
    await expectLater(f.save(store, saved), throwsFormatException);
    expect(await repo.read(f.catalog.storageKey), writing);
    expect(await repo.read(otherKey), 'unrelated author draft');
    expect((await NpcCampaignHeroStore(repository: repo).load(f.free, f.roles)).role!.characterId, f.hero.characterId);
  });

  testWidgets('phone editor restores selected effects without network, requires fresh approval and '
      'rejects another editor changing them after final review', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oldHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = oldHitTestPolicy);
    final repo = MemorySourceAnalysisCheckpointRepository();
    final saved = await _seed(f, repo);
    final gateway = _NoGateway(), transport = _NoTransport();
    await tester.pumpWidget(MaterialApp(home: WholeBookNpcCampaignPage(
      index: f.free.index, book: f.free.book, bookMap: f.free.bookMap, draft: f.free.draft,
      gateway: gateway, roleCatalog: _Roles(f.roles), draftStore: NpcWritingStore(repository: repo),
      aiWriter: ZaiNpcCampaignWriting(transport: transport))));
    await _tapLocalWork(tester, find.byKey(const Key('whole-npc-load-heroes')),
      ready: () => find.byType(DropdownButtonFormField<String>).evaluate().isNotEmpty);
    for (final key in ['whole-npc-quotes-reviewed', 'whole-npc-private-fiction']) {
      final target = find.byKey(Key(key));
      await _reveal(tester, target);
      expect(tester.widget<CheckboxListTile>(target).value, false);
      await tester.tap(target);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(target).value, true);
    }
    final state = find.byKey(const Key('npc-consequences-state'));
    await _tapLocalWork(tester, find.byKey(const Key('whole-npc-prepare')),
      ready: () => state.evaluate().isNotEmpty);
    await _reveal(tester, state);
    expect(tester.widget<Text>(state).data, contains('Восстановлено эффектов: 2'));
    final restore = find.byKey(const Key('npc-consequences-restore'));
    await _tapLocalWork(tester, restore,
      ready: () => find.byType(AlertDialog).evaluate().isNotEmpty);
    final consent = find.byKey(const Key('npc-consequences-consent'));
    await _reveal(tester, consent);
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    expect(tester.widget<FilledButton>(find.byKey(const Key('npc-consequences-accept'))).onPressed, isNull);
    final cancel = find.descendant(of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Отмена'));
    await _tapLocalWork(tester, cancel,
      ready: () => find.byType(AlertDialog).evaluate().isEmpty &&
          restore.evaluate().isNotEmpty &&
          tester.widget<OutlinedButton>(restore).onPressed != null);
    expect(find.byType(AlertDialog), findsNothing);
    // Cancellation dismisses only the modal, not the chosen authoring data;
    // it must not accept effects, install a game or make a cloud request.
    await _reveal(tester, state);
    expect(tester.widget<Text>(state).data, contains('Восстановлено эффектов: 2'));
    expect(await NpcCampaignConsequenceStore(repository: repo).recordHash(f.source), saved.recordHash);
    expect(gateway.calls, 0); expect(transport.calls, 0);
    await _tapLocalWork(tester, restore,
      ready: () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await _reveal(tester, consent);
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    await tester.tap(consent); await tester.pump();
    expect(tester.widget<CheckboxListTile>(consent).value, true);
    await _tapLocalWork(tester, find.byKey(const Key('npc-consequences-accept')),
      ready: () => state.evaluate().isNotEmpty &&
          tester.widget<Text>(state).data == 'Включено игровых эффектов: 2.');
    await _reveal(tester, state);
    expect(tester.widget<Text>(state).data, 'Включено игровых эффектов: 2.');
    final review = find.byKey(const Key('whole-npc-review-package'));
    final approval = find.byKey(const Key('whole-npc-final-approval'));
    await _tapLocalWork(tester, review,
      ready: () => approval.evaluate().isNotEmpty);
    await _reveal(tester, approval);
    expect(tester.widget<CheckboxListTile>(approval).value, false);
    final other = NpcCampaignConsequenceStore(repository: repo);
    await other.clear(source: f.source, originalArchive: f.base, roles: f.roles,
      expected: await f.load(other), confirmed: true);
    await tester.tap(approval); await tester.pump();
    expect(tester.widget<CheckboxListTile>(approval).value, true);
    final error = find.byKey(const Key('whole-npc-error'));
    await _tapLocalWork(tester, find.byKey(const Key('whole-npc-start')),
      ready: () => error.evaluate().isNotEmpty);
    await _reveal(tester, error);
    expect(tester.widget<SelectableText>(error).data, contains('Последствия изменены в другом окне'));
    expect(gateway.calls, 0); expect(transport.calls, 0);
    expect(tester.takeException(), isNull);
  });
}
