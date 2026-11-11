import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_npc_arc.dart';
import 'bookwide_source_encounters.dart';
import 'bookwide_storyplan_composer.dart';
import 'cross_act_consequence_gate.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'reviewed_hero_source_action.dart';
import 'story_plan.dart';
import 'whole_story_literary_bounded_repair.dart';

/// Both preview and compiler use this exact pure-Dart composition result.
/// No Flutter widget, model request, local storage or second rules engine.
final class MultiActPlanComposition {
  const MultiActPlanComposition({required this.plan, required this.npcArc});
  final StoryPlan plan;
  final BookwideNpcArc? npcArc;
}

abstract final class MultiActTrialPlanComposer {
  static MultiActPlanComposition compose({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    CrossActContinuityDraft? continuity,
    WholeStoryLiteraryRecheckApproval? recheckedRepair,
    Set<String> reviewedInteractiveEventIds = const {},
    ReviewedHeroRole? selectedHeroRole,
    bool reviewedHeroSourceAction = false,
    ReviewedHeroRole? npcEncounterRole,
    bool reviewedNpcEncounter = false,
    bool includeNpc = true,
    String npcPlayerLine = '',
    String npcReplyLine = '',
    required bool fictionalTrialAcknowledged,
    bool expanded = false,
  }) {
    if (index.sourceFingerprint != book.sourceFingerprint ||
        bookMap.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Чужая редакция при сборке многоактового плана.');
    }
    final basePlan = recheckedRepair?.draft ?? continuity?.plan ?? draft.plan;
    final sourcePlan = BookwideSourceEncounters.attach(
      index: index, book: book, bookMap: bookMap,
      draft: draft, plan: basePlan,
      reviewedEventIds: reviewedInteractiveEventIds,
      userConfirmedPrivateAdaptation: fictionalTrialAcknowledged,
      expanded: expanded,
    );
    final rolePlan = selectedHeroRole == null
        ? sourcePlan
        : selectedHeroRole.bindTo(sourcePlan, book, expanded: expanded);
    final attachNpc = includeNpc && reviewedNpcEncounter;
    if (attachNpc &&
        (npcEncounterRole == null ||
         npcEncounterRole.characterId == selectedHeroRole?.characterId)) {
      throw const FormatException(
          'Нужна отдельная подтверждённая личность NPC.');
    }
    // A preview may explicitly omit NPC to evaluate its original meeting
    // opportunity. Compilation ALWAYS uses the full (includeNpc=true) plan.
    final npcArc = attachNpc
        ? BookwideNpcArc.review(
            index: index, book: book, plan: rolePlan,
            role: npcEncounterRole!, privateFictionConfirmed: true,
            playerLine: npcPlayerLine, npcLine: npcReplyLine,
            expanded: expanded)
        : null;
    if (attachNpc && npcArc == null) {
      throw const FormatException(
          'В двух выбранных событиях нет проверенной встречи с NPC.');
    }
    final npcPlan = npcArc?.attach(rolePlan, book,
        expanded: expanded) ?? rolePlan;
    if (reviewedHeroSourceAction && selectedHeroRole == null) {
      throw const FormatException(
          'Ролевое действие требует проверенного постоянного character_id.');
    }
    final finalPlan = reviewedHeroSourceAction
        ? ReviewedHeroSourceAction.attach(
            index: index, book: book, plan: npcPlan,
            role: selectedHeroRole!,
            explicitlyConfirmedPrivateGameFiction: fictionalTrialAcknowledged,
            expanded: expanded)
        : npcPlan;
    return MultiActPlanComposition(plan: finalPlan, npcArc: npcArc);
  }
}
