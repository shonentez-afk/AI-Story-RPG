// Private *route discovery* through the SAME LocalRpgGameApi as Flutter.
//
// No Python simulator. Breadth-first play through ACTUAL enabled choices.
// Returns two reachable, distinct terminal scenes or fails closed.
// No source book text, dialogue, personal data or saves on stdout.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['format'] != 'rpg_author_native_route_discovery_v1' ||
      input['archive_b64'] is! String) {
    throw const FormatException('Invalid native route discovery request');
  }
  final world = Uint8List.fromList(
      base64Decode(input['archive_b64'] as String));
  final temp = Directory.systemTemp.createTempSync('rpg_discover_private_');
  BookworldCampaignStore? store;
  try {
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    final RpgGameApi api = LocalRpgGameApi(store);
    final installed = api.install(world);
    final queue = <List<String>>[<String>[]];
    var cursor = 0;
    final endings = <String>{};
    final found = <Map<String, Object?>>[];
    final explored = <String>{};
    const maxNodes = 3000;
    const maxSteps = 512;
    while (cursor < queue.length && cursor < maxNodes && found.length < 2) {
      final path = queue[cursor++];
      final campaign = api.start(installed.archiveHash);
      var state = api.load(campaign);
      for (final id in path) {
        final matches = state.choices.where(
            (choice) => choice.id == id && choice.enabled).toList();
        if (matches.length != 1 || state.isTerminal) {
          throw const FormatException('Native BFS reconstructed invalid path');
        }
        final outcome = api.choose(campaign,
            actionId: 'discover_' + state.revision.toString(),
            choiceId: id, expectedRevision: state.revision);
        if (!outcome.applied) {
          throw const FormatException('Native API refused discovered path');
        }
        state = api.load(campaign);
      }
      if (state.isTerminal) {
        if (endings.add(state.sceneId) && path.isNotEmpty) {
          found.add({
            'id': 'route_' + (found.length + 1).toString(),
            'choice_ids': path,
            'expected_ending_scene_id': state.sceneId,
          });
        }
        continue;
      }
      if (path.length >= maxSteps) continue;
      // Native state hashes are used only to skip genuinely equivalent
      // engine states; they are not a second state simulator.
      final hash = store.loadCampaign(campaign).metadata.stateHash;
      if (!explored.add(hash)) continue;
      final enabled = state.choices.where((c) => c.enabled).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final choice in enabled) {
        if (queue.length >= maxNodes) break;
        queue.add([...path, choice.id]);
      }
    }
    if (found.length != 2) {
      throw const FormatException(
          'Two distinct reachable native endings were not found in budget');
    }
    stdout.write(jsonEncode({
      'format': 'rpg_author_native_two_discovered_routes_v1',
      'archive_sha256': installed.archiveHash,
      'routes': found,
      'explored_states': explored.length,
      'true_rpg_api': true,
      'native_world_readonly': true,
    }));
  } finally {
    store?.close();
    temp.deleteSync(recursive: true);
  }
}
