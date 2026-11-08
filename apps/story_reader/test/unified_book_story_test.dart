import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/bookwide_unified_story.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/npc_campaign_consequences.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/unified_book_story_panel.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/zai_unified_book_story.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

Future<UnifiedBookStoryContext> fixture() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Авторская тестовая история о маяке', author: 'Синтетическая приёмка',
    chapters: [for (final name in names)
      List.filled(7, 'Дорога к маяку. ').join() +
      '$name нашёл ключ у ворот и предложил помощь для восстановления маяка. ' +
      List.filled(10, 'Впереди требовалось новое решение. ').join()]));
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analysis = await ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final rows = [for (var i = 0; i < 4; i++) SemanticCandidate.propose(source, chunk,
        category: SemanticCategory.event, startUtf16: chunk.startUtf16 + i * 10,
        endUtf16: chunk.startUtf16 + 175 + i * 10,
        label: 'Проверяемое событие у маяка', uncertainty: 'Литературный смысл требует проверки.')];
      return ZaiSemanticPreviewResult(batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: source.sourceFingerprint,
        chunkIds: [for (final c in window.chunks) c.id], candidates: rows),
        totalSuggestions: rows.length, rejectedCount: 0, rejectedNonRussian: 0);
    }).analyze(index: index, approvedManifestDigest: manifest.approvalDigest,
        explicitWholeBookConsent: true, maxWindowsPerRun: 64);
  final book = NarrativeBookModel.fromExisting(index: index,
      outline: ZaiWholeBookEventOutline.build(analysis));
  expect(book.events, hasLength(12));
  var graph = SourceEvidenceGraph.empty(index);
  for (var i = 0; i < names.length; i++) {
    final event = book.events.firstWhere((e) => e.source.chapterIndex == i);
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
  return UnifiedBookStoryContext.create(index: index, book: book,
      bookMap: BookwideActPlanner.build(index: index, book: book), roles: roles);
}

Map<String, dynamic> answer(UnifiedBookStoryContext context) => {
  'applicable': true,
  'campaign_goal': 'Восстановить маяк, договорившись с людьми на дороге и выполнив выбранные обязательства.',
  'central_conflict': 'Помощь каждого участника требует решения героя; отказ сохраняет другой путь, '
      'но не позволяет считать прежние договорённости исполненными.',
  'motivations': [for (final actor in context.shownData['actors'] as List) {
    'character_id': actor['character_id'], 'goal': 'Помочь восстановить дорогу к маяку, не нарушая договорённостей.',
    'reason': 'Упоминание связывает персонажа с ключом и предложением помощи; мотив является игровой гипотезой.',
    'source_event_ids': [(actor['source_event_ids'] as List).first],
  }],
  'acts': [for (var i = 0; i < context.actCount; i++) {
    'act_id': context.bookMap.acts[i].id,
    'purpose': 'Часть ${i + 1} продолжает общую попытку добраться до маяка и проверить цену принятой помощи.',
    'proposal': {
      'setup_event_id': context.bookMap.acts[i].events.first.id,
      'outcome_event_id': context.bookMap.acts[i].events.last.id,
      'kind': 'agreement',
      'dilemma': 'Принять помощь у ворот на пути к маяку или искать собственную дорогу.',
      'accept_intent': 'Принять предложенную помощь для восстановления маяка',
      'refuse_intent': 'Отказаться от помощи и искать другую дорогу',
      'followup_goal': 'Выполнить согласованное условие и продолжить путь к маяку',
      'finish_original_intent': 'Завершить принятое обязательство перед продолжением пути',
      'original_ending': 'Выполненное условие позволяет продолжить общий замысел восстановления маяка.',
      'alternative_search_goal': 'Найти дорогу к маяку без принятого предложения',
      'search_intent': 'Осмотреть обходную дорогу и найти другой способ',
      'alternative_discovery': 'Для игровой версии найден обходной путь, не требующий чужой помощи.',
      'use_discovery_intent': 'Выбрать найденную обходную дорогу к маяку',
      'alternative_ending': 'Герой продолжает путь иначе; отказ не создаёт обещания или чужого знания.',
    },
  }],
  'links': [for (var i = 1; i < context.actCount; i++) {
    'from_act_id': context.bookMap.acts[i - 1].id,
    'to_act_id': context.bookMap.acts[i].id, 'required_outcome': 'original',
    'reason': 'Новая помощь доступна в игровой версии только после исполнения предыдущего условия; '
        'иначе герой может отказаться и продолжить самостоятельный путь.',
  }],
};

class Prefs extends AiCloudPreferences {
  bool enabled = true;
  @override Future<bool> isEnabled() async => enabled;
}
class Vault implements AiApiKeyVault {
  String? key = 'not-a-real-key';
  @override Future<String?> read() async => key;
  @override Future<void> write(String value) async { key = value; }
  @override Future<void> delete() async { key = null; }
  @override Future<bool> hasKey() async => key != null;
}
class Transport implements AiHttpTransport {
  Transport(this.respond);
  final Future<AiHttpResponse> Function(String, int) respond;
  final bodies = <String>[];
  @override Future<AiHttpResponse> send({required Uri uri,
    required Map<String, String> headers, required String body}) async {
    expect(uri, ZaiModel.endpoint); bodies.add(body); return respond(body, bodies.length);
  }
}
AiHttpResponse response(Object output) => AiHttpResponse(200, jsonEncode({
  'choices': [{'finish_reason': 'stop', 'message': {'content': jsonEncode(output)}}],
}));
class Roles extends ReviewedHeroRoleCatalog {
  Roles(this.values);
  final List<ReviewedHeroRole> values;
  @override Future<List<ReviewedHeroRole>> load(BookSourceIndex index) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UnifiedBookStoryContext context;
  setUpAll(() async { context = await fixture(); });

  test('one exact context covers all events and acts, not a collection of sampled independent prompts', () {
    expect(context.eventCount, 12); expect(context.actCount, 3);
    final data = context.shownData;
    expect((data['acts'] as List).expand((a) => a['events'] as List), hasLength(12));
    for (final event in context.book.events) { expect(context.shownText, contains(event.source.quote)); }
    expect(context.shownText, isNot(contains(context.index.title)));
    expect(context.shownText, isNot(contains('private_note')));
    expect(UnifiedBookStoryContext.create(index: context.index, book: context.book,
      bookMap: context.bookMap, roles: context.roles.reversed.toList()).approvalDigest, context.approvalDigest);
  });

  test('single story proposal makes real causal dependencies and continues through existing hero items NPC compiler SQLite and alternate endings', () async {
    final draft = UnifiedBookStoryDraft.parse(context, jsonEncode(answer(context)));
    final linked = draft.accept(context: context, freshRoles: context.roles,
      approvedReviewDigest: draft.reviewDigest, allShownQuotesAndStoryReviewed: true,
      fictionalConsequencesConfirmed: true);
    expect(linked.formalRulesPassed, true);
    expect(linked.toDiagnosticJson()['enforced_story_links'], 2);
    expect(linked.plan.situations.expand((s) => s.decisions)
        .singleWhere((d) => d.id == 'act_2_accept_offer').requires, contains('act_1_original_outcome'));
    final hero = context.roles.singleWhere((r) => r.displayName == 'Артем');
    final source = WholeBookNpcSourcePlan.fromBook(index: context.index, book: context.book,
      bookMap: context.bookMap, draft: linked, selectedHeroRole: hero);
    expect(source.coverage.allDetectedEventsReferenced, true);
    final base = await source.compileBase(approvedPlanDigest: source.planDigest,
      approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
    final manifest = WholePlanGameplayBatchManifest.fromPlan(index: source.index,
        book: source.book, plan: source.plan, maxNewRequestsPerRun: 2);
    final proposals = [for (final ctx in manifest.contexts) GameplayCandidateDraft(
      sourceFingerprint: ctx.sourceFingerprint, approvalDigest: ctx.approvalDigest,
      candidates: [for (final c in ctx.choices)
        if (c.choiceId == 'act_1_accept_offer' || c.choiceId == 'act_1_honor_condition')
          GameplayCandidate(kind: 'item', id: 'source_key', label: 'ключ',
            op: c.choiceId == 'act_1_accept_offer' ? 'grant_item' : 'consume_item',
            sceneId: c.sceneId, choiceId: c.choiceId, sourceEventId: c.sourceEventId,
            uncertainty: 'Игровое владение ключом требует отдельного подтверждения.')])];
    final preview = NpcCampaignConsequences.preview(source: source, originalArchive: base.archive,
      currentReviewedRoles: context.roles, manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: {for (final p in proposals) for (final c in p.candidates)
        ReviewedGameplayCompiler.signature(c): 'Проверенный ключ используется как частное игровое последствие выбора.'});
    final effects = await NpcCampaignConsequences.accept(source: source, preview: preview,
      originalArchive: base.archive, freshReviewedRoles: context.roles,
      approvedDigest: preview.approvalDigest, explicitlyConfirmedPrivateFiction: true);
    final npcs = BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: context.roles);
    expect(npcs, hasLength(2));
    final reviewed = BookwideNpcCampaignAuthoring.review(source: source,
      verifiedBaseArchive: effects.archiveFor(source: source, originalArchive: base.archive),
      currentReviewedRoles: context.roles,
      selectedDrafts: [for (final npc in npcs) NpcCampaignDialogueDraft(candidateId: npc.id,
        playerLine: 'Обсудим дальнейший путь к маяку.', npcLine: 'Я помню нашу игровую встречу у ворот.')]);
    final built = await BookwideNpcCampaignAuthoring.compile(source: source, approval: reviewed,
      freshReviewedRoles: context.roles, approvedDigest: reviewed.approvalDigest, explicitlyConfirmedPrivateFiction: true);
    final world = const RichPrivateBookworldImporter().inspect(built.archive);
    expect(world.requiresNetwork, false);
    final path = <String>['act_1_pass_source', 'act_1_pass_source_2',
      'act_1_accept_offer', 'act_1_honor_condition', 'act_1_continue_original'];
    for (var i = 0; i < npcs.length; i++) {
      path.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(npcs[i].id),
        ReviewedNpcCampaignBookworldWriter.replyChoiceId(npcs[i].id),
        'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
      if (i == 0) path.add('act_2_continue_original');
    }
    final direct = StoryWorld(world.blueprint, socialRulebook: world.npcSocialRulebook);
    for (var i = 0; i < path.length; i++) {
      expect(direct.apply(actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true, reason: path[i]);
    }
    expect(direct.isTerminal, true); expect(direct.state.inventory, isEmpty);
    expect(direct.state.knowledge['player'], isEmpty);
    final alternative = StoryWorld(world.blueprint, socialRulebook: world.npcSocialRulebook);
    void alt(String choice) => expect(alternative.apply(
      actionId: 'alt_${alternative.state.revision}', choiceId: choice).applied, true, reason: choice);
    for (var act = 1; act <= 3; act++) {
      alt('act_${act}_pass_source'); alt('act_${act}_pass_source_2');
      if (act > 1) {
        expect(alternative.apply(actionId: 'denied_$act', choiceId: 'act_${act}_accept_offer').applied, false);
      }
      alt('act_${act}_refuse_offer'); alt('act_${act}_explore'); alt('act_${act}_use_discovery');
      expect(alternative.state.sceneId, 'act_${act}_alternate_resolution');
      // This is an actual mandatory action, not a test-only shortcut.
      alt('act_${act}_end_alternative');
      expect(alternative.state.sceneId, 'act_${act}_alternate_ending');
      if (act < 3) alt('act_${act}_continue_alternative');
    }
    expect(alternative.isTerminal, true);
    expect(alternative.state.sceneId, isNot(direct.state.sceneId));
    expect(alternative.state.inventory, isEmpty);
    final dir = await Directory.systemTemp.createTemp('whole_story_to_game_');
    late String campaign;
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        campaign = db.createCampaign(db.installBookworld(built.archive).archiveHash);
        for (var i = 0; i < 3; i++) {
          expect(db.commitChoice(campaign, actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).coordinator.state.inventory, {'source_key'});
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        expect(db.loadCampaign(campaign).coordinator.state.inventory, {'source_key'});
        for (var i = 3; i < path.length; i++) {
          expect(db.commitChoice(campaign, actionId: 'step_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).coordinator.state.stateHash, direct.state.stateHash);
      } finally { db.close(); }
    } finally { await dir.delete(recursive: true); }
  });

  test('incomplete acts, counterfeit identities, invented canon and backwards story dependencies never become a plan', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (v) => (v['acts'] as List).removeLast(), (v) => v['canon_verified'] = true,
      (v) => (v['motivations'] as List).first['character_id'] = 'npc_invented',
      (v) => (v['motivations'] as List).clear(),
      (v) => (v['acts'] as List).first['proposal']['setup_event_id'] = 'invented_event',
      (v) => (v['links'] as List).first['from_act_id'] = context.bookMap.acts.last.id,
      (v) => (v['links'] as List).first['required_outcome'] = 'any',
      (v) => (v['acts'] as List).first['proposal']['effects'] = ['teleport'],
    ];
    for (final mutate in mutations) {
      // Decoding gives real untrusted JSON types. A typed Map<String,String>
      // fixture must not throw BEFORE the parser sees a malicious List value.
      final raw = jsonDecode(jsonEncode(answer(context))) as Map<String, dynamic>;
      mutate(raw);
      expect(() => UnifiedBookStoryDraft.parse(context, jsonEncode(raw)), throwsFormatException);
    }
    final draft = UnifiedBookStoryDraft.parse(context, jsonEncode(answer(context)));
    expect(() => draft.accept(context: context, freshRoles: context.roles,
      approvedReviewDigest: draft.reviewDigest, allShownQuotesAndStoryReviewed: false,
      fictionalConsequencesConfirmed: true), throwsFormatException);
    expect(() => draft.accept(context: context, freshRoles: const [],
      approvedReviewDigest: draft.reviewDigest, allShownQuotesAndStoryReviewed: true,
      fictionalConsequencesConfirmed: true), throwsFormatException);
  });

  test('one consent covers identical bounded retries; a saved complete storyline reopens without another API call', () async {
    final repo = MemorySourceAnalysisCheckpointRepository(), store = UnifiedBookStoryStore(repository: repo);
    final transport = Transport((body, count) async => count == 1
      ? const AiHttpResponse(429, '{}', retryAfter: '0') : response(answer(context)));
    final service = ZaiUnifiedBookStory(preferences: Prefs(), vault: Vault(), transport: transport, retryWait: (_) async {});
    final saved = await service.generate(context: context, store: store,
      approvedDigest: context.approvalDigest, explicitCloudConsent: true, loadCurrentRoles: () async => context.roles);
    expect(transport.bodies, hasLength(2)); expect(transport.bodies.toSet(), hasLength(1));
    final sent = jsonDecode(transport.bodies.first) as Map;
    expect((sent['messages'] as List).last['content'], context.shownText);
    final reopened = await UnifiedBookStoryStore(repository: repo).load(context);
    expect(reopened.draft!.reviewDigest, saved.draft!.reviewDigest);
    expect(reopened.cloudConsent, false); expect(reopened.consequencesApproved, false);
    expect(reopened.draft!.canInstallDirectly, false);
    await service.generate(context: context, store: store, approvedDigest: context.approvalDigest,
      explicitCloudConsent: true, loadCurrentRoles: () async => context.roles);
    expect(transport.bodies, hasLength(2));
    final bytes = await repo.read(context.storageKey);
    expect(bytes, isNot(contains('not-a-real-key')));
    expect(bytes, isNot(contains(context.book.events.first.source.quote)));
  });

  test('no request without exact permission enabled account key and current characters', () async {
    final store = UnifiedBookStoryStore(repository: MemorySourceAnalysisCheckpointRepository());
    final prefs = Prefs()..enabled = false, vault = Vault();
    final transport = Transport((_, __) async => response(answer(context)));
    final service = ZaiUnifiedBookStory(preferences: prefs, vault: vault, transport: transport);
    Future<UnifiedStoryCheckpoint> run({bool consent = true, String? digest}) => service.generate(
      context: context, store: store, approvedDigest: digest ?? context.approvalDigest,
      explicitCloudConsent: consent, loadCurrentRoles: () async => context.roles);
    await expectLater(run(consent: false), throwsA(isA<AiSetupException>()));
    await expectLater(run(digest: 'wrong'), throwsA(isA<AiSetupException>()));
    await expectLater(run(), throwsA(isA<AiSetupException>()));
    prefs.enabled = true; vault.key = null;
    await expectLater(run(), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty); expect((await store.load(context)).draft, isNull);
  });

  test('source card change during retry blocks another POST; cancellation and bad JSON never persist progress', () async {
    final store = UnifiedBookStoryStore(repository: MemorySourceAnalysisCheckpointRepository());
    var roles = context.roles;
    final transport = Transport((_, __) async => const AiHttpResponse(429, '{}', retryAfter: '0'));
    final service = ZaiUnifiedBookStory(preferences: Prefs(), vault: Vault(), transport: transport,
      retryWait: (_) async { roles = []; });
    await expectLater(service.generate(context: context, store: store,
      approvedDigest: context.approvalDigest, explicitCloudConsent: true,
      loadCurrentRoles: () async => roles), throwsFormatException);
    expect(transport.bodies, hasLength(1));
    final token = ZaiPreviewCancellation()..cancel();
    await expectLater(service.generate(context: context, store: store,
      approvedDigest: context.approvalDigest, explicitCloudConsent: true,
      loadCurrentRoles: () async => context.roles, cancellation: token), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, hasLength(1));
    final bad = Transport((_, __) async => response({'applicable': true, 'canon_verified': true}));
    await expectLater(ZaiUnifiedBookStory(preferences: Prefs(), vault: Vault(), transport: bad).generate(
      context: context, store: store, approvedDigest: context.approvalDigest,
      explicitCloudConsent: true, loadCurrentRoles: () async => context.roles), throwsFormatException);
    expect((await store.load(context)).draft, isNull);
  });

  test('in-flight duplicate, write failure and corruption preserve a complete saved draft rather than re-paying silently', () async {
    final repo = MemorySourceAnalysisCheckpointRepository(), store = UnifiedBookStoryStore(repository: repo);
    final draft = UnifiedBookStoryDraft.parse(context, jsonEncode(answer(context)));
    repo.failNextWrite = true;
    await expectLater(store.save(context: context, draft: draft, expectedRecordHash: null), throwsA(isA<FileSystemException>()));
    expect((await store.load(context)).draft, isNull);
    final started = Completer<void>(), delayed = Completer<AiHttpResponse>();
    final transport = Transport((_, __) { started.complete(); return delayed.future; });
    final service = ZaiUnifiedBookStory(preferences: Prefs(), vault: Vault(), transport: transport);
    final pending = service.generate(context: context, store: store,
      approvedDigest: context.approvalDigest, explicitCloudConsent: true, loadCurrentRoles: () async => context.roles);
    await started.future;
    await expectLater(service.generate(context: context, store: store,
      approvedDigest: context.approvalDigest, explicitCloudConsent: true,
      loadCurrentRoles: () async => context.roles), throwsA(isA<AiSetupException>()));
    delayed.complete(response(answer(context)));
    final saved = await pending, bytes = await repo.read(context.storageKey);
    await expectLater(store.save(context: context, draft: draft, expectedRecordHash: null), throwsFormatException);
    expect(await repo.read(context.storageKey), bytes);
    final envelope = jsonDecode(bytes!) as Map<String, dynamic>;
    (envelope['payload'] as Map)['approved_for_install'] = true;
    envelope['sha256'] = unifiedStoryHash(envelope['payload']);
    await repo.write(context.storageKey, jsonEncode(envelope));
    await expectLater(store.load(context), throwsFormatException);
    expect(saved.consequencesApproved, false); expect(transport.bodies, hasLength(1));
  });

  testWidgets('whole-story review restores offline at phone width and cannot return gameplay consequences without both fresh approvals', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = UnifiedBookStoryStore(repository: MemorySourceAnalysisCheckpointRepository());
    await store.save(context: context, draft: UnifiedBookStoryDraft.parse(context, jsonEncode(answer(context))), expectedRecordHash: null);
    final transport = Transport((_, __) async => throw StateError('No cloud request is authorized'));
    MultiActStoryPlanDraft? accepted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UnifiedBookStoryPanel(
      index: context.index, book: context.book, bookMap: context.bookMap,
      roleCatalog: Roles(context.roles), store: store,
      gateway: ZaiUnifiedBookStory(preferences: Prefs(), vault: Vault(), transport: transport),
      onAccepted: (draft) => accepted = draft))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-story-goal')), findsOneWidget);
    for (final key in ['unified-story-review', 'unified-story-fiction']) {
      final control = find.byKey(Key(key));
      await tester.scrollUntilVisible(control, 160, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(control), alignment: 0.5);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(control).value, false); expect(accepted, isNull);
      await tester.tap(control); await tester.pump();
      expect(tester.widget<CheckboxListTile>(control).value, true);
    }
    final button = find.byKey(const Key('unified-story-accept'));
    await tester.ensureVisible(button); await tester.pump();
    await tester.tap(button); await tester.pumpAndSettle();
    expect(accepted, isNotNull);
    expect(accepted!.toDiagnosticJson()['enforced_story_links'], 2);
    expect(transport.bodies, isEmpty); expect(tester.takeException(), isNull);
  });
}
