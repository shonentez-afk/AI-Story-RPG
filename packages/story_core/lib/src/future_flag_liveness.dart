import 'dart:collection';

import 'blueprint.dart';

/// One EXISTING game transition. Read/write sets are a conservative
/// description of typed flags, never a new set of game rules.
class FutureFlagEdge {
  const FutureFlagEdge({
    required this.from,
    required this.to,
    this.reads = const <String>[],
    this.writes = const <String>[],
  });

  final String from;
  final String to;
  final Iterable<String> reads;
  final Iterable<String> writes;
}

/// Sound conservative projection for bounded reachability proofs.
///
/// Two concrete states at the SAME scene may be merged ONLY if every flag
/// that can still influence a future choice/contract has an equal value.
/// The proof never changes WorldState, WorldEvents, persistent flags,
/// actor-specific knowledge, inventory, social ledger or save hashes.
///
/// Dataflow is a reverse fixed point over the *entire unfiltered graph*:
/// uncertain branches/cycles are included, rather than guessed away.
/// An exclusive group is retained wherever a future choice may WRITE a
/// member; this prevents a dormant previous outcome concealing a future
/// exclusive-state violation. Additional reads cover invariants which inspect
/// a flag without adding an explicit condition to a player choice.
class FutureFlagLiveness {
  FutureFlagLiveness._(this._live);

  final Map<String, Set<String>> _live;

  static FutureFlagLiveness derive({
    required Iterable<String> scenes,
    required Iterable<FutureFlagEdge> edges,
    Iterable<Iterable<String>> exclusiveGroups =
        const <Iterable<String>>[],
    Map<String, Iterable<String>> additionalReadsByScene =
        const <String, Iterable<String>>{},
  }) {
    final ids = scenes.toSet();
    if (ids.isEmpty) throw const FormatException('Empty causal scene graph');
    final predecessors = <String, Set<String>>{
      for (final id in ids) id: <String>{},
    };
    final localReads = <String, Set<String>>{
      for (final id in ids) id: <String>{},
    };
    final futureWrites = <String, Set<String>>{
      for (final id in ids) id: <String>{},
    };
    for (final edge in edges) {
      if (!ids.contains(edge.from) || !ids.contains(edge.to)) {
        throw const FormatException('Unresolved causal scene edge');
      }
      predecessors[edge.to]!.add(edge.from);
      localReads[edge.from]!.addAll(edge.reads);
      futureWrites[edge.from]!.addAll(edge.writes);
    }
    for (final row in additionalReadsByScene.entries) {
      if (!ids.contains(row.key)) {
        throw const FormatException('Unknown causal invariant scene');
      }
      localReads[row.key]!.addAll(row.value);
    }

    // The queue grows only when an additional flag becomes relevant.
    // No recursion, route enumeration or temporal assumptions.
    void propagate(Map<String, Set<String>> values) {
      final queue = Queue<String>.from(ids);
      final pending = ids.toSet();
      while (queue.isNotEmpty) {
        final child = queue.removeFirst();
        pending.remove(child);
        for (final predecessor in predecessors[child]!) {
          final target = values[predecessor]!;
          final size = target.length;
          target.addAll(values[child]!);
          if (target.length != size && pending.add(predecessor)) {
            queue.addLast(predecessor);
          }
        }
      }
    }

    propagate(futureWrites);
    final groups = [
      for (final group in exclusiveGroups) group.toSet(),
    ];
    for (final scene in ids) {
      final writes = futureWrites[scene]!;
      for (final group in groups) {
        if (group.intersection(writes).isNotEmpty) {
          localReads[scene]!.addAll(group);
        }
      }
    }
    propagate(localReads);
    return FutureFlagLiveness._(Map.unmodifiable({
      for (final scene in ids)
        scene: Set<String>.unmodifiable(localReads[scene]!),
    }));
  }

  factory FutureFlagLiveness.fromBlueprint(StoryBlueprint blueprint) =>
      FutureFlagLiveness.derive(
        scenes: blueprint.scenes.keys,
        edges: [
          for (final scene in blueprint.scenes.values)
            for (final choice in scene.choices)
              FutureFlagEdge(
                from: scene.id,
                to: choice.nextSceneId,
                reads: [
                  for (final condition in choice.conditions)
                    if (condition.op == 'flag_is') condition.id!,
                ],
                writes: [
                  for (final effect in choice.effects)
                    if (effect.op == 'set_flag') effect.id!,
                ],
              ),
        ],
      );

  Set<String> at(String scene) {
    final flags = _live[scene];
    if (flags == null) {
      throw const FormatException('Unknown causal projection scene');
    }
    return flags;
  }

  int bitMask(String scene, Map<String, int> byFlag) {
    var mask = 0;
    for (final flag in at(scene)) {
      final bit = byFlag[flag];
      if (bit == null) {
        throw const FormatException('Projection uses an undeclared flag');
      }
      mask |= bit;
    }
    return mask;
  }
}
