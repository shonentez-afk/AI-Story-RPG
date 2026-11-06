import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

StoryBlueprint originalBlueprint() {
  final raw = File('../../shared_schemas/fixtures/manor_world_m17.json')
      .readAsStringSync();
  return StoryBlueprint.fromJson(jsonDecode(raw));
}

Map<String, dynamic> mutableFixture() => jsonDecode(
  File('../../shared_schemas/fixtures/manor_world_m17.json')
      .readAsStringSync(),
) as Map<String, dynamic>;

DecisionResult step(StoryWorld world, String id, String choice) =>
    world.apply(actionId: id, choiceId: choice,
      expectedRevision: world.state.revision);

void main() {
  test('offline blueprint validates 8 original demo scenes and a terminal', () {
    final blueprint = originalBlueprint();
    expect(blueprint.bookId, 'manor_m17_original_demo');
    expect(blueprint.scenes.length, 8);
    expect(blueprint.entrySceneId, 'gate');
    expect(blueprint.initial.stats['insight'], 0);
    expect(blueprint.actors, containsAll(['player', 'guard']));
  });

  test('private sourced CLASSIC contract is isolated from original_demo',
      () {
    final raw = mutableFixture();
    raw['rights_status'] = 'private_adaptation';
    raw['source_fingerprint'] = 'a' * 64;
    (raw['supported_modes'] as Map)['plots'] = ['ALTER_FATE'];
    final private = StoryBlueprint.fromJson(raw);
    expect(private.rightsStatus, 'private_adaptation');
    expect(private.sourceFingerprint, 'a' * 64);
    final world = StoryWorld(private);
    expect(world.state.sceneId, 'gate');
    final fallback = mutableFixture();
    expect(StoryBlueprint.fromJson(fallback).rightsStatus, 'original_demo');
    expect(StoryBlueprint.fromJson(fallback).sourceFingerprint, isNull);

    final lyingDemo = mutableFixture();
    lyingDemo['source_fingerprint'] = 'a' * 64;
    expect(() => StoryBlueprint.fromJson(lyingDemo), throwsFormatException);
    final falseRight = mutableFixture();
    falseRight['rights_status'] = 'public_domain';
    expect(() => StoryBlueprint.fromJson(falseRight), throwsFormatException);
    final invalidPrivate = mutableFixture();
    invalidPrivate['rights_status'] = 'private_adaptation';
    invalidPrivate['source_fingerprint'] = 'not_sha';
    expect(() => StoryBlueprint.fromJson(invalidPrivate),
        throwsFormatException);
    final fakeFreeMode = mutableFixture();
    fakeFreeMode['rights_status'] = 'private_adaptation';
    fakeFreeMode['source_fingerprint'] = 'a' * 64;
    (fakeFreeMode['supported_modes'] as Map)['plots'] = ['FREE_WORLD'];
    expect(() => StoryBlueprint.fromJson(fakeFreeMode),
        throwsFormatException);
  });

  test('denials have no side effects or fabricated items', () {
    final world = StoryWorld(originalBlueprint());
    final before = world.state.stateHash;
    expect(step(world, 'a_1', 'enter_hall').status, DecisionStatus.denied);
    expect(step(world, 'a_2', 'not_an_option').reason,
        'choice_not_in_current_scene');
    expect(world.state.inventory, isEmpty);
    expect(world.state.stats['insight'], 0);
    expect(world.state.revision, 0);
    expect(world.events, isEmpty);
    expect(world.state.stateHash, before);
    expect(world.state.knowledge['guard'], isEmpty);
  });

  test('35 deterministic turns, 2 locations, knowledge and terminal', () {
    final world = StoryWorld(originalBlueprint());
    final mirror = StoryWorld(originalBlueprint());
    void both(String id, String choice) {
      final a = step(world, id, choice);
      final b = step(mirror, id, choice);
      expect(a.status, DecisionStatus.applied, reason: id);
      expect(b.status, DecisionStatus.applied, reason: id);
      expect(a.event!.hash, b.event!.hash);
    }

    for (var i = 0; i < 23; i++) {
      both('inspect_$i', 'inspect_gate');
    }
    expect(world.state.tick, 46);
    both('walk_market_1', 'walk_market');
    both('talk_guard', 'ask_guard');
    both('walk_market_2', 'walk_market');
    both('take_map', 'buy_map');
    both('walk_market_3', 'walk_market');
    both('take_key', 'find_key');
    both('enter', 'enter_hall');
    both('ask_family', 'learn_from_guard');
    both('write', 'write_note');
    both('descend', 'go_cellar');
    both('open', 'open_vault');
    both('finish', 'publish_archive');
    expect(world.events.length, 35);
    expect(world.state.revision, 35);
    expect(world.state.sceneId, 'end_reveal');
    expect(world.isTerminal, isTrue);
    expect(world.state.flags['revealed'], true);
    expect(world.state.inventory, contains('map'));
    expect(world.state.inventory, isNot(contains('key')));
    expect(world.state.knowledge['player'],
        containsAll(['family_secret', 'archive_origin']));
    expect(world.state.knowledge['guard'], isEmpty);
    expect(world.state.stateHash, mirror.state.stateHash);
    final replayed = StoryWorld.replay(
      originalBlueprint(), world.events.map((e) => e.toJson()),
      expectedSequence: 35,
      expectedStateHash: world.state.stateHash,
    );
    expect(replayed.state.stateHash, world.state.stateHash);
    expect(replayed.events.last.hash, world.events.last.hash);
    expect(step(world, 'after_end', 'inspect_gate').reason,
        'terminal_scene');
  });

  test('duplicate action is idempotent, reused ID with new choice rejects', () {
    final world = StoryWorld(originalBlueprint());
    expect(step(world, 'unique_1', 'inspect_gate').applied, true);
    final hash = world.state.stateHash;
    final duplicate = world.apply(
        actionId: 'unique_1', choiceId: 'inspect_gate');
    expect(duplicate.status, DecisionStatus.duplicate);
    expect(world.events.length, 1);
    expect(world.state.stateHash, hash);
    expect(() => world.apply(
      actionId: 'unique_1', choiceId: 'walk_market'),
      throwsFormatException);
    expect(world.apply(
      actionId: 'second', choiceId: 'walk_market', expectedRevision: 0).reason,
      'stale_revision');
    expect(world.state.sceneId, 'gate');
  });

  test('failed second effect cannot partially grant inventory', () {
    final mutable = mutableFixture();
    final scenes = mutable['scenes'] as List<dynamic>;
    final gate = scenes.first as Map<String, dynamic>;
    final choices = gate['choices'] as List<dynamic>;
    final inspect = choices.first as Map<String, dynamic>;
    inspect['effects'] = [
      {'op': 'grant_item', 'id': 'map'},
      {'op': 'consume_item', 'id': 'key'},
    ];
    final world = StoryWorld(StoryBlueprint.fromJson(mutable));
    final hash = world.state.stateHash;
    final result = step(world, 'invalid_effect', 'inspect_gate');
    expect(result.reason, 'missing_item');
    expect(world.state.stateHash, hash);
    expect(world.state.inventory, isEmpty);
    expect(world.events, isEmpty);
  });

  test('event tampering and history truncation are detected by replay', () {
    final world = StoryWorld(originalBlueprint());
    for (var i = 0; i < 4; i++) {
      step(world, 'inspect_$i', 'inspect_gate');
    }
    final captured = world.events.map((e) =>
        Map<String, dynamic>.from(e.toJson())).toList();
    captured[1]['next_scene_id'] = 'market';
    expect(() => StoryWorld.replay(originalBlueprint(), captured),
        throwsFormatException);
    captured[1] = Map<String, dynamic>.from(world.events[1].toJson());
    captured.removeAt(1);
    expect(() => StoryWorld.replay(originalBlueprint(), captured),
        throwsFormatException);
  });

  test('replay is bound to exact blueprint version and expected head', () {
    final original = originalBlueprint();
    final world = StoryWorld(original);
    for (var i = 0; i < 4; i++) {
      expect(step(world, 'inspect_$i', 'inspect_gate').applied, true);
    }
    final complete = world.events.map((e) => e.toJson()).toList();
    final prefix = complete.take(3).toList();
    expect(() => StoryWorld.replay(original, prefix,
        expectedSequence: 4, expectedStateHash: world.state.stateHash),
        throwsFormatException);
    final altered = mutableFixture();
    altered['title'] = 'Новая версия тех же правил';
    final otherVersion = StoryBlueprint.fromJson(altered);
    expect(otherVersion.blueprintHash, isNot(original.blueprintHash));
    // Same choices/effects cannot silently import a log from a new story.
    expect(() => StoryWorld.replay(otherVersion, complete),
        throwsFormatException);
  });

  test('input catalog, scene references, modes and JSON DSL reject lies', () {
    final x = mutableFixture();
    (x['scenes'] as List)[0]['choices'][0]['next_scene_id'] = 'not_found';
    expect(() => StoryBlueprint.fromJson(x), throwsFormatException);

    final y = mutableFixture();
    (y['supported_modes'] as Map)['interactions'] = ['AI_FREEFORM'];
    expect(() => StoryBlueprint.fromJson(y), throwsFormatException);

    final incompatibleRole = mutableFixture();
    (incompatibleRole['supported_modes'] as Map)['roles'] = ['CUSTOM'];
    expect(() => StoryBlueprint.fromJson(incompatibleRole),
        throwsFormatException);

    final z = mutableFixture();
    (z['scenes'] as List)[0]['choices'][0]['effects'] = [
      {'op': 'run_python', 'code': 'print(1)'},
    ];
    expect(() => StoryBlueprint.fromJson(z), throwsFormatException);

    final p = mutableFixture();
    (p['scenes'] as List)[0]['choices'][0]['conditions'] = [
      {'op': 'has_item', 'id': 'unlisted_item'},
    ];
    expect(() => StoryBlueprint.fromJson(p), throwsFormatException);
  });

  test('a fork is isolated and lock reasons match core validation', () {
    final original = StoryWorld(originalBlueprint());
    final preview = original.fork();
    expect(original.choiceLockReason('enter_hall'),
        'condition_not_met:has_item');
    expect(preview.apply(
        actionId: 'tentative', choiceId: 'inspect_gate').applied, isTrue);
    expect(preview.state.revision, 1);
    expect(preview.events.length, 1);
    expect(original.state.revision, 0);
    expect(original.events, isEmpty);
    expect(original.choiceLockReason('inspect_gate'), isNull);
  });

  test('NPC knowledge is proven by an actual committed choice, not a book mention', () {
    final raw = mutableFixture();
    final scenes = raw['scenes'] as List<dynamic>;
    final gate = scenes.first as Map<String, dynamic>;
    final choices = gate['choices'] as List<dynamic>;
    final inspect = choices.first as Map<String, dynamic>;
    inspect['effects'] = [
      {'op': 'learn_fact', 'id': 'family_secret', 'actor': 'guard'},
    ];
    final blueprint = StoryBlueprint.fromJson(raw);
    final world = StoryWorld(blueprint);
    expect(world.actorKnowsFact('guard', 'family_secret'), isFalse);
    expect(world.factLearningEvents('guard', 'family_secret'), isEmpty);
    expect(world.actorKnowsFact('player', 'family_secret'), isFalse);

    // Taking a different branch does not grant knowledge from indexed prose.
    final alternate = StoryWorld(blueprint);
    expect(step(alternate, 'other_path', 'walk_market').applied, isTrue);
    expect(alternate.actorKnowsFact('guard', 'family_secret'), isFalse);
    expect(alternate.factLearningEvents('guard', 'family_secret'), isEmpty);

    // A rejected action has no knowledge effect or evidence.
    expect(step(world, 'denied_action', 'enter_hall').applied, isFalse);
    expect(world.factLearningEvents('guard', 'family_secret'), isEmpty);
    expect(step(world, 'teach_guard', 'inspect_gate').applied, isTrue);
    expect(world.actorKnowsFact('guard', 'family_secret'), isTrue);
    expect(world.actorKnowsFact('player', 'family_secret'), isFalse);
    final evidence = world.factLearningEvents('guard', 'family_secret');
    expect(evidence, hasLength(1));
    expect(evidence.single.actionId, 'teach_guard');
    expect(evidence.single.choiceId, 'inspect_gate');
    expect(evidence.single.hash, world.events.single.hash);
    expect(() => evidence.clear(), throwsUnsupportedError);
    expect(world.factLearningEvents('player', 'family_secret'), isEmpty);

    // Repeated action IDs cannot manufacture a second learning event.
    expect(world.apply(actionId: 'teach_guard', choiceId: 'inspect_gate')
        .status, DecisionStatus.duplicate);
    expect(world.factLearningEvents('guard', 'family_secret'), hasLength(1));

    // A verified replay proves the identical source of acquired knowledge.
    final restored = StoryWorld.replay(blueprint,
        world.events.map((event) => event.toJson()),
        expectedSequence: 1, expectedStateHash: world.state.stateHash);
    expect(restored.actorKnowsFact('guard', 'family_secret'), isTrue);
    expect(restored.factLearningEvents('guard', 'family_secret')
        .single.hash, evidence.single.hash);
    expect(() => restored.factLearningEvents('missing', 'family_secret'),
        throwsFormatException);
    expect(() => restored.actorKnowsFact('guard', 'missing'),
        throwsFormatException);
  });

  test('authoritative WorldState cannot be modified by UI callers', () {
    final world = StoryWorld(originalBlueprint());
    expect(() => world.state.inventory.add('key'), throwsUnsupportedError);
    expect(() => world.state.stats['trust'] = 1000, throwsUnsupportedError);
    expect(() => world.state.knowledge['guard']!.add('family_secret'),
        throwsUnsupportedError);
  });
}
