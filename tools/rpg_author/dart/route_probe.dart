// Reviewed PRIVATE route replay via the ONLY native LocalRpgGameApi.
//
// The TWO reviewer-locked routes are replayed with a shared source prefix:
// execute shared choices ONCE, fork the exact verified SQLite campaign head
// through RpgGameApi.start(parentCampaignId:...), then independently replay
// each distinct suffix. No parallel game rules, no forged state hashes and
// no raw source text or portable saves on stdout.
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
    final routeIds = <String>{};
    final routes = <({String id, List<String> choices})>[];
    for (final raw in input['routes'] as List) {
      if (raw is! Map<String, dynamic> ||
          raw.keys.toSet().difference({'id', 'choice_ids'}).isNotEmpty ||
          raw.keys.length != 2) {
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
      routes.add((id: id, choices: submitted.cast<String>()));
    }

    final first = routes[0].choices;
    final second = routes[1].choices;
    var commonLength = 0;
    while (commonLength < first.length && commonLength < second.length &&
           first[commonLength] == second[commonLength]) {
      commonLength++;
    }

    // Genuine SQLite state replay is authoritative for the shared prefix.
    final commonCampaign = api.start(installed.archiveHash);
    var commonState = api.load(commonCampaign);
    final commonScenes = <String>[commonState.sceneId];
    final commonChoices = <String>[];
    for (var i = 0; i < commonLength; i++) {
      final choiceId = first[i];
      if (commonState.isTerminal) {
        throw const FormatException('Reviewed common path ends prematurely');
      }
      final options = commonState.choices.where((choice) =>
          choice.id == choiceId && choice.enabled).toList();
      if (options.length != 1) {
        throw const FormatException('Shared prefix contains unavailable decision');
      }
      final revision = commonState.revision;
      final outcome = api.choose(commonCampaign,
          actionId: 'review_shared_' + revision.toString(),
          choiceId: choiceId, expectedRevision: revision);
      if (!outcome.applied || outcome.view.revision != revision + 1) {
        throw const FormatException('Native engine refused common path');
      }
      // choose() ALREADY returns the new native view; no second load().
      commonState = outcome.view;
      commonScenes.add(commonState.sceneId);
      commonChoices.add(choiceId);
    }

    final validated = <Map<String, dynamic>>[];
    for (final route in routes) {
      // Two independent forks from precisely the same inspected source
      // campaign, so no result is contaminated by the other ending.
      final campaignId = api.start(installed.archiveHash,
          parentCampaignId: commonCampaign);
      var state = api.load(campaignId);
      if (state.revision != commonLength ||
          state.sceneId != commonState.sceneId) {
        throw const FormatException('Native campaign fork changed shared state');
      }
      final scenes = <String>[...commonScenes];
      final sourceEvents = <String>[...commonChoices];
      for (final choiceId in route.choices.skip(commonLength)) {
        if (state.isTerminal) {
          throw const FormatException('Route continues after terminal ending');
        }
        final options = state.choices.where((choice) =>
            choice.id == choiceId && choice.enabled).toList();
        if (options.length != 1) {
          throw const FormatException('Route includes an unavailable decision');
        }
        final previousRevision = state.revision;
        final outcome = api.choose(campaignId,
            actionId: 'review_' + route.id + '_' + previousRevision.toString(),
            choiceId: choiceId, expectedRevision: previousRevision);
        if (!outcome.applied ||
            outcome.view.revision != previousRevision + 1) {
          throw const FormatException('Native RPG API refused reviewed choice');
        }
        state = outcome.view;
        scenes.add(state.sceneId);
        sourceEvents.add(choiceId);
      }
      if (!state.isTerminal || state.revision != route.choices.length ||
          state.journal.length != route.choices.length ||
          sourceEvents.length != route.choices.length) {
        throw const FormatException('Route did not end in a playable conclusion');
      }

      // Portable SQLite save/import is still verified for EACH ending,
      // including the independently forked common event prefix.
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
        'id': route.id,
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
