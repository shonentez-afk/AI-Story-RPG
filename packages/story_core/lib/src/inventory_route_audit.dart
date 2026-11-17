import 'blueprint.dart';
import 'causal_state_signature.dart';
import 'engine.dart';
import 'npc_social_ledger.dart';

/// Facts about ALL reachable gameplay states, never a current save or a
/// probability estimate. A declared pickup does not imply current ownership.
enum RouteItemPresence { always, sometimes, never }

class SceneInventoryEvidence {
  SceneInventoryEvidence._(this.sceneId, this.reachableStateCount,
      Set<String> catalog, Set<String> intersection, Set<String> union)
      : items = Set.unmodifiable(catalog),
        alwaysPresent = Set.unmodifiable(intersection),
        possiblyPresent = Set.unmodifiable(union),
        neverPresent = Set.unmodifiable(catalog.difference(union));

  final String sceneId;
  final int reachableStateCount;
  final Set<String> items, alwaysPresent, possiblyPresent, neverPresent;

  RouteItemPresence presenceOf(String itemId) {
    if (!items.contains(itemId)) {
      throw const FormatException('Unknown item in inventory route evidence');
    }
    if (alwaysPresent.contains(itemId)) return RouteItemPresence.always;
    if (possiblyPresent.contains(itemId)) return RouteItemPresence.sometimes;
    return RouteItemPresence.never;
  }

  Map<String, dynamic> toJson() => {
    'scene_id': sceneId,
    'reachable_states': reachableStateCount,
    'always_present': alwaysPresent.toList()..sort(),
    'branch_dependent': possiblyPresent.difference(alwaysPresent).toList()..sort(),
    'never_present': neverPresent.toList()..sort(),
  };
}

class InventoryRouteEvidence {
  InventoryRouteEvidence._(this.blueprintHash, this.exploredStates,
      Map<String, SceneInventoryEvidence> observations)
      : scenes = Map.unmodifiable(observations);

  final String blueprintHash;
  final int exploredStates;
  final Map<String, SceneInventoryEvidence> scenes;
  bool get exhaustive => true;
  bool get describesCurrentSave => false;
  bool get verifiesLiteraryCanon => false;
}

/// Source-independent, read-only authoring audit. Each edge is executed by
/// the SAME StoryWorld used in games, including inventory consumption and
/// optional social conditions. No Flutter, files, model calls or new rules.
///
/// This is an inventory proof, not a replacement for the campaign liveness
/// gate. Unknown/unreachable requested scenes and any exhausted budget throw
/// before a partial traversal could become a false 'always' or 'never'.
class StoryInventoryRouteAudit {
  const StoryInventoryRouteAudit._();

  static InventoryRouteEvidence inspect({
    required StoryBlueprint blueprint,
    required Iterable<String> sceneIds,
    NpcSocialRulebook? socialRulebook,
    int maxStates = 8192,
    int maxMoves = 256,
  }) {
    final targets = sceneIds.toSet();
    if (targets.isEmpty || targets.length > 192 ||
        targets.any((id) => !blueprint.scenes.containsKey(id)) ||
        maxStates < 1 || maxStates > 8192 || maxMoves < 1 || maxMoves > 256) {
      throw const FormatException('Invalid inventory route audit scope/budget');
    }
    socialRulebook?.validate(blueprint);
    final signature = CausalStateSignature(blueprint, socialRulebook);
    final first = StoryWorld(blueprint, socialRulebook: socialRulebook);
    final queue = <StoryWorld>[first];
    final seen = <String>{signature.of(first)};
    final counts = <String, int>{};
    final intersection = <String, Set<String>>{};
    final union = <String, Set<String>>{};

    for (var cursor = 0; cursor < queue.length; cursor++) {
      final world = queue[cursor];
      final sceneId = world.state.sceneId;
      if (targets.contains(sceneId)) {
        final inventory = world.state.inventory;
        counts[sceneId] = (counts[sceneId] ?? 0) + 1;
        union.putIfAbsent(sceneId, () => <String>{}).addAll(inventory);
        if (intersection.containsKey(sceneId)) {
          intersection[sceneId]!.retainAll(inventory);
        } else {
          intersection[sceneId] = Set<String>.of(inventory);
        }
      }
      if (world.isTerminal) continue;
      if (world.events.length >= maxMoves) {
        throw const FormatException('Inventory route audit exceeded move budget');
      }
      for (final choice in blueprint.scenes[sceneId]!.choices) {
        if (world.choiceLockReason(choice.id) != null) continue;
        final next = world.fork();
        final result = next.apply(
          actionId: 'inventory_audit_${world.state.revision + 1}',
          choiceId: choice.id, expectedRevision: world.state.revision,
        );
        if (!result.applied) continue;
        final key = signature.of(next);
        if (seen.contains(key)) continue;
        if (seen.length >= maxStates) {
          throw const FormatException('Inventory route audit exceeded state budget');
        }
        seen.add(key);
        queue.add(next);
      }
    }
    if (targets.any((id) => !counts.containsKey(id))) {
      throw const FormatException('Requested inventory scene is not reachable');
    }
    return InventoryRouteEvidence._(blueprint.blueprintHash, queue.length, {
      for (final id in targets)
        id: SceneInventoryEvidence._(id, counts[id]!, blueprint.items,
            intersection[id]!, union[id]!),
    });
  }
}
