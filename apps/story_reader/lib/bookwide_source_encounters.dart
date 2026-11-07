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

  /// Demand a source-locked REAL action witness for every separately
  /// approved interactive event. A citation in a scene is not a playable
  /// choice. This remains independent of any model's literary judgement.
  static Map<String, String> executableChoicesForReviewedEvents({
    required StoryPlan plan,
    required Set<String> reviewedEventIds,
  }) {
    final result = <String, String>{};
    if (reviewedEventIds.isEmpty) return const {};
    for (final scene in plan.situations) {
      if (!reviewedEventIds.contains(scene.sourceEventId) ||
          scene.route != StoryRoute.canonicalProposal) continue;
      for (final decision in scene.decisions) {
        if (decision.sourceEventId != scene.sourceEventId ||
            decision.route != StoryRoute.adaptationFiction) continue;
        final eventId = scene.sourceEventId!;
        if (result.containsKey(eventId)) {
          throw const FormatException(
              'Один исходный эпизод связан с несколькими игровыми действиями.');
        }
        result[eventId] = decision.id;
      }
    }
    if (result.length != reviewedEventIds.length ||
        !result.keys.toSet().containsAll(reviewedEventIds) ||
        result.values.toSet().length != result.length) {
      throw const FormatException(
          'Не каждому подтверждённому событию соответствует '
          'единственное проверяемое игровое решение.');
    }
    return Map<String, String>.unmodifiable(result);
  }

  // Source observations must stay bounded by the SAME StoryPlan/BookWorld
  // runtime and finite-state audit as the rest of the game.
  static const maxReviewedEvents = 48;
  static const maxReviewedEventsPerAct = 8;

  /// Candidate events in one source-validated act, apart from its 2 anchors.
  /// Book text order is not a claim about the in-world chronology.
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
        reviewedEventIds.length >
            draft.parts.length * maxReviewedEventsPerAct ||
        index.sourceFingerprint != book.sourceFingerprint ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != book.sourceFingerprint ||
        plan.entrySituationId != draft.parts.first.entrySituationId ||
        !book.analysisComplete || !draft.formalRulesPassed) {
      throw const FormatException(
          'Нужны согласие, текущая редакция и проверенный игровой план.');
    }

    // Verify every selected event against this exact edition and its act.
    // One source event may not be silently reused across multiple acts.
    final validByEvent = <String, int>{};
    for (var i = 0; i < draft.parts.length; i++) {
      for (final event in eligibleForAct(
        index: index, bookMap: bookMap, draft: draft, partIndex: i,
      )) {
        if (validByEvent.containsKey(event.id)) {
          throw const FormatException('Событие встречается в двух актах.');
        }
        validByEvent[event.id] = i;
      }
    }
    final byId = {for (final e in book.events) e.id: e};
    final selected = <int, List<NarrativeEvent>>{};
    for (final id in reviewedEventIds) {
      final event = byId[id];
      final partIndex = validByEvent[id];
      if (event == null || partIndex == null) {
        throw const FormatException(
            'Событие не принадлежит текущему акту или его цитате.');
      }
      event.source.validate(index);
      final group = selected.putIfAbsent(partIndex, () => []);
      group.add(event);
      if (group.length > maxReviewedEventsPerAct) {
        throw const FormatException(
            'На один акт разрешено не более восьми дополнительных событий.');
      }
    }
    for (final group in selected.values) {
      group.sort((a, b) =>
          a.narrativePosition.compareTo(b.narrativePosition));
    }

    // Preserve single-encounter IDs for old .bworld files and saves.
    // More than one selected event yields source-order _2/_3/... suffixes.
    // A changed set of source choices creates a new signed BookWorld.
    String encounterId(int act, int j) =>
        'act_${act + 1}_source_encounter${j == 0 ? '' : '_${j + 1}'}';
    String examineId(int act, int j) =>
        'act_${act + 1}_examine_source${j == 0 ? '' : '_${j + 1}'}';
    String passId(int act, int j) =>
        'act_${act + 1}_pass_source${j == 0 ? '' : '_${j + 1}'}';

    final reroute = <String, String>{
      for (final act in selected.keys)
        draft.parts[act].entrySituationId: encounterId(act, 0),
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
    for (final act in (selected.keys.toList()..sort())) {
      final group = selected[act]!;
      final originalEntry = draft.parts[act].entrySituationId;
      for (var j = 0; j < group.length; j++) {
        final event = group[j];
        final next = j + 1 < group.length
            ? encounterId(act, j + 1) : originalEntry;
        updatedScenes.add(StorySituation(
          id: encounterId(act, j),
          goal: 'Исследовать подтверждённый отрывок главы',
          conflict: 'Смысл цитаты и время события не подтверждены. '
              'Игровые действия ниже — вымышленная возможность '
              'изучить отрывок или продолжить путешествие.',
          chapterIndex: event.source.chapterIndex,
          sourceEventId: event.id,
          route: StoryRoute.canonicalProposal,
          terminal: false,
          decisions: [
            StoryDecision(
              id: examineId(act, j),
              intent: 'Изучить фрагмент и запомнить найденное',
              nextSituationId: next,
              sourceEventId: event.id,
              route: StoryRoute.adaptationFiction,
            ),
            StoryDecision(
              id: passId(act, j),
              intent: 'Пройти мимо, не исследуя отрывок',
              nextSituationId: next,
              route: StoryRoute.adaptationFiction,
            ),
          ],
        ));
      }
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
