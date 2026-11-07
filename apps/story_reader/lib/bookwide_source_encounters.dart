import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// Additional source events become ACTUAL, optional interactive scenes.
///
/// A player may examine a source-locked passage (and later acquire a
/// separately reviewed item/fact from this choice) or pass it. Both choices
/// are committed WorldEvents and replay with the ordinary story_core.
/// This is explicitly GAME FICTION: neither event meaning nor book-world
/// chronology is inferred from textual order. No second runtime or storage.
class BookwideSourceEncounters {
  const BookwideSourceEncounters._();

  static const maxReviewedEvents = 6;

  /// A bounded first step: at most one additional confirmed event per act.
  /// Never present a source proposal as a confirmed meaning or fact.
  static List<NarrativeEvent> eligibleForAct({
    required BookSourceIndex index,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    required int partIndex,
  }) {
    if (partIndex < 0 || partIndex >= draft.parts.length ||
        bookMap.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Другая карта книги для игровых событий');
    }
    final part = draft.parts[partIndex];
    final selectedAct = [
      for (final a in bookMap.acts) if (a.id == part.actId) a,
    ];
    if (selectedAct.length != 1) {
      throw const FormatException('Исходная часть книги не найдена');
    }
    return List.unmodifiable([
      for (final e in selectedAct.single.events)
        if (e.id != part.setupEventId && e.id != part.outcomeEventId) e,
    ]);
  }

  /// Source event -> interactive encounter -> ORIGINAL act entry.
  /// The prior act's two genuine alternatives both lead to the new source
  /// encounter before the next act; no previous choices/effects are changed.
  /// The original act decision remains responsible for narrative outcomes.
  static StoryPlan attach({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    required StoryPlan plan,
    required Set<String> reviewedEventIds,
    required bool userConfirmedPrivateAdaptation,
  }) {
    if (reviewedEventIds.isEmpty) return plan;
    if (!userConfirmedPrivateAdaptation ||
        reviewedEventIds.length > maxReviewedEvents ||
        reviewedEventIds.length > draft.parts.length ||
        index.sourceFingerprint != book.sourceFingerprint ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != book.sourceFingerprint ||
        plan.entrySituationId != draft.parts.first.entrySituationId ||
        !book.analysisComplete || !draft.formalRulesPassed) {
      throw const FormatException(
          'Нужны согласие, текущая редакция и проверенный игровой план.');
    }

    final selected = <int, NarrativeEvent>{};
    final known = {for (final e in book.events) e.id: e};
    for (final id in reviewedEventIds) {
      final event = known[id];
      if (event == null) {
        throw const FormatException('Игровая сцена не найдена в книге');
      }
      var partIndex = -1;
      for (var i = 0; i < draft.parts.length; i++) {
        if (eligibleForAct(
              index: index, bookMap: bookMap, draft: draft, partIndex: i,
            ).any((e) => e.id == id)) {
          partIndex = i;
          break;
        }
      }
      if (partIndex < 0 || selected.containsKey(partIndex)) {
        throw const FormatException(
            'Разрешено одно ДОПОЛНИТЕЛЬНОЕ событие на исходный акт');
      }
      event.source.validate(index);
      selected[partIndex] = event;
    }

    final reroute = <String, String>{
      for (final i in selected.keys)
        draft.parts[i].entrySituationId:
            'act_${i + 1}_source_encounter',
    };
    final updatedScenes = <StorySituation>[
      for (final scene in plan.situations)
        StorySituation(
          id: scene.id,
          goal: scene.goal,
          conflict: scene.conflict,
          chapterIndex: scene.chapterIndex,
          sourceEventId: scene.sourceEventId,
          route: scene.route,
          terminal: scene.terminal,
          decisions: [
            for (final d in scene.decisions)
              StoryDecision(
                id: d.id,
                intent: d.intent,
                nextSituationId: reroute[d.nextSituationId] ??
                    d.nextSituationId,
                sourceEventId: d.sourceEventId,
                route: d.route,
                requires: d.requires,
                forbids: d.forbids,
                adds: d.adds,
                removes: d.removes,
              ),
          ],
        ),
    ];
    for (final i in (selected.keys.toList()..sort())) {
      final e = selected[i]!;
      final prefix = 'act_${i + 1}_';
      final originalEntry = draft.parts[i].entrySituationId;
      updatedScenes.add(StorySituation(
        id: prefix + 'source_encounter',
        goal: 'Исследовать другой подтверждённый отрывок главы',
        conflict: 'Смысл цитаты и время события не подтверждены. '
            'Игровые действия ниже — вымышленная возможность '
            'изучить отрывок или продолжить путешествие.',
        chapterIndex: e.source.chapterIndex,
        sourceEventId: e.id,
        route: StoryRoute.canonicalProposal,
        terminal: false,
        decisions: [
          StoryDecision(
            id: prefix + 'examine_source',
            intent: 'Изучить фрагмент и запомнить найденное',
            nextSituationId: originalEntry,
            sourceEventId: e.id,
            route: StoryRoute.adaptationFiction,
          ),
          StoryDecision(
            id: prefix + 'pass_source',
            intent: 'Продолжить путь, не исследуя фрагмент',
            nextSituationId: originalEntry,
            route: StoryRoute.adaptationFiction,
          ),
        ],
      ));
    }
    final result = StoryPlan(
      sourceFingerprint: plan.sourceFingerprint,
      title: plan.title,
      entrySituationId:
          reroute[plan.entrySituationId] ?? plan.entrySituationId,
      flags: plan.flags,
      initialFlags: plan.initialFlags,
      situations: updatedScenes,
    );
    final check = result.validate(book);
    if (!check.isStructurallySound ||
        !check.branchChangesState || check.terminalSituations != 2) {
      throw const FormatException(
          'Новые игровые события нарушили достижимость маршрута.');
    }
    return result;
  }
}
