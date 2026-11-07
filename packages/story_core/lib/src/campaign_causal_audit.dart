import 'blueprint.dart';
import 'causal_state_signature.dart';
import 'codec.dart';
import 'engine.dart';
import 'npc_social_ledger.dart';

/// Fully explored and playable, a definite counterexample, or a bounded
/// search which must not masquerade as proof of completeness.
enum CampaignCausalStatus { playable, blocked, inconclusive }

/// A shortest real decision sequence that ends in a nonterminal scene
/// with NO legal moves. Only verified WorldEvents can prove such a trap.
class CampaignCausalTrap {
  CampaignCausalTrap._({
    required this.sceneId,
    required this.stateHash,
    required this.events,
    required this.choiceLockReasons,
  });

  final String sceneId;
  final String stateHash;
  final List<WorldEvent> events;
  final Map<String, String> choiceLockReasons;
  List<String> get choiceIds => List.unmodifiable(
      events.map((event) => event.choiceId));
}

/// The report never includes source-book text, private identities or cloud
/// predictions. Witnesses remain replayable with the same signed blueprint.
class CampaignCausalReport {
  CampaignCausalReport._({
    required this.status,
    required this.exploredStates,
    required this.exhaustive,
    required this.terminalWitnesses,
    required this.choiceWitnesses,
    required this.traps,
    required this.trapCount,
    required this.unprovenTerminalIds,
    required this.unprovenRequiredChoiceIds,
  });

  final CampaignCausalStatus status;
  final int exploredStates;
  final bool exhaustive;

  /// Shortest committed paths to each reached terminal scene.
  final Map<String, List<WorldEvent>> terminalWitnesses;

  /// Shortest committed paths which actually executed each reached choice.
  final Map<String, List<WorldEvent>> choiceWitnesses;

  /// First 16 deterministic counterexamples, ordered by BFS discovery.
  final List<CampaignCausalTrap> traps;
  final int trapCount;

  /// Only proof of *absence* when exhaustive is true. When truncated, these
  /// are simply not yet proven rather than known to be unreachable.
  final List<String> unprovenTerminalIds;
  final List<String> unprovenRequiredChoiceIds;

  bool get playable => status == CampaignCausalStatus.playable;
}

/// Offline coverage audit for one compiled multi-act StoryBlueprint.
///
/// This is NOT a graph walker or alternate game interpreter: every edge is a
/// successful StoryWorld.apply() on a fork. A reachable softlock, a missing
/// promised ending, and an optional required choice without an executable
/// path are rejected with hash-chain witnesses or exhaustive evidence.
/// Exact state equivalence is shared with StoryCausalRouteAudit, including
/// NPC knowledge, social memory, directed trust, life and item ownership.
///
/// No Flutter, SQLite, file access, Z.ai or modification of a real campaign.
class StoryCampaignCausalAudit {
  const StoryCampaignCausalAudit._();

  static CampaignCausalReport inspect({
    required StoryBlueprint blueprint,
    NpcSocialRulebook? socialRulebook,
    bool requireAllTerminals = true,
    Iterable<String> requiredChoiceIds = const [],
    int maxStates = 8192,
    int maxMoves = 256,
  }) {
    if (maxStates < 1 || maxStates > 20000 ||
        maxMoves < 1 || maxMoves > 2000) {
      throw const FormatException('Invalid campaign causal audit budget');
    }
    socialRulebook?.validate(blueprint);
    final allChoices = {
      for (final scene in blueprint.scenes.values)
        for (final choice in scene.choices) choice.id,
    };
    final required = <String>{};
    for (final choiceId in requiredChoiceIds) {
      jsonId(choiceId, 'campaign.required_choice_id');
      if (!allChoices.contains(choiceId) || !required.add(choiceId)) {
        throw const FormatException('Unknown or duplicate required choice');
      }
    }

    final requiredTerminals = <String>{
      if (requireAllTerminals)
        for (final scene in blueprint.scenes.values)
          if (scene.terminal) scene.id,
    };
    final signature = CausalStateSignature(blueprint, socialRulebook);
    final start = StoryWorld(blueprint, socialRulebook: socialRulebook);
    final visited = <String>{signature.of(start)};
    final queue = <StoryWorld>[start];

    final terminalWitnesses = <String, List<WorldEvent>>{};
    final choiceWitnesses = <String, List<WorldEvent>>{};
    final traps = <CampaignCausalTrap>[];
    var trapCount = 0;
    var limited = false;

    // Revalidate terminal and trap witnesses by replay rather than trusting
    // cached reachability labels, a prose plan, or a non-committed step.
    List<WorldEvent> checkedEvents(StoryWorld world) {
      final restored = StoryWorld.replay(
        blueprint, world.events.map((event) => event.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
        socialRulebook: socialRulebook,
      );
      if (restored.state.sceneId != world.state.sceneId) {
        throw StateError('Causal witness changed its final scene');
      }
      return List<WorldEvent>.unmodifiable(world.events);
    }

    for (var cursor = 0; cursor < queue.length; cursor++) {
      final world = queue[cursor];
      final scene = blueprint.scenes[world.state.sceneId]!;
      if (scene.terminal) {
        terminalWitnesses.putIfAbsent(
          scene.id, () => checkedEvents(world),
        );
        continue;
      }
      if (world.events.length >= maxMoves) {
        // The next real action might escape. This is NOT a trapped state.
        limited = true;
        continue;
      }

      var legalMoves = 0;
      final denied = <String, String>{};
      for (final choice in scene.choices) {
        final locked = world.choiceLockReason(choice.id);
        if (locked != null) {
          denied[choice.id] = locked;
          continue;
        }
        final next = world.fork();
        final result = next.apply(
          actionId: 'campaign_step_' +
              (world.events.length + 1).toString(),
          choiceId: choice.id,
          expectedRevision: world.state.revision,
        );
        if (!result.applied) {
          denied[choice.id] = result.reason ?? 'action_denied';
          continue;
        }
        legalMoves++;
        if (!choiceWitnesses.containsKey(choice.id)) {
          // A legal action's event, not only a reachable choice label.
          choiceWitnesses[choice.id] =
              List<WorldEvent>.unmodifiable(next.events);
        }
        final nextKey = signature.of(next);
        if (!visited.add(nextKey)) continue;
        if (visited.length > maxStates) {
          // No false "all endings covered" when the exploration ended
          // at a resource limit. Only states actually queued are examined.
          visited.remove(nextKey);
          limited = true;
          continue;
        }
        queue.add(next);
      }

      if (legalMoves == 0) {
        trapCount++;
        if (traps.length < 16) {
          traps.add(CampaignCausalTrap._(
            sceneId: scene.id,
            stateHash: world.state.stateHash,
            events: checkedEvents(world),
            choiceLockReasons:
                Map<String, String>.unmodifiable(denied),
          ));
        }
      }
    }

    final unprovenTerminals = requiredTerminals
        .difference(terminalWitnesses.keys.toSet()).toList()..sort();
    final unprovenChoices = required
        .difference(choiceWitnesses.keys.toSet()).toList()..sort();

    // A found trap is a real counterexample even if the search was bounded.
    // Missing endings and choices can ONLY be declared impossible after the
    // state space was fully explored. Inconclusive is distinct from blocked.
    final status = trapCount > 0 ||
        (!limited &&
          (unprovenTerminals.isNotEmpty ||
           unprovenChoices.isNotEmpty))
        ? CampaignCausalStatus.blocked
        : limited
            ? CampaignCausalStatus.inconclusive
            : CampaignCausalStatus.playable;

    return CampaignCausalReport._(
      status: status,
      exploredStates: queue.length,
      exhaustive: !limited,
      terminalWitnesses:
          Map<String, List<WorldEvent>>.unmodifiable(terminalWitnesses),
      choiceWitnesses:
          Map<String, List<WorldEvent>>.unmodifiable(choiceWitnesses),
      traps: List<CampaignCausalTrap>.unmodifiable(traps),
      trapCount: trapCount,
      unprovenTerminalIds: List<String>.unmodifiable(unprovenTerminals),
      unprovenRequiredChoiceIds:
          List<String>.unmodifiable(unprovenChoices),
    );
  }
}
