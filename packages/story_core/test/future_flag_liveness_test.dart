import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const npcId = 'npc_cccccccccccccccccccccccccccccccc';

/// Twenty independent choices create 2^20 distinct persistent flag maps.
/// They are REAL, replayable history. Only their future behavioral
/// equivalence is compressed after each act, not the data in WorldState.
StoryBlueprint longActs(int count, {bool lateTrap = false}) {
  final doc = jsonDecode(File(
    '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final bp = Map<String, dynamic>.from(doc['blueprint'] as Map);
  final initial = Map<String, dynamic>.from(bp['initial_state'] as Map);
  final flagIds = <String>[
    for (var i = 1; i <= count; i++) ...[
      'act_${i}_original',
      'act_${i}_alternative',
    ],
  ];
  initial['scene_id'] = 'act_1_decide';
  initial['flags'] = {for (final id in flagIds) id: false};
  initial['knowledge'] = {'player': <String>[], npcId: <String>[]};
  bp['initial_state'] = initial;
  bp['entry_scene_id'] = 'act_1_decide';
  bp['actors'] = ['player', npcId];
  bp['facts'] = ['npc_early_secret'];

  Map<String, Object> choice(String id, String destination,
      {List<Object> conditions = const [], List<Object> effects = const []}) =>
      {
        'id': id, 'label': 'Подтвержденный игровой выбор',
        'next_scene_id': destination,
        'conditions': conditions, 'effects': effects,
      };

  final scenes = <Map<String, Object>>[];
  for (var i = 1; i <= count; i++) {
    final original = 'act_${i}_original';
    final alternative = 'act_${i}_alternative';
    scenes.add({
      'id': 'act_${i}_decide',
      'text': 'В части ${i} герой делает два разных выбора.',
      'terminal': false,
      'choices': <Object>[
        choice('act_${i}_take_original', 'act_${i}_join', effects: [
          {'op': 'set_flag', 'id': original, 'value': true},
          if (i == 1) {'op': 'learn_fact', 'id': 'npc_early_secret',
            'actor': npcId},
        ]),
        choice('act_${i}_take_alternative', 'act_${i}_join', effects: [
          {'op': 'set_flag', 'id': alternative, 'value': true},
        ]),
      ],
    });
    scenes.add({
      'id': 'act_${i}_join',
      'text': 'Последствия части ${i} сохраняются для будущего.',
      'terminal': false,
      'choices': i < count ? <Object>[
        choice('act_${i}_continue', 'act_${i + 1}_decide'),
      ] : <Object>[
        choice('finish_original', 'end_original', conditions: [
          {'op': 'flag_is', 'id': original, 'value': true},
          if (lateTrap)
            {'op': 'flag_is', 'id': 'act_1_original', 'value': true},
        ]),
        choice('finish_alternative', 'end_alternative', conditions: [
          {'op': 'flag_is', 'id': alternative, 'value': true},
          if (lateTrap)
            {'op': 'flag_is', 'id': 'act_1_original', 'value': true},
        ]),
        choice('talk_npc', 'end_npc', conditions: [
          {'op': 'knows_fact', 'id': 'npc_early_secret',
            'actor': npcId},
        ]),
      ],
    });
  }
  for (final ending in ['end_original', 'end_alternative', 'end_npc']) {
    scenes.add({
      'id': ending, 'text': 'Игровой финал без облачной сети.',
      'terminal': true, 'choices': <Object>[],
    });
  }
  bp['scenes'] = scenes;
  return StoryBlueprint.fromJson(bp);
}

void main() {
  test('future-live flags retain cycle reads and future exclusivity writes',
      () {
    final projection = FutureFlagLiveness.derive(
      scenes: ['first', 'bridge', 'later', 'terminal'],
      edges: [
        const FutureFlagEdge(
          from: 'first', to: 'bridge',
          writes: ['old_original']),
        const FutureFlagEdge(from: 'bridge', to: 'later'),
        const FutureFlagEdge(
          from: 'later', to: 'terminal',
          writes: ['old_alternative']),
      ],
      exclusiveGroups: const [
        ['old_original', 'old_alternative'],
      ],
    );
    expect(projection.at('first'), contains('old_original'));
    // A future exclusive-group mutation still depends on previous custody.
    expect(projection.at('bridge'), contains('old_original'));
    expect(projection.at('bridge'), contains('old_alternative'));
    expect(projection.at('terminal'), isEmpty);

    final cycle = FutureFlagLiveness.derive(
      scenes: ['a', 'b', 'exit'],
      edges: [
        const FutureFlagEdge(from: 'a', to: 'b'),
        const FutureFlagEdge(from: 'b', to: 'a',
            reads: ['memory']),
        const FutureFlagEdge(from: 'b', to: 'exit'),
      ],
    );
    expect(cycle.at('a'), contains('memory'));
  });

  test('20 acts: proof completes while every old outcome and NPC fact'
      ' survives real hash-chain replay', () {
    final bp = longActs(20);
    final proof = FutureFlagLiveness.fromBlueprint(bp);
    expect(proof.at('act_10_join'), isNot(contains('act_1_original')));
    expect(proof.at('act_10_join'), contains('act_20_original'));

    final old = StoryCampaignCausalAudit.inspect(
      blueprint: bp, maxStates: 512, maxMoves: 128,
      requiredChoiceIds: ['talk_npc', 'finish_original',
        'finish_alternative'],
    );
    expect(old.status, CampaignCausalStatus.inconclusive);

    final verified = StoryCampaignCausalAudit.inspect(
      blueprint: bp, projectDormantFlags: true,
      maxStates: 512, maxMoves: 128,
      requiredChoiceIds: ['talk_npc', 'finish_original',
        'finish_alternative'],
    );
    expect(verified.status, CampaignCausalStatus.playable);
    expect(verified.exhaustive, true);
    expect(verified.traps, isEmpty);
    expect(verified.unprovenRequiredChoiceIds, isEmpty);

    final game = StoryWorld(bp);
    final selected = <String>[];
    for (var i = 1; i <= 20; i++) {
      final choiceId = i.isOdd
          ? 'act_${i}_take_original'
          : 'act_${i}_take_alternative';
      selected.add(choiceId);
      expect(game.apply(actionId: 'select_${i}',
          choiceId: choiceId).applied, isTrue);
      if (i < 20) {
        expect(game.apply(actionId: 'continue_${i}',
          choiceId: 'act_${i}_continue').applied, isTrue);
      }
    }
    for (var i = 1; i <= 20; i++) {
      expect(game.state.flags[
          'act_${i}_${i.isOdd ? 'original' : 'alternative'}'], true);
    }
    expect(game.state.knowledge[npcId], contains('npc_early_secret'));
    expect(game.choiceLockReason('talk_npc'), isNull);
    expect(game.apply(actionId: 'npc_final',
        choiceId: 'talk_npc').applied, isTrue);
    final restored = StoryWorld.replay(
      bp, game.events.map((event) => event.toJson()),
      expectedSequence: game.state.revision,
      expectedStateHash: game.state.stateHash,
    );
    expect(restored.state.stateHash, game.state.stateHash);
    expect(restored.state.flags, game.state.flags);
    expect(restored.state.knowledge, game.state.knowledge);
  });

  test('an act-one result read at act twelve cannot disappear:'
      ' alternative path is a genuine softlock', () {
    final bp = longActs(12, lateTrap: true);
    final liveness = FutureFlagLiveness.fromBlueprint(bp);
    expect(liveness.at('act_6_join'), contains('act_1_original'));
    final checked = StoryCampaignCausalAudit.inspect(
      blueprint: bp, projectDormantFlags: true,
      maxStates: 2048, maxMoves: 128,
    );
    expect(checked.status, CampaignCausalStatus.blocked);
    expect(checked.traps, isNotEmpty);
    final witness = checked.traps.first.events;
    final replayed = StoryWorld.replay(
      bp, witness.map((event) => event.toJson()),
      expectedSequence: witness.length,
      expectedStateHash: witness.isEmpty
          ? bp.initial.stateHash : witness.last.afterStateHash,
    );
    expect(replayed.state.sceneId, 'act_12_join');
  });
}
