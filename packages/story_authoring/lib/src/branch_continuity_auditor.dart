import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// M2h7b. Formal state continuity of a PRIVATE GAME, not book-world truth.
/// The existing StoryPlan + story_core are still the only rule executor.
enum ContinuityLedgerKind { promise, item, npcKnowledge }

class BranchContinuityRule {
  BranchContinuityRule({
    required this.id,
    required this.sourceFingerprint,
    required this.kind,
    required this.subjectId,
    required this.resourceId,
    required this.sourceEventId,
    required this.stateFlag,
    required this.grantDecisionId,
    required List<String> protectedDecisionIds,
    List<String> protectedSituationIds = const [],
    List<String> refusalDecisionIds = const [],
    List<String> revokeDecisionIds = const [],
    this.requiresFlagAtGrant,
    required this.reviewedAsGameFiction,
  })  : protectedDecisionIds = List.unmodifiable(protectedDecisionIds),
        protectedSituationIds = List.unmodifiable(protectedSituationIds),
        refusalDecisionIds = List.unmodifiable(refusalDecisionIds),
        revokeDecisionIds = List.unmodifiable(revokeDecisionIds);

  final String id, sourceFingerprint, subjectId, resourceId, sourceEventId;
  final ContinuityLedgerKind kind;
  final String stateFlag, grantDecisionId;
  final List<String> protectedDecisionIds, protectedSituationIds;
  final List<String> refusalDecisionIds, revokeDecisionIds;

  /// For transfers: require current holder's flag at the granting choice.
  final String? requiresFlagAtGrant;
  final bool reviewedAsGameFiction;
}

class BranchContinuityCounterexample {
  BranchContinuityCounterexample({
    required this.code,
    required this.ruleId,
    required this.sceneId,
    required this.decisionId,
    required List<String> pathChoiceIds,
  }) : pathChoiceIds = List.unmodifiable(pathChoiceIds);

  final String code, ruleId, sceneId, decisionId;
  final List<String> pathChoiceIds;

  Map<String, Object> toJson() => {
    'code': code, 'rule_id': ruleId, 'scene_id': sceneId,
    'decision_id': decisionId, 'path_choice_ids': pathChoiceIds,
  };
}

class BranchContinuityReport {
  BranchContinuityReport({
    required this.exploredStates,
    required List<BranchContinuityCounterexample> counterexamples,
  }) : counterexamples = List.unmodifiable(counterexamples);

  final int exploredStates;
  final List<BranchContinuityCounterexample> counterexamples;
  bool get passedFormalStateAudit => counterexamples.isEmpty;

  /// A replay-safe flag does not prove an AI's interpretation or an NPC's ID.
  bool get verifiesBookMeaning => false;
  bool get verifiesCharacterIdentity => false;
  bool get verifiesWorldChronology => false;
  bool get canPublishCanonicalRpg => false;

  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_branch_world_continuity_m2h7b_v1',
    'status': 'PRIVATE_GAME_STATE_ONLY',
    'explored_states': exploredStates,
    'formal_violations': counterexamples.length,
    'book_meaning_verified': false,
    'npc_identity_verified': false,
    'chronology_verified': false,
    'ready_for_canon': false,
    'counterexamples': [for (final item in counterexamples) item.toJson()],
  };
}

class _LedgerNode {
  const _LedgerNode(this.sceneId, this.flags, this.refusals, this.path);
  final String sceneId;
  final int flags, refusals;
  final List<String> path;
}

/// Replays all reachable flag states with refusal history and returns short
/// counterexample choice paths. This cannot change the scenario or saves.
class BranchContinuityAuditor {
  const BranchContinuityAuditor._();
  static const maxRules = 16;
  static const maxStates = 2500;
  static final RegExp _safeId = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  static BranchContinuityReport audit({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required List<BranchContinuityRule> rules,
    bool expanded = false,
  }) {
    if (index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        plan.title != book.title ||
        !book.analysisComplete ||
        rules.isEmpty || rules.length > (expanded ? 32 : maxRules) ||
        !plan.validate(book, expanded: expanded).isStructurallySound) {
      throw const FormatException('Непроверенный план или чужая редакция.');
    }
    final events = {for (final e in book.events) e.id: e};
    final scenes = {for (final s in plan.situations) s.id: s};
    final decisions = <String, StoryDecision>{
      for (final s in plan.situations)
        for (final d in s.decisions) d.id: d,
    };
    final sortedFlags = plan.flags.toList()..sort();
    final bits = <String, int>{
      for (var i = 0; i < sortedFlags.length; i++) sortedFlags[i]: 1 << i,
    };
    int mask(Iterable<String> flags) =>
        flags.fold<int>(0, (v, f) => v | bits[f]!);
    bool active(int state, String flag) => (state & bits[flag]!) != 0;

    final usedIds = <String>{};
    final usedFlags = <String>{};
    final ownership = <String>{};
    for (final rule in rules) {
      if (!_safeId.hasMatch(rule.id) || !usedIds.add(rule.id) ||
          !_safeId.hasMatch(rule.subjectId) ||
          !_safeId.hasMatch(rule.resourceId) ||
          rule.sourceFingerprint != index.sourceFingerprint ||
          !rule.reviewedAsGameFiction ||
          !bits.containsKey(rule.stateFlag) ||
          !usedFlags.add(rule.stateFlag) ||
          rule.protectedDecisionIds.isEmpty ||
          rule.protectedDecisionIds.length > 32 ||
          rule.protectedSituationIds.length > 32 ||
          rule.refusalDecisionIds.length > 16 ||
          rule.revokeDecisionIds.length > 16 ||
          rule.protectedDecisionIds.toSet().length !=
              rule.protectedDecisionIds.length ||
          rule.protectedSituationIds.toSet().length !=
              rule.protectedSituationIds.length ||
          rule.refusalDecisionIds.toSet().length !=
              rule.refusalDecisionIds.length ||
          rule.revokeDecisionIds.toSet().length !=
              rule.revokeDecisionIds.length ||
          rule.protectedDecisionIds.contains(rule.grantDecisionId) ||
          rule.refusalDecisionIds.contains(rule.grantDecisionId) ||
          rule.revokeDecisionIds.contains(rule.grantDecisionId) ||
          (rule.requiresFlagAtGrant != null &&
              (rule.requiresFlagAtGrant == rule.stateFlag ||
               !bits.containsKey(rule.requiresFlagAtGrant)))) {
        throw const FormatException('Некорректный учёт ресурсов и знаний.');
      }
      if (rule.kind == ContinuityLedgerKind.item &&
          !ownership.add(rule.resourceId + '|' + rule.subjectId)) {
        throw const FormatException('Повторный владелец одного предмета.');
      }
      final event = events[rule.sourceEventId];
      if (event == null) {
        throw const FormatException('Правило ссылается на чужое событие.');
      }
      event.source.validate(index);
      final grant = decisions[rule.grantDecisionId];
      if (grant == null ||
          grant.sourceEventId != rule.sourceEventId ||
          !grant.adds.contains(rule.stateFlag) ||
          plan.initialFlags.contains(rule.stateFlag) ||
          decisions.values.any((d) =>
              d.id != rule.grantDecisionId &&
              d.adds.contains(rule.stateFlag))) {
        throw const FormatException('Состояние создаёт неверное решение.');
      }
      for (final id in rule.protectedDecisionIds) {
        if (!decisions.containsKey(id)) {
          throw const FormatException('Отсутствует защищённое действие.');
        }
      }
      for (final id in rule.protectedSituationIds) {
        if (!scenes.containsKey(id)) {
          throw const FormatException('Отсутствует защищённая сцена.');
        }
      }
      for (final id in rule.refusalDecisionIds) {
        if (!decisions.containsKey(id) ||
            decisions[id]!.adds.contains(rule.stateFlag)) {
          throw const FormatException('Отказ создаёт обязательство.');
        }
      }
      // Any item loss or promise revocation must be declared explicitly.
      if (decisions.values.any((d) =>
          d.removes.contains(rule.stateFlag) &&
          !rule.revokeDecisionIds.contains(d.id))) {
        throw const FormatException('Ресурс теряется без проверенного '
            'действия передачи или утраты.');
      }
      for (final id in rule.revokeDecisionIds) {
        if (!decisions.containsKey(id) ||
            !decisions[id]!.removes.contains(rule.stateFlag)) {
          throw const FormatException('Утрата не удаляет ресурс.');
        }
      }
    }

    // Ledger checks inspect resource/owner flags outside ordinary choice
    // conditions. Retain them for ALL reachable scenes; never treat a
    // persistent ownership difference as irrelevant to the proof.
    final ledgerReads = <String>{
      for (final rule in rules) rule.stateFlag,
      for (final rule in rules)
        if (rule.requiresFlagAtGrant != null) rule.requiresFlagAtGrant!,
    };
    final proof = expanded ? plan.futureFlagLiveness(
      additionalReadsByScene: {
        for (final scene in plan.situations) scene.id: ledgerReads,
      },
    ) : null;
    final liveMasks = expanded ? {
      for (final scene in plan.situations)
        scene.id: proof!.bitMask(scene.id, bits),
    } : const <String, int>{};
    String stateKey(String scene, int flags, int refusals) =>
        scene + '|' + (expanded
          ? (flags & liveMasks[scene]!)
          : flags).toString() + '|' + refusals.toString();
    final queue = <_LedgerNode>[
      _LedgerNode(plan.entrySituationId, mask(plan.initialFlags), 0, const []),
    ];
    final discovered = <String>{
      stateKey(plan.entrySituationId, mask(plan.initialFlags), 0),
    };
    final visited = <String>{};
    final problems = <BranchContinuityCounterexample>[];
    final dedup = <String>{};

    void report(String code, BranchContinuityRule rule, _LedgerNode node,
        String decision, List<String> path) {
      if (!dedup.add(code + '|' + rule.id) || problems.length >= 32) return;
      problems.add(BranchContinuityCounterexample(
        code: code, ruleId: rule.id, sceneId: node.sceneId,
        decisionId: decision, pathChoiceIds: path,
      ));
    }

    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (queue.length > (expanded ? 8000 : maxStates)) {
        throw const FormatException('Слишком много состояний игрового мира.');
      }
      final node = queue[cursor];
      final key = stateKey(node.sceneId, node.flags, node.refusals);
      if (!visited.add(key)) continue;
      final scene = scenes[node.sceneId]!;
      for (var i = 0; i < rules.length; i++) {
        final rule = rules[i];
        if (rule.protectedSituationIds.contains(node.sceneId) &&
            !active(node.flags, rule.stateFlag)) {
          report('PREMATURE_SCENE', rule, node, '', node.path);
        }
        if ((node.refusals & (1 << i)) != 0 &&
            active(node.flags, rule.stateFlag)) {
          report('RESOURCE_AFTER_REFUSAL', rule, node, '', node.path);
        }
      }
      if (scene.terminal) continue;

      for (final choice in scene.decisions) {
        if ((node.flags & mask(choice.requires)) != mask(choice.requires) ||
            (node.flags & mask(choice.forbids)) != 0) continue;

        final path = [...node.path, choice.id];
        var refusals = node.refusals;
        for (var i = 0; i < rules.length; i++) {
          final rule = rules[i];
          final held = active(node.flags, rule.stateFlag);
          if (rule.protectedDecisionIds.contains(choice.id) && !held) {
            report('USE_WITHOUT_GRANT', rule, node, choice.id, path);
          }
          if (rule.grantDecisionId == choice.id &&
              (node.refusals & (1 << i)) != 0) {
            report('GRANT_AFTER_REFUSAL', rule, node, choice.id, path);
          }
          if (rule.grantDecisionId == choice.id &&
              rule.requiresFlagAtGrant != null &&
              !active(node.flags, rule.requiresFlagAtGrant!)) {
            report('TRANSFER_WITHOUT_OWNER', rule, node, choice.id, path);
          }
          if (rule.refusalDecisionIds.contains(choice.id)) {
            if (held) {
              report('REFUSAL_WHILE_OWNED', rule, node, choice.id, path);
            }
            refusals |= 1 << i;
          }
        }
        final nextFlags = (node.flags | mask(choice.adds)) &
            ~mask(choice.removes);
        for (final rule in rules) {
          if (rule.kind != ContinuityLedgerKind.item ||
              !active(nextFlags, rule.stateFlag)) continue;
          for (final other in rules) {
            if (identical(other, rule) ||
                other.kind != ContinuityLedgerKind.item ||
                other.resourceId != rule.resourceId ||
                other.subjectId == rule.subjectId ||
                !active(nextFlags, other.stateFlag)) continue;
            report('MULTIPLE_ITEM_OWNERS', rule, node, choice.id, path);
          }
        }
        if (expanded
            ? discovered.add(stateKey(choice.nextSituationId,
                nextFlags, refusals))
            : true) {
          queue.add(_LedgerNode(
            choice.nextSituationId, nextFlags, refusals, path));
        }
      }
    }
    return BranchContinuityReport(
      exploredStates: visited.length, counterexamples: problems);
  }
}
