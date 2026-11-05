import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';

/// M2g3c: a LIMITED structural repair. It never invents source facts,
/// changes BookWorld/SQLite, or declares model assertions to be canon.
///
/// Only two changes are allowed:
/// - add existing, externally supplied preconditions to a choice;
/// - require an existing source-event knowledge flag before an action.
///
/// State ownership, item transfers, cause of events, dialogue and literary
/// meaning are NEVER guessed by this helper.
class StoryRepairChange {
  StoryRepairChange({
    required this.invariantId,
    required this.decisionId,
    required List<String> addedRequires,
    required List<String> addedForbids,
  }) : addedRequires = List.unmodifiable(addedRequires),
       addedForbids = List.unmodifiable(addedForbids);

  final String invariantId, decisionId;
  final List<String> addedRequires, addedForbids;
}

class StoryRepairResult {
  StoryRepairResult({
    required this.draft,
    required this.before,
    required this.after,
    required List<StoryRepairChange> appliedChanges,
    required List<String> blockers,
  }) : appliedChanges = List.unmodifiable(appliedChanges),
       blockers = List.unmodifiable(blockers);

  /// This is always a proposed DRAFT, not an executable .bworld.
  final StoryPlan draft;
  final StoryCausalAudit before, after;
  final List<StoryRepairChange> appliedChanges;
  final List<String> blockers;
  bool get passedFormalContracts =>
      blockers.isEmpty && after.passedFormalContracts;
  bool get isSemanticallyAccepted => false;
  bool get readyToPlay => false;
}

class StoryPlanBoundedRepair {
  const StoryPlanBoundedRepair._();

  static StoryDecision _tighten(StoryDecision original,
      List<String> extraRequired, List<String> extraForbidden) {
    final requires = [
      ...original.requires,
      ...extraRequired.where((f) => !original.requires.contains(f)),
    ];
    final forbids = [
      ...original.forbids,
      ...extraForbidden.where((f) => !original.forbids.contains(f)),
    ];
    if (requires.toSet().intersection(forbids.toSet()).isNotEmpty) {
      throw const FormatException(
          'Исправление противоречит условиям исходного действия.');
    }
    return StoryDecision(
      id: original.id,
      intent: original.intent,
      nextSituationId: original.nextSituationId,
      sourceEventId: original.sourceEventId,
      route: original.route,
      requires: requires,
      forbids: forbids,
      adds: original.adds,
      removes: original.removes,
    );
  }

  static StoryPlan _replace(StoryPlan source,
      String choiceId, StoryDecision replacement) {
    return StoryPlan(
      sourceFingerprint: source.sourceFingerprint,
      title: source.title,
      entrySituationId: source.entrySituationId,
      flags: source.flags,
      initialFlags: source.initialFlags,
      situations: [
        for (final situation in source.situations)
          if (!situation.decisions.any((d) => d.id == choiceId))
            situation
          else
            StorySituation(
              id: situation.id,
              goal: situation.goal,
              conflict: situation.conflict,
              chapterIndex: situation.chapterIndex,
              sourceEventId: situation.sourceEventId,
              route: situation.route,
              terminal: situation.terminal,
              decisions: [
                for (final decision in situation.decisions)
                  if (decision.id == choiceId) replacement else decision,
              ],
            ),
      ],
    );
  }

  /// Reject a "repair" that disables the choice forever, even if the
  /// surrounding scene and two endings remain structurally reachable.
  static bool _decisionRemainsAvailable(StoryPlan plan, String choiceId) {
    final scenes = {for (final s in plan.situations) s.id: s};
    final flags = plan.flags.toList()..sort();
    final bitByFlag = <String, int>{
      for (var i = 0; i < flags.length; i++) flags[i]: 1 << i,
    };
    int mask(List<String> set) =>
        set.fold(0, (n, flag) => n | bitByFlag[flag]!);
    final queue = <(String, int)>[
      (plan.entrySituationId, mask(plan.initialFlags)),
    ];
    final seen = <String>{};
    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (queue.length > 2500) return false;
      final node = queue[cursor];
      if (!seen.add(node.$1 + ':' + node.$2.toString())) continue;
      for (final decision in scenes[node.$1]!.decisions) {
        if ((node.$2 & mask(decision.requires)) !=
                mask(decision.requires) ||
            (node.$2 & mask(decision.forbids)) != 0) continue;
        if (decision.id == choiceId) return true;
        final after = (node.$2 | mask(decision.adds)) &
            ~mask(decision.removes);
        queue.add((decision.nextSituationId, after));
      }
    }
    return false;
  }

  /// At most three local patches. Each patch must:
  /// 1. make a previously unsafe choice unavailable in that state;
  /// 2. keep all situations and both endings reachable;
  /// 3. reduce the number of distinct formal violations.
  /// If any rule cannot be repaired without damaging the graph, return the
  /// last valid DRAFT and explain the blocker; never force a "success".
  static StoryRepairResult attempt({
    required NarrativeBookModel book,
    required StoryPlan plan,
    required StoryCausalContract contract,
    int maxPatches = 3,
  }) {
    if (maxPatches < 1 || maxPatches > 3) {
      throw const FormatException('Допустимо от одного до трёх исправлений.');
    }
    final first = StoryPlanCausalAuditor.audit(
        plan: plan, book: book, contract: contract);
    var current = plan;
    var previous = first;
    final changes = <StoryRepairChange>[];
    final blockers = <String>[];
    final decisionRules = {
      for (final rule in contract.decisionInvariants)
        rule.id: rule,
    };
    final knowledgeRules = {
      for (final rule in contract.knowledgeGates)
        rule.id: rule,
    };
    for (var iteration = 0; iteration < maxPatches; iteration++) {
      if (previous.passedFormalContracts) break;
      // BFS returns the shortest known witness for each invariant; prioritize
      // violations that permit a SAFE precondition-only change.
      StoryCausalCounterexample? selected;
      for (final issue in previous.counterexamples) {
        if (issue.code == 'CAUSAL_PRECONDITION' &&
                decisionRules.containsKey(issue.invariantId) ||
            issue.code == 'PREMATURE_REVEAL' &&
                knowledgeRules.containsKey(issue.invariantId)) {
          selected = issue;
          break;
        }
      }
      if (selected == null) {
        blockers.add('Оставшиеся противоречия требуют решения редактора '
            '(например, передача предмета двум владельцам).');
        break;
      }
      final issue = selected;
      final rule = decisionRules[issue.invariantId];
      final gate = knowledgeRules[issue.invariantId];
      final wantedRequired = rule != null
          ? rule.requires : [gate!.knowledgeFlag];
      final wantedForbidden = rule?.forbids ?? const <String>[];
      StoryDecision? original;
      for (final scene in current.situations) {
        for (final decision in scene.decisions) {
          if (decision.id == issue.decisionId) original = decision;
        }
      }
      if (original == null) {
        blockers.add('Исходное решение больше не существует.');
        break;
      }
      final missingRequired = wantedRequired.where(
          (f) => !original!.requires.contains(f)).toList();
      final missingForbidden = wantedForbidden.where(
          (f) => !original!.forbids.contains(f)).toList();
      if (missingRequired.isEmpty && missingForbidden.isEmpty) {
        blockers.add('Повторное условие не устраняет найденную проблему.');
        break;
      }
      try {
        final candidate = _replace(current, original.id,
            _tighten(original, missingRequired, missingForbidden));
        if (!_decisionRemainsAvailable(candidate, original.id)) {
          blockers.add('Правка полностью запрещает действие и удаляет '
              'игровую возможность; нужна смысловая проверка.');
          break;
        }
        final checked = StoryPlanCausalAuditor.audit(
            plan: candidate, book: book, contract: contract);
        if (checked.counterexamples.length >=
            previous.counterexamples.length) {
          blockers.add('Предложенное исправление не уменьшило '
              'число причинных противоречий.');
          break;
        }
        current = candidate;
        previous = checked;
        changes.add(StoryRepairChange(
          invariantId: issue.invariantId,
          decisionId: issue.decisionId,
          addedRequires: missingRequired,
          addedForbids: missingForbidden,
        ));
      } on FormatException {
        blockers.add('Исправление нарушает достижимость сцен, '
            'развязок или исходные ограничения; нужна проверка редактора.');
        break;
      }
    }
    if (!previous.passedFormalContracts && blockers.isEmpty) {
      blockers.add('Достигнут предел локальных исправлений '
          'без полного устранения ошибок.');
    }
    return StoryRepairResult(
      draft: current,
      before: first,
      after: previous,
      appliedChanges: changes,
      blockers: blockers,
    );
  }
}
