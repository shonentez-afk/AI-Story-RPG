import 'narrative_book_model.dart';
import 'story_plan.dart';

/// M2g3c: *externally specified* logical invariants of a draft StoryPlan.
/// They are NOT extracted truths about the source. Reviewing the meaning of
/// a rule remains a separate semantic acceptance step.
class StoryDecisionInvariant {
  StoryDecisionInvariant({
    required this.id,
    required this.decisionId,
    List<String> requires = const [],
    List<String> forbids = const [],
  }) : requires = List.unmodifiable(requires),
       forbids = List.unmodifiable(forbids);

  final String id, decisionId;
  final List<String> requires, forbids;
}

/// For a source event, the only allowed introduction of a knowledge flag
/// must be a specific decision referencing that *event ID*. Source chapter
/// position alone grants nobody knowledge.
class StoryEventKnowledgeGate {
  StoryEventKnowledgeGate({
    required this.id,
    required this.revealEventId,
    required this.grantDecisionId,
    required this.knowledgeFlag,
    required List<String> protectedDecisionIds,
  }) : protectedDecisionIds = List.unmodifiable(protectedDecisionIds);

  final String id, revealEventId, grantDecisionId, knowledgeFlag;
  final List<String> protectedDecisionIds;
}

/// E.g. an item cannot simultaneously be carried by two actors.
/// Flags are typed game-state propositions, never free-form model commands.
class StoryExclusiveFlags {
  StoryExclusiveFlags({
    required this.id,
    required List<String> flags,
  }) : flags = List.unmodifiable(flags);

  final String id;
  final List<String> flags;
}

class StoryCausalContract {
  StoryCausalContract({
    List<StoryDecisionInvariant> decisionInvariants = const [],
    List<StoryEventKnowledgeGate> knowledgeGates = const [],
    List<StoryExclusiveFlags> exclusiveGroups = const [],
  }) : decisionInvariants = List.unmodifiable(decisionInvariants),
       knowledgeGates = List.unmodifiable(knowledgeGates),
       exclusiveGroups = List.unmodifiable(exclusiveGroups);

  final List<StoryDecisionInvariant> decisionInvariants;
  final List<StoryEventKnowledgeGate> knowledgeGates;
  final List<StoryExclusiveFlags> exclusiveGroups;
}

class StoryCausalCounterexample {
  StoryCausalCounterexample({
    required this.code,
    required this.invariantId,
    required this.situationId,
    required this.decisionId,
    required List<String> pathChoiceIds,
    required List<String> activeFlagsBefore,
  }) : pathChoiceIds = List.unmodifiable(pathChoiceIds),
       activeFlagsBefore = List.unmodifiable(activeFlagsBefore);

  final String code, invariantId, situationId, decisionId;
  /// Shortest known path from the entry to the invalid transition.
  final List<String> pathChoiceIds;
  final List<String> activeFlagsBefore;

  Map<String, Object> toJson() => {
    'code': code, 'invariant_id': invariantId,
    'situation_id': situationId, 'decision_id': decisionId,
    'path_choice_ids': pathChoiceIds,
    'active_flags_before': activeFlagsBefore,
  };
}

class StoryCausalAudit {
  StoryCausalAudit({
    required this.exploredStates,
    required List<StoryCausalCounterexample> counterexamples,
    required List<String> warnings,
  }) : counterexamples = List.unmodifiable(counterexamples),
       warnings = List.unmodifiable(warnings);

  final int exploredStates;
  final List<StoryCausalCounterexample> counterexamples;
  final List<String> warnings;

  bool get passedFormalContracts => counterexamples.isEmpty;
  bool get meaningVerified => false;
  bool get isPlayable => false;
  bool get canPublish => false;
}

class _AuditNode {
  const _AuditNode(this.scene, this.bits, this.path);
  final String scene;
  final int bits;
  final List<String> path;
}

/// A bounded BFS finds reproducible SHORTEST counterexample traces.
/// It checks game-state rules, NOT literary truth, actor identity or whether
/// the LLM correctly interpreted the book's original events.
class StoryPlanCausalAuditor {
  const StoryPlanCausalAuditor._();

  static StoryCausalAudit audit({
    required StoryPlan plan,
    required NarrativeBookModel book,
    required StoryCausalContract contract,
    bool expanded = false,
  }) {
    final basic = plan.validate(book, expanded: expanded);
    if (!basic.isStructurallySound) {
      throw const FormatException('StoryPlan не прошёл проверку состояний.');
    }
    final scenes = {for (final s in plan.situations) s.id: s};
    final decisions = <String, StoryDecision>{};
    for (final s in plan.situations) {
      for (final choice in s.decisions) {
        decisions[choice.id] = choice;
      }
    }
    final declared = plan.flags.toSet();
    final ids = <String>{};
    void checkId(String id) {
      if (id.trim().isEmpty || !ids.add(id)) {
        throw const FormatException('Дублированное правило причинности.');
      }
    }
    void checkFlags(List<String> flags) {
      if (flags.length > 32 || flags.length != flags.toSet().length ||
          flags.any((flag) => !declared.contains(flag))) {
        throw const FormatException('Правило использует неизвестное состояние.');
      }
    }
    for (final rule in contract.decisionInvariants) {
      checkId(rule.id);
      if (!decisions.containsKey(rule.decisionId)) {
        throw const FormatException('Правило ссылается на чужой выбор.');
      }
      checkFlags(rule.requires);
      checkFlags(rule.forbids);
      if (rule.requires.toSet().intersection(rule.forbids.toSet()).isNotEmpty) {
        throw const FormatException('Противоречивое причинное правило.');
      }
    }
    final eventIds = {for (final e in book.events) e.id};
    for (final gate in contract.knowledgeGates) {
      checkId(gate.id);
      if (!eventIds.contains(gate.revealEventId) ||
          !declared.contains(gate.knowledgeFlag) ||
          !decisions.containsKey(gate.grantDecisionId) ||
          gate.protectedDecisionIds.isEmpty ||
          gate.protectedDecisionIds.length !=
              gate.protectedDecisionIds.toSet().length ||
          gate.protectedDecisionIds.contains(gate.grantDecisionId) ||
          gate.protectedDecisionIds.any((id) => !decisions.containsKey(id))) {
        throw const FormatException('Неверное правило раскрытия знания.');
      }
      final grant = decisions[gate.grantDecisionId]!;
      if (grant.sourceEventId != gate.revealEventId ||
          !grant.adds.contains(gate.knowledgeFlag) ||
          decisions.values.any((choice) =>
              choice.id != gate.grantDecisionId &&
              choice.adds.contains(gate.knowledgeFlag)) ||
          plan.initialFlags.contains(gate.knowledgeFlag)) {
        throw const FormatException(
            'Знание должно открываться только указанным событием.');
      }
    }
    for (final group in contract.exclusiveGroups) {
      checkId(group.id);
      if (group.flags.length < 2) {
        throw const FormatException('В группе исключения мало состояний.');
      }
      checkFlags(group.flags);
    }

    final sortedFlags = plan.flags.toList()..sort();
    final bits = <String, int>{
      for (var i = 0; i < sortedFlags.length; i++)
        sortedFlags[i]: 1 << i,
    };
    int mask(Iterable<String> flags) =>
        flags.fold(0, (result, f) => result | bits[f]!);
    List<String> active(int state) => [
      for (final f in sortedFlags)
        if ((state & bits[f]!) != 0) f,
    ];
    final warnings = <String>[];
    final relevantFlags = <String>{
      for (final choice in decisions.values) ...choice.requires,
      for (final choice in decisions.values) ...choice.forbids,
      for (final rule in contract.decisionInvariants) ...rule.requires,
      for (final rule in contract.decisionInvariants) ...rule.forbids,
      for (final gate in contract.knowledgeGates) gate.knowledgeFlag,
      for (final group in contract.exclusiveGroups) ...group.flags,
    };
    for (final scene in plan.situations) {
      for (var i = 0; i < scene.decisions.length; i++) {
        for (var j = i + 1; j < scene.decisions.length; j++) {
          final a = scene.decisions[i];
          final b = scene.decisions[j];
          final change = {...a.adds, ...a.removes, ...b.adds, ...b.removes};
          if (a.nextSituationId == b.nextSituationId &&
              change.intersection(relevantFlags).isEmpty) {
            warnings.add('В ситуации ' + scene.id +
                ' возможны косметические варианты без разных последствий.');
          }
        }
      }
    }

    final queue = <_AuditNode>[
      _AuditNode(plan.entrySituationId, mask(plan.initialFlags), const []),
    ];
    final visited = <String>{
      plan.entrySituationId + ':' + mask(plan.initialFlags).toString(),
    };
    final violations = <StoryCausalCounterexample>[];
    final recorded = <String>{};

    void report(String code, String ruleId, _AuditNode current,
        String actionId, int before, List<String> path) {
      if (!recorded.add(ruleId + ':' + code) ||
          violations.length >= 32) return;
      violations.add(StoryCausalCounterexample(
        code: code, invariantId: ruleId,
        situationId: current.scene, decisionId: actionId,
        pathChoiceIds: path,
        activeFlagsBefore: active(before),
      ));
    }

    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (queue.length > (expanded ? 8000 : maxExploredStates)) {
        throw const FormatException('Слишком много проверяемых состояний.');
      }
      final node = queue[cursor];
      final scene = scenes[node.scene]!;
      if (scene.terminal) continue;
      for (final decision in scene.decisions) {
        if ((node.bits & mask(decision.requires)) !=
                mask(decision.requires) ||
            (node.bits & mask(decision.forbids)) != 0) continue;
        final path = [...node.path, decision.id];
        for (final rule in contract.decisionInvariants) {
          if (rule.decisionId == decision.id &&
              ((node.bits & mask(rule.requires)) != mask(rule.requires) ||
               (node.bits & mask(rule.forbids)) != 0)) {
            report('CAUSAL_PRECONDITION', rule.id, node,
                decision.id, node.bits, path);
          }
        }
        for (final gate in contract.knowledgeGates) {
          if (gate.protectedDecisionIds.contains(decision.id) &&
              (node.bits & bits[gate.knowledgeFlag]!) == 0) {
            report('PREMATURE_REVEAL', gate.id, node,
                decision.id, node.bits, path);
          }
        }
        final next = (node.bits | mask(decision.adds)) &
            ~mask(decision.removes);
        for (final group in contract.exclusiveGroups) {
          final activeCount = group.flags.where(
              (flag) => (next & bits[flag]!) != 0).length;
          if (activeCount > 1) {
            report('EXCLUSIVE_STATE_COLLISION', group.id, node,
                decision.id, node.bits, path);
          }
        }
        final target = decision.nextSituationId + ':' + next.toString();
        if (visited.add(target)) {
          queue.add(_AuditNode(decision.nextSituationId, next, path));
        }
      }
    }
    return StoryCausalAudit(
      exploredStates: visited.length,
      counterexamples: violations,
      warnings: warnings,
    );
  }

  static const maxExploredStates = 2500;
}
