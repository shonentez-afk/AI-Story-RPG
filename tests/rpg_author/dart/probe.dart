import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:story_core/story_core.dart';
import 'package:bookworld_format/bookworld_format.dart';

import '../../../apps/story_reader/lib/book_import.dart';
import '../../../apps/story_reader/lib/book_source_index.dart';

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
  } else {
    throw const FormatException('Unknown probe operation');
  }
}
