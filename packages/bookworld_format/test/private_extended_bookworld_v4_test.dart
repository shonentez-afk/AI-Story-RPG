import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const fixturePath = '../../shared_schemas/fixtures/private_classic_sample.json';
Map<String, dynamic> obj(Object? x) => Map<String, dynamic>.from(x as Map);

Map<String, dynamic> largeFixture({int additionalScenes = 200}) {
  final input = obj(jsonDecode(File(fixturePath).readAsStringSync()));
  final blueprint = obj(input['blueprint']);
  final source = obj(input['provenance']);
  final entry = obj((blueprint['scenes'] as List).first);
  final choices = (entry['choices'] as List).cast<Map<String, dynamic>>();
  final help = choices.firstWhere((x) => x['id'] == 'help');
  help['next_scene_id'] = 'long_0000';
  help['conditions'] = [
    {'op': 'tick_at_least', 'amount': 2}
  ];
  final fillers = <Map<String, dynamic>>[
    for (var i = 0; i < additionalScenes; i++)
      {
        'id': 'long_' + i.toString().padLeft(4, '0'),
        'text': 'Проверенная частная адаптация: эпизод ' + (i + 1).toString(),
        'terminal': false,
        'choices': [
          {
            'id': 'next_' + i.toString().padLeft(4, '0'),
            'label': 'Продолжить путь',
            'next_scene_id': i + 1 == additionalScenes
                ? 'canon_end'
                : 'long_' + (i + 1).toString().padLeft(4, '0'),
            'conditions': <Object>[],
            'effects': i == 0
                ? <Object>[{'op': 'advance_time', 'amount': 3}]
                : <Object>[],
          },
        ],
      },
  ];
  blueprint['scenes'] = [
    entry, ...fillers, ...(blueprint['scenes'] as List).skip(1),
  ];
  blueprint['items'] = ['initial_letter'];
  blueprint['facts'] = ['initial_secret'];
  final initial = obj(blueprint['initial_state']);
  initial['tick'] = 2;
  initial['inventory'] = ['initial_letter'];
  initial['knowledge'] = {'player': ['initial_secret']};
  blueprint['initial_state'] = initial;

  source['format'] = 'ai_story_private_provenance_v2';
  source['model_provenance'] = {
    'provider': 'none', 'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  final origin = obj((source['scene_origins'] as List).first);
  final quoted = (origin['source_refs'] as List).first as Map;
  final hash = quoted['quote_sha256'] as String;
  source['scene_origins'] = [
    origin,
    for (var i = 0; i < additionalScenes; i++)
      {
        'scene_id': 'long_' + i.toString().padLeft(4, '0'),
        'chapter_index': 0,
        'origin': 'EXPLICIT_ADAPTATION',
        'assertion_ids': <String>[],
        'source_refs': <Object>[],
      },
    ...(source['scene_origins'] as List).skip(1),
  ];
  source['presentation'] = {
    'hero': {
      'name': 'Игрок',
      'description': 'Участник частной структурной RPG по книге.',
    },
    'item_names': {'initial_letter': 'Письмо'},
    'item_descriptions': {'initial_letter': 'Письмо при герое'},
    'stat_names': <String, String>{},
    'fact_names': {'initial_secret': 'Известная герою подробность'},
    'scene_names': {
      for (final s in blueprint['scenes'] as List)
        (s as Map)['id'] as String: 'Часть ' + (s['id'] as String),
    },
  };
  source['initial_state_review'] = {
    'format': RichPrivateBookworldImporter.initialStateReviewFormat,
    'source_fingerprint': blueprint['source_fingerprint'],
    'review_scope': 'user_declared_private_game_fiction',
    'user_confirmed': true,
    'literary_canon_verified': false,
    'initial_tick': 2,
    'item_grants': [
      {'item_id': 'initial_letter', 'source_quote_sha256': hash},
    ],
    'fact_grants': [
      {
        'actor_id': 'player', 'fact_id': 'initial_secret',
        'source_quote_sha256': hash,
      },
    ],
  };
  input['blueprint'] = blueprint;
  input['provenance'] = source;
  return input;
}

void main() {
  const writer = RichPrivateBookworldWriter();
  const reader = RichPrivateBookworldImporter();

  test('v4 compiles >192 scenes, reviewed initial items/knowledge and time'
      ' and replays without cloud or Flutter', () {
    final sample = largeFixture();
    final archive = writer.build(
      blueprint: obj(sample['blueprint']),
      provenance: obj(sample['provenance']),
      sourceIndex: obj(sample['source_index']),
      expanded: true,
    );
    final v4 = reader.inspect(archive);
    expect(v4.formatVersion, 4);
    expect(v4.sourceChaptersIndexed, v4.sourceChaptersTotal);
    expect(v4.sceneOrigins.length, 203);
    expect(v4.sceneOrigins['long_0000']!.isSourcePassage, false);
    expect(v4.sceneOrigins['long_0000']!.chapterIndex, 0);
    expect(v4.sceneOrigins['entry']!.isSourcePassage, true);
    expect(v4.blueprint.scenes.length, 203);
    expect(v4.requiresNetwork, false);
    expect(v4.canDistributePublicly, false);
    final game = StoryWorld(v4.blueprint);
    expect(game.state.inventory, contains('initial_letter'));
    expect(game.state.knowledge['player'], contains('initial_secret'));
    expect(game.state.tick, 2);
    final enter = game.apply(actionId: 'help', choiceId: 'help');
    expect(enter.status, DecisionStatus.applied);
    expect(game.state.tick, 3);
    final turn = game.apply(actionId: 'into_chapter', choiceId: 'next_0000');
    expect(turn.status, DecisionStatus.applied);
    expect(game.state.tick, 7);
    final restored = StoryWorld.replay(
      v4.blueprint, game.events.map((e) => e.toJson()),
      expectedSequence: game.state.revision,
      expectedStateHash: game.state.stateHash,
    );
    expect(restored.state.stateHash, game.state.stateHash);
    expect(restored.state.inventory, contains('initial_letter'));
    final path = File('../../artifacts/bookworld/book_private_extended_dart.bworld');
    path.parent.createSync(recursive: true);
    path.writeAsBytesSync(archive);
  });

  test('legacy v3 rejects expanded world; tampered initial evidence fails', () {
    final sample = largeFixture();
    expect(() => writer.build(
      blueprint: obj(sample['blueprint']),
      provenance: obj(sample['provenance']),
      sourceIndex: obj(sample['source_index']),
    ), throwsFormatException);
    final corrupt = largeFixture();
    final provenance = obj(corrupt['provenance']);
    final review = obj(provenance['initial_state_review']);
    final claims = review['fact_grants'] as List;
    (claims.first as Map)['source_quote_sha256'] = '0' * 64;
    expect(() => writer.build(
      blueprint: obj(corrupt['blueprint']),
      provenance: provenance,
      sourceIndex: obj(corrupt['source_index']),
      expanded: true,
    ), throwsFormatException);
    final noConsent = largeFixture();
    obj(noConsent['provenance']['initial_state_review'])['user_confirmed'] =
        false;
    // Mutating a detached map has no effect; explicitly set the nested value.
    (noConsent['provenance']['initial_state_review'] as Map)['user_confirmed'] =
        false;
    expect(() => writer.build(
      blueprint: obj(noConsent['blueprint']),
      provenance: obj(noConsent['provenance']),
      sourceIndex: obj(noConsent['source_index']),
      expanded: true,
    ), throwsFormatException);
  });

  test('v4 reuses the exact private source and never grants free CANON', () {
    final sample = largeFixture(additionalScenes: 200);
    final payload = writer.build(
      blueprint: obj(sample['blueprint']),
      provenance: obj(sample['provenance']),
      sourceIndex: obj(sample['source_index']),
      expanded: true,
    );
    final verified = reader.inspect(payload);
    expect(verified.blueprint.rightsStatus, 'private_adaptation');
    expect(verified.blueprint.initial.tick, 2);
    expect(verified.presentation['hero']['name'], 'Игрок');
    expect(verified.formatVersion, 4);
  });
}
