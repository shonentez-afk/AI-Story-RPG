import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:test/test.dart';

const _fixturePath = '../../shared_schemas/fixtures/private_classic_sample.json';
const _npcId = 'npc_aaaaaaaaaaaaaaaaaaaa';
const _factId = 'fact_bbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> _knowledgeFixture() {
  final source = jsonDecode(File(_fixturePath).readAsStringSync())
      as Map<String, dynamic>;
  final bp = source['blueprint'] as Map<String, dynamic>;
  (bp['actors'] as List).add(_npcId);
  (bp['facts'] as List).add(_factId);
  ((bp['initial_state'] as Map<String, dynamic>)['knowledge']
      as Map<String, dynamic>)[_npcId] = <String>[];
  final entry = (bp['scenes'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((scene) => scene['id'] == 'entry');
  final choices = (entry['choices'] as List)
      .cast<Map<String, dynamic>>();
  (choices.singleWhere((choice) => choice['id'] == 'wait')['effects']
      as List).add({
    'op': 'learn_fact',
    'id': _factId,
    'actor': _npcId,
  });
  (choices.singleWhere((choice) => choice['id'] == 'help')['conditions']
      as List).add({
    'op': 'knows_fact',
    'id': _factId,
    'actor': _npcId,
  });
  return source;
}

void main() {
  test('120 real SQLite turns preserve NPC knowledge across .bwsave '
      'and independent devices', () {
    final sourceRoot = Directory.systemTemp
        .createTempSync('ai_story_npc_sqlite_source_');
    final receiverRoot = Directory.systemTemp
        .createTempSync('ai_story_npc_sqlite_receiver_');
    BookworldCampaignStore? source;
    BookworldCampaignStore? receiver;
    try {
      final data = _knowledgeFixture();
      final archive = const PrivateBookworldWriter().build(
        blueprint: data['blueprint'] as Map<String, dynamic>,
        provenance: data['provenance'] as Map<String, dynamic>,
        sourceIndex: data['source_index'] as Map<String, dynamic>,
      );
      final originating = BookworldCampaignStore.openPrivateDirectory(sourceRoot.path);
      source = originating;
      final installed = originating.installBookworld(archive);
      final campaign = originating.createCampaign(installed.archiveHash);

      final before = originating.loadCampaign(campaign);
      expect(before.metadata.revision, 0);
      expect(before.coordinator.state.knowledge[_npcId], isEmpty);
      final denied = originating.commitChoice(
        campaign, actionId: 'no_future_knowledge', choiceId: 'help',
        expectedRevision: 0,
      );
      expect(denied.applied, isFalse);
      expect(originating.loadCampaign(campaign).metadata.stateHash,
          before.metadata.stateHash);

      for (var i = 0; i < 120; i++) {
        final result = originating.commitChoice(
          campaign, actionId: 'wait_$i', choiceId: 'wait',
          expectedRevision: i,
        );
        expect(result.applied, isTrue, reason: 'SQLite turn $i');
      }
      final beforeBackup = originating.loadCampaign(campaign);
      expect(beforeBackup.metadata.revision, 120);
      expect(beforeBackup.coordinator.state.knowledge[_npcId], {_factId});
      expect(beforeBackup.coordinator.state.knowledge['player'], isEmpty);
      expect(beforeBackup.coordinator.sceneId, 'entry');

      final stableHash = beforeBackup.metadata.stateHash;
      final stableHead = beforeBackup.metadata.headEventHash;
      final portable = originating.exportPortable(campaign);
      final worldBackup = originating.exportBookworld(installed.archiveHash);
      expect(worldBackup, orderedEquals(archive));
      expect(portable, isNot(contains('source_index')));
      expect(portable, isNot(contains('source_text')));

      originating.close();
      source = null;
      final restarted = BookworldCampaignStore.openPrivateDirectory(sourceRoot.path);
      source = restarted;
      final reopened = restarted.loadCampaign(campaign);
      expect(reopened.metadata.revision, 120);
      expect(reopened.metadata.stateHash, stableHash);
      expect(reopened.metadata.headEventHash, stableHead);
      expect(reopened.coordinator.state.knowledge[_npcId], {_factId});

      final destination = BookworldCampaignStore.openPrivateDirectory(receiverRoot.path);
      receiver = destination;
      expect(() => destination.previewPortable(portable), throwsFormatException);
      destination.installBookworld(worldBackup);
      final preview = destination.previewPortable(portable);
      expect(preview.revision, 120);
      expect(preview.stateHash, stableHash);
      expect(destination.campaigns(), isEmpty);

      // Even a modified checkpoint with the original checksum must fail
      // before any new campaign is created.
      final tampered = jsonDecode(portable) as Map<String, dynamic>;
      tampered['checksum_sha256'] = List<String>.filled(64, '0').join();
      expect(() => destination.importPortable(jsonEncode(tampered)),
          throwsFormatException);
      expect(destination.campaigns(), isEmpty);

      final imported = destination.importPortable(portable);
      expect(imported, isNot(campaign));
      expect(destination.campaigns(), hasLength(1));
      final received = destination.loadCampaign(imported);
      expect(received.metadata.revision, 120);
      expect(received.metadata.stateHash, stableHash);
      expect(received.metadata.headEventHash, stableHead);
      expect(received.coordinator.state.knowledge[_npcId], {_factId});
      expect(received.coordinator.state.knowledge['player'], isEmpty);

      final canon = restarted.commitChoice(
        campaign, actionId: 'choose_canon', choiceId: 'help',
        expectedRevision: 120,
      );
      final alternate = destination.commitChoice(
        imported, actionId: 'choose_alternate', choiceId: 'leave',
        expectedRevision: 120,
      );
      expect(canon.applied, isTrue);
      expect(alternate.applied, isTrue);
      final firstEnd = restarted.loadCampaign(campaign);
      final secondEnd = destination.loadCampaign(imported);
      expect(firstEnd.coordinator.sceneId, 'canon_end');
      expect(secondEnd.coordinator.sceneId, 'alternate_end');
      expect(firstEnd.coordinator.isTerminal, isTrue);
      expect(secondEnd.coordinator.isTerminal, isTrue);
      expect(firstEnd.metadata.stateHash,
          isNot(secondEnd.metadata.stateHash));
      expect(firstEnd.coordinator.state.knowledge['player'], isEmpty);
      expect(secondEnd.coordinator.state.knowledge['player'], isEmpty);
    } finally {
      source?.close();
      receiver?.close();
      sourceRoot.deleteSync(recursive: true);
      receiverRoot.deleteSync(recursive: true);
    }
  });
}
