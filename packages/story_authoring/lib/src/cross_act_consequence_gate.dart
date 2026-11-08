import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';

/// M2h5: an explicit, REVIEWED AS FICTION dependency. It is NOT proof that
/// the novelist wrote that dependency or that a particular NPC knows it.
///
/// Cross-act decisions must have real consequences: a later choice is
/// available only when a particular EARLIER outcome did or did not occur.
/// Nothing is inferred automatically from page order or GLM suggestions.
enum CrossActPriorOutcome { original, alternative }
enum CrossActRuleMode { requiresPriorOutcome, forbidsPriorOutcome }

class CrossActConsequenceRule {
  const CrossActConsequenceRule({
    required this.id,
    required this.earlierActId,
    required this.laterActId,
    required this.earlierSourceEventId,
    required this.laterSourceEventId,
    required this.laterDecisionId,
    required this.priorOutcome,
    required this.mode,
    required this.reviewedAsGameFiction,
    required this.privateReviewReason,
  });

  final String id, earlierActId, laterActId;
  final String earlierSourceEventId, laterSourceEventId, laterDecisionId;
  final CrossActPriorOutcome priorOutcome;
  final CrossActRuleMode mode;

  /// Must represent a conscious editorial action, NEVER an LLM response
  /// being silently treated as accepted or as a source-backed fact.
  final bool reviewedAsGameFiction;
  final String privateReviewReason;
}

class CrossActRuleImpact {
  const CrossActRuleImpact({
    required this.ruleId,
    required this.allowedEarlierOutcomeStates,
    required this.blockedOppositeOutcomeStates,
  });

  final String ruleId;
  final int allowedEarlierOutcomeStates, blockedOppositeOutcomeStates;

  bool get changesLaterOptions =>
      allowedEarlierOutcomeStates > 0 && blockedOppositeOutcomeStates > 0;
}

class CrossActContinuityDraft {
  CrossActContinuityDraft._({
    required this.plan,
    required this.audit,
    required this.coverage,
    required List<CrossActRuleImpact> impacts,
  }) : impacts = List.unmodifiable(impacts);

  final StoryPlan plan;
  final StoryCausalAudit audit;
  final BookwideStoryCoverage coverage;
  final List<CrossActRuleImpact> impacts;

  bool get hasEnforcedContinuity =>
      impacts.isNotEmpty && impacts.every((x) => x.changesLaterOptions) &&
      audit.counterexamples.isEmpty;
  bool get hasVerifiedLiteraryCausality => false;
  bool get hasVerifiedNPCInformation => false;
  bool get hasVerifiedWorldChronology => false;
  bool get readyForBookWorld => false;
  bool get fullBookReady => false;

  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_cross_act_continuity_m2h5_v1',
    'status': 'REVIEWED_GAME_FICTION_DRAFT_ONLY',
    'enforced_rules': impacts.length,
    'rules_affect_available_choices': hasEnforcedContinuity,
    'formal_violations': audit.counterexamples.length,
    'source_events_referenced': coverage.referencedEvents,
    'source_events_total': coverage.allEvents,
    'source_verified_literary_cause': false,
    'npc_knowledge_verified': false,
    'ready_for_install': false,
  };
}

/// Deliberately separate from the existing BookWorld compiler. The source
/// is re-checked on EVERY application and the game-state graph is fully
/// re-explored after adding the downstream decision prerequisites.
class CrossActConsequenceGate {
  const CrossActConsequenceGate._();
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _control =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  /// Apply one EXPLICITLY APPROVED fictional consequence to EVERY adjacent
  /// book act, not just act 1 -> 2. A later acceptance needs the previous
  /// original outcome; the refusal path remains playable. Crucially, these
  /// are GAME-FICTION rules, never inferred from text order or model output.
  ///
  /// The existing [apply] verifies exact source event IDs, chapter/act order,
  /// reachable original/alternative branches and actual changed availability
  /// for each boundary. No new engine, flags or separate save schema.
  static CrossActContinuityDraft applyReviewedActChain({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    required bool userConfirmedFictionalContinuity,
    bool expanded = false,
  }) {
    if (!userConfirmedFictionalContinuity || draft.parts.length < 2) {
      throw const FormatException(
          'Подтвердите вымышленную зависимость всех частей книги.');
    }
    return apply(
      index: index,
      book: book,
      bookMap: bookMap,
      draft: draft,
      expanded: expanded,
      rules: [
        for (var i = 1; i < draft.parts.length; i++)
          CrossActConsequenceRule(
            id: 'reviewed_bookwide_link_' + i.toString(),
            earlierActId: draft.parts[i - 1].actId,
            laterActId: draft.parts[i].actId,
            earlierSourceEventId: draft.parts[i - 1].outcomeEventId,
            laterSourceEventId: draft.parts[i].setupEventId,
            laterDecisionId: 'act_' + (i + 1).toString() + '_accept_offer',
            priorOutcome: CrossActPriorOutcome.original,
            mode: CrossActRuleMode.requiresPriorOutcome,
            reviewedAsGameFiction: true,
            privateReviewReason:
                'Пользователь подтвердил отдельное игровое допущение '
                'для перехода между актами ' + i.toString() + ' и ' +
                (i + 1).toString() + ': согласие со следующим условием '
                'требует первоначального исхода предыдущей части. '
                'Это не установленная причинность исходной книги.',
          ),
      ],
    );
  }

  static CrossActContinuityDraft apply({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    required List<CrossActConsequenceRule> rules,
    bool expanded = false,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        draft.plan.sourceFingerprint != book.sourceFingerprint ||
        draft.plan.title != book.title ||
        !draft.formalRulesPassed ||
        draft.parts.length < 2 ||
        rules.isEmpty || rules.length > (expanded ? 32 : 12)) {
      throw const FormatException(
          'Нужен проверенный многоактовый черновик этой редакции.');
    }
    final parts = {
      for (var i = 0; i < draft.parts.length; i++)
        draft.parts[i].actId: i,
    };
    if (parts.length != draft.parts.length) {
      throw const FormatException('Повторяющиеся части книги.');
    }
    final events = {for (final e in book.events) e.id: e};
    final scenes = {for (final s in draft.plan.situations) s.id: s};
    final decisions = <String, (String, StoryDecision)>{};
    for (final scene in draft.plan.situations) {
      for (final choice in scene.decisions) {
        decisions[choice.id] = (scene.id, choice);
      }
    }
    if (!draft.plan.validate(book, expanded: expanded).isStructurallySound) {
      throw const FormatException(
          'Исходный план имеет нарушения игровых условий.');
    }
    final assigned = <String>{};
    final ruleIds = <String>{};
    final chosen = <String, (String, CrossActRuleMode)>{};

    for (final rule in rules) {
      if (!_id.hasMatch(rule.id) || !ruleIds.add(rule.id) ||
          !assigned.add(rule.laterDecisionId) ||
          !rule.reviewedAsGameFiction ||
          rule.privateReviewReason.trim().length < 20 ||
          rule.privateReviewReason.length > 400 ||
          _control.hasMatch(rule.privateReviewReason)) {
        throw const FormatException(
            'Причинное правило не прошло отдельное редакторское решение.');
      }
      final from = parts[rule.earlierActId];
      final to = parts[rule.laterActId];
      if (from == null || to == null || from >= to ||
          rule.earlierSourceEventId !=
              draft.parts[from].outcomeEventId ||
          rule.laterSourceEventId !=
              draft.parts[to].setupEventId) {
        throw const FormatException(
            'Свидетельства принадлежат другим частям или идут назад.');
      }
      final earlier = events[rule.earlierSourceEventId];
      final later = events[rule.laterSourceEventId];
      if (earlier == null || later == null ||
          earlier.narrativePosition >= later.narrativePosition ||
          bookMap.acts.where((a) =>
              a.id == rule.earlierActId &&
              a.events.any((e) => e.id == earlier.id)).length != 1 ||
          bookMap.acts.where((a) =>
              a.id == rule.laterActId &&
              a.events.any((e) => e.id == later.id)).length != 1) {
        throw const FormatException(
            'Нет подтверждения положений цитат в указанной книге.');
      }
      earlier.source.validate(index);
      later.source.validate(index);

      final target = decisions[rule.laterDecisionId];
      if (target == null ||
          target.$1 != draft.parts[to].entrySituationId ||
          scenes[target.$1]!.decisions.length < 2) {
        throw const FormatException(
            'Последствие должно менять именно выбор следующего акта.');
      }
      final previousFlag = 'act_' + (from + 1).toString() + '_' +
          (rule.priorOutcome == CrossActPriorOutcome.original
              ? 'original_outcome' : 'alternate_outcome');
      if (!draft.plan.flags.contains(previousFlag) ||
          target.$2.requires.contains(previousFlag) ||
          target.$2.forbids.contains(previousFlag)) {
        throw const FormatException('Состояние уже использовано в решении.');
      }
      chosen[rule.laterDecisionId] = (previousFlag, rule.mode);
    }

    // Explicit downstream effects must change availability, not merely
    // add a cosmetic memory flag. All other choices remain unchanged.
    final revisedScenes = [
      for (final scene in draft.plan.situations)
        StorySituation(
          id: scene.id, goal: scene.goal, conflict: scene.conflict,
          chapterIndex: scene.chapterIndex,
          sourceEventId: scene.sourceEventId,
          route: scene.route, terminal: scene.terminal,
          decisions: [
            for (final decision in scene.decisions)
              if (chosen.containsKey(decision.id))
                StoryDecision(
                  id: decision.id, intent: decision.intent,
                  nextSituationId: decision.nextSituationId,
                  sourceEventId: decision.sourceEventId,
                  route: decision.route,
                  requires: [
                    ...decision.requires,
                    if (chosen[decision.id]!.$2 ==
                        CrossActRuleMode.requiresPriorOutcome)
                      chosen[decision.id]!.$1,
                  ],
                  forbids: [
                    ...decision.forbids,
                    if (chosen[decision.id]!.$2 ==
                        CrossActRuleMode.forbidsPriorOutcome)
                      chosen[decision.id]!.$1,
                  ],
                  adds: decision.adds, removes: decision.removes,
                )
              else decision,
          ],
        ),
    ];
    final revised = StoryPlan(
      sourceFingerprint: draft.plan.sourceFingerprint,
      title: draft.plan.title,
      entrySituationId: draft.plan.entrySituationId,
      flags: draft.plan.flags,
      initialFlags: draft.plan.initialFlags,
      situations: revisedScenes,
    );
    final structure = revised.validate(book, expanded: expanded);
    if (!structure.isStructurallySound ||
        structure.terminalSituations != 2 ||
        !structure.branchChangesState) {
      throw const FormatException(
          'Поправки создали тупик или скрыли альтернативную концовку.');
    }
    final extra = <StoryDecisionInvariant>[
      for (final rule in rules)
        StoryDecisionInvariant(
          id: 'm2h5_' + rule.id,
          decisionId: rule.laterDecisionId,
          requires: rule.mode == CrossActRuleMode.requiresPriorOutcome
              ? [chosen[rule.laterDecisionId]!.$1] : [],
          forbids: rule.mode == CrossActRuleMode.forbidsPriorOutcome
              ? [chosen[rule.laterDecisionId]!.$1] : [],
        ),
    ];
    final contract = StoryCausalContract(
      decisionInvariants: [
        ...draft.causalContract.decisionInvariants, ...extra,
      ],
      knowledgeGates: draft.causalContract.knowledgeGates,
      exclusiveGroups: draft.causalContract.exclusiveGroups,
    );
    final audit = StoryPlanCausalAuditor.audit(
        plan: revised, book: book, contract: contract);
    if (audit.counterexamples.isNotEmpty) {
      throw const FormatException('Новые условия нарушили игровую причинность.');
    }

    final impacts = [
      for (final rule in rules)
        _checkRealImpact(revised,
            ruleId: rule.id,
            decisionId: rule.laterDecisionId,
            earlierActIndex: parts[rule.earlierActId]!,
            outcome: rule.priorOutcome,
            mode: rule.mode),
    ];
    if (impacts.any((x) => !x.changesLaterOptions)) {
      throw const FormatException(
          'Правило косметическое: оно не меняет доступные '
          'игроку решения в реальных прохождениях.');
    }
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: bookMap, book: book, story: revised);
    return CrossActContinuityDraft._(
      plan: revised, audit: audit, coverage: coverage, impacts: impacts);
  }

  static CrossActRuleImpact _checkRealImpact(
      StoryPlan plan, {
      required String ruleId,
      required String decisionId,
      required int earlierActIndex,
      required CrossActPriorOutcome outcome,
      required CrossActRuleMode mode,
  }) {
    final scenes = {for (final s in plan.situations) s.id: s};
    final sceneId = scenes.values
        .singleWhere((s) => s.decisions.any((d) => d.id == decisionId)).id;
    final sortedFlags = plan.flags.toList()..sort();
    final maskByFlag = <String, int>{
      for (var i = 0; i < sortedFlags.length; i++)
        sortedFlags[i]: 1 << i,
    };
    int mask(Iterable<String> flags) =>
        flags.fold<int>(0, (value, flag) => value | maskByFlag[flag]!);
    final earlier = 'act_' + (earlierActIndex + 1).toString() + '_';
    final prior = mask([earlier +
        (outcome == CrossActPriorOutcome.original
            ? 'original_outcome' : 'alternate_outcome')]);
    final opposite = mask([earlier +
        (outcome == CrossActPriorOutcome.original
            ? 'alternate_outcome' : 'original_outcome')]);
    final states = <(String, int)>[
      (plan.entrySituationId, mask(plan.initialFlags)),
    ];
    final seen = <String>{};
    var allowed = 0, blocked = 0;
    for (var i = 0; i < states.length; i++) {
      if (states.length > (expanded ? 8000 : 2500)) {
        throw const FormatException('Слишком много состояний для проверки.');
      }
      final state = states[i];
      final key = state.$1 + ':' + state.$2.toString();
      if (!seen.add(key)) continue;
      final scene = scenes[state.$1]!;
      if (scene.terminal) continue;
      if (scene.id == sceneId) {
        final decision = scene.decisions.singleWhere(
            (d) => d.id == decisionId);
        final enabled = (state.$2 & mask(decision.requires)) ==
                mask(decision.requires) &&
            (state.$2 & mask(decision.forbids)) == 0;
        final matching = (state.$2 & prior) != 0 &&
            (state.$2 & opposite) == 0;
        final opposing = (state.$2 & opposite) != 0 &&
            (state.$2 & prior) == 0;
        if (mode == CrossActRuleMode.requiresPriorOutcome) {
          if (matching && enabled) allowed++;
          if (opposing && !enabled) blocked++;
        } else {
          if (opposing && enabled) allowed++;
          if (matching && !enabled) blocked++;
        }
      }
      for (final d in scene.decisions) {
        if ((state.$2 & mask(d.requires)) != mask(d.requires) ||
            (state.$2 & mask(d.forbids)) != 0) continue;
        final next = (state.$2 | mask(d.adds)) & ~mask(d.removes);
        states.add((d.nextSituationId, next));
      }
    }
    return CrossActRuleImpact(
      ruleId: ruleId,
      allowedEarlierOutcomeStates: allowed,
      blockedOppositeOutcomeStates: blocked,
    );
  }
}
