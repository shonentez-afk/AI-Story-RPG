import 'dart:convert';
import 'dart:io';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File(
      '../../artifacts/bookworld/book_private_rich_items_python.bworld');

  test('independent clients transfer original archive and verified replay',
      () async {
    expect(fixture.existsSync(), isTrue);
    final dir = await Directory.systemTemp.createTemp('rpg_transfer_');
    BookworldCampaignStore? firstStore, secondStore;
    try {
      firstStore = BookworldCampaignStore.openPrivateDirectory(
          dir.path + '/client_a');
      secondStore = BookworldCampaignStore.openPrivateDirectory(
          dir.path + '/client_b');
      final first = RpgClientProtocol(LocalRpgGameApi(firstStore));
      final second = RpgClientProtocol(LocalRpgGameApi(secondStore));

      Future<Map<String, dynamic>> invoke(RpgClientProtocol protocol,
          String op, Map<String, Object?> args) async {
        final result = await protocol.handle({
          'version': RpgClientProtocol.version,
          'op': op, 'args': args,
        });
        expect(result['version'], RpgClientProtocol.version);
        return Map<String, dynamic>.from(result);
      }

      final caps = await invoke(first, 'capabilities', {});
      final capabilities = caps['result'] as Map;
      expect(capabilities['safe_free_text_confirmation'], true);
      expect(capabilities['self_contained_private_transfer'], true);
      expect(capabilities['web_runtime'], false);
      expect(capabilities['arbitrary_book_canon'], false);

      final installed = await invoke(first, 'install_world', {
        'archive_base64': base64Encode(fixture.readAsBytesSync()),
      });
      final worldHash = (installed['result'] as Map)['world_hash'] as String;
      final start = await invoke(first, 'start', {'world_hash': worldHash});
      final startView = start['result'] as Map;
      final id = startView['campaign_id'] as String;
      expect(startView['state_hash'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(startView['revision'], 0);

      final denied = await invoke(first, 'confirm_suggestion', {
        'campaign_id': id,
        'text': 'Подождать',
        'choice_id': 'wait',
        'fingerprint': 'f' * 64,
        'expected_revision': 0,
        'action_id': 'transfer_unauthorized',
        'user_confirmed': true,
      });
      expect(denied['ok'], false);
      expect(denied['error'], {'code': 'stale_revision'});

      final text = (startView['choices'] as List)
          .cast<Map>().firstWhere((c) => c['id'] == 'wait')['label'] as String;
      final offers = (await invoke(first, 'suggest_action', {
        'campaign_id': id, 'text': text,
      }))['result'] as Map;
      final offer = (offers['offers'] as List).first as Map;

      final noConsent = await invoke(first, 'confirm_suggestion', {
        'campaign_id': id, 'text': text, 'choice_id': 'wait',
        'fingerprint': offer['fingerprint'], 'expected_revision': 0,
        'action_id': 'transfer_no_consent', 'user_confirmed': false,
      });
      expect(noConsent['ok'], false);
      final fakeChoice = await invoke(first, 'confirm_suggestion', {
        'campaign_id': id, 'text': text, 'choice_id': 'help',
        'fingerprint': offer['fingerprint'], 'expected_revision': 0,
        'action_id': 'transfer_hidden', 'user_confirmed': true,
      });
      expect(fakeChoice['ok'], false);

      final moved = await invoke(first, 'confirm_suggestion', {
        'campaign_id': id, 'text': text, 'choice_id': 'wait',
        'fingerprint': offer['fingerprint'], 'expected_revision': 0,
        'action_id': 'transfer_wait', 'user_confirmed': true,
      });
      expect(moved['ok'], true);
      final movedView = moved['result'] as Map;
      expect(movedView['applied'], true);
      expect(movedView['revision'], 1);
      expect(movedView['state_hash'], isNot(startView['state_hash']));

      final stale = await invoke(first, 'confirm_suggestion', {
        'campaign_id': id, 'text': text, 'choice_id': 'wait',
        'fingerprint': offer['fingerprint'], 'expected_revision': 0,
        'action_id': 'transfer_stale', 'user_confirmed': true,
      });
      expect(stale['error'], {'code': 'stale_revision'});

      final page = await invoke(first, 'journal_page', {
        'campaign_id': id, 'after_sequence': 0,
        'limit': 1, 'expected_revision': 1,
      });
      final pageBody = page['result'] as Map;
      expect(pageBody['state_hash'], movedView['state_hash']);
      expect((pageBody['events'] as List), hasLength(1));
      expect(pageBody['next_sequence'], 1);
      expect(pageBody['has_more'], false);
      final wrongCursor = await invoke(first, 'journal_page', {
        'campaign_id': id, 'expected_revision': 0,
      });
      expect(wrongCursor['error'], {'code': 'stale_revision'});

      final exported = await invoke(first, 'export_bundle', {
        'campaign_id': id,
      });
      final bundle = (exported['result'] as Map)['bundle'] as Map;
      expect(bundle['format'], RpgCampaignTransfer.format);
      expect(bundle['world_hash'], worldHash);
      expect(bundle['state_hash'], movedView['state_hash']);

      final receipt = (await invoke(second, 'inspect_bundle', {
        'bundle': bundle,
      }))['result'] as Map;
      expect(receipt['archive_verified'], true);
      expect(receipt['world_installed'], false);
      expect(receipt['save_replay_verified'], false);
      expect(receipt['needs_explicit_confirmation'], true);

      final unapproved = await invoke(second, 'import_bundle', {
        'bundle': bundle, 'user_confirmed': false,
      });
      expect(unapproved['ok'], false);
      expect((await invoke(second, 'worlds', {}))['result'],
          {'worlds': []});

      for (final corrupted in [
        {...bundle, 'bundle_sha256': 'f' * 64},
        {...bundle, 'revision': 0},
        {...bundle, 'state_hash': '0' * 64},
      ]) {
        final bad = await invoke(second, 'import_bundle', {
          'bundle': corrupted, 'user_confirmed': true,
        });
        expect(bad['ok'], false);
        expect((await invoke(second, 'worlds', {}))['result'],
            {'worlds': []});
      }
      final restored = await invoke(second, 'import_bundle', {
        'bundle': bundle, 'user_confirmed': true,
      });
      expect(restored['ok'], true);
      final restoredView = restored['result'] as Map;
      expect(restoredView['status'], 'imported');
      expect(restoredView['campaign_id'], isNot(id));
      for (final key in [
        'scene_id', 'revision', 'state_hash', 'tick',
        'known_facts', 'inventory', 'npc_encountered', 'journal', 'choices',
      ]) {
        expect(restoredView[key], movedView[key], reason: key);
      }
      final installedReceipt = await invoke(second, 'inspect_bundle', {
        'bundle': bundle,
      });
      expect((installedReceipt['result'] as Map)['save_replay_verified'],
          true);
      final renewed = await invoke(second, 'view', {
        'campaign_id': restoredView['campaign_id'],
      });
      expect((renewed['result'] as Map)['state_hash'],
          movedView['state_hash']);
    } finally {
      firstStore?.close();
      secondStore?.close();
      await dir.delete(recursive: true);
    }
  });
}
