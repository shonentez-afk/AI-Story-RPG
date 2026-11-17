import 'blueprint.dart';
import 'causal_state_signature.dart';
import 'codec.dart';
import 'engine.dart';
import 'npc_social_ledger.dart';

/// A route is PROVEN only if the real, deterministic StoryWorld accepted
/// every action. A bounded search never calls a missing route "impossible".
enum CausalRouteStatus { proven, unreachable, inconclusive }

class CausalRouteReport {
  CausalRouteReport._({
    required this.status,
    required this.inspectedStates,
    required this.choiceIds,
    required this.events,
    required this.resultStateHash,
  });

  final CausalRouteStatus status;
  final int inspectedStates;
  /// Exact ordered choice IDs (no prose/LLM inference).
  final List<String> choiceIds;
  /// Hash-chained, independently replayable committed actions.
  final List<WorldEvent> events;
  final String? resultStateHash;

  bool get proven => status == CausalRouteStatus.proven;
}

/// Pure, bounded causal gameplay preflight for authored scenes and future
/// book-wide planners. It is NOT a second game interpreter: every edge is
/// tested through StoryWorld.apply, including conditions, social memory,
/// directed trust, life transitions and item custody.
///
/// Returns a shortest executable route if one can be found. An unreachable
/// result means the search exhausted distinguishable game states; a budget,
/// time-gate or step limit returns inconclusive instead of a false claim.
///
/// No source text, cloud model, Flutter, SQLite or filesystem dependency.
class StoryCausalRouteAudit {
  const StoryCausalRouteAudit._();

  static CausalRouteReport find({
    required StoryBlueprint blueprint,
    required String targetSceneId,
    String? requiredPriorChoiceId,
    String? forbiddenChoiceId,
    String? actorId,
    Iterable<String> requiredFactIds = const [],
    String? requiredMemoryId,
    int? minimumTrustToPlayer,
    NpcSocialRulebook? socialRulebook,
    int maxStates = 4096,
    int maxMoves = 128,
    bool projectDormantFlags = false,
  }) {
    jsonId(targetSceneId, 'causal.target_scene');
    if (!blueprint.scenes.containsKey(targetSceneId) ||
        maxStates < 1 || maxStates > 20000 ||
        maxMoves < 1 || maxMoves > 2000) {
      throw const FormatException('Invalid causal route audit scope/budget');
    }
    final choices = {
      for (final scene in blueprint.scenes.values)
        for (final choice in scene.choices) choice.id: choice,
    };
    if (requiredPriorChoiceId != null &&
        !choices.containsKey(requiredPriorChoiceId)) {
      throw const FormatException('Unknown required causal choice');
    }
    if (forbiddenChoiceId != null &&
        !choices.containsKey(forbiddenChoiceId)) {
      throw const FormatException('Unknown forbidden causal choice');
    }
    if (requiredPriorChoiceId != null &&
        requiredPriorChoiceId == forbiddenChoiceId) {
      throw const FormatException('Contradictory causal route requirements');
    }
    final facts = requiredFactIds.toSet();
    if (facts.length > 16 ||
        facts.any((fact) => !blueprint.facts.contains(fact))) {
      throw const FormatException('Unknown causal fact prerequisite');
    }
    final needsActor = facts.isNotEmpty ||
        requiredMemoryId != null || minimumTrustToPlayer != null;
    if ((needsActor && actorId == null) ||
        (actorId != null && !blueprint.actors.contains(actorId))) {
      throw const FormatException('Unknown causal route actor');
    }
    if ((requiredMemoryId != null || minimumTrustToPlayer != null) &&
        (socialRulebook == null || actorId == 'player' ||
         (minimumTrustToPlayer != null &&
          (minimumTrustToPlayer < 1 || minimumTrustToPlayer > 100)))) {
      throw const FormatException('Unreviewed social route prerequisite');
    }
    if (requiredMemoryId != null) {
      jsonId(requiredMemoryId, 'causal.memory_id');
      if (!socialRulebook!.rules.any((r) =>
          r.observerId == actorId && r.memoryId == requiredMemoryId)) {
        throw const FormatException('Unknown causal NPC memory');
      }
    }
    socialRulebook?.validate(blueprint);
    final start = StoryWorld(blueprint, socialRulebook: socialRulebook);
    final queue = <StoryWorld>[start];
    final visited = <String>{};
    var head = 0;
    var limited = false;
    // Campaign and individual NPC proofs share identical game-state
    // equivalence. Never merge routes on scene ID alone.
    final signature = CausalStateSignature(blueprint, socialRulebook,
      projectDormantFlags: projectDormantFlags);
    String stateKey(StoryWorld world) => signature.of(
      world, requiredPriorChoiceId: requiredPriorChoiceId,
    );

    visited.add(stateKey(start));
    while (head < queue.length) {
      final world = queue[head++];
      final state = world.state;
      if (state.sceneId == targetSceneId &&
          (requiredPriorChoiceId == null ||
              world.events.any((event) =>
                  event.choiceId == requiredPriorChoiceId)) &&
          (actorId == null || facts.every((fact) =>
              world.actorKnowsFact(actorId, fact)))) {
        final social = socialRulebook == null ? null
            : NpcSocialLedger.inspect(world, socialRulebook);
        if ((actorId == null || actorId == 'player' ||
                social == null ||
                social.lifeState(actorId) == NpcLifeState.present) &&
            (requiredMemoryId == null ||
                social!.hasMemory(actorId!, requiredMemoryId)) &&
            (minimumTrustToPlayer == null ||
                social!.directedScore(actorId!, 'player') >=
                    minimumTrustToPlayer)) {
          // Recheck the exact committed route, not only a cached summary.
          final checked = StoryWorld.replay(
            blueprint, world.events.map((e) => e.toJson()),
            expectedSequence: world.state.revision,
            expectedStateHash: world.state.stateHash,
            socialRulebook: socialRulebook,
          );
          if (checked.state.sceneId != targetSceneId) {
            throw StateError('Causal route witness disagrees with replay');
          }
          return CausalRouteReport._(
            status: CausalRouteStatus.proven,
            inspectedStates: head,
            choiceIds: List.unmodifiable(
                world.events.map((event) => event.choiceId)),
            events: world.events,
            resultStateHash: checked.state.stateHash,
          );
        }
      }
      if (world.isTerminal) continue;
      final current = blueprint.scenes[world.state.sceneId]!;
      if (world.events.length >= maxMoves) {
        // A later turn could still satisfy a time/knowledge/social gate.
        limited = true;
        continue;
      }
      for (final choice in current.choices) {
        if (choice.id == forbiddenChoiceId ||
            world.choiceLockReason(choice.id) != null) {
          continue;
        }
        final next = world.fork();
        final applied = next.apply(
          actionId: 'causal_step_' + (world.events.length + 1).toString(),
          choiceId: choice.id, expectedRevision: world.state.revision,
        );
        if (!applied.applied) continue;
        final key = stateKey(next);
        if (visited.contains(key)) continue;
        if (visited.length >= maxStates) {
          limited = true;
          continue;
        }
        visited.add(key);
        queue.add(next);
      }
    }
    return CausalRouteReport._(
      status: limited
          ? CausalRouteStatus.inconclusive : CausalRouteStatus.unreachable,
      inspectedStates: head,
      choiceIds: const [],
      events: const [],
      resultStateHash: null,
    );
  }
}
