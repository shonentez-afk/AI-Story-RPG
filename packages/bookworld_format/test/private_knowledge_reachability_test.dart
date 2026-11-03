import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const fixturePath = '../../shared_schemas/fixtures/private_classic_sample.json';
final npcId = 'npc_' + List.filled(20, 'a').join();
final factId = 'fact_' + List.filled(24, 'b').join();

Map<String, dynamic> fixture() =>
    jsonDecode(File(fixturePath).readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> blueprint(Map<String, dynamic> fixture) =>
    fixture['blueprint'] as Map<String, dynamic>;

Map<String, dynamic> choice(
    Map<String, dynamic> blueprint, String id) {
  for (final value in blueprint['scenes'] as List) {
    final scene = value as Map<String, dynamic>;
    for (final value in scene['choices'] as List) {
      final item = value as Map<String, dynamic>;
      if (item['id'] == id) return item;
    }
  }
  throw FormatException('Missing fixture choice $id');
}

Map<String, dynamic> actorKnowledgeFixture() {
  final data = fixture();
  final bp = blueprint(data);
  (bp['actors'] as List).add(npcId);
  (bp['facts'] as List).add(factId);
  final initial = bp['initial_state'] as Map<String, dynamic>;
  (initial['knowledge'] as Map<String, dynamic>)[npcId] = <String>[];
  (choice(bp, 'wait')['effects'] as List).add({
    'op': 'learn_fact', 'id': factId, 'actor': npcId,
  });
  (choice(bp, 'help')['conditions'] as List).add({
    'op': 'knows_fact', 'id': factId, 'actor': npcId,
  });
  return data;
}

VerifiedPrivateBookworld compile(Map<String, dynamic> data) {
  final zip = const PrivateBookworldWriter().build(
    blueprint: blueprint(data),
    provenance: data['provenance'] as Map<String, dynamic>,
    sourceIndex: data['source_index'] as Map<String, dynamic>,
  );
  return const PrivateBookworldImporter().inspect(zip);
}

void main() {
  test('legacy flag-only private worlds remain importable', () {
    final world = compile(fixture());
    expect(world.blueprint.actors, {'player'});
    expect(world.blueprint.facts, isEmpty);
  });

  test('NPC knowledge gates a choice until an actual game action', () {
    final imported = compile(actorKnowledgeFixture());
    expect(imported.blueprint.actors, containsAll(['player', npcId]));
    expect(imported.blueprint.facts, {factId});
    final world = StoryWorld(imported.blueprint);
    expect(world.state.knowledge[npcId], isEmpty);
    expect(world.state.knowledge['player'], isEmpty);
    final before = world.state.stateHash;
    final denied = world.apply(
      actionId: 'blocked', choiceId: 'help', expectedRevision: 0);
    expect(denied.applied, isFalse);
    expect(denied.reason, 'condition_not_met:knows_fact');
    expect(world.state.stateHash, before);
    expect(world.events, isEmpty);

    final learn = world.apply(
      actionId: 'meet_npc', choiceId: 'wait', expectedRevision: 0);
    expect(learn.applied, isTrue);
    expect(world.state.knowledge[npcId], {factId});
    expect(world.state.knowledge['player'], isEmpty);
    final reveal = world.apply(
      actionId: 'help_after_meeting', choiceId: 'help', expectedRevision: 1);
    expect(reveal.applied, isTrue);
    expect(world.isTerminal, isTrue);

    final journal = jsonDecode(jsonEncode(
      world.events.map((e) => e.toJson()).toList())) as List;
    final restored = StoryWorld.replay(
      imported.blueprint, journal,
      expectedSequence: 2, expectedStateHash: world.state.stateHash,
    );
    expect(restored.state.knowledge[npcId], {factId});
    expect(restored.state.knowledge['player'], isEmpty);
    expect(restored.state.stateHash, world.state.stateHash);
  });

  test('120 actions restore exact NPC knowledge and event hash', () {
    final imported = compile(actorKnowledgeFixture());
    final world = StoryWorld(imported.blueprint);
    for (var i = 0; i < 119; i++) {
      expect(world.apply(
        actionId: 'revisit_$i', choiceId: 'wait',
        expectedRevision: i,
      ).applied, isTrue);
    }
    expect(world.apply(
      actionId: 'finally_help', choiceId: 'help',
      expectedRevision: 119,
    ).applied, isTrue);
    expect(world.state.revision, 120);
    final events = jsonDecode(jsonEncode(
      world.events.map((e) => e.toJson()).toList())) as List;
    final restored = StoryWorld.replay(
      imported.blueprint, events,
      expectedSequence: 120, expectedStateHash: world.state.stateHash,
    );
    expect(restored.events.last.hash, world.events.last.hash);
    expect(restored.state.knowledge[npcId], {factId});
    final forged = jsonDecode(jsonEncode(events)) as List;
    (forged[60] as Map)['choice_id'] = 'leave';
    expect(() => StoryWorld.replay(
      imported.blueprint, forged,
      expectedSequence: 120, expectedStateHash: world.state.stateHash,
    ), throwsFormatException);
  });

  test('rejects pre-known secrets, wrong actor and unsupported conditions', () {
    final wrongInitial = actorKnowledgeFixture();
    ((blueprint(wrongInitial)['initial_state'] as Map)['knowledge'] as Map)
        [npcId] = [factId];
    expect(() => compile(wrongInitial), throwsFormatException);

    final wrongActor = actorKnowledgeFixture();
    (choice(blueprint(wrongActor), 'help')['conditions'] as List).last = {
      'op': 'knows_fact', 'id': factId, 'actor': 'player',
    };
    expect(() => compile(wrongActor), throwsFormatException);

    final wrongCondition = actorKnowledgeFixture();
    (choice(blueprint(wrongCondition), 'help')['conditions'] as List).last = {
      'op': 'tick_at_least', 'amount': 1,
    };
    expect(() => compile(wrongCondition), throwsFormatException);
  });

  test('rejects causally unreachable ending even if fact is declared', () {
    final blocked = actorKnowledgeFixture();
    final bp = blueprint(blocked);
    (choice(bp, 'wait')['effects'] as List).clear();
    (choice(bp, 'help')['effects'] as List).add({
      'op': 'learn_fact', 'id': factId, 'actor': npcId,
    });
    // The only grant sits behind its own prerequisite, so canon_end is
    // inaccessible. A static scene graph check would miss this.
    expect(() => compile(blocked), throwsFormatException);
  });

  test('rejects more than 2500 distinct knowledge/scene states', () {
    final data = fixture();
    final bp = blueprint(data);
    (bp['actors'] as List).add(npcId);
    final facts = bp['facts'] as List;
    final knowledge = (bp['initial_state'] as Map)['knowledge'] as Map;
    knowledge[npcId] = <String>[];
    final entry = (bp['scenes'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((scene) => scene['id'] == 'entry');
    final entryChoices = entry['choices'] as List;
    for (var i = 0; i < 13; i++) {
      final fact = 'fact_' +
          i.toRadixString(16).padLeft(24, '0');
      facts.add(fact);
      entryChoices.add({
        'id': 'collect_$i', 'label': 'Get information $i',
        'next_scene_id': 'entry', 'conditions': <Object>[],
        'effects': [
          {'op': 'learn_fact', 'id': fact, 'actor': npcId},
        ],
      });
    }
    expect(() => compile(data), throwsFormatException);
  });
}
