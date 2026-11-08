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
/// A replayable closed narrative cycle in the REAL reachable state graph.
/// This is not an infinite-loop heuristic: every state in its SCC lacks any
/// path to a terminal, after an exhaustive audit. Optional loops with an
/// executable escape are never reported.
class CampaignCausalCycle {
  CampaignCausalCycle._({
    required this.sceneId,
    required this.stateHash,
    required this.entryEvents,
    required this.cycleChoiceIds,
    required this.events,
  });

  final String sceneId;
  final String stateHash;
  /// Shortest replayable approach to the first state of this cycle.
  final List<WorldEvent> entryEvents;
  /// One real repeat, from and back to the equivalent gameplay state.
  final List<String> cycleChoiceIds;
  /// Complete replayable event chain: approach plus the first full repeat.
  final List<WorldEvent> events;
}

class CampaignCausalReport {
  CampaignCausalReport._({
    required this.status,
    required this.exploredStates,
    required this.exhaustive,
    required this.terminalWitnesses,
    required this.choiceWitnesses,
    required this.traps,
    required this.trapCount,
    required this.cycles,
    required this.cycleCount,
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

  /// Non-escaping cyclic SCCs, only reported after exhaustive exploration.
  final List<CampaignCausalCycle> cycles;
  final int cycleCount;

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
    /// Opt-in proof equivalence for source-reviewed v4, not a world mutation.
    bool projectDormantFlags = false,
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
    final signature = CausalStateSignature(blueprint, socialRulebook,
        projectDormantFlags: projectDormantFlags);
    final start = StoryWorld(blueprint, socialRulebook: socialRulebook);
    final firstKey = signature.of(start);
    final queue = <StoryWorld>[start];
    final stateKeys = <String>[firstKey];
    final stateIndex = <String, int>{firstKey: 0};
    // Include edges to already visited states: those are the crucial
    // backwards/self edges that the previous shortest-path BFS discarded.
    final edges = <List<({int to, String choiceId})>>[[]];

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
        final knownIndex = stateIndex[nextKey];
        if (knownIndex != null) {
          edges[cursor].add((to: knownIndex, choiceId: choice.id));
          continue;
        }
        if (queue.length >= maxStates) {
          // A transition into an unexamined state invalidates liveness proof.
          limited = true;
          continue;
        }
        final newIndex = queue.length;
        stateIndex[nextKey] = newIndex;
        edges[cursor].add((to: newIndex, choiceId: choice.id));
        queue.add(next);
        stateKeys.add(nextKey);
        edges.add([]);
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

    // Reverse reachability from ACTUAL terminal states, never from merely
    // graph-connected scene IDs. A loop is benign when a player can exit it.
    final reverse = List.generate(queue.length, (_) => <int>[]);
    final canReachTerminal = <int>{};
    final backwardQueue = <int>[];
    for (var i = 0; i < queue.length; i++) {
      if (blueprint.scenes[queue[i].state.sceneId]!.terminal) {
        canReachTerminal.add(i);
        backwardQueue.add(i);
      }
      for (final edge in edges[i]) {
        reverse[edge.to].add(i);
      }
    }
    for (var i = 0; i < backwardQueue.length; i++) {
      for (final predecessor in reverse[backwardQueue[i]]) {
        if (canReachTerminal.add(predecessor)) {
          backwardQueue.add(predecessor);
        }
      }
    }

    final cycles = <CampaignCausalCycle>[];
    var cycleCount = 0;
    if (!limited) {
      // Iterative Kosaraju: avoid recursion/stack overflow on large books.
      final seen = List<bool>.filled(queue.length, false);
      final finish = <int>[];
      for (var root = 0; root < queue.length; root++) {
        if (seen[root]) continue;
        final stack = <int>[root];
        final cursorByDepth = <int>[0];
        seen[root] = true;
        while (stack.isNotEmpty) {
          final node = stack.last;
          final offset = cursorByDepth.last;
          if (offset == edges[node].length) {
            finish.add(stack.removeLast());
            cursorByDepth.removeLast();
            continue;
          }
          cursorByDepth[cursorByDepth.length - 1] = offset + 1;
          final target = edges[node][offset].to;
          if (!seen[target]) {
            seen[target] = true;
            stack.add(target);
            cursorByDepth.add(0);
          }
        }
      }

      final assigned = List<bool>.filled(queue.length, false);
      for (final seed in finish.reversed) {
        if (assigned[seed]) continue;
        final members = <int>[];
        final pending = <int>[seed];
        assigned[seed] = true;
        while (pending.isNotEmpty) {
          final node = pending.removeLast();
          members.add(node);
          for (final predecessor in reverse[node]) {
            if (!assigned[predecessor]) {
              assigned[predecessor] = true;
              pending.add(predecessor);
            }
          }
        }
        final memberSet = members.toSet();
        final isCycle = members.length > 1 ||
            edges[members.single].any((edge) => edge.to == members.single);
        if (!isCycle ||
            members.any((node) => canReachTerminal.contains(node))) {
          continue;
        }

        cycleCount++;
        if (cycles.length == 16) continue;
        // A representative shortest approach, followed by one actual cycle.
        final entry = members.reduce((a, b) => a < b ? a : b);
        final firstEdge = edges[entry].firstWhere(
            (edge) => memberSet.contains(edge.to));
        final cycleChoices = <String>[firstEdge.choiceId];
        if (firstEdge.to != entry) {
          final routeQueue = <int>[firstEdge.to];
          final visited = <int>{firstEdge.to};
          final parent = <int, int>{};
          final viaChoice = <int, String>{};
          for (var i = 0;
              i < routeQueue.length && !visited.contains(entry); i++) {
            final node = routeQueue[i];
            for (final edge in edges[node]) {
              if (!memberSet.contains(edge.to) ||
                  !visited.add(edge.to)) continue;
              parent[edge.to] = node;
              viaChoice[edge.to] = edge.choiceId;
              routeQueue.add(edge.to);
              if (edge.to == entry) break;
            }
          }
          if (!visited.contains(entry)) {
            throw StateError('SCC cycle could not be reconstructed');
          }
          final reversed = <String>[];
          var step = entry;
          while (step != firstEdge.to) {
            reversed.add(viaChoice[step]!);
            step = parent[step]!;
          }
          cycleChoices.addAll(reversed.reversed);
        }
        final repeated = queue[entry].fork();
        for (var i = 0; i < cycleChoices.length; i++) {
          final result = repeated.apply(
            actionId: 'cycle_repeat_' + (i + 1).toString(),
            choiceId: cycleChoices[i],
            expectedRevision: repeated.state.revision,
          );
          if (!result.applied) {
            throw StateError('Recorded SCC cycle was not executable');
          }
        }
        if (signature.of(repeated) != stateKeys[entry]) {
          throw StateError('Recorded SCC cycle changed causal state');
        }
        cycles.add(CampaignCausalCycle._(
          sceneId: queue[entry].state.sceneId,
          stateHash: queue[entry].state.stateHash,
          entryEvents: checkedEvents(queue[entry]),
          cycleChoiceIds: List<String>.unmodifiable(cycleChoices),
          events: checkedEvents(repeated),
        ));
      }
    }

    final unprovenTerminals = requiredTerminals
        .difference(terminalWitnesses.keys.toSet()).toList()..sort();
    final unprovenChoices = required
        .difference(choiceWitnesses.keys.toSet()).toList()..sort();

    // A found trap is a real counterexample even if the search was bounded.
    // Missing endings and choices can ONLY be declared impossible after the
    // state space was fully explored. Inconclusive is distinct from blocked.
    final status = trapCount > 0 || cycleCount > 0 ||
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
      cycles: List<CampaignCausalCycle>.unmodifiable(cycles),
      cycleCount: cycleCount,
      unprovenTerminalIds: List<String>.unmodifiable(unprovenTerminals),
      unprovenRequiredChoiceIds:
          List<String>.unmodifiable(unprovenChoices),
    );
  }
}
