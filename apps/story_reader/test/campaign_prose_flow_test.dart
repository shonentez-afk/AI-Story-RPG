import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/bookwide_unified_story.dart';
import 'package:ai_story_reader/campaign_prose_authoring.dart';
import 'package:ai_story_reader/campaign_prose_page.dart';
import 'package:ai_story_reader/npc_campaign_consequences.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
import 'package:ai_story_reader/reviewed_story_narrative.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/whole_plan_gameplay_candidate_batch.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_campaign_prose_writer.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:bookworld_format/src/zip_v1.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

// Reuse the existing whole-story fixture; its main() is not invoked here.
import 'unified_book_story_test.dart' as story;

class _Fixture {
  _Fixture(this.source, this.archive, this.npcs);
  final WholeBookNpcSourcePlan source;
  final Uint8List archive;
  final List<BookwideNpcConversationCandidate> npcs;
  Future<CampaignProseManifest> manifest({Future<void> Function()? guard}) =>
      CampaignProseManifest.prepare(source: source, finalArchive: archive,
          verifyCurrent: guard ?? () async {});
  List<String> get path {
    final result = ['act_1_pass_source', 'act_1_pass_source_2',
      'act_1_accept_offer', 'act_1_honor_condition', 'act_1_continue_original'];
    for (var i = 0; i < npcs.length; i++) {
      result.addAll([ReviewedNpcCampaignBookworldWriter.meetChoiceId(npcs[i].id),
        ReviewedNpcCampaignBookworldWriter.replyChoiceId(npcs[i].id),
        'act_${i + 2}_accept_offer', 'act_${i + 2}_honor_condition']);
      if (i == 0) result.add('act_2_continue_original');
    }
    return result;
  }
}

Future<_Fixture> _fixture() async {
  final context = await story.fixture();
  final proposal = UnifiedBookStoryDraft.parse(context, jsonEncode(story.answer(context)));
  final narrative = ReviewedStoryNarrative.accept(context: context, proposal: proposal,
    freshRoles: context.roles, approvedReviewDigest: proposal.reviewDigest,
    allShownQuotesAndStoryReviewed: true, fictionalConsequencesConfirmed: true,
    verifySavedRevision: () async {});
  final source = WholeBookNpcSourcePlan.fromBook(index: context.index,
    book: context.book, bookMap: context.bookMap, draft: narrative,
    selectedHeroRole: context.roles.singleWhere((r) => r.displayName == 'Артем'));
  final base = await source.compileBase(approvedPlanDigest: source.planDigest,
    approvedHeroDigest: source.heroReviewDigest, allShownQuotesReviewed: true,
    privateFictionConfirmed: true);
  final manifest = WholePlanGameplayBatchManifest.fromPlan(index: source.index,
    book: source.book, plan: source.plan, maxNewRequestsPerRun: 2);
  final proposals = [for (final ctx in manifest.contexts) GameplayCandidateDraft(
    sourceFingerprint: ctx.sourceFingerprint, approvalDigest: ctx.approvalDigest,
    candidates: [for (final c in ctx.choices)
      if (c.choiceId == 'act_1_accept_offer' || c.choiceId == 'act_3_honor_condition')
        GameplayCandidate(kind: 'item', id: 'source_key', label: 'ключ',
          op: c.choiceId == 'act_1_accept_offer' ? 'grant_item' : 'consume_item',
          sceneId: c.sceneId, choiceId: c.choiceId, sourceEventId: c.sourceEventId,
          uncertainty: 'Автор проверяет частное игровое использование ключа.')])];
  final preview = NpcCampaignConsequences.preview(source: source,
    originalArchive: base.archive, currentReviewedRoles: context.roles,
    manifest: manifest, proposals: proposals,
    selectedUserReviewNotes: {for (final p in proposals) for (final c in p.candidates)
      ReviewedGameplayCompiler.signature(c): 'Ключ переносится между частями и расходуется только на проверенном пути.'});
  final effects = await NpcCampaignConsequences.accept(source: source, preview: preview,
    originalArchive: base.archive, freshReviewedRoles: context.roles,
    approvedDigest: preview.approvalDigest, explicitlyConfirmedPrivateFiction: true);
  final npcs = BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: context.roles);
  final review = BookwideNpcCampaignAuthoring.review(source: source,
    verifiedBaseArchive: effects.archiveFor(source: source, originalArchive: base.archive),
    currentReviewedRoles: context.roles,
    selectedDrafts: [for (final npc in npcs) NpcCampaignDialogueDraft(candidateId: npc.id,
      playerLine: 'Обсудим дальнейший путь к маяку.',
      npcLine: 'Я помню нашу отдельную игровую встречу у ворот.')]);
  final built = await BookwideNpcCampaignAuthoring.compile(source: source, approval: review,
    freshReviewedRoles: context.roles, approvedDigest: review.approvalDigest,
    explicitlyConfirmedPrivateFiction: true);
  return _Fixture(source, built.archive, npcs);
}

String _prose(String id) => 'Ветер с моря приносил запах соли, и стены маяка '
    'выступали из тумана всё отчётливее. Герой внимательно оглядел дорогу, '
    'стараясь не принимать надежду за уже исполненное решение. '
    'Контрольный эпизод содержит ${id.length} знаков в своём внутреннем обозначении.';
const _uncertainty = 'Синтетический текст для проверки механики, не литературный канон.';
Map<String, dynamic> _answer(String body) {
  final sent = jsonDecode(body) as Map;
  final batch = jsonDecode((sent['messages'] as List).last['content'] as String) as Map;
  return {'batch_id': batch['batch_id'], 'scenes': [for (final scene in batch['scenes'] as List)
    {'scene_id': scene['scene_id'], 'prose': _prose(scene['scene_id'] as String),
     'uncertainty': _uncertainty}]};
}
AiHttpResponse _response(Object value) => AiHttpResponse(200, jsonEncode({
  'choices': [{'finish_reason': 'stop', 'message': {'content': jsonEncode(value)}}],
}));
ZaiCampaignProse _service(story.Transport transport, {Future<void> Function(Duration)? wait}) =>
    ZaiCampaignProse(preferences: story.Prefs(), vault: story.Vault(),
      transport: transport, retryWait: wait ?? (_) async {});

Map<String, dynamic> _blueprint(Uint8List bytes) => jsonDecode(utf8.decode(
    BworldZipV1.readPrivate(bytes)['scenario/blueprint.json']!)) as Map<String, dynamic>;

Future<CampaignProseSession> _manual(CampaignProseManifest m, CampaignProseStore store) async =>
    store.save(manifest: m, expected: await store.load(m), entries: [for (final id in m.sceneIds)
      CampaignProseEntry(sceneId: id, text: _prose(id), uncertainty: _uncertainty)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUpAll(() async { f = await _fixture(); });

  test('all compiled scenes and both endings have exact story and final inventory contexts without hidden NPC speech', () async {
    final m = await f.manifest();
    final game = const RichPrivateBookworldImporter().inspect(f.archive);
    expect(m.sceneIds.toSet(), game.blueprint.scenes.keys.toSet());
    expect(m.contexts.values.where((c) => c['terminal'] == true), hasLength(2));
    final first = m.contexts['act_1_turning_point'] as Map;
    expect(first['player_inventory']['never_present'], contains('source_key'));
    expect(m.contexts['act_1_accept_path']['player_inventory']['always_present'], contains('source_key'));
    expect(m.contexts[f.npcs.first.firstSceneId]['player_inventory']['branch_dependent'], contains('source_key'));
    expect(m.contexts['act_3_original_ending']['player_inventory']['never_present'], contains('source_key'));
    expect(m.contextsJson, contains(f.source.narrative!.proposal.goal));
    expect(m.contextsJson, isNot(contains('Я помню нашу отдельную игровую встречу')));
    expect(m.contextsJson, isNot(contains('not-a-real-key')));
    final copy = m.originalArchive; copy[0] = 0;
    expect(sha256.convert(m.originalArchive).toString(), m.archiveSha256);
  });

  test('one approved complete text survives restart and preserves source, every rule, conditional dialogue, two endings and SQLite replay', () async {
    final m = await f.manifest();
    final folder = await Directory.systemTemp.createTemp('complete_prose_');
    try {
      final repo = FileSourceAnalysisCheckpointRepository(rootDirectory: () async => folder);
      final store = CampaignProseStore(repository: repo);
      final transport = story.Transport((body, count) async => count == 1
          ? const AiHttpResponse(429, '{}', retryAfter: '0') : _response(_answer(body)));
      final request = CampaignProseRequest.prepare(m, await store.load(m));
      await _service(transport).generate(manifest: m, store: store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true);
      expect(transport.bodies[0], transport.bodies[1]);
      final reopened = CampaignProseStore(repository:
          FileSourceAnalysisCheckpointRepository(rootDirectory: () async => folder));
      final session = await reopened.load(m);
      expect(session.entries, hasLength(m.sceneIds.length));
      expect(session.cloudConsent, false); expect(session.installConsent, false);
      final review = CampaignProseAcceptance.review(m, session);
      final built = await CampaignProseAcceptance.build(manifest: m, store: reopened, session: session,
        approvedDigest: ReviewedCampaignProseWriter.digest(review),
        fullTextReviewed: true, privateFictionConfirmed: true);
      expect(ReviewedCampaignProseWriter.mechanics(_blueprint(built)),
          ReviewedCampaignProseWriter.mechanics(_blueprint(f.archive)));
      final original = const RichPrivateBookworldImporter().inspect(f.archive);
      final game = const RichPrivateBookworldImporter().inspect(built);
      expect(game.bookworldId, isNot(original.bookworldId));
      expect(game.requiresNetwork, false); expect(game.canDistributePublicly, false);
      for (final id in m.sceneIds) {
        expect(game.blueprint.scenes[id]!.text, '${_prose(id)}\n\n${original.blueprint.scenes[id]!.text}');
      }
      final originalWorld = StoryWorld(original.blueprint, socialRulebook: original.npcSocialRulebook);
      final world = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      for (var i = 0; i < f.path.length; i++) {
        expect(originalWorld.apply(actionId: 'step_$i', choiceId: f.path[i], expectedRevision: i).applied, true);
        expect(world.apply(actionId: 'step_$i', choiceId: f.path[i], expectedRevision: i).applied, true);
        expect(world.state.toJson(), originalWorld.state.toJson());
      }
      expect(world.isTerminal, true); expect(world.state.inventory, isEmpty);
      expect(world.state.knowledge['player'], isEmpty);
      final replay = StoryWorld.replay(game.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision, expectedStateHash: world.state.stateHash,
        socialRulebook: game.npcSocialRulebook);
      expect(replay.state.stateHash, world.state.stateHash);
      final skipped = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      for (final id in f.path.take(5)) {
        expect(skipped.apply(actionId: 'skip_${skipped.state.revision}', choiceId: id).applied, true);
      }
      final npc = f.npcs.first;
      expect(skipped.apply(actionId: 'skip_meeting', choiceId: npc.firstExitChoiceId).applied, true);
      expect(skipped.choiceLockReason(ReviewedNpcCampaignBookworldWriter.replyChoiceId(npc.id)), isNotNull);
      final turns = RichSceneDialogue.verify((game.presentation['scene_dialogues'] as Map)[npc.responseSceneId],
          game.blueprint.scenes[npc.responseSceneId]!.text);
      final hidden = RichNpcDialogueKnowledge.redact(turns,
        (game.presentation['scene_dialogue_knowledge'] as Map)[npc.responseSceneId] as List,
        skipped.state.knowledge, social: NpcSocialLedger.inspect(skipped, game.npcSocialRulebook!),
        committedEvents: skipped.events, sceneId: npc.responseSceneId);
      expect(hidden.any((t) => t.text == 'Я помню нашу отдельную игровую встречу у ворот.'), false);
      expect(hidden.any((t) => t.text == RichNpcDialogueKnowledge.unavailableLine), true);
      final alternate = StoryWorld(game.blueprint, socialRulebook: game.npcSocialRulebook);
      for (var act = 1; act <= 3; act++) {
        for (final action in ['pass_source', 'pass_source_2', 'refuse_offer', 'explore',
          'use_discovery', 'end_alternative', if (act < 3) 'continue_alternative']) {
          expect(alternate.apply(actionId: 'alt_${alternate.state.revision}',
              choiceId: 'act_${act}_$action').applied, true, reason: 'act_${act}_$action');
        }
      }
      expect(alternate.isTerminal, true);
      expect(alternate.state.sceneId, isNot(world.state.sceneId));
      var db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/play');
      late String campaign;
      try {
        campaign = db.createCampaign(db.installBookworld(built).archiveHash);
        for (var i = 0; i < 3; i++) {
          expect(db.commitChoice(campaign, actionId: 'step_$i', choiceId: f.path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).coordinator.state.inventory, {'source_key'});
      } finally { db.close(); }
      db = BookworldCampaignStore.openPrivateDirectory('${folder.path}/play');
      try {
        expect(db.loadCampaign(campaign).coordinator.state.inventory, {'source_key'});
        for (var i = 3; i < f.path.length; i++) {
          expect(db.commitChoice(campaign, actionId: 'step_$i', choiceId: f.path[i], expectedRevision: i).applied, true);
        }
        expect(db.loadCampaign(campaign).coordinator.state.stateHash, world.state.stateHash);
        expect(db.exportPortable(campaign), isNotEmpty);
      } finally { db.close(); }
    } finally { await folder.delete(recursive: true); }
  });

  test('complete coverage and two fresh approvals are mandatory; edited text cannot reuse old approval', () async {
    final m = await f.manifest();
    final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    final empty = await store.load(m);
    expect(() => CampaignProseAcceptance.review(m, empty), throwsFormatException);
    final saved = await _manual(m, store);
    final review = CampaignProseAcceptance.review(m, saved);
    await expectLater(CampaignProseAcceptance.build(manifest: m, store: store, session: saved,
      approvedDigest: ReviewedCampaignProseWriter.digest(review),
      fullTextReviewed: false, privateFictionConfirmed: true), throwsFormatException);
    final first = saved.entries.values.first;
    await store.save(manifest: m, expected: saved, entries: [
      ...saved.entries.values.where((e) => e.sceneId != first.sceneId),
      CampaignProseEntry(sceneId: first.sceneId, text: '${first.text} Автор изменил последнюю строку.',
        uncertainty: _uncertainty)]);
    await expectLater(CampaignProseAcceptance.build(manifest: m, store: store, session: saved,
      approvedDigest: ReviewedCampaignProseWriter.digest(review),
      fullTextReviewed: true, privateFictionConfirmed: true), throwsFormatException);
  });

  test('missing cloud consent, disabled account and missing key send no data', () async {
    final m = await f.manifest(), store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    final request = CampaignProseRequest.prepare(m, await store.load(m));
    final transport = story.Transport((body, _) async => _response(_answer(body)));
    final prefs = story.Prefs()..enabled = false, vault = story.Vault();
    final service = ZaiCampaignProse(preferences: prefs, vault: vault, transport: transport);
    Future<CampaignProseSession> run(bool consent, String digest) => service.generate(
      manifest: m, store: store, request: request, approvedDigest: digest, explicitCloudConsent: consent);
    await expectLater(run(false, request.approvalDigest), throwsA(isA<AiSetupException>()));
    await expectLater(run(true, 'stale'), throwsA(isA<AiSetupException>()));
    await expectLater(run(true, request.approvalDigest), throwsA(isA<AiSetupException>()));
    prefs.enabled = true; vault.key = null;
    await expectLater(run(true, request.approvalDigest), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty);
  });

  test('cancellation saves completed batch; restart sends only remaining scenes and never manual text', () async {
    final m = await f.manifest(), repo = MemorySourceAnalysisCheckpointRepository();
    final store = CampaignProseStore(repository: repo);
    final first = m.sceneIds.first;
    var saved = await store.save(manifest: m, expected: await store.load(m),
      entries: [CampaignProseEntry(sceneId: first, text: _prose(first), uncertainty: _uncertainty)]);
    final transport = story.Transport((body, _) async => _response(_answer(body)));
    final token = ZaiPreviewCancellation();
    var request = CampaignProseRequest.prepare(m, saved);
    await expectLater(_service(transport).generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true, cancellation: token,
      onSaved: (_) => token.cancel()), throwsA(isA<AiSetupException>()));
    saved = await store.load(m);
    expect(saved.entries.length, 4); expect(transport.bodies, hasLength(1));
    final originalRecord = saved.entries[first]!.toJson();
    request = CampaignProseRequest.prepare(m, saved);
    for (final batch in request.batches) {
      final ids = (jsonDecode(batch)['scenes'] as List).map((s) => s['scene_id']);
      expect(ids.any(saved.entries.containsKey), false);
    }
    await _service(transport).generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true);
    expect((await store.load(m)).entries[first]!.toJson(), originalRecord);
  });

  test('changed author revision blocks retry and late response before saving', () async {
    var current = true;
    final m = await f.manifest(guard: () async {
      if (!current) throw const FormatException('Changed author revision');
    });
    final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    final request = CampaignProseRequest.prepare(m, await store.load(m));
    final retry = story.Transport((_, __) async => const AiHttpResponse(429, '{}', retryAfter: '0'));
    await expectLater(_service(retry, wait: (_) async { current = false; }).generate(
      manifest: m, store: store, request: request, approvedDigest: request.approvalDigest,
      explicitCloudConsent: true), throwsFormatException);
    expect(retry.bodies, hasLength(1)); expect((await store.load(m)).entries, isEmpty);
    current = true;
    final late = story.Transport((body, _) async { current = false; return _response(_answer(body)); });
    await expectLater(_service(late).generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true), throwsFormatException);
    expect((await store.load(m)).entries, isEmpty);
  });

  test('manual edit wins over an in-flight answer and duplicate generation cannot send', () async {
    final m = await f.manifest(), store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    final empty = await store.load(m), request = CampaignProseRequest.prepare(m, await store.load(m));
    final started = Completer<void>(), reply = Completer<AiHttpResponse>();
    final transport = story.Transport((_, __) { started.complete(); return reply.future; });
    final service = _service(transport);
    final pending = service.generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true);
    await started.future;
    await expectLater(service.generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true), throwsA(isA<AiSetupException>()));
    final manual = await store.save(manifest: m, expected: empty, entries: [
      CampaignProseEntry(sceneId: m.sceneIds.first, text: _prose('manual'), uncertainty: _uncertainty)]);
    final assertion = expectLater(pending, throwsFormatException);
    reply.complete(_response(_answer(transport.bodies.first)));
    await assertion;
    expect((await store.load(m)).recordHash, manual.recordHash);
    expect(transport.bodies, hasLength(1));
  });

  test('model effects, hidden speakers, incomplete packet and invented scene are rejected without writes', () async {
    final m = await f.manifest();
    for (final corrupt in <void Function(Map<String, dynamic>)>[
      (v) => v['effects'] = ['teleport'],
      (v) => (v['scenes'] as List).removeLast(),
      (v) => (v['scenes'] as List).first['scene_id'] = 'invented',
      (v) => (v['scenes'] as List).first['prose'] = 'Мария: «${_prose('speech')}»',
    ]) {
      final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
      final request = CampaignProseRequest.prepare(m, await store.load(m));
      final transport = story.Transport((body, _) async {
        final value = jsonDecode(jsonEncode(_answer(body))) as Map<String, dynamic>;
        corrupt(value); return _response(value);
      });
      await expectLater(_service(transport).generate(manifest: m, store: store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true), throwsFormatException);
      expect((await store.load(m)).entries, isEmpty); expect(transport.bodies, hasLength(1));
    }
  });

  test('failed persistence and forged permission checkpoint never create phantom completion', () async {
    final m = await f.manifest(), repo = MemorySourceAnalysisCheckpointRepository();
    final store = CampaignProseStore(repository: repo);
    final request = CampaignProseRequest.prepare(m, await store.load(m));
    repo.failNextWrite = true;
    final transport = story.Transport((body, _) async => _response(_answer(body)));
    await expectLater(_service(transport).generate(manifest: m, store: store, request: request,
      approvedDigest: request.approvalDigest, explicitCloudConsent: true), throwsA(isA<FileSystemException>()));
    expect((await store.load(m)).entries, isEmpty); expect(transport.bodies, hasLength(1));
    await _manual(m, store);
    final envelope = jsonDecode((await repo.read(m.storageKey))!) as Map<String, dynamic>;
    final payload = envelope['payload'] as Map<String, dynamic>;
    payload['install_consent'] = true; envelope['sha256'] = campaignProseHash(payload);
    final forged = jsonEncode(envelope); await repo.write(m.storageKey, forged);
    await expectLater(store.load(m), throwsFormatException);
    expect(await repo.read(m.storageKey), forged);
  });

  test('rehashed arbitrary rules and incomplete coverage cannot pass the text-only writer', () async {
    final m = await f.manifest();
    final narration = {for (final id in m.sceneIds) id: _prose(id)};
    final json = ReviewedCampaignProseWriter.review(archive: f.archive, narration: narration);
    for (final corrupt in <void Function(Map<String, dynamic>)>[
      (v) => v['effects'] = ['grant_anything'],
      (v) => (v['scenes'] as Map).remove(m.sceneIds.last),
      (v) => v['base_archive_sha256'] = '0' * 64,
    ]) {
      final value = jsonDecode(json) as Map<String, dynamic>; corrupt(value);
      final altered = jsonEncode(value);
      expect(() => const ReviewedCampaignProseWriter().build(verifiedArchive: f.archive,
        sourceIndex: Map<String, dynamic>.from(f.source.index.toJson()),
        reviewJson: altered, approvedDigest: ReviewedCampaignProseWriter.digest(altered),
        fullTextReviewed: true, privateFictionConfirmed: true), throwsFormatException);
    }
  });

  testWidgets('original scene text is accepted only through provided RPG API port', (tester) async {
    final manifest = (await tester.runAsync(() => f.manifest()))!;
    final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    Uint8List? chosen;
    var calls = 0;
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) =>
      Scaffold(body: ElevatedButton(onPressed: () {
        Navigator.of(ctx).push<Uint8List>(MaterialPageRoute(builder: (_) =>
          CampaignProsePage(manifest: manifest, store: store,
            acceptExisting: () async {
              calls++;
              return manifest.originalArchive;
            }))).then((result) { chosen = result; });
      }, child: const Text('Open RPG authoring'))))));
    await tester.tap(find.text('Open RPG authoring'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    final keep = find.byKey(const Key('campaign-prose-keep-original'));
    await tester.ensureVisible(keep);
    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(chosen, orderedEquals(manifest.originalArchive));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewed scene text sends exact consent and digest to RPG API port', (tester) async {
    final manifest = (await tester.runAsync(() => f.manifest()))!;
    final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    await _manual(manifest, store);
    var calls = 0;
    String? authorDigest;
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: CampaignProsePage(
      manifest: manifest, store: store,
      applyReviewed: (session, checkpointStore, digest, reviewed, fiction) async {
        calls++;
        expect(identical(checkpointStore, store), true);
        expect(session.entries.length, manifest.sceneIds.length);
        expect(reviewed, true);
        expect(fiction, true);
        authorDigest = digest;
        return manifest.originalArchive;
      },
    )));
    await tester.pumpAndSettle();
    for (final key in ['campaign-prose-full-review', 'campaign-prose-fiction']) {
      final choice = find.byKey(Key(key));
      await tester.scrollUntilVisible(choice, 160,
          maxScrolls: 65, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(choice);
      await tester.pump();
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    final accept = find.byKey(const Key('campaign-prose-accept'));
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(authorDigest, hasLength(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone opens complete local narration with unapproved controls and no request', (tester) async {
    final m = (await tester.runAsync(() => f.manifest()))!;
    final store = CampaignProseStore(repository: MemorySourceAnalysisCheckpointRepository());
    await _manual(m, store);
    final transport = story.Transport((_, __) async => throw StateError('No POST is allowed'));
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: CampaignProsePage(manifest: m, store: store,
      service: _service(transport))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campaign-prose-progress')), findsOneWidget);
    for (final key in ['campaign-prose-full-review', 'campaign-prose-fiction']) {
      final control = find.byKey(Key(key));
      await tester.scrollUntilVisible(control, 160, maxScrolls: 60, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(control), alignment: 0.5); await tester.pump();
      expect(tester.widget<CheckboxListTile>(control).value, false);
    }
    final accept = find.byKey(const Key('campaign-prose-accept'));
    await tester.ensureVisible(accept); await tester.pump();
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    expect(transport.bodies, isEmpty); expect(tester.takeException(), isNull);
  });
}
