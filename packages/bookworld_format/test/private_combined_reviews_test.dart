import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _npc = 'npc_cccccccccccccccccccccccccccccccc';

Map<String, dynamic> _fixture() {
  final input = jsonDecode(File('../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final bp = input['blueprint'] as Map<String, dynamic>;
  final source = input['provenance'] as Map<String, dynamic>;
  bp['actors'] = ['player', _npc];
  bp['facts'] = ['player_seen', 'npc_seen'];
  (bp['initial_state'] as Map)['knowledge'] = {'player': <String>[], _npc: <String>[]};
  final entry = (bp['scenes'] as List).first as Map;
  final choices = entry['choices'] as List;
  (choices.first as Map)['effects'] = [
    {'op': 'learn_fact', 'id': 'player_seen', 'actor': 'player'},
    {'op': 'learn_fact', 'id': 'npc_seen', 'actor': _npc},
  ];
  (choices[1] as Map)['conditions'] = [
    {'op': 'knows_fact', 'id': 'player_seen', 'actor': 'player'},
    {'op': 'knows_fact', 'id': 'npc_seen', 'actor': _npc},
  ];
  source['format'] = 'ai_story_private_provenance_v2';
  source['model_provenance'] = {
    'provider': 'none', 'model_id': null, 'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  source['presentation'] = {
    'hero': {'name': 'Игрок', 'description': 'Синтетическая проверка независимых знаний.'},
    'item_names': <String, String>{}, 'item_descriptions': <String, String>{},
    'stat_names': <String, String>{},
    'fact_names': {'player_seen': 'Мария', 'npc_seen': 'Встреча NPC'},
    'scene_names': {'entry': 'Начало', 'canon_end': 'Помощь', 'alternate_end': 'Отказ'},
  };
  final quote = ((source['scene_origins'] as List).first['source_refs'] as List)
      .first['quote_sha256'];
  source['npc_knowledge'] = {
    'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': bp['source_fingerprint'],
    'user_confirmed': true, 'literary_canon_verified': false,
    'grants': [
      {'scene_id': 'entry', 'choice_id': 'wait', 'actor_id': _npc,
       'fact_id': 'npc_seen', 'source_quote_sha256': quote},
    ],
  };
  source['gameplay_review'] = {
    'format': 'ai_story_private_gameplay_review_m2h8e1_v1',
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': bp['source_fingerprint'],
    'base_archive_sha256': List.filled(64, 'a').join(),
    'source_payload_digest': List.filled(64, 'b').join(),
    'user_confirmed': true, 'literary_canon_verified': false,
    'effects': [
      {'scene_id': 'entry', 'choice_id': 'wait', 'op': 'learn_fact', 'kind': 'fact',
       'id': 'player_seen', 'label': 'Мария', 'source_quote_sha256': quote,
       'review_note': 'Частный игровой факт о показанной цитате, не литературный канон.'},
    ],
  };
  return input;
}

void main() {
  const writer = RichPrivateBookworldWriter();
  const reader = RichPrivateBookworldImporter();

  test('strict importer joins exact player and NPC reviews; independent Python '
      'accepts the identical Dart-created ZIP and SQLite', () {
    final input = _fixture();
    final bytes = writer.build(
      blueprint: input['blueprint'] as Map<String, dynamic>,
      provenance: input['provenance'] as Map<String, dynamic>,
      sourceIndex: input['source_index'] as Map<String, dynamic>,
    );
    final checked = reader.inspect(bytes);
    final world = StoryWorld(checked.blueprint);
    expect(world.apply(actionId: 'no_facts', choiceId: 'help').applied, false);
    expect(world.apply(actionId: 'meeting', choiceId: 'wait').applied, true);
    expect(world.state.knowledge['player'], {'player_seen'});
    expect(world.state.knowledge[_npc], {'npc_seen'});
    expect(world.apply(actionId: 'help_after', choiceId: 'help').applied, true);
    expect(world.isTerminal, true);
    final copy = StoryWorld.replay(checked.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision, expectedStateHash: world.state.stateHash);
    expect(copy.state.stateHash, world.state.stateHash);
    final file = File('../../artifacts/bookworld/book_private_combined_reviews_dart.bworld');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    // Test-only cross-language tool, not a runtime dependency. M1.7 already
    // provisions Python to independently verify native-created BookWorlds.
    final python = Process.runSync('python3', [
      '-c',
      'import sys; from pathlib import Path; '
      'from tools.bookworld.private_rich_bookworld import verify; '
      'result = verify(Path(sys.argv[1]).read_bytes()); '
      'assert result["scene_count"] == 3; '
      'print("COMPOSED_DART_PYTHON_PASS")',
      file.absolute.path,
    ], workingDirectory: Directory('../..').absolute.path);
    expect(python.exitCode, 0, reason: '${python.stdout}\n${python.stderr}');
    expect(python.stdout, contains('COMPOSED_DART_PYTHON_PASS'));
  });

  test('NPC review cannot cover an extra player fact with the same fact id', () {
    final input = _fixture();
    final bp = input['blueprint'] as Map<String, dynamic>;
    final effects = (bp['scenes'] as List).first['choices'][0]['effects'] as List;
    effects.add({'op': 'learn_fact', 'id': 'npc_seen', 'actor': 'player'});
    expect(() => writer.build(blueprint: bp,
      provenance: input['provenance'] as Map<String, dynamic>,
      sourceIndex: input['source_index'] as Map<String, dynamic>), throwsFormatException);
  });

  test('composition rejects missing NPC evidence and rehashed source substitution', () {
    for (final mutation in ['remove', 'actor', 'quote', 'grant', 'unapproved']) {
      final input = _fixture();
      final source = input['provenance'] as Map<String, dynamic>;
      final npc = source['npc_knowledge'] as Map;
      final grant = (npc['grants'] as List).single as Map;
      switch (mutation) {
        case 'remove': source.remove('npc_knowledge');
        case 'actor': grant['actor_id'] = 'player';
        case 'quote': grant['source_quote_sha256'] = List.filled(64, 'f').join();
        case 'grant': npc['grants'] = <Object>[];
        case 'unapproved': npc['user_confirmed'] = false;
      }
      expect(() => writer.build(
        blueprint: input['blueprint'] as Map<String, dynamic>, provenance: source,
        sourceIndex: input['source_index'] as Map<String, dynamic>),
        throwsFormatException, reason: mutation);
    }
  });

  test('ordinary review cannot be reassigned to an NPC or omit a player action', () {
    for (final mutation in ['reassign', 'omit']) {
      final input = _fixture();
      final source = input['provenance'] as Map<String, dynamic>;
      final review = source['gameplay_review'] as Map;
      if (mutation == 'reassign') {
        (review['effects'] as List).single['id'] = 'npc_seen';
        (review['effects'] as List).single['label'] = 'Встреча NPC';
      } else { review['effects'] = <Object>[]; }
      expect(() => writer.build(
        blueprint: input['blueprint'] as Map<String, dynamic>, provenance: source,
        sourceIndex: input['source_index'] as Map<String, dynamic>), throwsFormatException);
    }
  });
}
