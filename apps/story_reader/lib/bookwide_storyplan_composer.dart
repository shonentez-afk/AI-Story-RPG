import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';
import 'story_plan_dilemma_generator.dart';
import 'story_plan_quality_gate.dart';
import 'zai_story_dilemma_proposal.dart';

/// A documented GAME-FICTION transition. It does NOT assert world chronology,
/// that the original author wrote a causal link, or that any NPC knows facts.
class MultiActFictionalBridge {
  const MultiActFictionalBridge({
    required this.fromSituationId,
    required this.nextActEntryId,
    required this.outcomeFlag,
  });

  final String fromSituationId, nextActEntryId, outcomeFlag;
  bool get isSupportedByBookCausality => false;
  bool get isVerifiedWorldTime => false;
  bool get isProposedGameFiction => true;
}

/// An ACT is a separately source-locked, formally validated dilemma.
/// Both source anchors have to belong to ONE exact segment of the book map.
class MultiActDilemmaPart {
  MultiActDilemmaPart({
    required this.actId,
    required this.entrySituationId,
    required this.setupEventId,
    required this.outcomeEventId,
    required this.sourceChapter,
  });

  final String actId, entrySituationId, setupEventId, outcomeEventId;
  final int sourceChapter;
  bool get meaningIsCanon => false;
}

/// A multi-act, structurally executable graph, but a *NON-PUBLISHABLE DRAFT*.
/// The bridges are transparent game-fiction; source-text order is never
/// silently upgraded into world chronology or a proof of causation.
///
/// Do not install this graph through the BookWorld compiler until an
/// independent literary/causal review approves each source transition.
class MultiActStoryPlanDraft {
  MultiActStoryPlanDraft._({
    required this.plan,
    required this.causalContract,
    required this.formalAudit,
    required this.coverage,
    required List<MultiActDilemmaPart> parts,
    required List<MultiActFictionalBridge> fictionalBridges,
    required List<String> blockers,
  }) : parts = List.unmodifiable(parts),
       fictionalBridges = List.unmodifiable(fictionalBridges),
       blockers = List.unmodifiable(blockers);

  final StoryPlan plan;
  final StoryCausalContract causalContract;
  final StoryCausalAudit formalAudit;
  final BookwideStoryCoverage coverage;
  final List<MultiActDilemmaPart> parts;
  final List<MultiActFictionalBridge> fictionalBridges;
  final List<String> blockers;

  bool get hasFormalCounterexamples =>
      formalAudit.counterexamples.isNotEmpty;
  bool get formalRulesPassed =>
      !hasFormalCounterexamples && blockers.every(
          (text) => !text.startsWith('Ошибка формальной проверки'));
  bool get hasConfirmedLiteraryMeaning => false;
  bool get hasConfirmedWorldChronology => false;
  bool get hasConfirmedActorKnowledge => false;
  bool get hasSourceProvenCausalBridges => false;
  bool get isReadyToInstall => false;
  bool get isFullBookRpg => false;
  bool get canPublish => false;

  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_multiact_storyplan_m2h2_v1',
    'status': 'DRAFT_ONLY',
    'act_count': parts.length,
    'game_situations': plan.situations.length,
    'source_events_referenced': coverage.referencedEvents,
    'source_events_total': coverage.allEvents,
    'fictional_bridge_count': fictionalBridges.length,
    'formal_counterexamples': formalAudit.counterexamples.length,
    'bookwide_source_coverage': coverage.allDetectedEventsReferenced,
    'world_causality_verified': false,
    'literary_meaning_verified': false,
    'is_playable': false,
  };
}

/// M2h2: deterministic StoryPlan composition from independently reviewed
/// *proposals* tied to disjoint book ACT segments.
///
/// No additional Z.ai call happens here. Future bounded per-act GLM calls must
/// have their own exact excerpt preview and explicit user consent.
/// This class never writes .bworld, SQLite or a saved campaign.
class BookwideStoryPlanComposer {
  const BookwideStoryPlanComposer._();

  static const maxDraftActs = 12;

  // rich-v3 retains its 32-flag contract. Longer campaigns lease only
  // transient process flags; each act keeps durable outcome flags.
  static const rollingAccepted = 'campaign_accepted';
  static const rollingDeclined = 'campaign_declined';
  static const rollingDiscovered = 'campaign_discovered';
  static const rollingFlags = <String>[
    rollingAccepted, rollingDeclined, rollingDiscovered,
  ];

  static MultiActStoryPlanDraft compose({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required List<StoryDilemmaProposal> actProposals,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        bookMap.chapters != book.chapterCount ||
        bookMap.sourceEvents != book.events.length ||
        actProposals.length < 2 ||
        actProposals.length > maxDraftActs) {
      throw const FormatException(
          'Для многоактового черновика нужны 2–12 разных '
          'предложений, основанных на завершённом анализе одной книги.');
    }

    // Independently confirm the supplied act map still matches exact source.
    final anchored = [
      for (final act in bookMap.acts)
        for (final event in act.events) event,
    ];
    if (anchored.length != book.events.length) {
      throw const FormatException('Карта книги потеряла события.');
    }
    for (var i = 0; i < anchored.length; i++) {
      if (anchored[i].id != book.events[i].id) {
        throw const FormatException(
            'Порядок событий карты не соответствует книге.');
      }
      anchored[i].source.validate(index);
    }
    final sourceActById = <String, BookActSegment>{};
    final actOrder = <String, int>{};
    for (var i = 0; i < bookMap.acts.length; i++) {
      final act = bookMap.acts[i];
      for (final event in act.events) {
        if (sourceActById.containsKey(event.id)) {
          throw const FormatException(
              'Событие дважды привязано к разным частям книги.');
        }
        sourceActById[event.id] = act;
        actOrder[event.id] = i;
      }
    }

    final parts = <MultiActDilemmaPart>[];
    final sceneGroups = <List<StorySituation>>[];
    final contracts = <StoryCausalContract>[];
    final flags = <String>[];
    final usedEvents = <String>{};
    final usedActIds = <String>{};
    // Preserve the exact old flag names for 2..6 act saved worlds.
    final rolling = actProposals.length > 6;
    var previousOrder = -1;

    for (var i = 0; i < actProposals.length; i++) {
      final proposal = actProposals[i];
      final firstAct = sourceActById[proposal.setupEventId];
      final secondAct = sourceActById[proposal.outcomeEventId];
      if (firstAct == null || secondAct == null ||
          firstAct.id != secondAct.id ||
          !usedActIds.add(firstAct.id) ||
          !usedEvents.add(proposal.setupEventId) ||
          !usedEvents.add(proposal.outcomeEventId) ||
          actOrder[proposal.setupEventId]! <= previousOrder) {
        throw const FormatException(
            'Предложения должны ссылаться на разные части книги '
            'и не пропускать проверки принадлежности событий.');
      }
      previousOrder = actOrder[proposal.setupEventId]!;
      // Same source-locked regeneration and bounded audit as the accepted
      // one-dilemma quality gate. The model's plan is NEVER trusted.
      final proposedPlan = StoryPlanDilemmaGenerator.propose(
          book, proposal);
      final quality = StoryPlanQualityGate.assess(
        book: book,
        preview: ZaiStoryDilemmaPreview(
            proposal: proposal, plan: proposedPlan, sampledEventCount: 2),
      );
      if (!quality.passedFormalPreflight) {
        throw const FormatException(
            'Одна из частей книги нарушает игровые условия.');
      }
      final local = quality.plan;
      final prefix = 'act_' + (i + 1).toString() + '_';
      String scoped(String localId) => prefix + localId;
      String stateFlag(String flag) {
        if (!rolling) return scoped(flag);
        if (flag.endsWith('_accepted')) return rollingAccepted;
        if (flag.endsWith('_declined')) return rollingDeclined;
        if (flag == 'alternative_found') return rollingDiscovered;
        if (flag == 'original_outcome' || flag == 'alternate_outcome') {
          return scoped(flag); // Durable, distinct ACT outcomes.
        }
        throw FormatException('Неизвестное локальное состояние акта: ' + flag);
      }
      final localScenes = <StorySituation>[];
      for (final original in local.situations) {
        localScenes.add(StorySituation(
          id: scoped(original.id),
          goal: original.goal,
          conflict: original.conflict,
          chapterIndex: original.chapterIndex,
          sourceEventId: original.sourceEventId,
          route: original.route,
          // The first N-1 ACT resolutions are transitions to the next
          // imaginary gameplay segment, not ending the whole book.
          terminal: original.terminal && i == actProposals.length - 1,
          decisions: [
            for (final choice in original.decisions)
              StoryDecision(
                id: scoped(choice.id),
                intent: choice.intent,
                nextSituationId: scoped(choice.nextSituationId),
                sourceEventId: choice.sourceEventId,
                route: choice.route,
                requires: [for (final f in choice.requires) stateFlag(f)],
                forbids: [for (final f in choice.forbids) stateFlag(f)],
                adds: [for (final f in choice.adds) stateFlag(f)],
                removes: [for (final f in choice.removes) stateFlag(f)],
              ),
          ],
        ));
      }
      sceneGroups.add(localScenes);
      flags.addAll([for (final f in local.flags) stateFlag(f)]);

      final originalContract =
          StoryPlanQualityGate.structuralContract(proposal);
      contracts.add(StoryCausalContract(
        decisionInvariants: [
          for (final rule in originalContract.decisionInvariants)
            StoryDecisionInvariant(
              id: scoped(rule.id),
              decisionId: scoped(rule.decisionId),
              requires: [for (final f in rule.requires) stateFlag(f)],
              forbids: [for (final f in rule.forbids) stateFlag(f)],
            ),
        ],
        exclusiveGroups: [
          for (final rule in originalContract.exclusiveGroups)
            StoryExclusiveFlags(
              id: scoped(rule.id),
              flags: [for (final f in rule.flags) stateFlag(f)],
            ),
        ],
      ));
      parts.add(MultiActDilemmaPart(
        actId: firstAct.id,
        entrySituationId: scoped(local.entrySituationId),
        setupEventId: proposal.setupEventId,
        outcomeEventId: proposal.outcomeEventId,
        sourceChapter: firstAct.chapterIndex,
      ));
    }

    final composedScenes = <StorySituation>[];
    final bridges = <MultiActFictionalBridge>[];
    final bridgeInvariants = <StoryDecisionInvariant>[];
    for (var i = 0; i < sceneGroups.length; i++) {
      final isLast = i == sceneGroups.length - 1;
      final prefix = 'act_' + (i + 1).toString() + '_';
      final nextEntry = isLast
          ? null : parts[i + 1].entrySituationId;
      for (final scene in sceneGroups[i]) {
        if (!isLast && (scene.id == prefix + 'original_ending' ||
            scene.id == prefix + 'alternate_ending')) {
          final isOriginal =
              scene.id == prefix + 'original_ending';
          final condition = prefix + (isOriginal
              ? 'original_outcome' : 'alternate_outcome');
          final opposite = prefix + (isOriginal
              ? 'alternate_outcome' : 'original_outcome');
          final bridgeId = prefix + (isOriginal
              ? 'continue_original' : 'continue_alternative');
          composedScenes.add(StorySituation(
            id: scene.id,
            goal: scene.goal,
            conflict: scene.conflict +
                ' Переход к следующей части — игровая выдумка. '
                'В оригинале его причинность не подтверждена.',
            chapterIndex: scene.chapterIndex,
            sourceEventId: scene.sourceEventId,
            route: scene.route,
            terminal: false,
            decisions: [
              StoryDecision(
                id: bridgeId,
                intent: 'Продолжить придуманную игровую линию '
                    'в следующей части книги',
                nextSituationId: nextEntry!,
                route: StoryRoute.adaptationFiction,
                requires: [condition],
                forbids: [opposite],
                // Retire only short-lived slots. The WorldEvent ledger
                // preserves the full history and outcome flags stay live.
                removes: rolling ? rollingFlags : const [],
              ),
            ],
          ));
          bridges.add(MultiActFictionalBridge(
            fromSituationId: scene.id,
            nextActEntryId: nextEntry,
            outcomeFlag: condition,
          ));
          bridgeInvariants.add(StoryDecisionInvariant(
            id: bridgeId + '_requires_own_outcome',
            decisionId: bridgeId,
            requires: [condition],
            forbids: [opposite],
          ));
        } else {
          composedScenes.add(scene);
        }
      }
    }
    final draft = StoryPlan(
      sourceFingerprint: book.sourceFingerprint,
      title: book.title,
      entrySituationId: parts.first.entrySituationId,
      flags: rolling ? flags.toSet().toList() : flags,
      initialFlags: const [],
      situations: composedScenes,
    );
    final validation = draft.validate(book);
    if (!validation.isStructurallySound ||
        !validation.branchChangesState ||
        validation.terminalSituations != 2) {
      throw const FormatException(
          'Многоактовый план содержит тупики или неравнозначные выходы.');
    }
    final mergedContract = StoryCausalContract(
      decisionInvariants: [
        for (final contract in contracts) ...contract.decisionInvariants,
        ...bridgeInvariants,
      ],
      exclusiveGroups: [
        for (final contract in contracts) ...contract.exclusiveGroups,
      ],
    );
    final audit = StoryPlanCausalAuditor.audit(
        plan: draft, book: book, contract: mergedContract);
    if (audit.counterexamples.isNotEmpty) {
      throw const FormatException(
          'Многоактовый маршрут нарушает причинные условия.');
    }
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: bookMap, book: book, story: draft);
    final blockers = <String>[
      'Причинность переходов между частями — игровая гипотеза.',
      'Нужна независимая проверка хронологии, знаний персонажей '
          'и исходного литературного смысла.',
      if (!coverage.allDetectedEventsReferenced)
        'Не все найденные события оригинала вошли в сюжетный черновик.',
      if (!coverage.allChaptersCovered)
        'Некоторые главы пока отсутствуют в сценарии.',
      'Написание игровых сцен и полная компиляция книги ещё не выполнены.',
    ];
    return MultiActStoryPlanDraft._(
      plan: draft,
      causalContract: mergedContract,
      formalAudit: audit,
      coverage: coverage,
      parts: parts,
      fictionalBridges: bridges,
      blockers: blockers,
    );
  }
}
