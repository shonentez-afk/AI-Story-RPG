import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:test/test.dart';

Uint8List _bytes(String source) =>
    Uint8List.fromList(utf8.encode(source));

void main() {
  test('public authoring API indexes and scans without Flutter or cloud',
      () async {
    const RpgAuthoringApi api = LocalRpgAuthoringApi();
    final input = _bytes('Мария открыла дверь. Иван ждал у ворот.');
    final book = api.parseBook('story.txt', input);
    final index = api.indexBook(book);
    final source = api.inspectSource('story.txt', input);
    expect(source.index.sourceFingerprint, index.sourceFingerprint);
    expect(source.hasCompleteText, isTrue);

    OfflineScanCheckpoint? saved;
    final scan = await api.scanSource(source,
        onCheckpoint: (checkpoint) => saved = checkpoint);
    expect(scan.summary['is_playable_rpg'], false);
    expect(scan.summary['is_literary_canon'], false);
    expect(saved, isNotNull);
    final replay = await api.scanSource(source, resume: saved);
    expect(replay.summary, scan.summary);
    final prepared = await api.prepareBook(source);
    expect(prepared.status['is_playable_rpg'], false);
    expect(prepared.status['requires_cloud'], false);
    expect(prepared.readiness.canStartPlayableBook, isFalse);
    expect(prepared.sourceFingerprint, index.sourceFingerprint);
    expect(RpgApiContract.arbitraryBookCanon, isFalse);
    expect(RpgApiContract.dynamicAiGameMaster, isFalse);
  });

  test('one-book/one-tale API scopes source without changing library book',
      () async {
    const RpgAuthoringApi api = LocalRpgAuthoringApi();
    final fb2 = _bytes('<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Сказки</book-title>'
        '</title-info></description><body>'
        '<section><p>Первая история.</p></section>'
        '<section><p>Вторая история.</p></section>'
        '</body></FictionBook>');
    final complete = api.openSource('tales.fb2', fb2);
    final scoped = api.openSource('tales.fb2', fb2, selectedChapter: 1);
    expect(complete.index.chapterCount, 2);
    expect(scoped.index.chapterCount, 1);
    expect(scoped.sourceFingerprint, isNot(complete.sourceFingerprint));
    OfflineScanCheckpoint? cp;
    final prepared = await api.prepareBook(scoped,
        onCheckpoint: (value) => cp = value);
    expect(prepared.status['stage'], 'BOOK_SOURCE_PREPARED_NEEDS_REVIEW');
    expect(cp, isNotNull);
    final repeat = await api.prepareBook(scoped, resume: cp);
    expect(repeat.status, prepared.status);
    await expectLater(api.prepareBook(complete, resume: cp),
        throwsFormatException);
  });

  test('public game API keeps signed choices, SQLite replay and portable saves',
      () {
    final archive = Uint8List.fromList(File(
        '../../artifacts/bookworld/book_private_rich_items_python.bworld')
        .readAsBytesSync());
    final directory = Directory.systemTemp.createTempSync('rpg_api_client_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(directory.path);
      RpgGameApi game = LocalRpgGameApi(store);
      final world = game.install(archive);
      final id = game.start(world.archiveHash);
      expect(game.load(id).revision, 0);
      expect(game.load(id).inventory, isNot(contains('map')));
      final denied = game.choose(id,
          actionId: 'api_denied', choiceId: 'help',
          expectedRevision: 0);
      expect(denied.applied, isFalse);
      expect(game.load(id).revision, 0);
      expect(game.choose(id, actionId: 'api_wait',
          choiceId: 'wait', expectedRevision: 0).applied, isTrue);
      expect(game.choose(id, actionId: 'api_transfer',
          choiceId: 'give_map', expectedRevision: 1).applied, isTrue);
      final committed = game.load(id);
      expect(committed.journal, hasLength(2));
      expect(committed.npcItemOwners['map'], isNotNull);
      final portable = game.exportSave(id);
      expect(game.previewSave(portable,
          expectedWorldHash: world.archiveHash).revision, 2);
      store.close();
      store = null;

      store = BookworldCampaignStore.openPrivateDirectory(directory.path);
      game = LocalRpgGameApi(store);
      expect(game.load(id).revision, 2);
      final imported = game.importSave(portable,
          expectedWorldHash: world.archiveHash);
      final recovered = game.load(imported);
      expect(recovered.sceneId, committed.sceneId);
      expect(recovered.npcItemOwners, committed.npcItemOwners);
      expect(recovered.journal.map((e) => e.choiceLabel).toList(),
          committed.journal.map((e) => e.choiceLabel).toList());
    } finally {
      store?.close();
      directory.deleteSync(recursive: true);
    }
  });
  test('complete-campaign narration API is usable without Flutter', () {
    const RpgCampaignProseApi api = LocalRpgCampaignProseApi();
    const request = '{"format":"ai_story_campaign_prose_request_v1",'
        '"batch_id":"source_scope","scenes":[{"scene_id":"entry"}]}';
    const prose = 'Старый маяк возник впереди, и его свет постепенно '
        'становился заметнее. Путник молча оценивал дорогу и ещё '
        'не принимал никакого решения, наблюдая за тихим морем.';
    final answer = jsonEncode({
      'choices': [{
        'finish_reason': 'stop',
        'message': {
          'content': jsonEncode({
            'batch_id': 'source_scope',
            'scenes': [{
              'scene_id': 'entry',
              'prose': prose,
              'uncertainty': 'Литературный смысл требует отдельной проверки.',
            }],
          }),
        },
      }],
    });
    final proposal = api.parseBatch(request, answer);
    expect(proposal.single.origin, 'ai_draft');
    expect(proposal.single.sceneId, 'entry');
    expect(() => api.parseBatch(request, answer.replaceFirst(
        'source_scope', 'forged_scope')), throwsFormatException);
    expect(LocalRpgCampaignProseApi.systemPrompt,
        contains('Никаких effects'));
  });

}
