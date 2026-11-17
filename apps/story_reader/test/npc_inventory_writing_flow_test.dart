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
import 'package:ai_story_reader/npc_inventory_writing_context.dart';
import 'package:ai_story_reader/npc_writing_consent_dialog.dart';
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
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
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
  _Fixture(this.source, this.roles, this.base);
  final WholeBookNpcSourcePlan source;
  final List<ReviewedHeroRole> roles;
  final Uint8List base;
  late Uint8List withKey, spentKey;
  late NpcInventoryWritingContext inventory, spentInventory;
  List<BookwideNpcConversationCandidate> get conversations =>
      BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: roles);
  NpcWritingCatalog get catalog => NpcWritingCatalog(source: source, candidates: conversations);
  WholePlanGameplayBatchManifest get manifest => WholePlanGameplayBatchManifest.fromPlan(
      index: source.index, book: source.book, plan: source.plan, maxNewRequestsPerRun: 2);
  List<GameplayCandidateDraft> proposals(bool consume) => [for (final context in manifest.contexts)
    GameplayCandidateDraft(sourceFingerprint: context.sourceFingerprint, approvalDigest: context.approvalDigest,
      candidates: [for (final choice in context.choices)
        if (choice.choiceId == 'act_1_accept_offer' || (consume && choice.choiceId == 'act_1_honor_condition'))
          GameplayCandidate(kind: 'item', id: 'source_key', label: 'ключ',
            op: choice.choiceId == 'act_1_accept_offer' ? 'grant_item' : 'consume_item',
            sceneId: choice.sceneId, choiceId: choice.choiceId, sourceEventId: choice.sourceEventId,
            uncertainty: 'Игровое владение не доказывает литературную истину.')])];
  Map<String, String> notes(bool consume) => {for (final draft in proposals(consume)) for (final c in draft.candidates)
    ReviewedGameplayCompiler.signature(c): 'Проверено как частное игровое правило; выбор пути не предрешён.'};
  Future<Uint8List> variant(bool consume) async {
    final preview = NpcCampaignConsequences.preview(source: source, originalArchive: base,
      currentReviewedRoles: roles, manifest: manifest, proposals: proposals(consume), selectedUserReviewNotes: notes(consume));
    final accepted = await NpcCampaignConsequences.accept(source: source, preview: preview,
      originalArchive: base, freshReviewedRoles: roles, approvedDigest: preview.approvalDigest,
      explicitlyConfirmedPrivateFiction: true);
    return accepted.archiveFor(source: source, originalArchive: base);
  }
}

Future<_Fixture> _fixture() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Предметы и две встречи: синтетическая книга', author: 'Автономная приёмка',
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
  final draft = BookwideStoryPlanComposer.compose(index: index, book: book, bookMap: map,
    actProposals: [for (var i = 0; i < 3; i++) StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: book.events.where((e) => e.source.chapterIndex == i).first.id,
      outcomeEventId: book.events.where((e) => e.source.chapterIndex == i).last.id,
      kind: StoryDilemmaKind.disclosure, dilemma: 'Принять предложение или продолжить путь самому',
      acceptIntent: 'Принять предложение', refuseIntent: 'Отказаться',
      followupGoal: 'Выполнить выбранное условие', finishOriginalIntent: 'Исполнить обещание',
      originalEnding: 'Завершить исходный путь', alternativeSearchGoal: 'Найти другой путь',
      searchIntent: 'Исследовать дорогу', alternativeDiscovery: 'Найдена другая дорога',
      useDiscoveryIntent: 'Выбрать найденный путь', alternativeEnding: 'Завершить иной путь')]);
  final free = WholeBookNpcSourcePlan.fromBook(index: index, book: book, bookMap: map, draft: draft);
  var graph = SourceEvidenceGraph.empty(index);
  for (var i = 0; i < names.length; i++) {
    final event = book.events.firstWhere((e) => e.source.chapterIndex == i && free.extraEventIds.contains(e.id));
    final offset = event.source.quote.indexOf(names[i]);
    expect(offset, greaterThanOrEqualTo(0));
    final mention = SourceEvidence.propose(index, chunkId: event.source.chunkId, kind: EvidenceKind.character,
      startUtf16: event.source.startUtf16 + offset, endUtf16: event.source.startUtf16 + offset + names[i].length);
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
  final f = _Fixture(source, roles, base.archive);
  f.withKey = await f.variant(false);
  f.spentKey = await f.variant(true);
  f.inventory = await NpcInventoryWritingContext.prepare(source: source,
      reviewedArchive: f.withKey, conversations: f.conversations);
  f.spentInventory = await NpcInventoryWritingContext.prepare(source: source,
      reviewedArchive: f.spentKey, conversations: f.conversations);
  return f;
}

class _Harness {
  _Harness(this.f, this.repo);
  final _Fixture f;
  final MemorySourceAnalysisCheckpointRepository repo;
  late final store = NpcWritingStore(repository: repo);
  late final effects = NpcCampaignConsequenceStore(repository: repo);
  late NpcConsequenceDraft effectDraft;
  late NpcWritingSession initial;
  late Uint8List currentArchive = f.withKey;
  late List<ReviewedHeroRole> currentRoles = f.roles;
  final guardedRevisions = <int>[];
  Future<void> initialize() async {
    final empty = await effects.load(source: f.source, originalArchive: f.base, roles: f.roles);
    effectDraft = await effects.save(source: f.source, originalArchive: f.base, roles: f.roles,
      expected: empty, manifest: f.manifest, proposals: f.proposals(false), selectedUserReviewNotes: f.notes(false));
    final candidates = f.conversations;
    initial = await store.save(f.catalog, expectedRevision: 0, edits: [for (var i = 0; i < candidates.length; i++)
      NpcWritingEdit(id: candidates[i].id, dependencies: [if (i > 0) candidates[i - 1].id])]);
  }
  Future<void> guard(NpcWritingSession expected) async {
    guardedRevisions.add(expected.revision);
    f.source.verifyCurrentHero(currentRoles);
    final fresh = NpcWritingCatalog(source: f.source, candidates:
        BookwideNpcCampaignAuthoring.discover(source: f.source, currentReviewedRoles: currentRoles));
    if (fresh.digest != f.catalog.digest) throw const FormatException('Карточки изменились.');
    await effects.assertUnchanged(f.source, effectDraft);
    f.inventory.assertCurrent(source: f.source, reviewedArchive: currentArchive);
  }
  Future<void> removeEffects() async {
    await effects.clear(source: f.source, originalArchive: f.base, roles: f.roles,
      expected: effectDraft, confirmed: true);
  }
  NpcWritingRequest request([NpcWritingSession? session]) => NpcWritingRequest.prepare(
      f.catalog, session ?? initial, perRequest: 1, inventoryContext: f.inventory);
}

class _Preferences extends AiCloudPreferences {
  bool enabled = true;
  @override Future<bool> isEnabled() async => enabled;
}
class _Vault implements AiApiKeyVault {
  @override Future<String?> read() async => 'fake-unit-key';
  @override Future<void> write(String value) async {}
  @override Future<void> delete() async {}
  @override Future<bool> hasKey() async => true;
}
AiHttpResponse _reply(Map<String, dynamic> batch, {bool forged = false}) => AiHttpResponse(200,
  jsonEncode({'choices': [{'finish_reason': 'stop', 'message': {'content': jsonEncode({
    'batch_id': batch['batch_id'],
    'proposals': [for (final row in batch['conversations'] as List) {
      'candidate_id': row['candidate_id'], 'actor_id': row['actor_id'],
      'player_line': 'Я хочу уточнить дорогу у ворот.',
      'npc_line': 'Я помню нашу встречу и могу обсудить дорогу.',
      'uncertainty': 'Предметы зависят от пути; смысл реплик требует проверки автора.',
      if (forged) 'effects': [{'op': 'grant_item', 'id': 'source_key'}],
    }], 'skipped': <Object>[],
  })}}]}));
class _Transport implements AiHttpTransport {
  final bodies = <String>[];
  Future<AiHttpResponse> Function(int, Map<String, dynamic>)? handler;
  @override Future<AiHttpResponse> send({required Uri uri,
      required Map<String, String> headers, required String body}) async {
    bodies.add(body);
    final batch = jsonDecode((jsonDecode(body) as Map)['messages'].last['content'] as String)
        as Map<String, dynamic>;
    return handler == null ? _reply(batch) : await handler!(bodies.length, batch);
  }
}
ZaiNpcCampaignWriting _writer(_Transport transport, {Future<void> Function(Duration)? wait,
    _Preferences? preferences}) => ZaiNpcCampaignWriting(preferences: preferences ?? _Preferences(),
      vault: _Vault(), transport: transport, retryWait: wait ?? (_) async {});
Future<NpcWritingSession> _generate(_Harness h, _Transport t, {
  NpcWritingRequest? request, ZaiPreviewCancellation? cancel,
  Future<void> Function(Duration)? wait,
}) {
  final r = request ?? h.request();
  return _writer(t, wait: wait).generate(catalog: h.f.catalog, store: h.store,
    request: r, approvedDigest: r.approvalDigest, explicitCloudConsent: true,
    cancellation: cancel, verifyAuthorRevision: h.guard);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUpAll(() async { f = await _fixture(); });
  Future<_Harness> harness() async {
    final h = _Harness(f, MemorySourceAnalysisCheckpointRepository());
    await h.initialize(); return h;
  }

  test('real compiled item variants bind shown route inventory without pretending '
      'a possible pickup is current ownership or NPC knowledge', () async {
    final h = await harness();
    for (final c in f.conversations) {
      final possible = f.inventory.forConversation(c);
      final absent = f.spentInventory.forConversation(c);
      expect(possible['response_scene']['branch_dependent'], contains('source_key'));
      expect(possible['response_scene']['always_present'], isNot(contains('source_key')));
      expect(absent['response_scene']['never_present'], contains('source_key'));
      expect(absent['first_scene']['never_present'], contains('source_key'));
    }
    final r = h.request();
    final payload = jsonDecode(r.batches.first) as Map;
    expect(payload['inventory_context']['archive_sha256'], f.inventory.archiveSha256);
    expect(payload['inventory_context']['item_names']['source_key'], 'ключ');
    expect(payload['inventory_context']['grants_npc_knowledge'], false);
    expect(payload['inventory_context']['describes_current_save'], false);
    expect(payload['inventory_context']['scope'], 'reviewed_base_routes_before_npc_overlay');
    expect(r.shownText, contains(f.inventory.archiveSha256));
    expect(r.shownText, isNot(contains('review_note')));
    final changed = NpcWritingRequest.prepare(f.catalog, h.initial, perRequest: 1,
      inventoryContext: f.spentInventory);
    expect(changed.approvalDigest, isNot(r.approvalDigest));
    final copy = f.inventory.cloudHeader;
    (copy['item_names'] as Map)['source_key'] = 'подмена';
    expect(f.inventory.cloudHeader['item_names']['source_key'], 'ключ');
    expect(() => f.inventory.assertCurrent(source: f.source, reviewedArchive: f.spentKey), throwsFormatException);
  });

  test('inventory request cannot transmit without fresh exact consent and a revision guard', () async {
    final h = await harness(), transport = _Transport();
    final r = h.request();
    final writer = _writer(transport);
    for (final consent in [false, true]) {
      await expectLater(writer.generate(catalog: f.catalog, store: h.store, request: r,
        approvedDigest: r.approvalDigest, explicitCloudConsent: consent), throwsA(isA<AiSetupException>()));
    }
    await expectLater(writer.generate(catalog: f.catalog, store: h.store, request: r,
      approvedDigest: 'stale-consent', explicitCloudConsent: true,
      verifyAuthorRevision: h.guard), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty);
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
  });

  test('429 retries retain byte-identical inventory; saved batches advance own '
      'revision and only unfinished conversations resume before offline SQLite gameplay', () async {
    final h = await harness(), first = _Transport();
    first.handler = (call, batch) async => call == 1 ? _reply(batch) : AiHttpResponse(429, '{}');
    final request = h.request();
    await expectLater(_generate(h, first, request: request), throwsA(isA<AiSetupException>()));
    expect(first.bodies, hasLength(4));
    expect(first.bodies[1], first.bodies[2]); expect(first.bodies[2], first.bodies[3]);
    for (var i = 0; i < first.bodies.length; i++) {
      final payload = (jsonDecode(first.bodies[i]) as Map)['messages'].last['content'];
      expect(payload, request.batches[i == 0 ? 0 : 1]);
    }
    final restartedStore = NpcWritingStore(repository: h.repo);
    final saved = await restartedStore.load(f.catalog);
    expect(saved.edits.values.where((e) => e.complete), hasLength(1));
    final resume = h.request(saved), second = _Transport();
    expect(resume.requestCount, 1);
    expect(resume.approvalDigest, isNot(request.approvalDigest));
    final completed = await _generate(h, second, request: resume);
    expect(second.bodies, hasLength(1));
    expect(completed.edits.values.every((e) => e.complete), true);
    expect(h.guardedRevisions.toSet(), containsAll([h.initial.revision, saved.revision]));
    final approval = BookwideNpcCampaignAuthoring.review(source: f.source,
      verifiedBaseArchive: f.withKey, currentReviewedRoles: f.roles,
      selectedDrafts: completed.edits.values.map((e) => e.toDraft()).toList());
    final built = await BookwideNpcCampaignAuthoring.compile(source: f.source, approval: approval,
      freshReviewedRoles: f.roles, approvedDigest: approval.approvalDigest, explicitlyConfirmedPrivateFiction: true);
    final game = const RichPrivateBookworldImporter().inspect(built.archive);
    expect(game.requiresNetwork, false);
    final opportunity = ReviewedHeroSourceAction.find(index: f.source.index, book: f.source.book,
      plan: f.source.plan, role: f.source.selectedHeroRole!)!;
    final path = <String>['${opportunity.observeSceneId}_hero_observe',
      '${opportunity.recallSceneId}_hero_recall', 'act_1_accept_offer',
      'act_1_honor_condition', 'act_1_continue_original'];
    for (var i = 0; i < f.conversations.length; i++) {
      final c = f.conversations[i];
      path.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(c.id),
        ReviewedNpcCampaignBookworldWriter.replyChoiceId(c.id),
        'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
      if (i < f.conversations.length - 1) path.add('act_${i + 2}_continue_original');
    }
    final world = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
    for (var i = 0; i < path.length; i++) {
      expect(world.apply(actionId: 'turn_$i', choiceId: path[i], expectedRevision: i).applied, true);
    }
    expect(world.isTerminal, true); expect(world.state.inventory, {'source_key'});
    expect(world.state.knowledge['player'], isEmpty);
    final replay = StoryWorld.replay(game.blueprint, world.events.map((e) => e.toJson()),
      expectedSequence: path.length, expectedStateHash: world.state.stateHash, socialRulebook: game.npcSocialRulebook);
    expect(replay.state.stateHash, world.state.stateHash);
    final dir = await Directory.systemTemp.createTemp('inventory_npc_cloud_guard_');
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      late String campaign;
      try {
        campaign = db.createCampaign(db.installBookworld(built.archive).archiveHash);
        for (var i = 0; i < 3; i++) {
          expect(db.commitChoice(campaign, actionId: 'turn_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        expect(db.loadCampaign(campaign).coordinator.state.inventory, {'source_key'});
        for (var i = 3; i < path.length; i++) {
          expect(db.commitChoice(campaign, actionId: 'turn_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).coordinator.state.stateHash, world.state.stateHash);
      } finally { db.close(); }
    } finally { await dir.delete(recursive: true); }
  });

  test('an effect changed during 429 wait prevents the retry and retains original writing', () async {
    final h = await harness(), transport = _Transport();
    transport.handler = (_, batch) async => AiHttpResponse(429, '{}');
    await expectLater(_generate(h, transport, wait: (_) async => h.removeEffects()), throwsFormatException);
    expect(transport.bodies, hasLength(1));
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
    expect((await h.effects.load(source: f.source, originalArchive: f.base, roles: f.roles)).preview, isNull);
  });

  test('late response is not saved after another editor changes the exact item selection', () async {
    final h = await harness(), transport = _Transport();
    transport.handler = (_, batch) async { await h.removeEffects(); return _reply(batch); };
    await expectLater(_generate(h, transport), throwsFormatException);
    expect(transport.bodies, hasLength(1));
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
  });

  test('late response cannot replace another authors manual line or revoked hero card', () async {
    final h = await harness(), transport = _Transport();
    final id = h.initial.edits.keys.first;
    transport.handler = (_, batch) async {
      await h.store.save(f.catalog, expectedRevision: h.initial.revision, edits: [
        for (final edit in h.initial.edits.values) edit.id == id
          ? NpcWritingEdit(id: id, playerLine: 'Ручная правка автора, сохранить.', dependencies: edit.dependencies) : edit,
      ]);
      return _reply(batch);
    };
    await expectLater(_generate(h, transport), throwsA(isA<AiSetupException>()));
    expect((await h.store.load(f.catalog)).edits[id]!.playerLine, 'Ручная правка автора, сохранить.');
    final revoked = await harness(), unused = _Transport();
    revoked.currentRoles = [];
    await expectLater(_generate(revoked, unused), throwsFormatException);
    expect(unused.bodies, isEmpty);
  });

  test('cancellation and disk failure stop before next request without false saved progress', () async {
    final h = await harness(), transport = _Transport(), token = ZaiPreviewCancellation();
    transport.handler = (_, batch) async { token.cancel(); return _reply(batch); };
    await expectLater(_generate(h, transport, cancel: token), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, hasLength(1));
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
    final failing = await harness(), second = _Transport();
    second.handler = (_, batch) async { failing.repo.failNextWrite = true; return _reply(batch); };
    await expectLater(_generate(failing, second), throwsA(isA<FileSystemException>()));
    expect(second.bodies, hasLength(1));
    expect((await failing.store.load(f.catalog)).snapshotDigest, failing.initial.snapshotDigest);
  });

  test('model-supplied item rules remain invalid despite correct inventory context', () async {
    final h = await harness(), transport = _Transport();
    transport.handler = (_, batch) async => _reply(batch, forged: true);
    await expectLater(_generate(h, transport), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, hasLength(1));
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
    expect(f.inventory.archiveSha256,
        const RichPrivateBookworldImporter().inspect(f.withKey).archiveSha256);
  });

  test('context cannot silently omit a requested conversation or accept corrupt bytes', () async {
    final partial = await NpcInventoryWritingContext.prepare(source: f.source,
      reviewedArchive: f.withKey, conversations: [f.conversations.first]);
    final h = await harness();
    expect(() => NpcWritingRequest.prepare(f.catalog, h.initial, inventoryContext: partial), throwsFormatException);
    final broken = Uint8List.fromList(f.withKey)..[0] = 0;
    await expectLater(NpcInventoryWritingContext.prepare(source: f.source,
      reviewedArchive: broken, conversations: f.conversations), throwsA(isA<FormatException>()));
  });

  testWidgets('phone consent shows exact inventory payload; cancellation and reopening '
      'never restore cloud permission or change durable drafts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final h = await harness(), request = h.request();
    bool? answer;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(key: const Key('open-inventory-consent'), onPressed: () async {
        answer = await showDialog<bool>(context: context, builder: (_) =>
          NpcWritingConsentDialog(request: request, heroName: f.source.heroName));
      }, child: const Text('Открыть'))))));
    Future<void> tap(Finder finder) async {
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder); await tester.pumpAndSettle();
    }
    await tap(find.byKey(const Key('open-inventory-consent')));
    final consent = find.byKey(const Key('npc-writing-cloud-consent'));
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    expect(tester.widget<FilledButton>(find.byKey(const Key('npc-writing-cloud-send'))).onPressed, isNull);
    await tap(find.text('Точные данные для отправки'));
    expect(tester.widget<SelectableText>(find.byKey(const Key('npc-writing-shown-bytes'))).data, request.shownText);
    await tap(find.text('Точные данные для отправки'));
    await tap(find.text('Отмена'));
    expect(answer, false);
    expect((await h.store.load(f.catalog)).snapshotDigest, h.initial.snapshotDigest);
    await tap(find.byKey(const Key('open-inventory-consent')));
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    await tap(consent);
    expect(tester.widget<CheckboxListTile>(consent).value, true);
    await tap(find.byKey(const Key('npc-writing-cloud-send')));
    expect(answer, true);
    expect(tester.takeException(), isNull);
  });
}
