import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'bookwide_unified_story.dart';
import 'reviewed_hero_role.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';

/// Authoring-only carrier of an explicitly accepted story revision. The
/// delegated plan is the SAME cross-act audited plan, not another runtime.
/// Textual motives are writing guidance, never learned facts or executed rules.
/// The live verifier is deliberately kept outside every data-only worker.
class ReviewedStoryNarrative implements MultiActStoryPlanDraft {
  ReviewedStoryNarrative._(this._plan, this.context, this.proposal,
      this._verifySavedRevision);

  final MultiActStoryPlanDraft _plan;
  final UnifiedBookStoryContext context;
  final UnifiedBookStoryDraft proposal;
  final Future<void> Function() _verifySavedRevision;

  factory ReviewedStoryNarrative.accept({
    required UnifiedBookStoryContext context,
    required UnifiedBookStoryDraft proposal,
    required List<ReviewedHeroRole> freshRoles,
    required String approvedReviewDigest,
    required bool allShownQuotesAndStoryReviewed,
    required bool fictionalConsequencesConfirmed,
    required Future<void> Function() verifySavedRevision,
  }) {
    final checked = UnifiedBookStoryDraft.parse(context, proposal.responseJson);
    if (checked.reviewDigest != proposal.reviewDigest) {
      throw const FormatException('Общая история изменилась перед подтверждением.');
    }
    final plan = checked.accept(context: context, freshRoles: freshRoles,
      approvedReviewDigest: approvedReviewDigest,
      allShownQuotesAndStoryReviewed: allShownQuotesAndStoryReviewed,
      fictionalConsequencesConfirmed: fictionalConsequencesConfirmed);
    return ReviewedStoryNarrative._(plan, context, checked, verifySavedRevision);
  }

  String get reviewDigest => proposal.reviewDigest;
  void verifyRoles(List<ReviewedHeroRole> roles) => context.verifyCurrent(roles);
  Future<void> verifyLive() => _verifySavedRevision();

  /// Fresh maps are returned; callers cannot mutate the accepted proposal.
  /// No full-book text, endings, notebook secrets or other NPC motives here.
  Map<String, dynamic> get cloudHeader => {
    'format': 'ai_story_accepted_narrative_context_v1',
    'review_digest': reviewDigest,
    'scope': 'AUTHOR_APPROVED_PRIVATE_FICTION_NOT_ACTOR_KNOWLEDGE',
    'plot_mode': 'PRIVATE_ALTER_FATE',
    'campaign_goal': proposal.goal,
    'central_conflict': proposal.conflict,
    'literary_canon_verified': false,
    'imports_actor_knowledge': false,
    'describes_current_save': false,
    'source_order_is_world_chronology': false,
  };

  Map<String, dynamic> forConversation({required String characterId,
    required String firstEventId, required String responseEventId}) {
    final events = {for (final e in context.book.events) e.id: e};
    final first = events[firstEventId], response = events[responseEventId];
    final motives = proposal.motivations.where((m) => m.characterId == characterId).toList();
    final actorRows = (context.shownData['actors'] as List)
        .where((row) => row['character_id'] == characterId).toList();
    if (first == null || response == null || motives.length != 1 ||
        actorRows.length != 1 || first.narrativePosition > response.narrativePosition ||
        !(actorRows.single['source_event_ids'] as List).contains(firstEventId) ||
        !(actorRows.single['source_event_ids'] as List).contains(responseEventId)) {
      throw const FormatException('Разговор не связан с персонажем принятого сюжета.');
    }
    first.source.validate(context.index); response.source.validate(context.index);
    final motive = motives.single;
    // This is a conservative textual spoiler boundary, NOT a deduction of
    // world time or what this character knows. Never drop half the evidence
    // while keeping a conclusion whose remaining basis lies in a later event.
    final available = motive.sourceEventIds.every((id) =>
        events[id] != null && events[id]!.narrativePosition <= first.narrativePosition);
    Map<String, dynamic> actFor(String eventId) {
      final index = context.bookMap.acts.indexWhere((act) =>
          act.events.any((event) => event.id == eventId));
      if (index < 0) throw const FormatException('Нет акта для принятого события.');
      final act = proposal.acts[index];
      final incoming = proposal.links.where((link) => link.toActId == act.actId).toList();
      return {
        'act_id': act.actId, 'act_number': index + 1,
        'purpose': act.purpose,
        'status': 'AUTHOR_INTENTION_NOT_COMPLETED_ACTION',
        'conditional_links': [for (final link in incoming) {
          'from_act_id': link.fromActId,
          'required_prior_outcome': link.outcome.name,
          'guarded_choice_id': 'act_${index + 1}_accept_offer',
          'reason': link.reason,
          'prior_outcome_has_occurred': 'UNKNOWN_FOR_THIS_DIALOGUE',
          'refusal_remains_available': true,
          'grants_npc_knowledge': false,
        }],
      };
    }
    return {
      'character_id': characterId,
      'motive_status': available ? 'REVIEWED_FICTION_NOT_KNOWLEDGE'
          : 'WITHHELD_FUTURE_SOURCE_BASIS',
      if (available) 'motive': {
        'goal': motive.goal, 'reason': motive.reason,
        'source_basis': [for (final id in motive.sourceEventIds) {
          'event_id': id, 'chapter': events[id]!.source.chapterIndex,
          'quote': events[id]!.source.quote,
        }],
        'literary_truth_verified': false,
      },
      'first_act': actFor(firstEventId),
      'response_act': actFor(responseEventId),
      'instruction_scope': 'Do not speak a motive as a disclosed secret, '
          'a conditional link as an accomplished promise, or an author goal '
          'as a fact known by an NPC. Skip an unsupported line.',
    };
  }

  @override StoryPlan get plan => _plan.plan;
  @override StoryCausalContract get causalContract => _plan.causalContract;
  @override StoryCausalAudit get formalAudit => _plan.formalAudit;
  @override BookwideStoryCoverage get coverage => _plan.coverage;
  @override List<MultiActDilemmaPart> get parts => _plan.parts;
  @override List<MultiActFictionalBridge> get fictionalBridges => _plan.fictionalBridges;
  @override List<String> get blockers => _plan.blockers;
  @override bool get hasFormalCounterexamples => _plan.hasFormalCounterexamples;
  @override bool get formalRulesPassed => _plan.formalRulesPassed;
  @override bool get hasConfirmedLiteraryMeaning => false;
  @override bool get hasConfirmedWorldChronology => false;
  @override bool get hasConfirmedActorKnowledge => false;
  @override bool get hasSourceProvenCausalBridges => false;
  @override bool get isReadyToInstall => false;
  @override bool get isFullBookRpg => false;
  @override bool get canPublish => false;
  @override Map<String, Object> toDiagnosticJson() => {
    ..._plan.toDiagnosticJson(), 'accepted_story_review': reviewDigest,
    'narrative_is_runtime_knowledge': false,
  };
}
