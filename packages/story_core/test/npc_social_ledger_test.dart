import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

StoryBlueprint _blueprint() => StoryBlueprint.fromJson(jsonDecode(
  File('../../shared_schemas/fixtures/manor_world_m17.json')
      .readAsStringSync(),
));

NpcSocialRulebook _rules(StoryBlueprint blueprint) => NpcSocialRulebook(
  blueprintHash: blueprint.blueprintHash,
  rules: const [
    NpcSocialRule(
      memoryId: 'guard_heard_request',
      sceneId: 'gate',
      choiceId: 'inspect_gate',
      observerId: 'guard',
      kind: NpcMemoryKind.promiseReceived,
      relatedActorId: 'player',
      relationshipDelta: 10,
    ),
    NpcSocialRule(
      memoryId: 'player_left_guard',
      sceneId: 'gate',
      choiceId: 'walk_market',
      observerId: 'player',
      kind: NpcMemoryKind.witnessed,
      relatedActorId: 'guard',
      relationshipDelta: -3,
    ),
  ],
);

void main() {
  test('NPC memories and one-way relations follow committed events only', () {
    final blueprint = _blueprint();
    final world = StoryWorld(blueprint);
    final rules = _rules(blueprint);
    final initial = NpcSocialLedger.inspect(world, rules);
    expect(initial.memoriesFor('guard'), isEmpty);
    expect(initial.directedScore('guard', 'player'), 0);
    expect(initial.directedScore('player', 'guard'), 0);
    expect(() => initial.memoriesFor('unknown_actor'), throwsFormatException);
    expect(() => initial.directedScore('guard', 'unknown_actor'),
        throwsFormatException);

    final blocked = world.apply(
      actionId: 'blocked', choiceId: 'enter_hall');
    expect(blocked.applied, isFalse);
    expect(NpcSocialLedger.inspect(world, rules).memoriesFor('guard'),
        isEmpty);

    final first = world.apply(
      actionId: 'remembered', choiceId: 'inspect_gate');
    expect(first.applied, isTrue);
    final after = NpcSocialLedger.inspect(world, rules);
    expect(after.hasMemory('guard', 'guard_heard_request'), isTrue);
    expect(after.memoriesFor('guard').single.event.hash, first.event!.hash);
    expect(after.memoriesFor('guard').single.kind,
        NpcMemoryKind.promiseReceived);
    expect(after.directedScore('guard', 'player'), 10);
    expect(after.directedScore('player', 'guard'), 0);
    // A memory is not the same thing as learning a fact.
    expect(world.state.knowledge['guard'], isEmpty);
    expect(world.state.knowledge['player'], isEmpty);
    expect(() => after.memoriesFor('guard').clear(),
        throwsUnsupportedError);

    // Reusing one action ID is idempotent, not a second remembered event.
    expect(world.apply(actionId: 'remembered', choiceId: 'inspect_gate')
        .status, DecisionStatus.duplicate);
    expect(NpcSocialLedger.inspect(world, rules).directedScore(
        'guard', 'player'), 10);
    // A repeatable choice with a NEW action ID still cannot farm reputation.
    expect(world.apply(actionId: 'inspect_again', choiceId: 'inspect_gate')
        .applied, isTrue);
    expect(NpcSocialLedger.inspect(world, rules).directedScore(
        'guard', 'player'), 10);
    expect(NpcSocialLedger.inspect(world, rules).memoriesFor('guard'),
        hasLength(1));

    final second = world.apply(
      actionId: 'travel', choiceId: 'walk_market');
    expect(second.applied, isTrue);
    final visited = NpcSocialLedger.inspect(world, rules);
    expect(visited.hasMemory('player', 'player_left_guard'), isTrue);
    expect(visited.directedScore('guard', 'player'), 10);
    expect(visited.directedScore('player', 'guard'), -3);
    expect(visited.memoriesFor('player').single.event.hash,
        second.event!.hash);

    final rebuilt = StoryWorld.replay(
      blueprint,
      world.events.map((event) => event.toJson()),
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
    );
    final replayed = NpcSocialLedger.inspect(rebuilt, rules);
    expect(replayed.snapshotHash, visited.snapshotHash);
    expect(replayed.rulebookDigest, visited.rulebookDigest);
    expect(replayed.memoriesFor('guard').single.event.hash,
        visited.memoriesFor('guard').single.event.hash);
  });

  test('alternative branch cannot import absent memories or relations', () {
    final blueprint = _blueprint();
    final world = StoryWorld(blueprint);
    expect(world.apply(actionId: 'skip', choiceId: 'walk_market').applied,
        isTrue);
    final ledger = NpcSocialLedger.inspect(world, _rules(blueprint));
    expect(ledger.memoriesFor('guard'), isEmpty);
    expect(ledger.directedScore('guard', 'player'), 0);
    expect(ledger.hasMemory('player', 'player_left_guard'), isTrue);
    expect(ledger.directedScore('player', 'guard'), -3);
  });

  test('explicit bounded repeats never create unlimited NPC favor', () {
    final bp = _blueprint();
    final world = StoryWorld(bp);
    final rules = NpcSocialRulebook(
        blueprintHash: bp.blueprintHash,
        rules: const [
          NpcSocialRule(
            memoryId: 'guard_repeated_help', sceneId: 'gate',
            choiceId: 'inspect_gate', observerId: 'guard',
            kind: NpcMemoryKind.helped,
            relatedActorId: 'player', relationshipDelta: 7,
            maxTriggers: 2,
          ),
        ]);
    for (var i = 0; i < 5; i++) {
      expect(world.apply(
          actionId: 'repeat_$i', choiceId: 'inspect_gate').applied,
          isTrue);
    }
    final snapshot = NpcSocialLedger.inspect(world, rules);
    expect(snapshot.memoriesFor('guard'), hasLength(2));
    expect(snapshot.directedScore('guard', 'player'), 14);
    expect(snapshot.memoriesFor('guard').last.event.sequence, 2);
    expect(snapshot.directedScore('player', 'guard'), 0);
  });

  test('relations and witnesses are explicitly checked against the blueprint',
      () {
    final bp = _blueprint();
    void rejects(List<NpcSocialRule> rules) => expect(
      () => NpcSocialLedger.inspect(StoryWorld(bp),
        NpcSocialRulebook(blueprintHash: bp.blueprintHash, rules: rules)),
      throwsFormatException,
    );
    rejects([
      const NpcSocialRule(
        memoryId: 'bad', sceneId: 'gate', choiceId: 'inspect_gate',
        observerId: 'imaginary_npc', kind: NpcMemoryKind.witnessed,
      ),
    ]);
    rejects([
      const NpcSocialRule(
        memoryId: 'wrong_choice', sceneId: 'gate', choiceId: 'find_key',
        observerId: 'guard', kind: NpcMemoryKind.witnessed,
      ),
    ]);
    rejects([
      const NpcSocialRule(
        memoryId: 'self', sceneId: 'gate', choiceId: 'inspect_gate',
        observerId: 'guard', kind: NpcMemoryKind.witnessed,
        relatedActorId: 'guard', relationshipDelta: 10,
      ),
    ]);
    rejects([
      const NpcSocialRule(
        memoryId: 'missing_target', sceneId: 'gate',
        choiceId: 'inspect_gate',
        observerId: 'guard', kind: NpcMemoryKind.witnessed,
        relationshipDelta: -2,
      ),
    ]);
    rejects([
      const NpcSocialRule(
        memoryId: 'too_many', sceneId: 'gate', choiceId: 'inspect_gate',
        observerId: 'guard', kind: NpcMemoryKind.witnessed,
        relatedActorId: 'player', relationshipDelta: 21,
      ),
    ]);
    rejects([
      const NpcSocialRule(
        memoryId: 'bad_repeat', sceneId: 'gate',
        choiceId: 'inspect_gate',
        observerId: 'guard', kind: NpcMemoryKind.witnessed,
        maxTriggers: 0,
      ),
    ]);
    rejects(List.filled(2, const NpcSocialRule(
      memoryId: 'duplicate', sceneId: 'gate', choiceId: 'inspect_gate',
      observerId: 'guard', kind: NpcMemoryKind.witnessed,
    )));

    final wrong = NpcSocialRulebook(
      blueprintHash: 'f' * 64, rules: const []);
    expect(() => NpcSocialLedger.inspect(StoryWorld(bp), wrong),
        throwsFormatException);
  });

  test('private NPC social rules demand a permanent actor identity', () {
    final raw = jsonDecode(
      File('../../shared_schemas/fixtures/manor_world_m17.json')
          .readAsStringSync()) as Map<String, dynamic>;
    raw['rights_status'] = 'private_adaptation';
    raw['source_fingerprint'] = 'a' * 64;
    (raw['supported_modes'] as Map)['plots'] = ['ALTER_FATE'];
    final legacy = StoryBlueprint.fromJson(raw);
    final oldId = NpcSocialRulebook(
      blueprintHash: legacy.blueprintHash,
      rules: const [
        NpcSocialRule(
          memoryId: 'remember_legacy', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.witnessed,
        ),
      ],
    );
    expect(() => NpcSocialLedger.inspect(StoryWorld(legacy), oldId),
        throwsFormatException);

    final stable = 'npc_${'b' * 32}';
    final stableRaw = jsonDecode(
        jsonEncode(raw).replaceAll('"guard"', '"$stable"'));
    final blueprint = StoryBlueprint.fromJson(stableRaw);
    final approved = NpcSocialRulebook(
      blueprintHash: blueprint.blueprintHash,
      rules: [
        NpcSocialRule(
          memoryId: 'remember_permanent', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: stable,
          kind: NpcMemoryKind.promiseReceived,
          relatedActorId: 'player', relationshipDelta: 4,
        ),
      ],
    );
    final world = StoryWorld(blueprint);
    expect(world.apply(actionId: 'agreed', choiceId: 'inspect_gate').applied,
        isTrue);
    final ledger = NpcSocialLedger.inspect(world, approved);
    expect(ledger.directedScore(stable, 'player'), 4);
    expect(ledger.hasMemory(stable, 'remember_permanent'), isTrue);
  });

  test('approved scene presence prevents teleporting NPC eyewitness', () {
    final bp = _blueprint();
    NpcSocialRulebook reviewed({
      required List<NpcSceneWitness> witnesses,
      NpcMemoryKind kind = NpcMemoryKind.witnessed,
      int score = 8,
    }) => NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: witnesses,
      rules: [
        NpcSocialRule(
          memoryId: 'guard_saw_this',
          sceneId: 'gate', choiceId: 'inspect_gate',
          observerId: 'guard', kind: kind,
          relatedActorId: 'player', relationshipDelta: score,
        ),
      ],
    );
    const present = NpcSceneWitness(
      sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.present,
    );
    final approved = reviewed(witnesses: [present]);
    final world = StoryWorld(bp);
    expect(world.apply(actionId: 'x', choiceId: 'inspect_gate').applied, isTrue);
    final actual = NpcSocialLedger.inspect(world, approved);
    expect(actual.directedScore('guard', 'player'), 8);
    expect(actual.memoriesFor('guard').single.witnessMode,
        NpcWitnessMode.present);
    final replay = StoryWorld.replay(bp, world.events.map((e) => e.toJson()),
        expectedSequence: 1, expectedStateHash: world.state.stateHash);
    expect(NpcSocialLedger.inspect(replay, approved).snapshotHash,
        actual.snapshotHash);

    // A guard marked present in another scene cannot see the gate.
    final elsewhere = reviewed(witnesses: const [
      NpcSceneWitness(
        sceneId: 'market', actorId: 'guard',
        mode: NpcWitnessMode.present,
      ),
    ]);
    expect(() => NpcSocialLedger.inspect(world, elsewhere),
        throwsFormatException);
    expect(() => NpcSocialLedger.inspect(world, reviewed(witnesses: [])),
        throwsFormatException);
    expect(() => NpcSocialLedger.inspect(world, reviewed(
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.reported,
        ),
      ],
    )), throwsFormatException);
    expect(() => NpcSocialLedger.inspect(world, reviewed(
      witnesses: [present, present],
    )), throwsFormatException);
  });

  test('reviewed NPC memory and trust authoritatively lock decisions/replay',
      () {
    final bp = _blueprint();
    final rules = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.present),
      ],
      rules: const [
        NpcSocialRule(
          memoryId: 'guard_remembers_promise', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.promiseReceived,
          relatedActorId: 'player', relationshipDelta: 10),
      ],
      choiceGates: const [
        NpcSocialChoiceGate(
          sceneId: 'gate', choiceId: 'walk_market', actorId: 'guard',
          requiredMemoryId: 'guard_remembers_promise',
          minimumTrustToPlayer: 10),
      ],
    );
    final world = StoryWorld(bp, socialRulebook: rules);
    final initialHash = world.state.stateHash;
    expect(world.choiceLockReason('walk_market'),
        'condition_not_met:npc_memory');
    final denied = world.apply(actionId: 'no', choiceId: 'walk_market');
    expect(denied.status, DecisionStatus.denied);
    expect(world.state.stateHash, initialHash);
    expect(world.events, isEmpty);
    expect(world.apply(actionId: 'witnessed', choiceId: 'inspect_gate').applied,
        isTrue);
    expect(world.choiceLockReason('walk_market'), isNull);
    final checkpoint = world.events.map((event) => event.toJson()).toList();
    final restored = StoryWorld.replay(bp, checkpoint,
      socialRulebook: rules,
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
    );
    expect(restored.choiceLockReason('walk_market'), isNull);
    expect(restored.state.stateHash, world.state.stateHash);
    expect(world.apply(actionId: 'to_market', choiceId: 'walk_market').applied,
        isTrue);
    final withoutGate = StoryWorld(bp);
    expect(withoutGate.apply(actionId: 'unearned', choiceId: 'walk_market')
        .applied, isTrue);
    expect(() => StoryWorld.replay(bp,
        withoutGate.events.map((event) => event.toJson()),
        socialRulebook: rules,
        expectedSequence: withoutGate.state.revision,
        expectedStateHash: withoutGate.state.stateHash),
        throwsFormatException);
    final tooHigh = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: rules.witnesses,
      rules: rules.rules,
      choiceGates: const [
        NpcSocialChoiceGate(
          sceneId: 'gate', choiceId: 'walk_market', actorId: 'guard',
          requiredMemoryId: 'guard_remembers_promise',
          minimumTrustToPlayer: 11),
      ],
    );
    expect(StoryWorld.replay(bp, checkpoint, socialRulebook: tooHigh)
        .choiceLockReason('walk_market'), 'condition_not_met:npc_trust');
  });

  test('NPC departure/return/death are event-sourced, guarded and replayed', () {
    final bp = _blueprint();
    final rules = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.present),
      ],
      rules: const [
        NpcSocialRule(
          memoryId: 'saw_departure', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.witnessed),
      ],
      choiceGates: const [
        NpcSocialChoiceGate(
          sceneId: 'gate', choiceId: 'enter_hall', actorId: 'guard',
          requiredMemoryId: 'saw_departure'),
      ],
      lifeTransitions: const [
        NpcLifeTransition(
          sceneId: 'gate', choiceId: 'inspect_gate',
          actorId: 'guard', nextState: NpcLifeState.absent),
        NpcLifeTransition(
          sceneId: 'market', choiceId: 'return_gate',
          actorId: 'guard', nextState: NpcLifeState.present),
        NpcLifeTransition(
          sceneId: 'market', choiceId: 'buy_map',
          actorId: 'guard', nextState: NpcLifeState.dead),
      ],
    );
    final world = StoryWorld(bp, socialRulebook: rules);
    expect(NpcSocialLedger.inspect(world, rules).lifeState('guard'),
        NpcLifeState.present);
    expect(world.choiceLockReason('enter_hall'),
        'condition_not_met:npc_memory');
    expect(world.apply(actionId: 'depart', choiceId: 'inspect_gate').applied,
        isTrue);
    final absent = NpcSocialLedger.inspect(world, rules);
    expect(absent.lifeState('guard'), NpcLifeState.absent);
    expect(world.choiceLockReason('enter_hall'),
        'condition_not_met:npc_unavailable');
    final oldHead = world.events.last.hash;
    expect(world.apply(actionId: 'depart_again', choiceId: 'inspect_gate')
        .status, DecisionStatus.denied);
    expect(world.events.last.hash, oldHead);
    expect(world.apply(actionId: 'go_to_market', choiceId: 'walk_market')
        .applied, isTrue);
    final branch = world.fork();
    expect(world.apply(actionId: 'returned', choiceId: 'return_gate').applied,
        isTrue);
    expect(NpcSocialLedger.inspect(world, rules).lifeState('guard'),
        NpcLifeState.present);
    expect(world.choiceLockReason('enter_hall'), isNull);
    expect(world.apply(actionId: 'market_again', choiceId: 'walk_market')
        .applied, isTrue);
    expect(world.choiceLockReason('return_gate'),
        'condition_not_met:npc_life_transition');
    expect(world.apply(actionId: 'death', choiceId: 'buy_map').applied,
        isTrue);
    expect(NpcSocialLedger.inspect(world, rules).lifeState('guard'),
        NpcLifeState.dead);
    expect(world.choiceLockReason('enter_hall'),
        'condition_not_met:npc_unavailable');
    final checkpoint = world.events.map((e) => e.toJson()).toList();
    final replayed = StoryWorld.replay(bp, checkpoint,
      socialRulebook: rules, expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash);
    expect(NpcSocialLedger.inspect(replayed, rules).snapshotHash,
        NpcSocialLedger.inspect(world, rules).snapshotHash);
    expect(replayed.apply(actionId: 'visit_again', choiceId: 'walk_market')
        .applied, isTrue);
    expect(replayed.choiceLockReason('return_gate'),
        'condition_not_met:npc_life_transition');
    expect(replayed.choiceLockReason('buy_map'),
        'condition_not_met:npc_life_transition');
    // An alternative branch has its OWN event history; return is valid there.
    expect(branch.apply(actionId: 'different_return', choiceId: 'return_gate')
        .applied, isTrue);
    expect(NpcSocialLedger.inspect(branch, rules).lifeState('guard'),
        NpcLifeState.present);
    expect(() => StoryWorld.replay(bp, checkpoint,
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash),
        returnsNormally); // Old, unguarded replay does not imply verified NPC state.
  });

  test('circular NPC memories cannot deadlock two authored decisions', () {
    final bp = _blueprint();
    final rules = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.present),
      ],
      rules: const [
        NpcSocialRule(
          memoryId: 'before_inspect', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.witnessed),
        NpcSocialRule(
          memoryId: 'after_market', sceneId: 'gate',
          choiceId: 'walk_market', observerId: 'guard',
          kind: NpcMemoryKind.witnessed),
      ],
      choiceGates: const [
        NpcSocialChoiceGate(
          sceneId: 'gate', choiceId: 'inspect_gate', actorId: 'guard',
          requiredMemoryId: 'after_market'),
        NpcSocialChoiceGate(
          sceneId: 'gate', choiceId: 'walk_market', actorId: 'guard',
          requiredMemoryId: 'before_inspect'),
      ],
    );
    expect(() => StoryWorld(bp, socialRulebook: rules),
        throwsFormatException);
  });

  test('NPC item custody is authoritative and event-sourced, no phantom gifts',
      () {
    final raw = jsonDecode(
      File('../../shared_schemas/fixtures/manor_world_m17.json')
          .readAsStringSync()) as Map<String, dynamic>;
    final market = (raw['scenes'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((scene) => scene['id'] == 'market');
    final choices = (market['choices'] as List)
        .cast<Map<String, dynamic>>();
    (choices.singleWhere((c) => c['id'] == 'ask_guard')['effects']
        as List).add({'op': 'consume_item', 'id': 'map'});
    (choices.singleWhere((c) => c['id'] == 'return_gate')['effects']
        as List).add({'op': 'grant_item', 'id': 'map'});
    final bp = StoryBlueprint.fromJson(raw);
    final contract = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'market', actorId: 'guard', mode: NpcWitnessMode.present),
      ],
      rules: const [],
      itemTransfers: const [
        NpcItemTransfer(
          sceneId: 'market', choiceId: 'ask_guard', itemId: 'map',
          fromActorId: 'player', toActorId: 'guard'),
        NpcItemTransfer(
          sceneId: 'market', choiceId: 'return_gate', itemId: 'map',
          fromActorId: 'guard', toActorId: 'player'),
      ],
    );
    final world = StoryWorld(bp, socialRulebook: contract);
    expect(world.apply(actionId: 'trip1', choiceId: 'walk_market').applied,
        isTrue);
    expect(world.choiceLockReason('return_gate'),
        'condition_not_met:npc_item_owner');
    expect(world.choiceLockReason('ask_guard'),
        'condition_not_met:npc_item_owner');
    expect(world.apply(actionId: 'buy', choiceId: 'buy_map').applied, isTrue);
    expect(NpcSocialLedger.inspect(world, contract).itemOwner('map'), 'player');
    expect(world.apply(actionId: 'trip2', choiceId: 'walk_market').applied,
        isTrue);
    expect(world.apply(actionId: 'gift', choiceId: 'ask_guard').applied, isTrue);
    final given = NpcSocialLedger.inspect(world, contract);
    expect(given.itemOwner('map'), 'guard');
    expect(given.itemsHeldBy('guard'), ['map']);
    expect(world.state.inventory, isNot(contains('map')));
    expect(() => given.itemOwner('missing'), throwsFormatException);

    expect(world.apply(actionId: 'trip3', choiceId: 'walk_market').applied,
        isTrue);
    // New "grant_item" while the guard carries the same unique item must
    // not duplicate ownership or produce a confirmed event.
    final beforeRevision = world.state.revision;
    final beforeHead = world.events.last.hash;
    final forged = world.apply(actionId: 'counterfeit', choiceId: 'buy_map');
    expect(forged.status, DecisionStatus.denied);
    expect(forged.reason, 'condition_not_met:npc_item_custody');
    expect(world.state.revision, beforeRevision);
    expect(world.events.last.hash, beforeHead);
    expect(world.apply(actionId: 'return', choiceId: 'return_gate').applied,
        isTrue);
    final returned = NpcSocialLedger.inspect(world, contract);
    expect(returned.itemOwner('map'), 'player');
    expect(returned.itemsHeldBy('guard'), isEmpty);
    expect(world.state.inventory, contains('map'));
    final replay = StoryWorld.replay(
      bp, world.events.map((event) => event.toJson()),
      socialRulebook: contract,
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
    );
    final recovered = NpcSocialLedger.inspect(replay, contract);
    expect(recovered.itemOwner('map'), 'player');
    expect(recovered.snapshotHash, returned.snapshotHash);

    final unreviewed = StoryWorld(bp);
    expect(unreviewed.apply(actionId: 'trip', choiceId: 'walk_market')
        .applied, isTrue);
    expect(unreviewed.apply(actionId: 'phantom', choiceId: 'return_gate')
        .applied, isTrue);
    expect(() => StoryWorld.replay(
      bp, unreviewed.events.map((event) => event.toJson()),
      socialRulebook: contract,
      expectedSequence: unreviewed.state.revision,
      expectedStateHash: unreviewed.state.stateHash,
    ), throwsFormatException);
  });

  test('rumor is second-hand information, not witnessed promise or trust',
      () {
    final bp = _blueprint();
    final witness = const NpcSceneWitness(
      sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.reported,
    );
    final rumor = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true, witnesses: [witness],
      rules: const [
        NpcSocialRule(
          memoryId: 'guard_heard_gossip', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.rumorHeard,
        ),
      ],
    );
    final world = StoryWorld(bp);
    expect(world.apply(actionId: 'a', choiceId: 'inspect_gate').applied, isTrue);
    final snapshot = NpcSocialLedger.inspect(world, rumor);
    expect(snapshot.memoriesFor('guard').single.witnessMode,
        NpcWitnessMode.reported);
    expect(snapshot.directedScore('guard', 'player'), 0);
    final changed = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true,
      witnesses: const [
        NpcSceneWitness(
          sceneId: 'gate', actorId: 'guard', mode: NpcWitnessMode.present,
        ),
      ],
      rules: rumor.rules,
    );
    expect(changed.digest, isNot(rumor.digest));
    final falseTrust = NpcSocialRulebook(
      blueprintHash: bp.blueprintHash,
      requireReviewedWitnesses: true, witnesses: [witness],
      rules: const [
        NpcSocialRule(
          memoryId: 'false_trust', sceneId: 'gate',
          choiceId: 'inspect_gate', observerId: 'guard',
          kind: NpcMemoryKind.rumorHeard,
          relatedActorId: 'player', relationshipDelta: 5,
        ),
      ],
    );
    expect(() => NpcSocialLedger.inspect(world, falseTrust),
        throwsFormatException);
  });

  test('independent rulebook fingerprint makes changing authored rules visible',
      () {
    final bp = _blueprint();
    final original = _rules(bp);
    final reversed = NpcSocialRulebook(
        blueprintHash: bp.blueprintHash,
        rules: original.rules.reversed.toList());
    expect(original.digest, reversed.digest);
    final replaced = NpcSocialRulebook(
        blueprintHash: bp.blueprintHash,
        rules: [
          const NpcSocialRule(
            memoryId: 'guard_heard_request',
            sceneId: 'gate', choiceId: 'inspect_gate',
            observerId: 'guard', kind: NpcMemoryKind.promiseBroken,
            relatedActorId: 'player', relationshipDelta: -10,
          ),
        ]);
    expect(original.digest, isNot(replaced.digest));
    final world = StoryWorld(bp);
    expect(world.apply(actionId: 'act', choiceId: 'inspect_gate').applied,
        isTrue);
    final before = NpcSocialLedger.inspect(world, original);
    final after = NpcSocialLedger.inspect(world, replaced);
    expect(before.snapshotHash, isNot(after.snapshotHash));
    expect(before.directedScore('guard', 'player'), 10);
    expect(after.directedScore('guard', 'player'), -10);
    // A separate rulebook must be bound to the save/approved revision
    // before it can ever authorize gameplay or dialogue.
  });
}
