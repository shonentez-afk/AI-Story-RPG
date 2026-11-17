import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _npc = 'npc_cccccccccccccccccccccccccccccccc';
const _second = 'npc_dddddddddddddddddddddddddddddddd';

StoryBlueprint _scenario({
  bool unreachableProducer = false,
  bool grantToOther = false,
}) {
  final fixture = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final data = fixture['blueprint'] as Map<String, dynamic>;
  (data['actors'] as List).addAll([_npc, _second]);
  (data['facts'] as List).add('npc_secret');
  final initial = data['initial_state'] as Map<String, dynamic>;
  (initial['knowledge'] as Map<String, dynamic>)[_npc] = <String>[];
  (initial['knowledge'] as Map<String, dynamic>)[_second] = <String>[];
  final entry = (data['scenes'] as List).first as Map<String, dynamic>;
  final choices = entry['choices'] as List;
  final learn = choices[0] as Map<String, dynamic>;
  final help = choices[1] as Map<String, dynamic>;
  (learn['effects'] as List).add({
    'op': 'learn_fact', 'id': 'npc_secret',
    'actor': grantToOther ? _second : _npc,
  });
  if (unreachableProducer) {
    // The producer is in the source graph, but no approved action
    // can set "helped" to TRUE before reaching it.
    (learn['conditions'] as List).add({
      'op': 'flag_is', 'id': 'helped', 'value': true,
    });
  }
  (help['conditions'] as List).add({
    'op': 'knows_fact', 'id': 'npc_secret', 'actor': _npc,
  });
  return StoryBlueprint.fromJson(data);
}

NpcSocialRulebook _relations(StoryBlueprint bp) => NpcSocialRulebook(
  blueprintHash: bp.blueprintHash,
  rules: const [
    NpcSocialRule(
      memoryId: 'npc_remembers_promise',
      sceneId: 'entry', choiceId: 'wait',
      observerId: _npc, kind: NpcMemoryKind.promiseReceived,
      relatedActorId: 'player', relationshipDelta: 10,
    ),
  ],
  choiceGates: const [
    NpcSocialChoiceGate(
      sceneId: 'entry', choiceId: 'help', actorId: _npc,
      requiredMemoryId: 'npc_remembers_promise',
      minimumTrustToPlayer: 10,
    ),
  ],
  // A portable world would have explicitly reviewed witness metadata.
  witnesses: const [
    NpcSceneWitness(
      sceneId: 'entry', actorId: _npc, mode: NpcWitnessMode.present,
    ),
  ],
  requireReviewedWitnesses: true,
);

void main() {
  test('engine audit proves a REAL committed learning route, not graph reach', () {
    final bp = _scenario();
    final proof = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      actorId: _npc, requiredFactIds: const ['npc_secret'],
    );
    expect(proof.status, CausalRouteStatus.proven);
    expect(proof.choiceIds, ['wait', 'help']);
    expect(proof.events, hasLength(2));
    final rebuilt = StoryWorld.replay(
      bp, proof.events.map((event) => event.toJson()),
      expectedSequence: 2, expectedStateHash: proof.resultStateHash,
    );
    expect(rebuilt.state.sceneId, 'canon_end');
    expect(rebuilt.actorKnowsFact(_npc, 'npc_secret'), isTrue);
    expect(rebuilt.actorKnowsFact(_second, 'npc_secret'), isFalse);
    // No repeated mutable search objects or unstable wall-clock stamps.
    final repeat = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      actorId: _npc, requiredFactIds: const ['npc_secret'],
    );
    expect(repeat.events.map((e) => e.hash).toList(),
        proof.events.map((e) => e.hash).toList());
  });

  test('game branch without promise never leaks secret or future dialogue', () {
    final bp = _scenario();
    final skipped = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'alternate_end',
      forbiddenChoiceId: 'wait',
    );
    expect(skipped.status, CausalRouteStatus.proven);
    expect(skipped.choiceIds, ['leave']);
    final alternate = StoryWorld.replay(
      bp, skipped.events.map((event) => event.toJson()),
      expectedSequence: 1, expectedStateHash: skipped.resultStateHash,
    );
    expect(alternate.actorKnowsFact(_npc, 'npc_secret'), isFalse);
    expect(StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      forbiddenChoiceId: 'wait',
      actorId: _npc, requiredFactIds: const ['npc_secret'],
    ).status, CausalRouteStatus.unreachable);
  });

  test('structural graph path is not a real route when producer is locked', () {
    final bp = _scenario(unreachableProducer: true);
    final proof = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      actorId: _npc, requiredFactIds: const ['npc_secret'],
    );
    // The raw graph still contains entry -> wait -> entry -> help -> end,
    // but StoryWorld itself never commits wait.
    expect(proof.status, CausalRouteStatus.unreachable);
    expect(proof.choiceIds, isEmpty);
    expect(proof.events, isEmpty);
  });

  test('actor-scoped facts never transfer from another NPC with same role', () {
    final bp = _scenario(grantToOther: true);
    expect(StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      actorId: _npc, requiredFactIds: const ['npc_secret'],
    ).status, CausalRouteStatus.unreachable);
  });

  test('social gate and trust are earned only by replayed witnessed memory', () {
    final bp = _scenario();
    final social = _relations(bp);
    social.validate(bp);
    final proof = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait', actorId: _npc,
      requiredFactIds: const ['npc_secret'],
      requiredMemoryId: 'npc_remembers_promise',
      minimumTrustToPlayer: 10,
      socialRulebook: social,
    );
    expect(proof.status, CausalRouteStatus.proven);
    expect(proof.choiceIds, ['wait', 'help']);
    final verified = StoryWorld.replay(bp,
      proof.events.map((e) => e.toJson()),
      expectedSequence: 2, expectedStateHash: proof.resultStateHash,
      socialRulebook: social,
    );
    final snapshot = NpcSocialLedger.inspect(verified, social);
    expect(snapshot.hasMemory(_npc, 'npc_remembers_promise'), isTrue);
    expect(snapshot.directedScore(_npc, 'player'), 10);
    expect(snapshot.directedScore('player', _npc), 0);
    expect(StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      forbiddenChoiceId: 'wait',
      requiredMemoryId: 'npc_remembers_promise', actorId: _npc,
      socialRulebook: social,
    ).status, CausalRouteStatus.unreachable);
  });

  test('bounded search refuses to confuse incomplete and impossible', () {
    final bp = _scenario();
    final limited = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait', actorId: _npc,
      requiredFactIds: const ['npc_secret'],
      maxMoves: 1,
    );
    expect(limited.status, CausalRouteStatus.inconclusive);
    expect(limited.proven, isFalse);
    final limitedStates = StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      maxStates: 1,
    );
    expect(limitedStates.status, CausalRouteStatus.inconclusive);
    expect(limitedStates.events, isEmpty);
  });

  test('unknown actor/choice and contradictory route are refused', () {
    final bp = _scenario();
    expect(() => StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      actorId: 'npc_not_reviewed', requiredFactIds: const ['npc_secret'],
    ), throwsFormatException);
    expect(() => StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait', forbiddenChoiceId: 'wait',
    ), throwsFormatException);
    expect(() => StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'invented',
    ), throwsFormatException);
    expect(() => StoryCausalRouteAudit.find(
      blueprint: bp, targetSceneId: 'canon_end',
      actorId: _npc, minimumTrustToPlayer: 10,
    ), throwsFormatException);
  });
}
