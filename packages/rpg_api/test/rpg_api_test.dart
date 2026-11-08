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
    expect(RpgApiContract.arbitraryBookCanon, isFalse);
    expect(RpgApiContract.dynamicAiGameMaster, isFalse);
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
}
