import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:story_core/story_core.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';

import 'package:story_authoring/story_authoring.dart';
import 'package:rpg_api/rpg_api.dart';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['operation'] == 'source') {
    final book = BookImporter.parse(input['filename'] as String,
        Uint8List.fromList(base64Decode(input['data'] as String)));
    final index = BookSourceIndexer.index(book,
        maxChunkUtf16: input['chunk_size'] as int);
    stdout.write(jsonEncode(index.toJson()));
  } else if (input['operation'] == 'blueprint') {
    final blueprint = StoryBlueprint.fromJson(input['blueprint']);
    stdout.write(jsonEncode({
      'book_id': blueprint.bookId,
      'scene_count': blueprint.scenes.length,
    }));
  } else if (input['operation'] == 'private_archive') {
    final bytes = Uint8List.fromList(base64Decode(input['data'] as String));
    final world = const PrivateBookworldImporter().inspect(bytes);
    stdout.write(jsonEncode({
      'book_id': world.bookworldId,
      'source_fingerprint': world.sourceFingerprint,
      'archive_sha256': world.archiveSha256,
      'scene_count': world.blueprint.scenes.length,
      'can_distribute': world.canDistributePublicly,
      'requires_network': world.requiresNetwork,
    }));
  } else if (input['operation'] == 'panel_world') {
    final data = Uint8List.fromList(base64Decode(input['data'] as String));
    final checked = const BookworldImporter().inspect(data);
    final paths = input['paths'] as List<dynamic>;
    final routes = <Map<String, dynamic>>[];
    for (var routeIndex = 0; routeIndex < paths.length; routeIndex++) {
      final world = StoryWorld(checked.blueprint);
      final turns = <Map<String, dynamic>>[];
      final choices = paths[routeIndex] as List<dynamic>;
      for (var i = 0; i < choices.length; i++) {
        final id = choices[i] as String;
        final result = world.apply(
          actionId: 'test_${routeIndex}_${i}',
          choiceId: id,
          expectedRevision: world.state.revision,
        );
        if (!result.applied) {
          throw FormatException('Test route ${routeIndex}, choice ${id}: '
              '${result.reason}');
        }
        turns.add({
          'choice': id,
          'revision': world.state.revision,
          'stats': world.state.stats,
          'inventory': world.state.inventory.toList()..sort(),
          'known_facts': (world.state.knowledge['player'] ?? <String>{})
              .toList()..sort(),
          'journal_choices': world.events.map((e) => e.choiceId).toList(),
        });
      }
      final restored = StoryWorld.replay(
        checked.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
      );
      if (restored.state.stateHash != world.state.stateHash ||
          restored.events.length != world.events.length) {
        throw const FormatException('Replay lost Hero/Items/Journal state');
      }
      routes.add({
        'turns': turns,
        'terminal': world.isTerminal,
        'replayed': restored.state.stateHash == world.state.stateHash,
        'final_state_hash': world.state.stateHash,
      });
    }
    stdout.write(jsonEncode({
      'world_id': checked.bookworldId,
      'routes': routes,
    }));
  } else if (input['operation'] == 'rich_private') {
    final bytes = Uint8List.fromList(base64Decode(input['data'] as String));
    final verified = const RichPrivateBookworldImporter().inspect(bytes);
    var olderRejected = false;
    try {
      const PrivateBookworldImporter().inspect(bytes);
    } on FormatException {
      olderRejected = true;
    }
    if (!olderRejected) {
      throw const FormatException('Old v2 importer incorrectly accepted v3');
    }
    final journeys = <Map<String, dynamic>>[];
    for (final path in input['paths'] as List<dynamic>) {
      final world = StoryWorld(verified.blueprint);
      final turns = <Map<String, dynamic>>[];
      for (final choice in path as List<dynamic>) {
        final result = world.apply(
          actionId: 'rich_turn_' + (world.state.revision + 1).toString(),
          choiceId: choice as String,
          expectedRevision: world.state.revision,
        );
        if (!result.applied) {
          throw FormatException('Denied rich game choice: ' +
              choice.toString() + ' (' + result.reason.toString() + ')');
        }
        turns.add({
          'choice': choice,
          'stats': world.state.stats,
          'inventory': world.state.inventory.toList()..sort(),
          'facts': (world.state.knowledge['player'] ?? <String>{}).toList()..sort(),
          'journal': world.events.map((e) => e.choiceId).toList(),
        });
      }
      final restored = StoryWorld.replay(
        verified.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
      );
      journeys.add({
        'turns': turns,
        'terminal': world.isTerminal,
        'replay_ok': restored.state.stateHash == world.state.stateHash &&
            restored.events.length == world.events.length,
      });
    }
    stdout.write(jsonEncode({
      'book_id': verified.bookworldId,
      'format_version': verified.formatVersion,
      'source_fingerprint': verified.sourceFingerprint,
      'archive_sha256': verified.archiveSha256,
      'hero': verified.presentation['hero'],
      'item_names': verified.presentation['item_names'],
      'stat_names': verified.presentation['stat_names'],
      'fact_names': verified.presentation['fact_names'],
      'journeys': journeys,
      'v2_rejected_v3': olderRejected,
      'private_only': !verified.canDistributePublicly,
    }));
  } else if (input['operation'] == 'npc_public_api') {
    // Deliberately instantiate the SAME public API as Flutter and CLI.
    // The test supplies the SQLite directory and checks canonical replay.
    final archive = Uint8List.fromList(base64Decode(input['data'] as String));
    final private = Directory.systemTemp.createTempSync('rpg_e6j_npc_api_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(private.path);
      final RpgGameApi api = LocalRpgGameApi(store);
      final installed = api.install(archive);
      final campaignId = api.start(installed.archiveHash);
      for (final choice in input['path'] as List<dynamic>) {
        final previous = api.load(campaignId);
        final outcome = api.choose(campaignId,
          actionId: 'e6j_act_' + (previous.revision + 1).toString(),
          choiceId: choice as String,
          expectedRevision: previous.revision);
        if (!outcome.applied) {
          throw FormatException('Public RPG API refused selected NPC action: '
            + choice.toString() + ' (' + outcome.reason.toString() + ')');
        }
      }
      final view = api.load(campaignId);
      final signed = store.loadCampaign(campaignId);
      final hash = signed.metadata.stateHash;
      final saved = api.exportSave(campaignId);
      final importedId = api.importSave(saved,
          expectedWorldHash: installed.archiveHash);
      final imported = api.load(importedId);
      final verifiedSave = store.loadCampaign(importedId);
      if (verifiedSave.metadata.stateHash != hash ||
          imported.revision != view.revision) {
        throw const FormatException('NPC public API .bwsave lost verified state');
      }
      stdout.write(jsonEncode({
        'revision': view.revision,
        'scene_id': view.sceneId,
        'terminal': view.isTerminal,
        'tick': view.tick,
        'inventory': view.inventory,
        'known_facts': view.knownFacts,
        'npc_knowledge': {
          for (final actor in signed.coordinator.state.knowledge.keys)
            if (actor != 'player')
              actor: signed.coordinator.state.knowledge[actor]!.toList()..sort(),
        },
        'npc_relations': [
          for (final relation in view.npcRelations) {
            'actor_id': relation.actorId,
            'directed_score': relation.directedScore,
            'memory_count': relation.memoryCount,
            'memory_kinds': relation.memoryKinds,
            'life_state': relation.lifeState,
          }
        ],
        'npc_life_states': view.npcLifeStates,
        'choices': [
          for (final choice in view.choices) {
            'id': choice.id,
            'enabled': choice.enabled,
            'lock_reason': choice.lockReason,
          }
        ],
        'journal': view.journal.map((event) => event.choiceLabel).toList(),
        'state_hash': hash,
        'portable_save_verified': true,
      }));
    } finally {
      store?.close();
      private.deleteSync(recursive: true);
    }
  } else if (input['operation'] == 'rich_campaign') {
    final archive = Uint8List.fromList(base64Decode(input['data'] as String));
    final temp = Directory.systemTemp.createTempSync('rpg_e4_campaign_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      final installed = store.installBookworld(archive);
      final campaignId = store.createCampaign(installed.archiveHash);
      for (final choice in input['path'] as List<dynamic>) {
        final record = store.loadCampaign(campaignId);
        final outcome = store.commitChoice(
          campaignId,
          actionId: 'demo_action_' + (record.metadata.revision + 1).toString(),
          choiceId: choice as String,
          expectedRevision: record.metadata.revision,
        );
        if (!outcome.applied) {
          throw FormatException('SQLite rejected real game action: ' +
              outcome.reason.toString());
        }
      }
      final record = store.loadCampaign(campaignId);
      final expectedHash = record.metadata.stateHash;
      final save = store.exportPortable(campaignId);
      final fork = store.createCampaign(installed.archiveHash,
          parentCampaignId: campaignId);
      final forkRecord = store.loadCampaign(fork);
      store.close();
      store = null;

      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      final resumed = store.loadCampaign(campaignId);
      if (resumed.metadata.stateHash != expectedHash ||
          resumed.coordinator.events.length != record.coordinator.events.length) {
        throw const FormatException('SQLite failed rich game persistence');
      }
      final importedId = store.importPortable(save);
      final imported = store.loadCampaign(importedId);
      if (imported.metadata.stateHash != expectedHash ||
          forkRecord.metadata.stateHash != expectedHash) {
        throw const FormatException('Rich .bwsave or fork lost the game state');
      }
      stdout.write(jsonEncode({
        'revision': resumed.metadata.revision,
        'stats': resumed.coordinator.state.stats,
        'inventory': resumed.coordinator.state.inventory.toList()..sort(),
        'facts': (resumed.coordinator.state.knowledge['player'] ?? <String>{})
            .toList()..sort(),
        'journal': resumed.coordinator.events.map((e) => e.choiceId).toList(),
        'state_hash': expectedHash,
        'restart_ok': true,
        'save_import_ok': true,
        'fork_ok': true,
      }));
    } finally {
      store?.close();
      temp.deleteSync(recursive: true);
    }
  } else {
    throw const FormatException('Unknown probe operation');
  }
}
