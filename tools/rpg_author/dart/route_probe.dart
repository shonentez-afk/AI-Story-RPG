// Source-bound, frontend-independent PRIVATE gameplay acceptance via rpg_api.
//
// Pure external CLI adapter: never implement RPG rules or expose unknown
// NPC secrets. Uses the SAME public LocalRpgGameApi as Flutter, SQLite replay
// and the native Bookworld importer. No private book files are written here.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['format'] != 'rpg_author_two_routes_native_v1' ||
      input['archive_b64'] is! String ||
      input['routes'] is! List ||
      (input['routes'] as List).length != 2) {
    throw const FormatException('Native two-route request must be explicit');
  }
  final world = Uint8List.fromList(
      base64Decode(input['archive_b64'] as String));
  final temp = Directory.systemTemp.createTempSync('rpg_private_routes_');
  BookworldCampaignStore? store;
  try {
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    final RpgGameApi api = LocalRpgGameApi(store);
    final installed = api.install(world);
    final validated = <Map<String, dynamic>>[];
    final routeIds = <String>{};
    for (final raw in input['routes'] as List) {
      if (raw is! Map<String, dynamic> ||
          raw.keys.toSet().difference({'id', 'choice_ids'}).isNotEmpty) {
        throw const FormatException('Unknown route evidence fields');
      }
      final id = raw['id'];
      final submitted = raw['choice_ids'];
      if (id is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(id) ||
          !routeIds.add(id) || submitted is! List ||
          submitted.isEmpty || submitted.length > 512 ||
          submitted.any((s) => s is! String || s.isEmpty)) {
        throw const FormatException('Invalid native route identity or length');
      }
      final steps = submitted.cast<String>();
      final campaignId = api.start(installed.archiveHash);
      var state = api.load(campaignId);
      final scenes = <String>[state.sceneId];
      final sourceEvents = <String>[];
      for (final choiceId in steps) {
        if (state.isTerminal) {
          throw const FormatException('Route continues after terminal ending');
        }
        final options = state.choices.where((choice) =>
            choice.id == choiceId).toList();
        if (options.length != 1 || !options.single.enabled) {
          throw const FormatException('Route includes an unavailable decision');
        }
        final previousRevision = state.revision;
        final outcome = api.choose(campaignId,
            actionId: 'review_' + id + '_' + previousRevision.toString(),
            choiceId: choiceId, expectedRevision: previousRevision);
        if (!outcome.applied) {
          throw const FormatException('Native RPG API refused reviewed choice');
        }
        state = api.load(campaignId);
        if (state.revision != previousRevision + 1) {
          throw const FormatException('Invalid replayed campaign revision');
        }
        scenes.add(state.sceneId);
        sourceEvents.add(choiceId);
      }
      if (!state.isTerminal || state.revision != steps.length ||
          state.journal.length != steps.length) {
        throw const FormatException('Route did not end in a playable conclusion');
      }
      final before = store.loadCampaign(campaignId).metadata.stateHash;
      final saved = api.exportSave(campaignId);
      final importedId = api.importSave(saved,
          expectedWorldHash: installed.archiveHash);
      final restored = api.load(importedId);
      final after = store.loadCampaign(importedId).metadata.stateHash;
      if (before != after || restored.revision != state.revision ||
          restored.sceneId != state.sceneId ||
          restored.isTerminal != state.isTerminal) {
        throw const FormatException('Portable save changed replayed native state');
      }
      validated.add({
        'id': id,
        'choice_ids': sourceEvents,
        'scene_ids': scenes,
        'ending_scene_id': state.sceneId,
        'terminal': true,
        'revisions': state.revision,
        'journal_count': state.journal.length,
        'state_hash': before,
        'portable_save_verified': true,
        'visible_npc_item_owners': state.npcItemOwners,
        'known_player_facts': state.knownFacts,
      });
    }
    stdout.write(jsonEncode({
      'format': 'rpg_author_native_two_routes_evidence_v1',
      'archive_sha256': installed.archiveHash,
      'verified_routes': validated,
      'true_rpg_api': true,
      'native_sqlite_portable_saves': true,
    }));
  } finally {
    store?.close();
    temp.deleteSync(recursive: true);
  }
}
