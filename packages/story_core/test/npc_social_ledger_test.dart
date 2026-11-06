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
