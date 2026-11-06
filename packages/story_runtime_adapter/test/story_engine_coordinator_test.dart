import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:story_runtime_adapter/story_runtime_adapter.dart';
import 'package:test/test.dart';

Map<String, dynamic> mutableFixture() => jsonDecode(
  File('../../shared_schemas/fixtures/manor_world_m17.json')
      .readAsStringSync(),
) as Map<String, dynamic>;

StoryBlueprint fixture() => StoryBlueprint.fromJson(mutableFixture());

DecisionResult take(
  StoryEngineCoordinator adapter, String id, String choice,
) => adapter.choose(
  actionId: id,
  choiceId: choice,
  expectedRevision: adapter.state.revision,
);

void main() {
  test('selected story_engine starts at the exact authoritative core scene', () {
    final adapter = StoryEngineCoordinator.start(fixture());
    expect(adapter.sceneId, 'gate');
    expect(adapter.sceneText, fixture().scenes['gate']!.text);
    expect(adapter.state.revision, 0);
    expect(adapter.events, isEmpty);
    expect(adapter.choices.length, 4);
    expect(adapter.choices.map((v) => v.id),
        containsAll(['inspect_gate', 'walk_market', 'enter_hall', 'leave']));
    expect(adapter.choices.singleWhere((v) => v.id == 'enter_hall').enabled,
        isFalse);
    expect(adapter.isTerminal, isFalse);
  });

  test('35 confirmed choices have identical core hashes and restored scene', () {
    final blueprint = fixture();
    var coordinator = StoryEngineCoordinator.start(blueprint);
    final standalone = StoryWorld(blueprint);
    void both(String id, String choice) {
      final bridged = take(coordinator, id, choice);
      final reference = standalone.apply(
        actionId: id,
        choiceId: choice,
        expectedRevision: standalone.state.revision,
      );
      expect(bridged.applied, isTrue, reason: id);
      expect(reference.applied, isTrue, reason: id);
      expect(bridged.event!.hash, reference.event!.hash);
      expect(coordinator.state.stateHash, standalone.state.stateHash);
      expect(coordinator.sceneId, standalone.state.sceneId);
    }

    for (var i = 0; i < 23; i++) {
      both('inspect_$i', 'inspect_gate');
    }
    final halfway = coordinator.checkpoint();
    coordinator = StoryEngineCoordinator.restore(blueprint, halfway);
    expect(coordinator.state.revision, 23);
    expect(coordinator.sceneId, 'gate');

    both('market_1', 'walk_market');
    both('trust', 'ask_guard');
    both('market_2', 'walk_market');
    both('map', 'buy_map');
    both('market_3', 'walk_market');
    both('key', 'find_key');
    both('hall', 'enter_hall');
    both('family', 'learn_from_guard');
    both('note', 'write_note');
    both('cellar', 'go_cellar');
    both('vault', 'open_vault');
    both('publish', 'publish_archive');

    expect(coordinator.state.revision, 35);
    expect(coordinator.isTerminal, isTrue);
    expect(coordinator.choices, isEmpty);
    expect(coordinator.state.flags['revealed'], true);
    expect(coordinator.state.knowledge['player'], contains('archive_origin'));
    expect(coordinator.state.knowledge['guard'], isEmpty);
    expect(coordinator.events.length, 35);

    final exported = jsonDecode(jsonEncode(coordinator.checkpoint()));
    final restored = StoryEngineCoordinator.restore(blueprint, exported);
    expect(restored.state.stateHash, coordinator.state.stateHash);
    expect(restored.events.last.hash, coordinator.events.last.hash);
    expect(restored.sceneId, 'end_reveal');
    expect(take(restored, 'after_end', 'inspect_gate').reason,
        'terminal_scene');
  });

  test('Dart runtime adapter exposes event-scoped NPC facts after replay', () {
    final raw = mutableFixture();
    final gate = (raw['scenes'] as List).first as Map<String, dynamic>;
    final inspect = (gate['choices'] as List).first as Map<String, dynamic>;
    inspect['effects'] = [
      {'op': 'learn_fact', 'id': 'family_secret', 'actor': 'guard'},
    ];
    final blueprint = StoryBlueprint.fromJson(raw);
    final adapter = StoryEngineCoordinator.start(blueprint);
    expect(adapter.actorKnowsFact('guard', 'family_secret'), isFalse);
    expect(adapter.factLearningEvents('guard', 'family_secret'), isEmpty);
    expect(take(adapter, 'teach_guard', 'inspect_gate').applied, isTrue);
    expect(adapter.actorKnowsFact('guard', 'family_secret'), isTrue);
    expect(adapter.actorKnowsFact('player', 'family_secret'), isFalse);
    expect(adapter.factLearningEvents('guard', 'family_secret')
        .single.actionId, 'teach_guard');
    final restored = StoryEngineCoordinator.restore(
        blueprint, jsonDecode(jsonEncode(adapter.checkpoint())));
    expect(restored.actorKnowsFact('guard', 'family_secret'), isTrue);
    expect(restored.factLearningEvents('guard', 'family_secret')
        .single.hash, adapter.events.single.hash);
  });

  test('blocked move leaves both engine scene and world hash unchanged', () {
    final coordinator = StoryEngineCoordinator.start(fixture());
    final before = coordinator.state.stateHash;
    expect(take(coordinator, 'blocked_1', 'enter_hall').reason,
        'condition_not_met:has_item');
    expect(take(coordinator, 'blocked_2', 'not_existing').reason,
        'choice_not_in_current_scene');
    expect(coordinator.events, isEmpty);
    expect(coordinator.sceneId, 'gate');
    expect(coordinator.state.stateHash, before);
    expect(take(coordinator, 'retry', 'walk_market').applied, isTrue);
    expect(coordinator.sceneId, 'market');
  });

  test('a duplicate action never advances engine twice', () {
    final coordinator = StoryEngineCoordinator.start(fixture());
    expect(take(coordinator, 'first', 'inspect_gate').applied, isTrue);
    final stateHash = coordinator.state.stateHash;
    final duplicated = coordinator.choose(
      actionId: 'first', choiceId: 'inspect_gate');
    expect(duplicated.status, DecisionStatus.duplicate);
    expect(coordinator.state.stateHash, stateHash);
    expect(coordinator.events.length, 1);
    expect(() => coordinator.choose(
      actionId: 'first', choiceId: 'walk_market'),
      throwsFormatException);
    expect(coordinator.choose(
      actionId: 'fresh', choiceId: 'walk_market', expectedRevision: 0).reason,
      'stale_revision');
    expect(coordinator.sceneId, 'gate');
  });

  test('failed effect after a valid effect does not change engine or core', () {
    final raw = mutableFixture();
    final gate = (raw['scenes'] as List).first as Map<String, dynamic>;
    final inspect = (gate['choices'] as List).first as Map<String, dynamic>;
    inspect['effects'] = [
      {'op': 'grant_item', 'id': 'map'},
      {'op': 'consume_item', 'id': 'key'},
    ];
    final coordinator =
        StoryEngineCoordinator.start(StoryBlueprint.fromJson(raw));
    final before = coordinator.state.stateHash;
    expect(take(coordinator, 'cannot_spend', 'inspect_gate').reason,
        'missing_item');
    expect(coordinator.state.inventory, isEmpty);
    expect(coordinator.events, isEmpty);
    expect(coordinator.state.stateHash, before);
    expect(coordinator.sceneId, 'gate');
    expect(take(coordinator, 'valid', 'walk_market').applied, isTrue);
    expect(coordinator.sceneId, 'market');
  });

  test('two independent campaigns cannot share items or journal', () {
    final blueprint = fixture();
    final first = StoryEngineCoordinator.start(blueprint);
    final second = StoryEngineCoordinator.start(blueprint);
    take(first, 'first_walk', 'walk_market');
    take(first, 'first_key', 'find_key');
    expect(first.state.inventory, contains('key'));
    expect(second.state.inventory, isEmpty);
    expect(second.events, isEmpty);
    expect(second.sceneId, 'gate');
    expect(take(second, 'leave', 'leave').applied, isTrue);
    expect(second.isTerminal, isTrue);
    expect(first.isTerminal, isFalse);
  });

  test('checkpoint is exact-bookworld-bound, not opaque engine snapshot', () {
    final blueprint = fixture();
    final coordinator = StoryEngineCoordinator.start(blueprint);
    take(coordinator, 'inspect', 'inspect_gate');
    final recorded = coordinator.checkpoint();
    expect(recorded['book_id'], blueprint.bookId);
    expect(recorded['blueprint_sha256'], blueprint.blueprintHash);
    expect(recorded.containsKey('engine_snapshot'), isFalse);
    expect(recorded['head_event_sha256'], coordinator.events.last.hash);
    final changed = mutableFixture();
    changed['title'] = 'Иная редакция того же тестового мира';
    expect(() => StoryEngineCoordinator.restore(
        StoryBlueprint.fromJson(changed), recorded),
        throwsFormatException);
  });

  test('truncated tail, altered event and hash mismatch never restore', () {
    final blueprint = fixture();
    final coordinator = StoryEngineCoordinator.start(blueprint);
    for (var i = 0; i < 4; i++) {
      take(coordinator, 'inspect_$i', 'inspect_gate');
    }
    Map<String, dynamic> fresh() => jsonDecode(
        jsonEncode(coordinator.checkpoint())) as Map<String, dynamic>;

    final short = fresh();
    (short['events'] as List).removeLast();
    expect(() => StoryEngineCoordinator.restore(blueprint, short),
        throwsFormatException);

    final changed = fresh();
    ((changed['events'] as List)[1] as Map)['next_scene_id'] = 'market';
    expect(() => StoryEngineCoordinator.restore(blueprint, changed),
        throwsFormatException);

    final wrongHash = fresh();
    wrongHash['head_event_sha256'] = List.filled(64, 'f').join();
    expect(() => StoryEngineCoordinator.restore(blueprint, wrongHash),
        throwsFormatException);

    final wrongVersion = fresh();
    wrongVersion['schema_version'] = 8;
    expect(() => StoryEngineCoordinator.restore(blueprint, wrongVersion),
        throwsFormatException);
  });

  test('empty checkpoint restores initial scene without any chosen action', () {
    final blueprint = fixture();
    final original = StoryEngineCoordinator.start(blueprint);
    final rebuilt = StoryEngineCoordinator.restore(
      blueprint, jsonDecode(jsonEncode(original.checkpoint())),
    );
    expect(rebuilt.sceneId, 'gate');
    expect(rebuilt.events, isEmpty);
    expect(rebuilt.state.stateHash, original.state.stateHash);
  });
}
