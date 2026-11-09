import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:test/test.dart';

void main() {
  test('BookWorld v4 transfers to an empty client and survives SQLite reopen',
      () async {
    final fixture = File(
        '../../artifacts/bookworld/book_private_extended_dart.bworld');
    expect(fixture.existsSync(), isTrue);
    final archive = Uint8List.fromList(fixture.readAsBytesSync());
    final intake = const LocalRpgWorldIntakeApi().inspect(archive);
    expect(intake.formatVersion, 4);
    final root = await Directory.systemTemp.createTemp('rpg_v4_bundle_');
    BookworldCampaignStore? a, b, reopened;
    try {
      final bDir = root.path + '/destination';
      a = BookworldCampaignStore.openPrivateDirectory(root.path + '/source');
      b = BookworldCampaignStore.openPrivateDirectory(bDir);
      final source = LocalRpgGameApi(a);
      final dest = LocalRpgGameApi(b);

      final installed = source.install(archive);
      expect(installed.archiveHash, intake.archiveHash);
      final srcId = source.start(installed.archiveHash);
      final view = source.load(srcId);
      expect(view.stateHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      final bundle = RpgCampaignTransfer.create(source, srcId);
      final preview = RpgCampaignTransfer.inspect(dest, bundle);
      expect(preview['archive_verified'], true);
      expect(preview['world_installed'], false);
      expect(preview['save_replay_verified'], false);
      expect(() => RpgCampaignTransfer.restore(dest, bundle,
          confirmed: false), throwsFormatException);
      expect(dest.worlds(), isEmpty);

      final restoredId = RpgCampaignTransfer.restore(dest, bundle,
          confirmed: true);
      expect(restoredId, isNot(srcId));
      final copy = dest.load(restoredId);
      expect(copy.stateHash, view.stateHash);
      expect(copy.revision, view.revision);
      expect(copy.sceneId, view.sceneId);
      expect(copy.inventory, view.inventory);
      expect(copy.knownFacts, view.knownFacts);
      expect(copy.sceneSource?.chapterIndex, view.sceneSource?.chapterIndex);
      expect(copy.sceneSource?.isSourcePassage,
          view.sceneSource?.isSourcePassage);
      expect(copy.npcRelations.length, view.npcRelations.length);
      expect(RpgCampaignTransfer.inspect(dest, bundle)
          ['save_replay_verified'], true);

      b.close();
      b = null;
      reopened = BookworldCampaignStore.openPrivateDirectory(bDir);
      final durable = LocalRpgGameApi(reopened).load(restoredId);
      expect(durable.stateHash, view.stateHash);
      expect(durable.sceneId, view.sceneId);
      expect(durable.sceneSource?.chapterIndex,
          view.sceneSource?.chapterIndex);
    } finally {
      a?.close();
      b?.close();
      reopened?.close();
      await root.delete(recursive: true);
    }
  });
}
