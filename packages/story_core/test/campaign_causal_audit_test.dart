import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const npcA = 'npc_cccccccccccccccccccccccccccccccc';
const npcB = 'npc_dddddddddddddddddddddddddddddddd';

StoryBlueprint fixture({
  bool unreachableCanon = false,
  bool addDeadEnd = false,
  bool npc = false,
}) {
  final document = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final raw = document['blueprint'] as Map<String, dynamic>;
  final entry = (raw['scenes'] as List).first as Map<String, dynamic>;
  final choices = entry['choices'] as List;
  final wait = choices[0] as Map<String, dynamic>;
  final help = choices[1] as Map<String, dynamic>;

  if (unreachableCanon) {
    // The loop never sets "helped". The raw GRAPH reaches the ending;
    // a valid world never does.
    (help['conditions'] as List).add(
        {'op': 'flag_is', 'id': 'helped', 'value': true});
  }
  if (addDeadEnd) {
    wait['next_scene_id'] = 'sealed';
    (raw['scenes'] as List).add({
      'id': 'sealed',
      'text': 'У закрытых ворот герой остался без ключа.',
      'terminal': false,
      'choices': [
        {
          'id': 'unlock',
          'label': 'Открыть закрытые ворота',
          'next_scene_id': 'canon_end',
          'conditions': [
            {'op': 'flag_is', 'id': 'helped', 'value': true},
          ],
          'effects': <dynamic>[],
        },
      ],
    });
  }
  if (npc) {
    (raw['actors'] as List).addAll([npcA, npcB]);
    (raw['facts'] as List).add('npc_secret');
    final knowledge = (raw['initial_state'] as Map)['knowledge'] as Map;
    knowledge[npcA] = <String>[];
    knowledge[npcB] = <String>[];
    (wait['effects'] as List).add({
      'op': 'learn_fact', 'actor': npcA, 'id': 'npc_secret',
    });
    (help['conditions'] as List).add({
      'op': 'knows_fact', 'actor': npcA, 'id': 'npc_secret',
    });
  }
  return StoryBlueprint.fromJson(raw);
}

NpcSocialRulebook reviewedSocial(StoryBlueprint blueprint) =>
    NpcSocialRulebook(
      blueprintHash: blueprint.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'entry', actorId: npcA,
          mode: NpcWitnessMode.present,
        ),
      ],
      rules: const [
        NpcSocialRule(
          memoryId: 'npc_remembers_promise', sceneId: 'entry',
          choiceId: 'wait', observerId: npcA,
          kind: NpcMemoryKind.promiseReceived, relatedActorId: 'player',
          relationshipDelta: 10,
        ),
      ],
      choiceGates: const [
        NpcSocialChoiceGate(
          sceneId: 'entry', choiceId: 'help', actorId: npcA,
          requiredMemoryId: 'npc_remembers_promise',
          minimumTrustToPlayer: 10,
        ),
      ],
    );

void main() {
  test('a complete campaign has replayable endings and all real choices', () {
    final bp = fixture();
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: bp,
      requiredChoiceIds: const ['wait', 'help', 'leave'],
    );
    expect(report.status, CampaignCausalStatus.playable);
    expect(report.playable, isTrue);
    expect(report.exhaustive, isTrue);
    expect(report.traps, isEmpty);
    expect(report.trapCount, 0);
    expect(report.unprovenTerminalIds, isEmpty);
    expect(report.unprovenRequiredChoiceIds, isEmpty);
    expect(report.terminalWitnesses.keys,
        containsAll(['canon_end', 'alternate_end']));
    expect(report.choiceWitnesses.keys,
        containsAll(['wait', 'help', 'leave']));
    for (final entry in report.terminalWitnesses.entries) {
      final replayed = StoryWorld.replay(
        bp, entry.value.map((event) => event.toJson()),
        expectedSequence: entry.value.length,
        expectedStateHash: entry.value.last.afterStateHash,
      );
      expect(replayed.state.sceneId, entry.key);
      expect(replayed.isTerminal, isTrue);
    }
    final again = StoryCampaignCausalAudit.inspect(
      blueprint: bp,
      requiredChoiceIds: const ['wait', 'help', 'leave'],
    );
    expect(again.exploredStates, report.exploredStates);
    expect(again.terminalWitnesses['canon_end']!.map((e) => e.hash),
        report.terminalWitnesses['canon_end']!.map((e) => e.hash));
  });

  test('structurally connected but impossible ending is rejected', () {
    final bp = fixture(unreachableCanon: true);
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: bp, requiredChoiceIds: const ['help'],
    );
    expect(report.status, CampaignCausalStatus.blocked);
    expect(report.exhaustive, isTrue);
    expect(report.unprovenTerminalIds, ['canon_end']);
    expect(report.unprovenRequiredChoiceIds, ['help']);
    expect(report.traps, isEmpty);
    expect(report.terminalWitnesses.containsKey('alternate_end'), isTrue);
    expect(report.choiceWitnesses.containsKey('help'), isFalse);
  });

  test('a reachable softlock has a shortest replayable witness', () {
    final bp = fixture(addDeadEnd: true);
    final report = StoryCampaignCausalAudit.inspect(blueprint: bp);
    expect(report.status, CampaignCausalStatus.blocked);
    expect(report.exhaustive, isTrue);
    expect(report.terminalWitnesses.length, 2);
    expect(report.trapCount, 1);
    final trap = report.traps.single;
    expect(trap.sceneId, 'sealed');
    expect(trap.choiceIds, ['wait']);
    expect(trap.choiceLockReasons,
        {'unlock': 'condition_not_met:flag_is'});
    final replayed = StoryWorld.replay(
      bp, trap.events.map((event) => event.toJson()),
      expectedSequence: trap.events.length,
      expectedStateHash: trap.stateHash,
    );
    expect(replayed.state.sceneId, 'sealed');
    expect(replayed.isTerminal, isFalse);
    expect(replayed.choiceLockReason('unlock'),
        'condition_not_met:flag_is');
    expect(() => trap.choiceLockReasons.clear(),
        throwsUnsupportedError);
    expect(() => trap.events.clear(), throwsUnsupportedError);
  });

  test('state and depth budgets do NOT classify unknown endings as blocked',
      () {
    final bp = fixture();
    final limitedStates = StoryCampaignCausalAudit.inspect(
        blueprint: bp, maxStates: 1);
    expect(limitedStates.status, CampaignCausalStatus.inconclusive);
    expect(limitedStates.exhaustive, isFalse);
    expect(limitedStates.trapCount, 0);
    expect(limitedStates.unprovenTerminalIds, isNotEmpty);
    final limitedMoves = StoryCampaignCausalAudit.inspect(
        blueprint: fixture(npc: true), maxMoves: 1);
    // The "wait" choice teaches the NPC a fact, so the distinct
    // nonterminal state cannot be fully explored after just one move.
    expect(limitedMoves.status, CampaignCausalStatus.inconclusive);
    expect(limitedMoves.exhaustive, isFalse);
  });

  test('NPC trust, exact facts, and replayed memory gate campaign routes', () {
    final bp = fixture(npc: true);
    final social = reviewedSocial(bp);
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: bp, socialRulebook: social,
      requiredChoiceIds: const ['wait', 'help', 'leave'],
    );
    expect(report.playable, isTrue);
    expect(report.terminalWitnesses['canon_end']!.map((e) => e.choiceId),
        ['wait', 'help']);
    final canonical = report.terminalWitnesses['canon_end']!;
    final replayed = StoryWorld.replay(
      bp, canonical.map((event) => event.toJson()),
      expectedSequence: canonical.length,
      expectedStateHash: canonical.last.afterStateHash,
      socialRulebook: social,
    );
    final snapshot = NpcSocialLedger.inspect(replayed, social);
    expect(snapshot.hasMemory(npcA, 'npc_remembers_promise'), isTrue);
    expect(snapshot.directedScore(npcA, 'player'), 10);
    expect(snapshot.directedScore('player', npcA), 0);
    expect(replayed.actorKnowsFact(npcA, 'npc_secret'), isTrue);
    expect(replayed.actorKnowsFact(npcB, 'npc_secret'), isFalse);
    final skipped = report.terminalWitnesses['alternate_end']!;
    final offPath = StoryWorld.replay(
      bp, skipped.map((event) => event.toJson()),
      expectedSequence: skipped.length,
      expectedStateHash: skipped.last.afterStateHash,
      socialRulebook: social,
    );
    expect(offPath.actorKnowsFact(npcA, 'npc_secret'), isFalse);
  });

  test('required choices are audited without fabricating a terminal contract',
      () {
    final bp = fixture(unreachableCanon: true);
    final noForcedTerminals = StoryCampaignCausalAudit.inspect(
      blueprint: bp,
      requireAllTerminals: false,
    );
    expect(noForcedTerminals.playable, isTrue);
    final required = StoryCampaignCausalAudit.inspect(
      blueprint: bp, requireAllTerminals: false,
      requiredChoiceIds: const ['help'],
    );
    expect(required.status, CampaignCausalStatus.blocked);
    expect(required.unprovenRequiredChoiceIds, ['help']);
    expect(required.unprovenTerminalIds, isEmpty);
  });

  test('unknown or repeated choice IDs and bad budgets fail closed', () {
    final bp = fixture();
    expect(() => StoryCampaignCausalAudit.inspect(
      blueprint: bp, requiredChoiceIds: const ['invented'],
    ), throwsFormatException);
    expect(() => StoryCampaignCausalAudit.inspect(
      blueprint: bp, requiredChoiceIds: const ['help', 'help'],
    ), throwsFormatException);
    expect(() => StoryCampaignCausalAudit.inspect(
      blueprint: bp, maxStates: 0,
    ), throwsFormatException);
    expect(() => StoryCampaignCausalAudit.inspect(
      blueprint: bp, maxMoves: 0,
    ), throwsFormatException);
  });
}
