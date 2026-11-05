import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _fixture = '../../shared_schemas/fixtures/private_classic_sample.json';
const _output = '../../artifacts/bookworld/book_private_rich_dart.bworld';

Map<String, dynamic> _asObject(Object? value) =>
    Map<String, dynamic>.from(value as Map);

Map<String, dynamic> _richSample() {
  final input = _asObject(jsonDecode(File(_fixture).readAsStringSync()));
  final blueprint = _asObject(input['blueprint']);
  final provenance = _asObject(input['provenance']);
  // The original synthetic story requires only narrative flags.
  // No invented equipment, stats or player knowledge is inserted.
  expect(blueprint['items'], isEmpty);
  expect(blueprint['facts'], isEmpty);
  expect(_asObject(_asObject(blueprint['initial_state'])['stats']), isEmpty);
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = <String, dynamic>{
    'provider': 'none',
    'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none',
    'method': 'local_fixture',
  };
  provenance['presentation'] = <String, dynamic>{
    'hero': <String, String>{
      'name': 'Игрок',
      'description': 'Герой синтетической проверки решения.',
    },
    'item_names': <String, String>{},
    'item_descriptions': <String, String>{},
    'stat_names': <String, String>{},
    'fact_names': <String, String>{},
    'scene_names': <String, String>{
      'entry': 'Начало пути',
      'canon_end': 'Помощь оказана',
      'alternate_end': 'Герой ушёл',
    },
  };
  input['provenance'] = provenance;
  return input;
}

void main() {
  const writer = RichPrivateBookworldWriter();
  const importer = RichPrivateBookworldImporter();

  test('native rich v3 writes deterministic offline package with real hero and honest empty catalogs', () {
    final input = _richSample();
    final bytes = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final inspected = importer.inspect(bytes);
    expect(inspected.bookworldId, 'book_private_sample');
    expect(inspected.sourceFingerprint, 'a' * 64);
    expect(inspected.presentation['hero'], containsPair('name', 'Игрок'));
    expect(inspected.presentation['item_names'], isEmpty);
    expect(inspected.presentation['stat_names'], isEmpty);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.requiresNetwork, false);
    expect(inspected.blueprint.initial.stats, isEmpty);
    expect(inspected.blueprint.items, isEmpty);
    expect(inspected.blueprint.facts, isEmpty);
    final second = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    expect(second, orderedEquals(bytes));
    expect(() => const PrivateBookworldImporter().inspect(bytes), throwsFormatException);
    final output = File(_output);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes, flush: true);
  });

  test('native v3 records configured Z.ai model request, without claiming literary truth', () {
    final input = _richSample();
    final provenance = _asObject(input['provenance']);
    provenance['model_provenance'] = {
      'provider': 'zai',
      'model_id': 'glm-4.7-flash',
      'model_id_status': 'requested',
      'tool': 'AI Story RPG',
      'method': 'built_in',
    };
    final package = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: provenance,
      sourceIndex: _asObject(input['source_index']),
    );
    final imported = importer.inspect(package);
    expect(imported.presentation['hero'], containsPair('name', 'Игрок'));
    expect(imported.sourceFingerprint, 'a' * 64);
    final wrong = _asObject(provenance['model_provenance']);
    wrong['model_id'] = 'different_model';
    provenance['model_provenance'] = wrong;
    expect(() => writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: provenance,
      sourceIndex: _asObject(input['source_index']),
    ), throwsFormatException);
  });

  test('native v3 replays two real flag-based endings without fake inventory', () {
    final input = _richSample();
    final raw = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final verified = importer.inspect(raw);
    for (final target in ['help', 'leave']) {
      final world = StoryWorld(verified.blueprint);
      final result = world.apply(
        actionId: 'native_rich_$target',
        choiceId: target,
        expectedRevision: 0,
      );
      expect(result.status, DecisionStatus.applied);
      expect(world.isTerminal, true);
      expect(world.events.single.choiceId, target);
      expect(world.state.stats, isEmpty);
      expect(world.state.inventory, isEmpty);
      expect(world.state.knowledge['player'], isEmpty);
      final restored = StoryWorld.replay(
        verified.blueprint,
        world.events.map((event) => event.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
      );
      expect(restored.state.stateHash, world.state.stateHash);
    }
  });

  test('native v3 blocks wrong book, invented item, dishonest model and fake citation', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (input) => (input['source_index'] as Map)['source_fingerprint'] = 'f' * 64,
      (input) => (input['blueprint'] as Map)['items'] = ['ghost'],
      (input) => (input['provenance'] as Map)['model_provenance'] = {
        'provider': 'openai',
        'model_id': 'made_up_model',
        'model_id_status': 'user_declared',
        'tool': 'ChatGPT', 'method': 'external',
      },
      (input) {
        final origins = _asObject(input['provenance'])['scene_origins'] as List;
        final refs = (origins.first as Map)['source_refs'] as List;
        (refs.first as Map)['quote_sha256'] = 'f' * 64;
      },
    ]) {
      final input = _richSample();
      mutate(input);
      expect(() => writer.build(
        blueprint: _asObject(input['blueprint']),
        provenance: _asObject(input['provenance']),
        sourceIndex: _asObject(input['source_index']),
      ), throwsFormatException);
    }
  });

  test('reviewed v2 scenario promotes automatically to real rich v3 hero and journal', () {
    final input = _asObject(jsonDecode(File(_fixture).readAsStringSync()));
    final original = const PrivateBookworldWriter().build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final upgraded = writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: 'Путник',
      sceneTitles: {'entry': 'Путник решает', 'canon_end': 'Помощь',
                    'alternate_end': 'Отказ'},
    );
    final rich = importer.inspect(upgraded);
    expect(rich.bookworldId, isNot('book_private_sample'));
    expect(rich.presentation['hero'], containsPair('name', 'Путник'));
    expect(rich.presentation['scene_names'],
        containsPair('entry', 'Путник решает'));
    expect(rich.presentation['item_names'], isEmpty);
    expect(rich.blueprint.initial.stats, isEmpty);
    expect(rich.blueprint.items, isEmpty);
    expect(rich.blueprint.facts, isEmpty);
    expect(rich.sourceFingerprint, 'a' * 64);
    expect(rich.canDistributePublicly, false);
    final again = writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: 'Путник',
      sceneTitles: {'entry': 'Путник решает', 'canon_end': 'Помощь',
                    'alternate_end': 'Отказ'},
    );
    expect(again, orderedEquals(upgraded));
    expect(() => const PrivateBookworldImporter().inspect(upgraded),
        throwsFormatException);
    for (final action in ['help', 'leave']) {
      final world = StoryWorld(rich.blueprint);
      expect(world.apply(actionId: 'rich_' + action, choiceId: action,
          expectedRevision: 0).status, DecisionStatus.applied);
      expect(world.isTerminal, true);
      expect(world.events.single.choiceId, action);
      expect(world.state.inventory, isEmpty);
      expect(world.state.stats, isEmpty);
    }

    final corruptIndex = _asObject(input['source_index']);
    corruptIndex['source_fingerprint'] = 'f' * 64;
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: corruptIndex,
    ), throwsFormatException);
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: '',
    ), throwsFormatException);
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      sceneTitles: {'another_book_scene': 'Подмена'},
    ), throwsFormatException);
  });

  test('rich v3 rejects damaged ZIP without adopting it as an older format', () {
    final input = _richSample();
    final data = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final modified = Uint8List.fromList(data);
    modified[110] ^= 0xff;
    expect(() => importer.inspect(modified), throwsFormatException);
  });
}
