import 'dart:convert';
import 'dart:io';

import 'package:ai_story_rpg_cli/rpg_loopback_server.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:test/test.dart';

void main() {
  test('independent HTTP client uses identical public API and SQLite rules',
      () async {
    final fixture = File(
        '../../artifacts/bookworld/book_private_rich_items_python.bworld');
    expect(fixture.existsSync(), isTrue);
    final temp = await Directory.systemTemp.createTemp('rpg_loopback_');
    RpgLoopbackServer? server;
    BookworldCampaignStore? store;
    final client = HttpClient();
    try {
      server = await RpgLoopbackServer.bind(
          privateStoreDirectory: temp.path + '/http-store');
      store = BookworldCampaignStore.openPrivateDirectory(
          temp.path + '/pure-store');
      final pure = RpgClientProtocol(LocalRpgGameApi(store));

      Future<(int, Map<String, dynamic>)> send(
          String op, Map<String, Object?> args,
          {bool auth = true, String? origin, String? version}) async {
        final request = await client.postUrl(server!.endpoint);
        request.headers.contentType = ContentType.json;
        if (auth) request.headers.set('x-rpg-token', server!.token);
        if (origin != null) request.headers.set('origin', origin);
        request.write(jsonEncode({
          'version': version ?? RpgClientProtocol.version,
          'op': op,
          'args': args,
        }));
        final response = await request.close();
        final body = jsonDecode(
            await utf8.decoder.bind(response).join()) as Map<String, dynamic>;
        return (response.statusCode, body);
      }

      Future<Map<String, dynamic>> invokeLocal(
          String op, Map<String, Object?> args) async =>
          Map<String, dynamic>.from(await pure.handle({
            'version': RpgClientProtocol.version,
            'op': op,
            'args': args,
          }));

      final unauthorized = await send('capabilities', {}, auth: false);
      expect(unauthorized.$1, HttpStatus.unauthorized);
      expect(unauthorized.$2['ok'], false);
      final crossSite = await send(
          'capabilities', {}, origin: 'http://untrusted.example');
      expect(crossSite.$1, HttpStatus.forbidden);
      final mismatch = await send('capabilities', {}, version: 'bogus');
      expect(mismatch.$2['error'], {'code': 'unsupported_version'});
      final caps = await send('capabilities', {});
      expect(caps.$1, HttpStatus.ok);
      expect(caps.$2, await invokeLocal('capabilities', {}));
      expect((caps.$2['result'] as Map)['arbitrary_book_canon'], false);
      expect((caps.$2['result'] as Map)['dynamic_ai_game_master'], false);

      final world = base64Encode(fixture.readAsBytesSync());
      final preview = await send('inspect_world',
          {'archive_base64': world});
      expect(preview.$2['ok'], true);
      expect((preview.$2['result'] as Map)['is_private'], true);
      expect((preview.$2['result'] as Map)['literary_canon_proven'], false);
      final audit = await send('audit_world', {
        'archive_base64': world, 'max_states': 2048, 'max_moves': 96,
      });
      expect(audit.$2['ok'], true);
      expect(['playable', 'blocked', 'inconclusive'],
          contains((audit.$2['result'] as Map)['status']));

      final first = await send('install_world', {'archive_base64': world});
      final second = await invokeLocal(
          'install_world', {'archive_base64': world});
      expect(first.$2, second);
      final hash = (first.$2['result'] as Map)['world_hash'] as String;

      final httpStart = (await send('start', {'world_hash': hash})).$2;
      final localStart = await invokeLocal('start', {'world_hash': hash});
      expect(httpStart['ok'], true);
      final remoteView = httpStart['result'] as Map;
      final localView = localStart['result'] as Map;
      expect(remoteView['scene_id'], localView['scene_id']);
      expect(remoteView['revision'], 0);
      expect(remoteView['inventory'], localView['inventory']);
      expect(remoteView['choices'], localView['choices']);
      expect(remoteView['npc_encountered'], localView['npc_encountered']);
      final httpId = remoteView['campaign_id'] as String;
      final waitLabel = (remoteView['choices'] as List)
          .cast<Map>().firstWhere((c) => c['id'] == 'wait')['label'] as String;
      final offered = await send('suggest_action', {
        'campaign_id': httpId, 'text': waitLabel,
      });
      expect(offered.$2['ok'], true);
      expect(((offered.$2['result'] as Map)['offers'] as List).first['choice_id'],
          'wait');

      final hinted = ((offered.$2['result'] as Map)['offers']
          as List).first as Map;
      final unconfirmed = await send('confirm_suggestion', {
        'campaign_id': httpId, 'text': waitLabel,
        'choice_id': 'wait', 'fingerprint': hinted['fingerprint'],
        'expected_revision': 0, 'action_id': 'http_no_consent',
        'user_confirmed': false,
      });
      expect(unconfirmed.$2['ok'], false);
      expect((unconfirmed.$2['error'] as Map)['code'], 'invalid_input');
      final journalBefore = await send('journal_page', {
        'campaign_id': httpId, 'after_sequence': 0, 'limit': 1,
      });
      expect((journalBefore.$2['result'] as Map)['events'], isEmpty);

      final localId = localView['campaign_id'] as String;

      final forbidden = await send('choose', {
        'campaign_id': httpId,
        'choice_id': 'help',
        'action_id': 'rpc_blocked',
        'expected_revision': 0,
      });
      expect((forbidden.$2['result'] as Map)['applied'], false);
      expect((forbidden.$2['result'] as Map)['revision'], 0);

      final httpChoice = (await send('choose', {
        'campaign_id': httpId, 'choice_id': 'wait',
        'action_id': 'rpc_wait', 'expected_revision': 0,
      })).$2['result'] as Map;
      final localChoice = (await invokeLocal('choose', {
        'campaign_id': localId, 'choice_id': 'wait',
        'action_id': 'local_wait', 'expected_revision': 0,
      }))['result'] as Map;
      expect(httpChoice['applied'], true);
      for (final key in [
        'scene_id', 'revision', 'tick', 'inventory', 'known_facts',
        'npc_encountered', 'choices', 'journal'
      ]) {
        expect(httpChoice[key], localChoice[key], reason: key);
      }
      final repeated = (await send('choose', {
        'campaign_id': httpId, 'choice_id': 'wait',
        'action_id': 'rpc_wait', 'expected_revision': 0,
      })).$2['result'] as Map;
      expect(repeated['duplicate'], true);
      expect(repeated['revision'], 1);

      final journalAfter = (await send('journal_page', {
        'campaign_id': httpId, 'after_sequence': 0, 'limit': 1,
        'expected_revision': 1,
      })).$2['result'] as Map;
      expect(journalAfter['has_more'], false);
      expect(journalAfter['state_hash'], httpChoice['state_hash']);
      expect(journalAfter['events'], httpChoice['journal']);
      final staleSuggestion = (await send('confirm_suggestion', {
        'campaign_id': httpId, 'text': waitLabel,
        'choice_id': 'wait', 'fingerprint': hinted['fingerprint'],
        'expected_revision': 0, 'action_id': 'http_stale',
        'user_confirmed': true,
      })).$2;
      expect(staleSuggestion['error'], {'code': 'stale_revision'});

      final saved = (await send('export_save', {
        'campaign_id': httpId
      })).$2['result'] as Map;
      final imported = (await send('import_save', {
        'world_hash': hash, 'save_text': saved['save_text']
      })).$2['result'] as Map;
      expect(imported['revision'], httpChoice['revision']);
      expect(imported['journal'], httpChoice['journal']);
      expect(imported['inventory'], httpChoice['inventory']);
      expect(imported['npc_encountered'], httpChoice['npc_encountered']);

      final bundle = (await send('export_bundle', {
        'campaign_id': httpId,
      })).$2['result'] as Map;
      expect((bundle['bundle'] as Map)['format'],
          RpgCampaignTransfer.format);
      final bundleReceipt = (await send('inspect_bundle', {
        'bundle': bundle['bundle'],
      })).$2['result'] as Map;
      expect(bundleReceipt['save_replay_verified'], true);
      final noImport = (await send('import_bundle', {
        'bundle': bundle['bundle'], 'user_confirmed': false,
      })).$2;
      expect(noImport['ok'], false);

      final invalid = await send('import_save', {
        'world_hash': 'f' * 64, 'save_text': saved['save_text'],
      });
      expect(invalid.$2['ok'], false);
      expect(invalid.$2['error'], {'code': 'invalid_input'});
      final prepared = await send('inspect_creation', {
        'intent': const RpgCreationIntent(
          route: RpgCreationRoute.reviewedBookwide,
          plot: RpgCreationPlot.canon,
        ).toJson(),
      });
      expect((prepared.$2['result'] as Map)['supported'], false);
    } finally {
      client.close(force: true);
      await server?.close();
      store?.close();
      await temp.delete(recursive: true);
    }
  });
}
