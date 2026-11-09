import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _anna = 'npc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Uint8List _book() => Uint8List.fromList(utf8.encode(
    List.generate(900, (i) => 'Анна шла по дороге. '
      'В главе есть реальное событие номер ' + i.toString() +
      ' и ещё одно утверждение.').join('\n')));

Map<String, dynamic> _review(
    VerifiedRichPrivateBookworld base) {
  final first = base.sceneOrigins['canon_00000']!;
  final second = base.sceneOrigins['canon_00001']!;
  return {
    'format': ReviewedCanonCausalBookworldWriter.reviewFormat,
    'review_scope': 'human_reviewed_private_story_causality',
    'source_fingerprint': base.sourceFingerprint,
    'base_archive_sha256': base.archiveSha256,
    'user_confirmed': true,
    'semantic_canon_automatically_verified': false,
    'witnesses': [{
      'scene_id': first.sceneId,
      'actor_id': _anna,
      'display_name': 'Анна',
      'source_quote_sha256': first.sourceQuoteSha256,
      'mode': 'present',
    }],
    'invariants': [{
      'scene_id': second.sceneId,
      'actor_id': _anna,
      'forbidden_memory_id': 'gm_anna_warning',
      'minimum_trust': null,
      'maximum_trust': null,
      'source_quote_sha256': second.sourceQuoteSha256,
    }],
  };
}

Map<String, dynamic> _proposal({
  String player = 'Предупредить Анну',
  String memory = 'gm_anna_warning',
  String narrative = 'Анна услышала предупреждение, и история изменилась.',
  int trustDelta = 4, String? goal = 'gm_anna_avoids_trap',
  String intent = 'continue',
  bool withNpc = true,
}) => {
  'format': FreeformActionDraft.format,
  'scope': FreeformActionDraft.fictionScope,
  'player_text': player,
  'narration': narrative,
  'effects': <Object>[],
  if (withNpc)
    'npc_interaction': {
      'actor_id': _anna,
      'memory_id': memory,
      'kind': 'warned',
      'trust_delta': trustDelta,
      'goal_id': goal,
    },
  'plot_intent': intent,
};

({Uint8List base, Uint8List reviewed, Map<String, dynamic> sourceIndex,
    String reviewJson, String approvedDigest}) _files() {
  final bytes = _book();
  final index = BookSourceIndexer.index(BookImporter.parse('story.txt', bytes));
  final rawIndex = Map<String, dynamic>.from(index.toJson());
  final api = const LocalRpgLiteralCanonApi();
  final preview = api.prepareIndex(index);
  expect(preview.chunkCount, greaterThan(2));
  final base = api.compileIndex(index,
    approvedDigest: preview.approvalDigest, userConfirmed: true);
  final checked = const RichPrivateBookworldImporter().inspect(base);
  final reviewJson = canonicalJson(_review(checked));
  final digest = ReviewedCanonCausalBookworldWriter.digest(reviewJson);
  final reviewed = api.compileReviewedCausality(
    verifiedBaseArchive: base, sourceIndex: rawIndex,
    reviewJson: reviewJson, approvedDigest: digest,
    userConfirmed: true);
  return (base: base, reviewed: reviewed, sourceIndex: rawIndex,
    reviewJson: reviewJson, approvedDigest: digest);
}

void main() {
  test('source-locked NPC witness / expected future event produce a private '
      'new v5 with unchanged full CANON text', () {
    final input = _files();
    final original = const RichPrivateBookworldImporter().inspect(input.base);
    final changed = const RichPrivateBookworldImporter()
        .inspect(input.reviewed);
    expect(changed.formatVersion, 5);
    expect(changed.sourceLiteralCanonVerified, true);
    expect(changed.blueprint.actors, contains(_anna));
    expect(changed.npcSocialRulebook?.dynamicInteractionsEnabled, true);
    expect(changed.npcSocialRulebook?.canonInvariants, hasLength(1));
    expect(changed.presentation['npc_display_names'], {_anna: 'Анна'});
    expect(changed.sourceFingerprint, original.sourceFingerprint);
    expect(changed.archiveSha256, isNot(original.archiveSha256));
    for (final scene in original.blueprint.scenes.entries) {
      expect(changed.blueprint.scenes[scene.key]!.text, scene.value.text);
    }
    expect(changed.canDistributePublicly, false);
    expect(changed.requiresNetwork, false);
  });

  test('warn NPC: reviewed presence, durable directed trust and memory, '
      'automatic CANON -> ALTER_FATE, scenes, goals, end, SQLite replay',
      () async {
    final input = _files();
    final first = await Directory.systemTemp.createTemp('canon_causal_npc_');
    final second = await Directory.systemTemp.createTemp('canon_causal_import_');
    BookworldCampaignStore? primary, target;
    try {
      primary = BookworldCampaignStore.openPrivateDirectory(first.path);
      final game = LocalRpgGameApi(primary);
      final world = game.install(input.reviewed);
      final campaign = game.start(world.archiveHash);
      final current = game.load(campaign);
      expect(current.sourceLiteralCanon, true);
      expect(current.activePlotMode, 'CANON');
      expect(current.availableNpcTargets, {_anna: 'Анна'});
      expect(current.npcRelations.single.displayName, 'Анна');
      expect(current.npcRelations.single.directedScore, 0);

      final warning = FreeformActionDraft.fromJson(_proposal());
      final proposed = game.previewFreeform(campaign, warning,
          expectedRevision: 0);
      expect(game.load(campaign).revision, 0);
      final accepted = game.commitFreeform(campaign,
          actionId: 'warn_anna_1', draft: warning,
          expectedRevision: 0,
          approvalDigest: proposed.approvalDigest, userConfirmed: true);
      expect(accepted.applied, true);
      expect(accepted.view.activePlotMode, 'ALTER_FATE');
      expect(accepted.view.sceneId, 'gm_scene_1');
      expect(accepted.view.sceneText, warning.narration);
      expect(accepted.view.sceneSource?.isSourcePassage, false);
      expect(accepted.view.choices, isEmpty);
      expect(accepted.view.npcRelations.single.directedScore, 4);
      expect(accepted.view.npcRelations.single.memoryCount, 1);
      expect(accepted.view.npcRelations.single.currentGoal,
          'gm_anna_avoids_trap');

      final denied = game.choose(campaign,
          actionId: 'fake_canon_next', choiceId: 'canon_next_00000',
          expectedRevision: 1);
      expect(denied.applied, false);
      expect(denied.reason, 'timeline_diverged_into_alter_fate');

      final nextAction = FreeformActionDraft.fromJson(_proposal(
        player: 'Помочь Анне укрыться',
        memory: 'gm_anna_safe_hiding',
        narrative: 'В новой истории Анна скрылась в безопасном доме.',
        trustDelta: 3, goal: 'gm_anna_returns_home',
      ));
      final preview2 = game.previewFreeform(campaign, nextAction,
          expectedRevision: 1);
      final done = game.commitFreeform(campaign,
          actionId: 'aid_anna_2', draft: nextAction,
          expectedRevision: 1,
          approvalDigest: preview2.approvalDigest,
          userConfirmed: true);
      expect(done.view.sceneId, 'gm_scene_2');
      expect(done.view.npcRelations.single.directedScore, 7);
      expect(done.view.npcRelations.single.memoryCount, 2);
      expect(done.view.npcRelations.single.currentGoal,
          'gm_anna_returns_home');

      final ending = FreeformActionDraft.fromJson(_proposal(
        player: 'Завершить новый путь',
        narrative: 'Анна и герой уехали, новая история завершилась.',
        withNpc: false, intent: 'end',
      ));
      final finalPreview = game.previewFreeform(campaign, ending,
          expectedRevision: 2);
      final ended = game.commitFreeform(campaign,
          actionId: 'ending_3', draft: ending,
          expectedRevision: 2,
          approvalDigest: finalPreview.approvalDigest,
          userConfirmed: true);
      expect(ended.view.isTerminal, true);
      expect(ended.view.sceneId, 'gm_scene_3');
      expect(ended.view.activePlotMode, 'ALTER_FATE');
      expect(ended.view.freeformAvailable, false);

      final backup = game.exportSave(campaign);
      target = BookworldCampaignStore.openPrivateDirectory(second.path);
      final replica = LocalRpgGameApi(target);
      replica.install(input.reviewed);
      final imported = replica.importSave(backup,
          expectedWorldHash: world.archiveHash);
      final replayed = replica.load(imported);
      expect(replayed.stateHash, ended.view.stateHash);
      expect(replayed.sceneText, ended.view.sceneText);
      expect(replayed.activePlotMode, 'ALTER_FATE');
      expect(replayed.npcRelations.single.directedScore, 7);
      expect(replayed.npcRelations.single.currentGoal,
          'gm_anna_returns_home');
      expect(replayed.isTerminal, true);
      expect(replayed.journal.length, 3);
    } finally {
      primary?.close(); target?.close();
      await first.delete(recursive: true);
      await second.delete(recursive: true);
    }
  });

  test('benign witnessed NPC memory keeps the honest CANON timeline: '
      'only a reviewed causal contradiction may branch', () async {
    final files = _files();
    final dir = await Directory.systemTemp.createTemp('canon_safe_npc_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final api = LocalRpgGameApi(store);
      final entry = api.install(files.reviewed);
      final id = api.start(entry.archiveHash);
      final harmless = FreeformActionDraft.fromJson(_proposal(
        player: 'Поговорить с Анной о дороге',
        memory: 'gm_anna_weather_chat',
        narrative: 'Анна услышала вопрос о погоде, книга не изменилась.',
        trustDelta: 0,
        goal: 'gm_anna_looks_at_clouds',
      ));
      final preview = api.previewFreeform(id, harmless,
          expectedRevision: 0);
      final changed = api.commitFreeform(id,
          actionId: 'chat_anna_1', draft: harmless,
          expectedRevision: 0,
          approvalDigest: preview.approvalDigest,
          userConfirmed: true);
      expect(changed.applied, true);
      expect(changed.view.activePlotMode, 'CANON');
      expect(changed.view.sceneId, 'canon_00000');
      expect(changed.view.npcRelations.single.memoryCount, 1);
      expect(changed.view.npcRelations.single.currentGoal,
          'gm_anna_looks_at_clouds');
      final advanced = api.choose(id,
          actionId: 'book_advance_2', choiceId: 'canon_next_00000',
          expectedRevision: 1);
      expect(advanced.applied, true);
      expect(advanced.view.activePlotMode, 'CANON');
      expect(advanced.view.sceneId, 'canon_00001');
      expect(advanced.view.sceneSource?.isSourcePassage, true);
      expect(advanced.view.npcRelations.single.memoryCount, 1);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('fake NPC identity, missing witness, stale approval, early ending '
      'and uncited canonical obligation fail closed', () async {
    final files = _files();
    final api = const LocalRpgLiteralCanonApi();
    expect(() => api.compileReviewedCausality(
      verifiedBaseArchive: files.base,
      sourceIndex: files.sourceIndex,
      reviewJson: files.reviewJson,
      approvedDigest: '0' * 64, userConfirmed: true), throwsFormatException);
    expect(() => api.compileReviewedCausality(
      verifiedBaseArchive: files.base,
      sourceIndex: files.sourceIndex,
      reviewJson: files.reviewJson,
      approvedDigest: files.approvedDigest,
      userConfirmed: false), throwsFormatException);
    final bad = jsonDecode(files.reviewJson) as Map<String, dynamic>;
    (bad['invariants'] as List).first['source_quote_sha256'] = '0' * 64;
    final changed = canonicalJson(bad);
    expect(() => api.compileReviewedCausality(
      verifiedBaseArchive: files.base,
      sourceIndex: files.sourceIndex,
      reviewJson: changed,
      approvedDigest: ReviewedCanonCausalBookworldWriter.digest(changed),
      userConfirmed: true), throwsFormatException);
    final dir = await Directory.systemTemp.createTemp('canon_negative_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final world = game.install(files.reviewed);
      final id = game.start(world.archiveHash);
      // An unreviewed actor must fail closed either during JSON admission
      // or during the subsequent source-witness gameplay validation.
      expect(() {
        final unreviewed = FreeformActionDraft.fromJson({
          ..._proposal(),
          'npc_interaction': {
            ...(_proposal()['npc_interaction'] as Map),
            'actor_id': 'npc_' + 'b' * 32,
          },
        });
        game.previewFreeform(id, unreviewed, expectedRevision: 0);
      }, throwsFormatException);
      final prematureEnd = FreeformActionDraft.fromJson(
          _proposal(withNpc: false, intent: 'end'));
      expect(() => game.previewFreeform(id, prematureEnd,
          expectedRevision: 0), throwsFormatException);
      expect(game.load(id).revision, 0);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('second-language JSON API compiles the same source-locked NPC world '
      'and persists a real causal branch, not a frontend-only conversation',
      () async {
    final files = _files();
    final dir = await Directory.systemTemp.createTemp('canon_causal_json_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final client = RpgClientProtocol(LocalRpgGameApi(store));
      Future<Map<String, dynamic>> invoke(
          String op, Map<String, Object?> args) async {
        final result = await client.handle({
          'version': RpgClientProtocol.version,
          'op': op, 'args': args,
        });
        expect(result['ok'], true, reason: result.toString());
        return Map<String, dynamic>.from(result['result'] as Map);
      }
      final compiled = await invoke('compile_reviewed_causal_canon', {
        'archive_base64': base64Encode(files.base),
        'source_index': files.sourceIndex,
        'review_json': files.reviewJson,
        'approved_digest': files.approvedDigest,
        'user_confirmed': true,
      });
      expect(compiled['reviewed_npc_actor_count'], 1);
      expect(compiled['reviewed_causal_checkpoint_count'], 1);
      expect(base64Decode(compiled['archive_base64'] as String),
          files.reviewed);
      final installed = await invoke('install_world', {
        'archive_base64': compiled['archive_base64'],
      });
      final started = await invoke('start', {
        'world_hash': installed['world_hash'],
      });
      expect(started['active_plot_mode'], 'CANON');
      final cid = started['campaign_id'] as String;
      final preview = await invoke('preview_dynamic_action', {
        'campaign_id': cid,
        'expected_revision': 0,
        'proposal': _proposal(),
      });
      final applied = await invoke('commit_dynamic_action', {
        'campaign_id': cid,
        'expected_revision': 0,
        'action_id': 'warn_via_json_1',
        'proposal': _proposal(),
        'approval_digest': preview['approval_digest'],
        'user_confirmed': true,
      });
      expect(applied['applied'], true);
      expect(applied['active_plot_mode'], 'ALTER_FATE');
      expect(applied['scene_id'], 'gm_scene_1');
      expect((applied['npc_encountered'] as List).single['directed_score'],
          4);
      expect((applied['npc_encountered'] as List).single
          ['current_private_goal'], 'gm_anna_avoids_trap');
      final denied = await invoke('choose', {
        'campaign_id': cid, 'action_id': 'skip_causal_gate',
        'choice_id': 'canon_next_00000', 'expected_revision': 1,
      });
      expect(denied['applied'], false);
      expect(denied['reason'], 'timeline_diverged_into_alter_fate');
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });
  test('v2 causal graph: NPC learns and branches',
      () async {
    final baseline = _files();
    final base = const RichPrivateBookworldImporter().inspect(baseline.base);
    final raw = _review(base);
    final scenes = base.blueprint.scenes.keys.toList();
    raw['format'] = ReviewedCanonCausalBookworldWriter.graphReviewFormat;
    raw['event_graph'] = [
      for (var i = 0; i < scenes.length; i++)
        {
          'scene_id': scenes[i],
          'source_quote_sha256':
              base.sceneOrigins[scenes[i]]!.sourceQuoteSha256,
          'depends_on': i == 0 ? <String>[] : [scenes[i - 1]],
          'preconditions': i == 1 ? [{
            'op': 'fact_unknown', 'actor_id': _anna,
            'id': 'gm_announcement', 'value': null,
          }] : <Object>[],
          'effects': <Object>[],
        }
    ];
    final json = canonicalJson(raw);
    final checkedArchive = const LocalRpgLiteralCanonApi()
        .compileReviewedCausality(
          verifiedBaseArchive: baseline.base,
          sourceIndex: baseline.sourceIndex,
          reviewJson: json,
          approvedDigest: ReviewedCanonCausalBookworldWriter.digest(json),
          userConfirmed: true,
        );
    final imported = const RichPrivateBookworldImporter()
        .inspect(checkedArchive);
    expect(imported.npcSocialRulebook?.bookCausality?.nodes.length,
        imported.blueprint.scenes.length);
    final dir = await Directory.systemTemp.createTemp('causal_v2_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final api = LocalRpgGameApi(store);
      final world = api.install(checkedArchive);
      final safeId = api.start(world.archiveHash);
      final safeAdvance = api.choose(safeId,
        actionId: 'advance', choiceId: 'canon_next_00000',
        expectedRevision: 0);
      expect(safeAdvance.applied, true);
      expect(safeAdvance.view.activePlotMode, 'CANON');

      final id = api.start(world.archiveHash);
      final learning = FreeformActionDraft.fromJson({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': 'Я узнал новость',
        'narration': 'Игрок узнал новость до встречи.',
        'effects': [
          {'op': 'learn_fact', 'actor': 'player',
           'id': 'gm_announcement'},
          {'op': 'grant_item', 'id': 'gm_keepsake'},
        ],
      });
      final p = api.previewFreeform(id, learning, expectedRevision: 0);
      final first = api.commitFreeform(id, actionId: 'learn', draft: learning,
        expectedRevision: 0, approvalDigest: p.approvalDigest,
        userConfirmed: true);
      expect(first.view.activePlotMode, 'CANON');

      final share = FreeformActionDraft.fromJson({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': 'Я сообщил Анне новость',
        'narration': 'Анна узнала новую информацию и изменила решение.',
        'effects': <Object>[],
        'npc_interaction': {
          'actor_id': _anna,
          'memory_id': 'gm_announcement_shared',
          'kind': 'warned',
          'trust_delta': 2,
          'goal_id': 'gm_avoid_trap',
          'learn_fact_id': 'gm_announcement',
          'give_item_id': 'gm_keepsake',
        },
      });
      final p2 = api.previewFreeform(id, share, expectedRevision: 1);
      final done = api.commitFreeform(id, actionId: 'share', draft: share,
        expectedRevision: 1, approvalDigest: p2.approvalDigest,
        userConfirmed: true);
      expect(done.view.activePlotMode, 'ALTER_FATE');
      expect(done.view.npcRelations.single.currentGoal, 'gm_avoid_trap');
      expect(done.view.inventory, isNot(contains('gm_keepsake')));
      expect(done.view.npcItemOwners['gm_keepsake'], _anna);

      final returnItem = FreeformActionDraft.fromJson({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': 'Анна возвращает вещь',
        'narration': 'Анна вернула сохранённую вещь герою.',
        'effects': <Object>[],
        'npc_interaction': {
          'actor_id': _anna, 'memory_id': 'gm_item_return',
          'kind': 'helped', 'trust_delta': 1,
          'goal_id': 'gm_back_home',
          'take_item_id': 'gm_keepsake',
        },
      });
      final returnPreview = api.previewFreeform(id, returnItem,
          expectedRevision: 2);
      final returned = api.commitFreeform(id,
          actionId: 'npc_item_return', draft: returnItem,
          expectedRevision: 2,
          approvalDigest: returnPreview.approvalDigest,
          userConfirmed: true);
      expect(returned.view.inventory, contains('gm_keepsake'));
      expect(api.choose(id, actionId: 'cannot_skip_to_book',
        choiceId: 'canon_next_00000', expectedRevision: 2).applied, false);
      final save = api.exportSave(id);
      final clone = api.importSave(save, expectedWorldHash: world.archiveHash);
      final replay = api.load(clone);
      expect(replay.stateHash, returned.view.stateHash);
      expect(replay.activePlotMode, 'ALTER_FATE');
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('two source-reviewed NPCs react autonomously: witnessed warning '
      'relays a verified fact and blocks the future canon', () async {
    const boris = 'npc_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final sourceBytes = Uint8List.fromList(utf8.encode(
      List.generate(720, (i) => 'Анна и Борис стояли у старой башни. '
        'Событие книги номер ${i.toString()} было описано свидетелем.')
          .join('\n')));
    final index = BookSourceIndexer.index(
        BookImporter.parse('two_npc.txt', sourceBytes));
    const canon = LocalRpgLiteralCanonApi();
    final prep = canon.prepareIndex(index);
    final original = canon.compileIndex(index,
        approvedDigest: prep.approvalDigest, userConfirmed: true);
    final originalWorld =
        const RichPrivateBookworldImporter().inspect(original);
    final scenes = originalWorld.blueprint.scenes.keys.toList();
    expect(scenes.length, greaterThan(2));
    final firstQuote =
        originalWorld.sceneOrigins[scenes.first]!.sourceQuoteSha256;
    final secondQuote =
        originalWorld.sceneOrigins[scenes[1]]!.sourceQuoteSha256;
    final review = {
      'format': ReviewedCanonCausalBookworldWriter.graphReviewFormat,
      'review_scope': 'human_reviewed_private_story_causality',
      'source_fingerprint': originalWorld.sourceFingerprint,
      'base_archive_sha256': originalWorld.archiveSha256,
      'user_confirmed': true,
      'semantic_canon_automatically_verified': false,
      'witnesses': [
        {
          'scene_id': scenes.first,
          'actor_id': _anna,
          'display_name': 'Анна',
          'source_quote_sha256': firstQuote,
          'mode': 'present',
        },
        {
          'scene_id': scenes.first,
          'actor_id': boris,
          'display_name': 'Борис',
          'source_quote_sha256': firstQuote,
          'mode': 'present',
        },
      ],
      'invariants': [{
        'scene_id': scenes[1],
        'actor_id': _anna,
        'forbidden_memory_id': 'gm_never_used',
        'minimum_trust': null,
        'maximum_trust': null,
        'source_quote_sha256': secondQuote,
      }],
      'event_graph': [
        for (var i = 0; i < scenes.length; i++)
          {
            'scene_id': scenes[i],
            'source_quote_sha256':
                originalWorld.sceneOrigins[scenes[i]]!.sourceQuoteSha256,
            'depends_on': i == 0 ? <String>[] : [scenes[i - 1]],
            'preconditions': i == scenes.length - 1 ? [{
              'op': 'fact_unknown', 'actor_id': boris,
              'id': 'gm_signal', 'value': null,
            }] : <Object>[],
            'effects': <Object>[],
          }
      ],
      'npc_reactions': [{
        'scene_id': scenes.first,
        'source_quote_sha256': firstQuote,
        'actor_id': _anna,
        'trigger_memory_id': 'gm_anna_receives_signal',
        'minimum_trust': 2,
        'response_memory_id': 'gm_anna_warns_boris',
        'next_goal_id': 'gm_help_boris',
        'relay_fact_id': 'gm_signal',
        'relay_to_actor_id': boris,
      }],
    };
    final reviewJson = canonicalJson(review);
    final archive = canon.compileReviewedCausality(
      verifiedBaseArchive: original,
      sourceIndex: Map<String, dynamic>.from(index.toJson()),
      reviewJson: reviewJson,
      approvedDigest:
          ReviewedCanonCausalBookworldWriter.digest(reviewJson),
      userConfirmed: true,
    );
    final checked = const RichPrivateBookworldImporter().inspect(archive);
    expect(checked.npcSocialRulebook!.automaticReactions.length, 1);
    final dir = await Directory.systemTemp.createTemp('two_npc_reaction_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final installed = game.install(archive);
      final id = game.start(installed.archiveHash);
      FreeformActionDraft draft(Map<String, Object?> input) =>
          FreeformActionDraft.fromJson(input);
      final learning = draft({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': 'Я узнал сигнал',
        'narration': 'Герой запомнил условный сигнал.',
        'effects': [
          {'op': 'learn_fact', 'actor': 'player', 'id': 'gm_signal'}
        ],
      });
      final first = game.previewFreeform(id, learning, expectedRevision: 0);
      game.commitFreeform(id, actionId: 'learn_signal', draft: learning,
          expectedRevision: 0, approvalDigest: first.approvalDigest,
          userConfirmed: true);
      final warning = draft({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': 'Я сообщил Анне сигнал',
        'narration': 'Анна решила предупредить Бориса.',
        'effects': <Object>[],
        'npc_interaction': {
          'actor_id': _anna,
          'memory_id': 'gm_anna_receives_signal',
          'kind': 'warned',
          'trust_delta': 3,
          'goal_id': 'gm_anna_considers',
          'learn_fact_id': 'gm_signal',
        },
      });
      final pre = game.previewFreeform(id, warning, expectedRevision: 1);
      final done = game.commitFreeform(id, actionId: 'npc_relays',
          draft: warning, expectedRevision: 1,
          approvalDigest: pre.approvalDigest, userConfirmed: true);
      expect(done.view.activePlotMode, 'ALTER_FATE');
      final anna = done.view.npcRelations
          .singleWhere((npc) => npc.actorId == _anna);
      final friend = done.view.npcRelations
          .singleWhere((npc) => npc.actorId == boris);
      expect(anna.currentGoal, 'gm_help_boris');
      expect(anna.memoryCount, 2);
      expect(friend.memoryCount, 1);
      final portable = game.exportSave(id);
      final clone = game.importSave(portable,
          expectedWorldHash: installed.archiveHash);
      expect(game.load(clone).stateHash, done.view.stateHash);
      expect(game.load(clone).npcRelations
          .singleWhere((npc) => npc.actorId == boris).memoryCount, 1);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('ALTER_FATE long-run plan: ordered beats, promises, NPC identity, '
      'ending and independent SQLite replay', () async {
    final fixture = _files();
    final first = await Directory.systemTemp.createTemp('alter_plot_source_');
    final second = await Directory.systemTemp.createTemp('alter_plot_other_');
    BookworldCampaignStore? source, destination;
    try {
      source = BookworldCampaignStore.openPrivateDirectory(first.path);
      final game = LocalRpgGameApi(source);
      final world = game.install(fixture.reviewed);
      final id = game.start(world.archiveHash);
      FreeformActionDraft proposal(String action, String narrative,
          {String intent = 'continue', Map<String, dynamic>? beat}) =>
          FreeformActionDraft.fromJson({
        'format': FreeformActionDraft.format,
        'scope': FreeformActionDraft.fictionScope,
        'player_text': action,
        'narration': narrative,
        'effects': <Object>[],
        'plot_intent': intent,
        if (beat != null) 'plot_beat': beat,
      });
      Map<String, dynamic> step(String beat, String? predecessor,
          {List<String> opened = const [],
           List<String> resolved = const [],
           String lead = 'player', String objective = 'gm_save_anna'}) => {
        'format': AlternateStoryBeat.format,
        'beat_id': beat, 'thread_id': 'gm_anna_rescue_thread',
        'previous_beat_id': predecessor,
        'lead_actor_id': lead,
        'objective_id': objective,
        'participant_actor_ids': ['player', if (lead != 'player') lead],
        'opened_obligation_ids': opened,
        'resolved_obligation_ids': resolved,
        'route': 'protect',
      };
      final opening = proposal('Остановить книжный путь',
          'Герой решил действовать иначе, чем описано в книге.',
          intent: 'diverge');
      final preview = game.previewFreeform(id, opening, expectedRevision: 0);
      final entered = game.commitFreeform(id, actionId: 'diverge_1',
          draft: opening, expectedRevision: 0,
          approvalDigest: preview.approvalDigest, userConfirmed: true);
      expect(entered.view.activePlotMode, 'ALTER_FATE');
      expect(entered.view.alternatePlotContinuity['beat_count'], 0);

      final firstBeat = proposal('Обещать помочь',
          'Герой обещал выполнить новую задачу.',
          beat: step('gm_rescue_start', null,
              opened: ['gm_keep_promise']));
      final p1 = game.previewFreeform(id, firstBeat, expectedRevision: 1);
      final initial = game.commitFreeform(id, actionId: 'beat_1',
          draft: firstBeat, expectedRevision: 1,
          approvalDigest: p1.approvalDigest, userConfirmed: true);
      expect(initial.view.alternatePlotContinuity['open_obligation_ids'],
          ['gm_keep_promise']);
      expect(initial.view.alternatePlotContinuity['last_beat_id'],
          'gm_rescue_start');
      final directions = initial.view.alternatePlotContinuity['next_directions']
          as List;
      expect((directions.single as Map)['obligation_id'],
          'gm_keep_promise');

      // A model cannot end the story without satisfying a commitment,
      // invent a predecessor or suppress the already active plan.
      final skipped = proposal('Новый сюжет без обязательств',
          'Всё забыли.');
      expect(() => game.previewFreeform(id, skipped, expectedRevision: 2),
          throwsFormatException);
      final fake = proposal('Подменить прошлое', 'Новое предложение.',
          beat: step('gm_fake_beat', 'gm_not_the_previous'));
      expect(() => game.previewFreeform(id, fake, expectedRevision: 2),
          throwsFormatException);
      final earlyEnding = proposal('Конец', 'Незавершённая история.',
          intent: 'end', beat: step(
              'gm_early_end', 'gm_rescue_start'));
      expect(() => game.previewFreeform(id, earlyEnding,
          expectedRevision: 2), throwsFormatException);
      expect(game.load(id).revision, 2);

      final fulfilled = proposal('Сдержать обещание',
          'Герой сдержал данное обещание и завершил свой путь.',
          intent: 'end',
          beat: step('gm_rescue_end', 'gm_rescue_start',
              resolved: ['gm_keep_promise']));
      final p2 = game.previewFreeform(id, fulfilled, expectedRevision: 2);
      final ending = game.commitFreeform(id, actionId: 'beat_2',
          draft: fulfilled, expectedRevision: 2,
          approvalDigest: p2.approvalDigest, userConfirmed: true);
      expect(ending.view.isTerminal, true);
      expect(ending.view.alternatePlotContinuity['open_obligation_ids'],
          isEmpty);
      expect(ending.view.alternatePlotContinuity['beat_count'], 2);

      final bytes = game.exportSave(id);
      destination = BookworldCampaignStore.openPrivateDirectory(second.path);
      final replica = LocalRpgGameApi(destination);
      replica.install(fixture.reviewed);
      final restoredId = replica.importSave(bytes,
          expectedWorldHash: world.archiveHash);
      final restored = replica.load(restoredId);
      expect(restored.stateHash, ending.view.stateHash);
      expect(restored.alternatePlotContinuity,
          ending.view.alternatePlotContinuity);
      expect(restored.journal.length, 3);
    } finally {
      source?.close();
      destination?.close();
      await first.delete(recursive: true);
      await second.delete(recursive: true);
    }
  });

  test('NPC promise lifecycle is replayed and gates a future CANON event',
      () async {
    final fixture = _files();
    final dir = await Directory.systemTemp.createTemp('npc_promise_lifecycle_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final world = game.install(fixture.reviewed);
      final id = game.start(world.archiveHash);
      FreeformActionDraft interaction(String label, String memory,
          String kind, String promise) =>
          FreeformActionDraft.fromJson({
            'format': FreeformActionDraft.format,
            'scope': FreeformActionDraft.fictionScope,
            'player_text': label,
            'narration': 'Последствие обещания влияет на будущие события.',
            'effects': <Object>[],
            'npc_interaction': {
              'actor_id': _anna, 'memory_id': memory,
              'kind': kind, 'trust_delta': 0, 'goal_id': null,
              'promise_id': promise,
            },
          });
      final impossible = interaction('Выдать обещание за выполненное',
          'gm_fake_promise_result', 'promise_fulfilled',
          'gm_find_safe_shelter');
      expect(() => game.previewFreeform(id, impossible,
          expectedRevision: 0), throwsFormatException);
      final made = interaction('Пообещать Анне укрытие',
          'gm_promise_given', 'promise_received', 'gm_find_safe_shelter');
      final start = game.previewFreeform(id, made, expectedRevision: 0);
      final offered = game.commitFreeform(id, actionId: 'promise_open_1',
          draft: made, expectedRevision: 0,
          approvalDigest: start.approvalDigest, userConfirmed: true);
      expect(offered.view.npcRelations.single.openPromiseIds,
          ['gm_find_safe_shelter']);
      final duplicate = interaction('Ещё раз то же самое',
          'gm_promise_duplicate_memory', 'promise_received',
          'gm_find_safe_shelter');
      expect(() => game.previewFreeform(id, duplicate,
          expectedRevision: 1), throwsFormatException);
      final fulfilled = interaction('Сдержать слово',
          'gm_promise_kept', 'promise_fulfilled',
          'gm_find_safe_shelter');
      final ready = game.previewFreeform(id, fulfilled,
          expectedRevision: 1);
      final committed = game.commitFreeform(id,
          actionId: 'promise_fulfill_2', draft: fulfilled,
          expectedRevision: 1, approvalDigest: ready.approvalDigest,
          userConfirmed: true);
      expect(committed.view.npcRelations.single.openPromiseIds, isEmpty);
      expect(committed.view.npcRelations.single.memoryKinds['promiseFulfilled'],
          1);
      final save = game.exportSave(id);
      final restoredId = game.importSave(save,
          expectedWorldHash: world.archiveHash);
      final restored = game.load(restoredId);
      expect(restored.stateHash, committed.view.stateHash);
      expect(restored.npcRelations.single.openPromiseIds, isEmpty);
      expect(() => game.previewFreeform(id, impossible,
          expectedRevision: 2), throwsFormatException);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('source-reviewed delayed NPC decision acts on later turns without '
      'another player contact, then autonomously breaks CANON', () async {
    final prepared = _files();
    final original = const RichPrivateBookworldImporter()
        .inspect(prepared.base);
    final sceneIds = original.blueprint.scenes.keys.toList();
    final review = _review(original);
    review['format'] = ReviewedCanonCausalBookworldWriter.graphReviewFormat;
    (review['invariants'] as List).first['forbidden_memory_id'] =
        'gm_never_seen_elsewhere';
    review['event_graph'] = [
      for (var i = 0; i < sceneIds.length; i++) {
        'scene_id': sceneIds[i],
        'source_quote_sha256':
            original.sceneOrigins[sceneIds[i]]!.sourceQuoteSha256,
        'depends_on': i == 0 ? <String>[] : [sceneIds[i - 1]],
        'preconditions': i == 1 ? [{
          'op': 'goal_is',
          'actor_id': _anna,
          'id': 'gm_anna_waits',
          'value': null,
        }] : <Object>[],
        'effects': <Object>[],
      },
    ];
    review['npc_delayed_decisions'] = [{
      'scene_id': sceneIds.first,
      'source_quote_sha256':
          original.sceneOrigins[sceneIds.first]!.sourceQuoteSha256,
      'actor_id': _anna,
      'trigger_memory_id': 'gm_anna_warning',
      'turns_after_trigger': 2,
      'minimum_trust': 2,
      'response_memory_id': 'gm_anna_decides_to_leave',
      'next_goal_id': 'gm_anna_seeks_shelter',
    }];
    Uint8List build(Map<String, dynamic> reviewed) {
      final json = canonicalJson(reviewed);
      return const LocalRpgLiteralCanonApi().compileReviewedCausality(
        verifiedBaseArchive: prepared.base,
        sourceIndex: prepared.sourceIndex,
        reviewJson: json,
        approvedDigest: ReviewedCanonCausalBookworldWriter.digest(json),
        userConfirmed: true,
      );
    }
    final negative = jsonDecode(jsonEncode(review)) as Map<String, dynamic>;
    (negative['npc_delayed_decisions'] as List).first[
        'turns_after_trigger'] = 0;
    expect(() => build(negative), throwsFormatException);
    (negative['npc_delayed_decisions'] as List).first[
        'turns_after_trigger'] = 2;
    (negative['npc_delayed_decisions'] as List).first[
        'source_quote_sha256'] = '0' * 64;
    expect(() => build(negative), throwsFormatException);

    final archive = build(review);
    final compiled = const RichPrivateBookworldImporter().inspect(archive);
    expect(compiled.npcSocialRulebook!.delayedDecisions, hasLength(1));
    final dir = await Directory.systemTemp.createTemp('npc_future_agency_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final installed = game.install(archive);
      final id = game.start(installed.archiveHash);
      final warning = FreeformActionDraft.fromJson({
        ..._proposal(player: 'Анна, подожди у моста',
          memory: 'gm_anna_warning', goal: 'gm_anna_waits',
          narrative: 'Анна услышала предупреждение и стала ждать.'),
      });
      final p = game.previewFreeform(id, warning, expectedRevision: 0);
      final first = game.commitFreeform(id, actionId: 'warn_without_diverge',
          draft: warning, expectedRevision: 0,
          approvalDigest: p.approvalDigest, userConfirmed: true);
      expect(first.view.activePlotMode, 'CANON');
      expect(first.view.npcRelations.single.currentGoal, 'gm_anna_waits');
      expect(first.view.npcRelations.single.autonomousDecisionIds, isEmpty);
      FreeformActionDraft passTurn(int n) =>
          FreeformActionDraft.fromJson(_proposal(
            player: 'Исследовать берег $n',
            narrative: 'Герой продолжает свои исследования без разговора с Анной.',
            withNpc: false));
      final step2 = passTurn(2);
      final p2 = game.previewFreeform(id, step2, expectedRevision: 1);
      final second = game.commitFreeform(id, actionId: 'without_npc_2',
          draft: step2, expectedRevision: 1,
          approvalDigest: p2.approvalDigest, userConfirmed: true);
      expect(second.view.activePlotMode, 'CANON');
      expect(second.view.npcRelations.single.currentGoal, 'gm_anna_waits');
      final step3 = passTurn(3);
      final p3 = game.previewFreeform(id, step3, expectedRevision: 2);
      final third = game.commitFreeform(id, actionId: 'without_npc_3',
          draft: step3, expectedRevision: 2,
          approvalDigest: p3.approvalDigest, userConfirmed: true);
      expect(third.view.activePlotMode, 'ALTER_FATE');
      expect(third.view.npcRelations.single.currentGoal,
          'gm_anna_seeks_shelter');
      expect(third.view.npcRelations.single.autonomousDecisionIds,
          ['gm_anna_decides_to_leave']);
      final projected = RpgClientProtocol.projectView(third.view);
      final npcData = (projected['npc_encountered'] as List).single as Map;
      expect(npcData['autonomous_decision_ids'],
          ['gm_anna_decides_to_leave']);
      final exported = game.exportSave(id);
      final imported = game.importSave(exported,
          expectedWorldHash: installed.archiveHash);
      final replay = game.load(imported);
      expect(replay.stateHash, third.view.stateHash);
      expect(replay.npcRelations.single.autonomousDecisionIds,
          third.view.npcRelations.single.autonomousDecisionIds);
      expect(replay.alternatePlotContinuity,
          third.view.alternatePlotContinuity);
      expect(game.choose(id, actionId: 'illegal_book_continuation',
        choiceId: 'canon_next_00000', expectedRevision: 3).applied, false);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

}
