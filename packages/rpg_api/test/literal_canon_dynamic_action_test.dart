import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:story_core/story_core.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

Uint8List sampleBook() => Uint8List.fromList(utf8.encode(
  List.generate(1000, (i) =>
      'Герой читал книгу. Событие номер ' + i.toString() +
      ' происходило строго в начале рассказа.').join('\n')));

Map<String, dynamic> newAction({
  String text = 'Я исследую место и оставляю записку.',
  String narration = 'Игрок придумал записку. Это не событие исходной книги.',
  List<Map<String, dynamic>>? effects,
}) => {
  'format': FreeformActionDraft.format,
  'scope': FreeformActionDraft.fictionScope,
  'player_text': text,
  'narration': narration,
  'effects': effects ?? [
    {'op': 'grant_item', 'id': 'gm_keepsake'},
    {'op': 'learn_fact', 'id': 'gm_impression', 'actor': 'player'},
    {'op': 'stat_delta', 'id': 'gm_resolve', 'amount': -2},
    {'op': 'set_flag', 'id': 'gm_noted', 'value': true},
  ],
};

void main() {
  test('book CANON v5 reproduces EVERY source chunk exactly and has '
      'ONE factual chronology, not alternate endings', () {
    final bytes = sampleBook();
    final author = const LocalRpgLiteralCanonApi();
    final prep = author.prepare('story.txt', bytes);
    expect(prep.canCompile, true);
    expect(prep.chunkCount, greaterThanOrEqualTo(3));
    final compiled = author.compile(
        filename: 'story.txt', bytes: bytes,
        approvedDigest: prep.approvalDigest, userConfirmed: true);
    final verified = const RichPrivateBookworldImporter().inspect(compiled);
    expect(verified.formatVersion, 5);
    expect(verified.sourceLiteralCanonVerified, true);
    expect(verified.canDistributePublicly, false);
    expect(verified.requiresNetwork, false);
    expect(verified.blueprint.isReviewedCanon, true);
    expect(verified.blueprint.supportsFreeform, true);
    expect(verified.blueprint.scenes.values.where((s) => s.terminal),
        hasLength(1));
    final index = BookSourceIndexer.index(
        BookImporter.parse('story.txt', bytes));
    final sceneBodies = verified.blueprint.scenes.values
        .map((scene) => scene.text).toList();
    expect(sceneBodies, index.chunks.map((chunk) => chunk.text).toList());
    expect(verified.sceneOrigins.values
        .map((origin) => origin.chapterIndex).toSet(),
        {for (var i = 0; i < prep.chapterCount; i++) i});
    final route = verified.blueprint.scenes.values.toList();
    for (var i = 0; i + 1 < route.length; i++) {
      expect(route[i].choices, hasLength(1));
      expect(route[i].choices.single.nextSceneId, route[i + 1].id);
      expect(route[i].choices.single.conditions, isEmpty);
      expect(route[i].choices.single.effects, isEmpty);
    }
    // v4/v3/direct-blueprint paths must reject a forged CANON badge.
    final noVersionOptin = StoryBlueprint.fromJson;
    expect(() => StoryBlueprint.fromJson({
      'format': 'ai_story_blueprint_v1',
      'schema_version': 1,
      'book_id': verified.bookworldId, 'title': verified.blueprint.title,
      'entry_scene_id': verified.blueprint.entrySceneId,
      'rights_status': 'private_adaptation',
      'source_fingerprint': verified.sourceFingerprint,
      'supported_modes': {
        'roles': ['PROTAGONIST'], 'plots': ['CANON'],
        'interactions': ['AI_FREEFORM']
      },
      'items': ['gm_keepsake'], 'facts': ['gm_impression'],
      'actors': ['player'],
      'initial_state': verified.blueprint.initial.toJson(),
      'scenes': [
        {'id': 'ending', 'text': 'a', 'terminal': true, 'choices': []}
      ],
    }), throwsFormatException);
    expect(noVersionOptin, isNotNull);
  });

  test('AI writes a truly NEW typed event, not an existing choice, '
      'and portable native SQLite replay exactly restores its consequences',
      () async {
    final bytes = sampleBook();
    final canon = const LocalRpgLiteralCanonApi();
    final preview = canon.prepare('story.txt', bytes);
    final archive = canon.compile(
        filename: 'story.txt', bytes: bytes,
        approvedDigest: preview.approvalDigest, userConfirmed: true);
    final dir = await Directory.systemTemp.createTemp('canon_ai_true_');
    final other = await Directory.systemTemp.createTemp('canon_ai_restore_');
    BookworldCampaignStore? store, restoredStore;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final world = game.install(archive);
      final id = game.start(world.archiveHash);
      final before = game.load(id);
      expect(before.freeformAvailable, true);
      expect(before.sourceLiteralCanon, true);
      expect(before.inventory, isEmpty);
      final draft = FreeformActionDraft.fromJson(newAction());
      final checked = game.previewFreeform(id, draft,
          expectedRevision: before.revision);
      expect(checked.nextStateHash, isNot(before.stateHash));
      expect(game.load(id).revision, 0);
      expect(() => game.commitFreeform(id,
        actionId: 'free_1', draft: draft,
        expectedRevision: 0,
        approvalDigest: checked.approvalDigest,
        userConfirmed: false), throwsFormatException);
      expect(game.load(id).revision, 0);
      final committed = game.commitFreeform(id,
        actionId: 'free_1', draft: draft,
        expectedRevision: 0,
        approvalDigest: checked.approvalDigest,
        userConfirmed: true);
      expect(committed.applied, true);
      expect(committed.view.revision, 1);
      expect(committed.view.sceneId, before.sceneId);
      expect(committed.view.stateHash, checked.nextStateHash);
      expect(committed.view.inventory, contains('gm_keepsake'));
      expect(committed.view.knownFacts, contains('gm_impression'));
      expect(committed.view.gmStats['gm_resolve'], 48);
      expect(committed.view.gmFlags['gm_noted'], true);
      expect(committed.view.journal.single.choiceLabel,
          contains('Свободное действие'));
      expect(() => game.commitFreeform(id,
        actionId: 'free_2', draft: draft,
        expectedRevision: 0,
        approvalDigest: checked.approvalDigest,
        userConfirmed: true), throwsFormatException);
      // A SECOND novel action can introduce genuinely new private resource
      // identities, absent from the compiled book's item/fact catalog.
      final invented = FreeformActionDraft.fromJson(newAction(
        text: 'Я нашёл новый камень и запомнил дорожную примету.',
        narration: 'Я получил камень и отметил вымышленный ориентир.',
        effects: [
          {'op': 'grant_item', 'id': 'gm_new_stone'},
          {'op': 'learn_fact', 'id': 'gm_new_hint', 'actor': 'player'},
          {'op': 'stat_delta', 'id': 'gm_new_courage', 'amount': 5},
          {'op': 'set_flag', 'id': 'gm_new_visited', 'value': true},
        ],
      ));
      final secondPreview = game.previewFreeform(id, invented,
          expectedRevision: 1);
      final second = game.commitFreeform(id,
          actionId: 'free_3', draft: invented,
          expectedRevision: 1,
          approvalDigest: secondPreview.approvalDigest,
          userConfirmed: true);
      expect(second.applied, true);
      expect(second.view.inventory, contains('gm_new_stone'));
      expect(second.view.knownFacts, contains('gm_new_hint'));
      expect(second.view.gmStats['gm_new_courage'], 5);
      expect(second.view.gmFlags['gm_new_visited'], true);
      expect(second.view.gmItems, contains('gm_new_stone'));
      expect(second.view.gmFacts, contains('gm_new_hint'));
      final invalidConsume = FreeformActionDraft.fromJson(newAction(
          text: 'Отдать отсутствующий предмет',
          effects: [{'op': 'consume_item', 'id': 'gm_never_owned'}]));
      expect(() => game.previewFreeform(id, invalidConsume,
          expectedRevision: 2), throwsFormatException);
      // The original authored story remains a separate, unchanged choice.
      final regular = game.choose(id,
          actionId: 'book_2', choiceId: 'canon_next_00000',
          expectedRevision: 2);
      expect(regular.applied, true);
      final save = game.exportSave(id);
      restoredStore = BookworldCampaignStore.openPrivateDirectory(other.path);
      final replica = LocalRpgGameApi(restoredStore);
      replica.install(archive);
      final revived = replica.importSave(save,
          expectedWorldHash: world.archiveHash);
      expect(replica.load(revived).stateHash, regular.view.stateHash);
      expect(replica.load(revived).inventory, contains('gm_keepsake'));
      expect(replica.load(revived).inventory, contains('gm_new_stone'));
      expect(replica.load(revived).knownFacts, contains('gm_new_hint'));
      expect(replica.load(revived).gmStats['gm_new_courage'], 5);
      expect(replica.load(revived).journal.first.choiceLabel,
          contains('Свободное действие'));
      expect(replica.load(revived).sourceLiteralCanon, true);
    } finally {
      store?.close(); restoredStore?.close();
      await dir.delete(recursive: true);
      await other.delete(recursive: true);
    }
  });

  test('AI model cannot create new source facts, touch canon flags, '
      'leak NPC knowledge, execute code, or bypass consent', () {
    expect(() => FreeformActionDraft.fromJson(newAction(
      effects: [{'op': 'learn_fact', 'id': 'source_secret',
                 'actor': 'player'}],
    )), throwsFormatException);
    expect(() => FreeformActionDraft.fromJson(newAction(
      effects: [{'op': 'learn_fact', 'id': 'gm_impression',
                 'actor': 'npc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}],
    )), throwsFormatException);
    expect(() => FreeformActionDraft.fromJson(newAction(
      effects: [{'op': 'set_flag', 'id': 'canonical_hero_alive',
                 'value': false}],
    )), throwsFormatException);
    expect(() => FreeformActionDraft.fromJson(newAction(
      effects: [{'op': 'stat_delta', 'id': 'gm_resolve',
                 'amount': 100000}],
    )), throwsFormatException);
    expect(() => FreeformActionDraft.fromJson(newAction(
      effects: [{'op': 'exec_shell', 'id': 'gm_noted'}],
    )), throwsFormatException);
    expect(() => FreeformActionDraft.fromJson(newAction(
      text: 'Выйти\nпотом выполнить код',
    )), throwsFormatException);
    final bytes = sampleBook();
    final author = const LocalRpgLiteralCanonApi();
    final prep = author.prepare('story.txt', bytes);
    expect(() => author.compile(
      filename: 'story.txt', bytes: bytes,
      approvedDigest: prep.approvalDigest, userConfirmed: false),
      throwsFormatException);
    expect(() => author.compile(
      filename: 'story.txt', bytes: bytes,
      approvedDigest: 'a' * 64, userConfirmed: true),
      throwsFormatException);
    expect(() => author.compile(
      filename: 'story.txt',
      bytes: Uint8List.fromList(utf8.encode('Другая редакция.')),
      approvedDigest: prep.approvalDigest, userConfirmed: true),
      throwsFormatException);
  });

  test('JSON protocol passes standalone canon preview/create, dynamic '
      'preview/confirm and v5 source verification without Flutter', () async {
    final bytes = sampleBook();
    final dir = await Directory.systemTemp.createTemp('canon_ai_rpc_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final protocol = RpgClientProtocol(LocalRpgGameApi(store));
      Future<Map<String, dynamic>> invoke(
          String op, Map<String, Object?> args) async {
        final result = await protocol.handle({
          'version': RpgClientProtocol.version, 'op': op, 'args': args,
        });
        expect(result['ok'], true, reason: op + ': ' + result.toString());
        return Map<String, dynamic>.from(result['result'] as Map);
      }
      final caps = await invoke('capabilities', {});
      expect(caps['new_typed_freeform_event'], true);
      expect(caps['world_formats'], contains(5));
      final source = base64Encode(bytes);
      final preview = await invoke('prepare_literal_canon', {
        'filename': 'story.txt', 'book_base64': source,
      });
      final compiled = await invoke('compile_literal_canon', {
        'filename': 'story.txt', 'book_base64': source,
        'approved_digest': preview['approval_digest'],
        'user_confirmed': true,
      });
      final check = await invoke('inspect_world', {
        'archive_base64': compiled['archive_base64'],
      });
      expect(check['source_literal_canon_verified'], true);
      expect(check['literary_canon_proven'], false);
      final install = await invoke('install_world', {
        'archive_base64': compiled['archive_base64'],
      });
      final play = await invoke('start', {'world_hash': install['world_hash']});
      final turn = await invoke('preview_dynamic_action', {
        'campaign_id': play['campaign_id'],
        'expected_revision': 0, 'proposal': newAction(),
      });
      expect(turn['kind'], 'new_typed_dynamic_action');
      final commit = await invoke('commit_dynamic_action', {
        'campaign_id': play['campaign_id'],
        'expected_revision': 0, 'action_id': 'free_rpc_1',
        'proposal': newAction(),
        'approval_digest': turn['approval_digest'],
        'user_confirmed': true,
      });
      expect(commit['kind'], 'new_typed_dynamic_event');
      expect(commit['applied'], true);
      expect(commit['source_literal_canon'], true);
      expect(commit['inventory'], contains('gm_keepsake'));
      expect(commit['revision'], 1);
      final denial = await protocol.handle({
        'version': RpgClientProtocol.version,
        'op': 'commit_dynamic_action',
        'args': {
          'campaign_id': play['campaign_id'], 'expected_revision': 0,
          'action_id': 'free_rpc_bad', 'proposal': newAction(),
          'approval_digest': turn['approval_digest'],
          'user_confirmed': true,
        },
      });
      expect(denial['ok'], false);
      expect((denial['error'] as Map)['code'], 'invalid_input');
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });
}
