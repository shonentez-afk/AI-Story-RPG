import 'intermediate_story_blueprint.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'story_plan_bounded_repair.dart';
import 'story_plan_causal_audit.dart';
import 'story_plan_dilemma_generator.dart';
import 'zai_story_dilemma_proposal.dart';

/// M2g3d: a fail-closed, source-locked gate between one UNTRUSTED GLM
/// proposal and future book-world compilation. This is an editorial DRAFT,
/// not a generated game or a claim that the AI understood the book.
///
/// It verifies the proposal/plan pair was not modified, checks all observable
/// state transitions, and only permits the existing bounded precondition
/// repair. It never changes the source, BookWorld, SQLite or a saved game.
class StoryPlanQualityReport {
  StoryPlanQualityReport({
    required this.plan,
    required this.causalContract,
    required this.repair,
    required this.intermediateDraft,
    required this.sourceEventCount,
    required this.chaptersWithEvents,
    required this.chapterCount,
    required List<String> blockers,
    required List<String> reviewRequirements,
  }) : blockers = List.unmodifiable(blockers),
       reviewRequirements = List.unmodifiable(reviewRequirements);

  /// Both are draft-only. Do NOT call a private book-world writer here.
  final StoryPlan plan;
  final StoryCausalContract causalContract;
  final StoryRepairResult repair;
  final IntermediateStoryBlueprint intermediateDraft;
  final int sourceEventCount, chaptersWithEvents, chapterCount;
  final List<String> blockers, reviewRequirements;

  bool get passedFormalPreflight =>
      blockers.isEmpty &&
      repair.passedFormalContracts &&
      repair.after.counterexamples.isEmpty;

  bool get meaningConfirmed => false;
  bool get chronologyConfirmed => false;
  bool get sceneProseApproved => false;
  bool get readyToInstall => false;
  bool get readyToPlay => false;
  bool get canPublish => false;
  bool get wholeBookCovered =>
      chapterCount > 0 && chaptersWithEvents == chapterCount;

  /// Structured private readiness data. This contains no quotes, API keys,
  /// user-entered prose, book title or original text.
  Map<String, Object> toReadinessJson() => {
    'status': 'DRAFT_ONLY',
    'source_events': sourceEventCount,
    'chapters_with_event_proposals': chaptersWithEvents,
    'total_chapters': chapterCount,
    'situations': plan.situations.length,
    'formal_preflight_passed': passedFormalPreflight,
    'causal_violations_before': repair.before.counterexamples.length,
    'causal_violations_after': repair.after.counterexamples.length,
    'bounded_repairs': repair.appliedChanges.length,
    'formal_blockers': blockers.length,
    'semantic_review_required': true,
    'meaning_confirmed': false,
    'chronology_confirmed': false,
    'ready_to_install': false,
    'ready_to_play': false,
  };
}

class StoryPlanQualityGate {
  const StoryPlanQualityGate._();

  static String _prefix(StoryDilemmaKind kind) {
    return switch (kind) {
      StoryDilemmaKind.agreement => 'agreement',
      StoryDilemmaKind.exchange => 'exchange',
      StoryDilemmaKind.disclosure => 'disclosure',
    };
  }

  /// These are enforceable GAME rules, not observations about the text.
  /// A promise/offer can only be fulfilled if that particular route was
  /// accepted. A speculative alternate route cannot grant knowledge
  /// of source events, item ownership or new canonical dialogue.
  static StoryCausalContract structuralContract(
      StoryDilemmaProposal proposal) {
    final prefix = _prefix(proposal.kind);
    final accepted = prefix + '_accepted';
    final declined = prefix + '_declined';
    return StoryCausalContract(
      decisionInvariants: [
        StoryDecisionInvariant(
          id: 'accepted_before_honor',
          decisionId: 'honor_condition',
          requires: [accepted], forbids: [declined],
        ),
        StoryDecisionInvariant(
          id: 'declined_before_exploration',
          decisionId: 'explore',
          requires: [declined], forbids: [accepted],
        ),
        StoryDecisionInvariant(
          id: 'discovery_before_use',
          decisionId: 'use_discovery',
          requires: [declined, 'alternative_found'],
          forbids: [accepted],
        ),
        StoryDecisionInvariant(
          id: 'alternative_before_finish',
          decisionId: 'end_alternative',
          requires: [declined, 'alternate_outcome'],
          forbids: [accepted],
        ),
      ],
      exclusiveGroups: [
        StoryExclusiveFlags(
          id: 'one_acceptance_route',
          flags: [accepted, declined],
        ),
        StoryExclusiveFlags(
          id: 'one_outcome_route',
          flags: ['original_outcome', 'alternate_outcome'],
        ),
      ],
      // No NPC knowledge gate is fabricated from chapter order.
      // Such rules require separately verified evidence in M2g3e.
    );
  }

  static StoryPlanQualityReport assess({
    required NarrativeBookModel book,
    required ZaiStoryDilemmaPreview preview,
  }) {
    final proposal = preview.proposal;
    final supplied = preview.plan;
    if (proposal == null || supplied == null ||
        !preview.foundCandidate || !book.analysisComplete ||
        proposal.sourceFingerprint != book.sourceFingerprint) {
      throw const FormatException(
          'Нет проверенного предложения для текущей редакции книги.');
    }
    // Regenerate the draft from the source-bound proposal rather than
    // trusting a potentially modified plan returned by a UI or model.
    final regenerated = StoryPlanDilemmaGenerator.propose(book, proposal);
    if (supplied.encode() != regenerated.encode()) {
      throw const FormatException(
          'План изменился после анализа источника; проверка отменена.');
    }
    final contract = structuralContract(proposal);
    final repair = StoryPlanBoundedRepair.attempt(
      book: book,
      plan: regenerated,
      contract: contract,
      maxPatches: 3,
    );

    final formalBlockers = <String>[
      ...repair.blockers,
      if (!repair.passedFormalContracts)
        'Найдены нерешённые противоречия игровых условий.',
      if (repair.after.counterexamples.isNotEmpty)
        'Остаются пути с нарушениями причинных правил.',
    ];
    // Still a DRAFT even with zero formal violations. Passing programmatic
    // tests says nothing about the literary truth of AI's interpretation.
    final reviewRequirements = <String>[
      'Проверить смысл обеих исходных цитат и причинность между ними.',
      'Отдельно подтвердить хронологию мира, включая ретроспективы.',
      'Проверить знания, имена и мотивацию каждого действующего лица.',
      'Написать и вычитать художественные сцены и обе концовки.',
      'Проверить весь путь от исходной книги до финала на Windows и Android.',
      if (book.chaptersWithEventProposals < book.chapterCount)
        'В некоторых главах нет предложенных событий: '
            'сценарий не охватывает исходную книгу.',
    ];
    return StoryPlanQualityReport(
      plan: repair.draft,
      causalContract: contract,
      repair: repair,
      intermediateDraft: repair.draft.toIntermediateDraft(
        book,
        rights: PreparationRights.privateUse,
      ),
      sourceEventCount: book.events.length,
      chapterCount: book.chapterCount,
      chaptersWithEvents: book.chaptersWithEventProposals,
      blockers: formalBlockers,
      reviewRequirements: reviewRequirements,
    );
  }
}
