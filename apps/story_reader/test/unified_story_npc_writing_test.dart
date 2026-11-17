import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/bookwide_unified_story.dart';
import 'package:ai_story_reader/npc_campaign_consequences.dart';
import 'package:ai_story_reader/npc_campaign_writing_session.dart';
import 'package:ai_story_reader/npc_inventory_writing_context.dart';
import 'package:ai_story_reader/npc_writing_consent_dialog.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/reviewed_story_narrative.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
import 'package:ai_story_reader/zai_npc_campaign_writing.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/zai_unified_book_story.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

// Reuse the same source-reviewed synthetic book, not a second toy engine.
import 'unified_book_story_test.dart' as original;

class _Author {
  _Author._(this.context, this.repo, this.storyStore, this.proposal)
      : roles = [...context.roles];
  final UnifiedBookStoryContext context;
  final MemorySourceAnalysisCheckpointRepository repo;
  final UnifiedBookStoryStore storyStore;
  final UnifiedBookStoryDraft proposal;
  List<ReviewedHeroRole> roles;
  late final ReviewedStoryNarrative accepted;
  late final WholeBookNpcSourcePlan source;
  late final NpcWritingCatalog catalog;
  NpcWritingStore get writing => NpcWritingStore(repository: repo);

  static Future<_Author> create(UnifiedBookStoryContext context,
      {MemorySourceAnalysisCheckpointRepository? repository,
       void Function(Map<String, dynamic>)? change}) async {
    final repo = repository ?? MemorySourceAnalysisCheckpointRepository();
    final raw = jsonDecode(jsonEncode(original.answer(context))) as Map<String, dynamic>;
    for (final motive in raw['motivations'] as List) {
      final role = context.roles.singleWhere((r) => r.characterId == motive['character_id']);
      motive['goal'] = 'Авторский мотив персонажа ${role.displayName}: помочь восстановить маяк без чужих обещаний.';
    }
    change?.call(raw);
    final proposal = UnifiedBookStoryDraft.parse(context, jsonEncode(raw));
    final store = UnifiedBookStoryStore(repository: repo);
    final old = await store.load(context);
    final saved = await store.save(context: context, draft: proposal, expectedRecordHash: old.recordHash);
    final result = _Author._(context, repo, store, proposal);
    Future<void> verify() async {
      context.verifyCurrent(result.roles);
      final current = await store.load(context);
      if (current.recordHash != saved.recordHash || current.draft?.reviewDigest != proposal.reviewDigest) {
        throw const FormatException('Общий сюжет изменён в другом окне.');
      }
    }
    result.accepted = ReviewedStoryNarrative.accept(context: context, proposal: proposal,
      freshRoles: result.roles, approvedReviewDigest: proposal.reviewDigest,
      allShownQuotesAndStoryReviewed: true, fictionalConsequencesConfirmed: true,
      verifySavedRevision: verify);
    result.source = WholeBookNpcSourcePlan.fromBook(index: context.index, book: context.book,
      bookMap: context.bookMap, draft: result.accepted,
      selectedHeroRole: context.roles.singleWhere((r) => r.displayName == 'Артем'));
    result.catalog = NpcWritingCatalog(source: result.source,
      candidates: BookwideNpcCampaignAuthoring.discover(source: result.source, currentReviewedRoles: result.roles));
    return result;
  }

  Future<NpcWritingSession> select() => writing.save(catalog, expectedRevision: 0,
    edits: [for (final c in catalog.candidates.values) NpcWritingEdit(id: c.id)]);

  Future<void> changeSavedStory() async {
    final raw = jsonDecode(proposal.responseJson) as Map<String, dynamic>;
    raw['central_conflict'] = 'Новая авторская редакция конфликта: помощь требует иного объяснения, а не старого согласия.';
    final current = await storyStore.load(context);
    await storyStore.save(context: context, draft: UnifiedBookStoryDraft.parse(context, jsonEncode(raw)),
      expectedRecordHash: current.recordHash);
  }

  Future<void> guard(NpcWritingSession expected) async {
    source.verifyCurrentHero(roles);
    expect((await writing.load(catalog)).snapshotDigest, expected.snapshotDigest);
  }
}

Map<String, dynamic> _payload(String body) => jsonDecode(
    (jsonDecode(body) as Map)['messages'].last['content'] as String) as Map<String, dynamic>;

AiHttpResponse _dialogue(String body, {bool forged = false}) {
  final payload = _payload(body);
  return original.response({
    'batch_id': payload['batch_id'],
    'proposals': [for (final c in payload['conversations'] as List) {
      'candidate_id': c['candidate_id'], 'actor_id': c['actor_id'],
      'player_line': 'Поговорим о том, как продолжить путь к маяку.',
      'npc_line': 'Я готов обсудить помощь, не считая чужое обещание выполненным.',
      'uncertainty': 'Автор проверяет соответствие замыслу и всем доступным путям.',
      if (forged) 'effects': [{'op': 'learn_fact', 'id': 'invented_motive'}],
    }],
    'skipped': [],
  });
}
ZaiNpcCampaignWriting _writer(original.Transport transport,
    {Future<void> Function(Duration)? wait}) => ZaiNpcCampaignWriting(
      preferences: original.Prefs(), vault: original.Vault(), transport: transport,
      retryWait: wait ?? (_) async {});

Future<Uint8List> _items(_Author a) async {
  final source = a.source;
  final base = await source.compileBase(approvedPlanDigest: source.planDigest,
    approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
  final manifest = WholePlanGameplayBatchManifest.fromPlan(index: source.index,
    book: source.book, plan: source.plan, maxNewRequestsPerRun: 2);
  final drafts = [for (final ctx in manifest.contexts) GameplayCandidateDraft(
    sourceFingerprint: ctx.sourceFingerprint, approvalDigest: ctx.approvalDigest,
    candidates: [for (final c in ctx.choices)
      if (c.choiceId == 'act_1_accept_offer' || c.choiceId == 'act_1_honor_condition')
        GameplayCandidate(kind: 'item', id: 'source_key', label: 'ключ',
          op: c.choiceId == 'act_1_accept_offer' ? 'grant_item' : 'consume_item',
          sceneId: c.sceneId, choiceId: c.choiceId, sourceEventId: c.sourceEventId,
          uncertainty: 'Авторская игровая трактовка исходного ключа.')])];
  final preview = NpcCampaignConsequences.preview(source: source, originalArchive: base.archive,
    currentReviewedRoles: a.roles, manifest: manifest, proposals: drafts,
    selectedUserReviewNotes: {for (final d in drafts) for (final c in d.candidates)
      ReviewedGameplayCompiler.signature(c): 'Получение и расходование ключа одобрены для частной истории.'});
  final accepted = await NpcCampaignConsequences.accept(source: source, preview: preview,
    originalArchive: base.archive, freshReviewedRoles: a.roles,
    approvedDigest: preview.approvalDigest, explicitlyConfirmedPrivateFiction: true);
  return accepted.archiveFor(source: source, originalArchive: base.archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UnifiedBookStoryContext context;
  setUpAll(() async { context = await original.fixture(); });

  test('shown conversation carries accepted goal, relevant motive and conditional act intent, not other actor knowledge', () async {
    final a = await _Author.create(context), state = await a.select();
    final request = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1);
    expect(request.hasStoryContext, true); expect(request.candidateCount, 2);
    for (final encoded in request.batches) {
      final data = jsonDecode(encoded) as Map;
      expect(data['accepted_story_context']['campaign_goal'], a.proposal.goal);
      expect(data['accepted_story_context']['imports_actor_knowledge'], false);
      final c = (data['conversations'] as List).single as Map;
      final guide = c['story_guidance'] as Map;
      expect(guide['character_id'], c['actor_id']);
      expect(guide['motive_status'], 'REVIEWED_FICTION_NOT_KNOWLEDGE');
      for (final m in a.proposal.motivations) {
        expect(encoded, m.characterId == c['actor_id'] ? contains(m.goal) : isNot(contains(m.goal)));
      }
      expect(guide['first_act']['conditional_links'].single['prior_outcome_has_occurred'], 'UNKNOWN_FOR_THIS_DIALOGUE');
      expect(guide['first_act']['conditional_links'].single['grants_npc_knowledge'], false);
      expect(encoded, isNot(contains('original_ending')));
      expect(encoded, isNot(contains(context.index.title)));
      expect(utf8.encode(encoded).length, lessThanOrEqualTo(10 * 1024));
    }
    final changedCopy = a.accepted.cloudHeader..['campaign_goal'] = 'mutated';
    expect(changedCopy['campaign_goal'], 'mutated');
    expect(a.accepted.cloudHeader['campaign_goal'], a.proposal.goal);
  });

  test('motive-only edit keeps mechanics but isolates old manual writing and revokes final approval', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final old = await _Author.create(context, repository: repo);
    final state = await old.select();
    await old.writing.save(old.catalog, expectedRevision: state.revision, edits: [
      for (final c in old.catalog.candidates.values) NpcWritingEdit(id: c.id,
        playerLine: 'Сохранённая ручная реплика героя.', npcLine: 'Сохранённый ручной ответ собеседника.')]);
    final oldBytes = await repo.read(old.catalog.storageKey);
    final newer = await _Author.create(context, repository: repo, change: (raw) {
      (raw['motivations'] as List).first['reason'] = 'Изменённое авторское объяснение цели, не новое игровое действие.';
    });
    expect(newer.source.planDigest, old.source.planDigest);
    expect(newer.catalog.digest, isNot(old.catalog.digest));
    expect(newer.catalog.storageKey, isNot(old.catalog.storageKey));
    expect((await newer.writing.load(newer.catalog)).edits, isEmpty);
    expect(await repo.read(old.catalog.storageKey), oldBytes);
    await expectLater(old.accepted.verifyLive(), throwsFormatException);
    await newer.accepted.verifyLive();
    final base = await newer.source.compileBase(approvedPlanDigest: newer.source.planDigest,
      approvedHeroDigest: newer.source.heroReviewDigest, allShownQuotesReviewed: true, privateFictionConfirmed: true);
    final lines = (await old.writing.load(old.catalog)).edits.values.map((e) => e.toDraft()).toList();
    final previousApproval = BookwideNpcCampaignAuthoring.review(source: old.source,
      verifiedBaseArchive: base.archive, currentReviewedRoles: old.roles, selectedDrafts: lines);
    final currentApproval = BookwideNpcCampaignAuthoring.review(source: newer.source,
      verifiedBaseArchive: base.archive, currentReviewedRoles: newer.roles, selectedDrafts: lines);
    expect(currentApproval.reviewJson, previousApproval.reviewJson);
    expect(currentApproval.approvalDigest, isNot(previousApproval.approvalDigest));
    await expectLater(BookwideNpcCampaignAuthoring.compile(source: newer.source, approval: previousApproval,
      freshReviewedRoles: newer.roles, approvedDigest: previousApproval.approvalDigest,
      explicitlyConfirmedPrivateFiction: true), throwsFormatException);
    await expectLater(BookwideNpcCampaignAuthoring.compile(source: old.source, approval: previousApproval,
      freshReviewedRoles: old.roles, approvedDigest: previousApproval.approvalDigest,
      explicitlyConfirmedPrivateFiction: true), throwsFormatException);
  });

  test('a later textual basis withholds the whole motive without leaking future hypothesis or actor secrets', () async {
    final target = context.roles.singleWhere((r) => r.displayName == 'Борис');
    const hidden = 'Будущий мотив Бориса нельзя сообщать из более позднего события.';
    final a = await _Author.create(context, change: (raw) {
      final motive = (raw['motivations'] as List).singleWhere((m) => m['character_id'] == target.characterId);
      motive['goal'] = hidden;
      motive['source_event_ids'] = [context.book.events.last.id];
    });
    final state = await a.select();
    final request = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1);
    final batch = request.batches.singleWhere((raw) =>
      ((jsonDecode(raw) as Map)['conversations'] as List).single['actor_id'] == target.characterId);
    final guide = (jsonDecode(batch) as Map)['conversations'].single['story_guidance'] as Map;
    expect(guide['motive_status'], 'WITHHELD_FUTURE_SOURCE_BASIS');
    expect(guide.containsKey('motive'), false); expect(batch, isNot(contains(hidden)));
  });

  test('legacy per-act writing preserves storage and payload shape without silently injecting a story', () async {
    final proposal = UnifiedBookStoryDraft.parse(context, jsonEncode(original.answer(context)));
    final oldPlan = proposal.accept(context: context, freshRoles: context.roles,
      approvedReviewDigest: proposal.reviewDigest, allShownQuotesAndStoryReviewed: true,
      fictionalConsequencesConfirmed: true);
    final source = WholeBookNpcSourcePlan.fromBook(index: context.index, book: context.book,
      bookMap: context.bookMap, draft: oldPlan);
    final catalog = NpcWritingCatalog(source: source,
      candidates: BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: context.roles));
    expect(catalog.storageKey, npcWritingHash({'scope': 'npc_authoring_v1',
      'source': source.index.sourceFingerprint, 'plan': source.planDigest}));
    final store = NpcWritingStore(repository: MemorySourceAnalysisCheckpointRepository());
    final saved = await store.save(catalog, expectedRevision: 0,
      edits: [NpcWritingEdit(id: catalog.candidates.keys.first)]);
    final request = NpcWritingRequest.prepare(catalog, saved);
    expect(request.hasStoryContext, false);
    final payload = jsonDecode(request.batches.single) as Map;
    expect(payload.keys.toSet(), {'format', 'status', 'conversations', 'batch_id'});
    expect(payload['conversations'].single.containsKey('story_guidance'), false);
  });

  test('narrative disclosure requires exact new consent and an author revision guard', () async {
    final a = await _Author.create(context), state = await a.select();
    final request = NpcWritingRequest.prepare(a.catalog, state);
    final transport = original.Transport((body, _) async => _dialogue(body));
    Future<NpcWritingSession> run({bool consent = true, bool guard = true, String? digest}) =>
      _writer(transport).generate(catalog: a.catalog, store: a.writing, request: request,
        approvedDigest: digest ?? request.approvalDigest, explicitCloudConsent: consent,
        verifyAuthorRevision: guard ? a.guard : null);
    await expectLater(run(consent: false), throwsA(isA<AiSetupException>()));
    await expectLater(run(guard: false), throwsA(isA<AiSetupException>()));
    await expectLater(run(digest: 'stale'), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty);
    expect((await a.writing.load(a.catalog)).snapshotDigest, state.snapshotDigest);
  });

  test('story mutation during retry revokes the next POST; mutation or revoked cast during response preserves exact writing bytes', () async {
    final a = await _Author.create(context), state = await a.select();
    final request = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1);
    final retry = original.Transport((_, __) async => const AiHttpResponse(429, '{}', retryAfter: '0'));
    await expectLater(_writer(retry, wait: (_) => a.changeSavedStory()).generate(
      catalog: a.catalog, store: a.writing, request: request, approvedDigest: request.approvalDigest,
      explicitCloudConsent: true, verifyAuthorRevision: a.guard), throwsFormatException);
    expect(retry.bodies, hasLength(1));
    for (final revokeCast in [false, true]) {
      final b = await _Author.create(context), saved = await b.select();
      final req = NpcWritingRequest.prepare(b.catalog, saved, perRequest: 1);
      final before = await b.repo.read(b.catalog.storageKey);
      final started = Completer<String>(), response = Completer<AiHttpResponse>();
      final delayed = original.Transport((body, _) { started.complete(body); return response.future; });
      final pending = _writer(delayed).generate(catalog: b.catalog, store: b.writing,
        request: req, approvedDigest: req.approvalDigest, explicitCloudConsent: true,
        verifyAuthorRevision: (_) async {});
      final failed = expectLater(pending, throwsFormatException);
      final body = await started.future;
      if (revokeCast) { b.roles = []; } else { await b.changeSavedStory(); }
      response.complete(_dialogue(body)); await failed;
      expect(delayed.bodies, hasLength(1));
      expect(await b.repo.read(b.catalog.storageKey), before);
    }
  });

  test('accepted narrative and real inventory survive retry/resume, compose one offline game and SQLite restart', () async {
    final a = await _Author.create(context), state = await a.select();
    final archive = await _items(a);
    final inventory = await NpcInventoryWritingContext.prepare(source: a.source,
      reviewedArchive: archive, conversations: a.catalog.candidates.values);
    final request = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1, inventoryContext: inventory);
    final transport = original.Transport((body, count) async => count == 1
      ? const AiHttpResponse(429, '{}', retryAfter: '0') : _dialogue(body));
    final token = ZaiPreviewCancellation();
    await expectLater(_writer(transport).generate(catalog: a.catalog, store: a.writing,
      request: request, approvedDigest: request.approvalDigest, explicitCloudConsent: true,
      verifyAuthorRevision: a.guard, cancellation: token,
      onSaved: (_) async => token.cancel()), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, hasLength(2)); expect(transport.bodies.toSet(), hasLength(1));
    expect((jsonDecode(transport.bodies.first) as Map)['messages'].last['content'], request.batches.first);
    final sent = _payload(transport.bodies.first);
    expect(sent['accepted_story_context']['review_digest'], a.proposal.reviewDigest);
    expect(sent['inventory_context']['grants_npc_knowledge'], false);
    expect(sent['conversations'].single['player_inventory_routes']['first_scene']['never_present'], contains('source_key'));
    final restored = await a.writing.load(a.catalog);
    expect(restored.edits.values.where((e) => e.complete), hasLength(1));
    final resume = NpcWritingRequest.prepare(a.catalog, restored, perRequest: 1, inventoryContext: inventory);
    expect(resume.candidateCount, 1);
    final rest = original.Transport((body, _) async => _dialogue(body));
    final completed = await _writer(rest).generate(catalog: a.catalog, store: a.writing,
      request: resume, approvedDigest: resume.approvalDigest, explicitCloudConsent: true,
      verifyAuthorRevision: a.guard);
    expect(rest.bodies, hasLength(1));
    expect(completed.canInstallDirectly, false);
    expect(completed.edits.values.every((e) => e.complete), true);
    final review = BookwideNpcCampaignAuthoring.review(source: a.source, verifiedBaseArchive: archive,
      currentReviewedRoles: a.roles, selectedDrafts: completed.edits.values.map((e) => e.toDraft()).toList());
    expect(review.storyReviewDigest, a.proposal.reviewDigest);
    final built = await BookwideNpcCampaignAuthoring.compile(source: a.source, approval: review,
      freshReviewedRoles: a.roles, approvedDigest: review.approvalDigest, explicitlyConfirmedPrivateFiction: true);
    final game = const RichPrivateBookworldImporter().inspect(built.archive);
    expect(game.requiresNetwork, false);
    final candidates = BookwideNpcCampaignAuthoring.discover(source: a.source, currentReviewedRoles: a.roles);
    final path = <String>['act_1_pass_source', 'act_1_pass_source_2', 'act_1_accept_offer',
      'act_1_honor_condition', 'act_1_continue_original'];
    for (var i = 0; i < candidates.length; i++) {
      path.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(candidates[i].id),
        ReviewedNpcCampaignBookworldWriter.replyChoiceId(candidates[i].id),
        'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
      if (i == 0) path.add('act_2_continue_original');
    }
    final direct = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
    for (var i = 0; i < path.length; i++) {
      expect(direct.apply(actionId: 'narrative_$i', choiceId: path[i], expectedRevision: i).applied, true, reason: path[i]);
    }
    expect(direct.isTerminal, true); expect(direct.state.inventory, isEmpty);
    expect(direct.state.knowledge['player'], isEmpty);
    for (final c in candidates) {
      expect(direct.state.knowledge[c.role.characterId], {ReviewedNpcCampaignBookworldWriter.factId(c.id)});
      expect(game.blueprint.scenes[c.responseSceneId]!.text, contains(completed.edits[c.id]!.npcLine));
    }
    final dir = await Directory.systemTemp.createTemp('story_dialogue_sqlite_');
    late String id;
    try {
      var db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        id = db.createCampaign(db.installBookworld(built.archive).archiveHash);
        for (var i = 0; i < 3; i++) {
          expect(db.commitChoice(id, actionId: 'narrative_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try {
        expect(db.loadCampaign(id).coordinator.state.inventory, {'source_key'});
        for (var i = 3; i < path.length; i++) {
          expect(db.commitChoice(id, actionId: 'narrative_$i', choiceId: path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(id).coordinator.state.stateHash, direct.state.stateHash);
      } finally { db.close(); }
    } finally { await dir.delete(recursive: true); }
  });

  test('a story-guided model still cannot supply executable effects or write over a manual line', () async {
    final a = await _Author.create(context), state = await a.select();
    final req = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1);
    final bad = original.Transport((body, _) async => _dialogue(body, forged: true));
    await expectLater(_writer(bad).generate(catalog: a.catalog, store: a.writing,
      request: req, approvedDigest: req.approvalDigest, explicitCloudConsent: true,
      verifyAuthorRevision: a.guard), throwsA(isA<AiSetupException>()));
    expect((await a.writing.load(a.catalog)).snapshotDigest, state.snapshotDigest);
    final first = a.catalog.candidates.keys.first;
    final manual = await a.writing.save(a.catalog, expectedRevision: state.revision,
      edits: [for (final c in a.catalog.candidates.values)
        NpcWritingEdit(id: c.id, playerLine: c.id == first ? 'Сохранить ручной замысел автора.' : '')]);
    final remaining = NpcWritingRequest.prepare(a.catalog, manual, perRequest: 1);
    expect(remaining.candidateCount, 1);
    expect(remaining.batches.single, isNot(contains('Сохранить ручной замысел автора.')));
    final good = original.Transport((body, _) async => _dialogue(body));
    final saved = await _writer(good).generate(catalog: a.catalog, store: a.writing,
      request: remaining, approvedDigest: remaining.approvalDigest, explicitCloudConsent: true,
      verifyAuthorRevision: a.guard);
    expect(saved.edits[first]!.playerLine, manual.edits[first]!.playerLine);
  });

  testWidgets('phone consent exposes the same story data and never restores approval', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = await _Author.create(context), state = await a.select();
    final request = NpcWritingRequest.prepare(a.catalog, state, perRequest: 1);
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await showDialog<bool>(context: ctx, builder: (_) => NpcWritingConsentDialog(
          request: request, heroName: a.source.heroName));
      }, child: const Text('Показать согласие'))))));
    await tester.tap(find.text('Показать согласие')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('npc-writing-story-summary')), findsOneWidget);
    final payload = find.byKey(const Key('npc-writing-exact-payload'));
    await tester.ensureVisible(payload); await tester.pump();
    await tester.tap(payload); await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('npc-writing-shown-bytes'))).data, request.shownText);
    final consent = find.byKey(const Key('npc-writing-cloud-consent'));
    await tester.ensureVisible(consent); await tester.pump();
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    expect(tester.widget<FilledButton>(find.byKey(const Key('npc-writing-cloud-send'))).onPressed, isNull);
    await tester.tap(find.text('Отмена')); await tester.pumpAndSettle();
    expect(result, false); expect((await a.writing.load(a.catalog)).snapshotDigest, state.snapshotDigest);
    expect(tester.takeException(), isNull);
  });
}
