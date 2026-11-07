import 'package:story_core/story_core.dart';

import 'bookwide_source_encounters.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// One end-to-end, source-bound GAMEPLAY contract for an imported campaign.
/// It verifies both anchor choices of every act, all user-reviewed source
/// encounters, and both boundary decisions between consecutive acts.
/// Literary chronology, canonical meaning and NPC truth remain unproven.
class BookwideCampaignContract {
  BookwideCampaignContract._({
    required Map<String, String> sourceDecisions,
    required List<String> bridgeDecisions,
    required List<String> actEntryScenes,
  }) : sourceDecisions = Map.unmodifiable(sourceDecisions),
       bridgeDecisions = List.unmodifiable(bridgeDecisions),
       actEntryScenes = List.unmodifiable(actEntryScenes);

  final Map<String, String> sourceDecisions;
  final List<String> bridgeDecisions, actEntryScenes;

  List<String> get requiredChoiceIds => List.unmodifiable([
    ...sourceDecisions.values, ...bridgeDecisions,
  ]);

  static BookwideCampaignContract fromPlan({
    required NarrativeBookModel book,
    required MultiActStoryPlanDraft draft,
    required StoryPlan plan,
    required Set<String> reviewedInteractiveEventIds,
  }) {
    if (!book.analysisComplete ||
        book.sourceFingerprint != plan.sourceFingerprint ||
        book.title != plan.title ||
        draft.plan.sourceFingerprint != plan.sourceFingerprint ||
        draft.parts.length < 2) {
      throw const FormatException('Неверная редакция составной кампании.');
    }
    final events = {for (final e in book.events) e.id: e};
    final scenes = {for (final s in plan.situations) s.id: s};
    if (scenes.length != plan.situations.length) {
      throw const FormatException('Повторён ID сцены книги.');
    }
    final source = <String, String>{
      ...BookwideSourceEncounters.executableChoicesForReviewedEvents(
        plan: plan, reviewedEventIds: reviewedInteractiveEventIds,
      ),
    };
    final bridges = <String>[];
    final entries = <String>[];
    final rolling = draft.parts.length > 6;

    for (var i = 0; i < draft.parts.length; i++) {
      final prefix = 'act_${i + 1}_';
      final part = draft.parts[i];
      final setup = events[part.setupEventId];
      final outcome = events[part.outcomeEventId];
      if (setup == null || outcome == null ||
          setup.source.chapterIndex != part.sourceChapter ||
          outcome.source.chapterIndex != part.sourceChapter ||
          part.entrySituationId != prefix + 'turning_point') {
        throw const FormatException('Якорь акта не связан с исходной книгой.');
      }
      final first = scenes[prefix + 'turning_point'];
      final followup = scenes[prefix + 'accept_path'];
      if (first == null || followup == null ||
          first.sourceEventId != part.setupEventId ||
          followup.sourceEventId != part.outcomeEventId ||
          first.route != StoryRoute.canonicalProposal ||
          followup.route != StoryRoute.canonicalProposal) {
        throw const FormatException(
            'Опорное событие подменено или не представлено сценой.');
      }
      StoryDecision sourceChoice(
          StorySituation scene, String id, String eventId, String next) {
        final matches = scene.decisions.where((d) => d.id == id).toList();
        if (matches.length != 1 ||
            matches.single.sourceEventId != eventId ||
            matches.single.route != StoryRoute.canonicalProposal ||
            matches.single.nextSituationId != next) {
          throw FormatException(
              'Опорный выбор ' + id + ' не связан с событием источника.');
        }
        return matches.single;
      }

      final accept = sourceChoice(first, prefix + 'accept_offer',
          part.setupEventId, prefix + 'accept_path');
      final honor = sourceChoice(followup, prefix + 'honor_condition',
          part.outcomeEventId, prefix + 'original_ending');
      if (source.containsKey(part.setupEventId) ||
          source.containsKey(part.outcomeEventId) ||
          part.setupEventId == part.outcomeEventId ||
          source.values.contains(accept.id) ||
          source.values.contains(honor.id)) {
        throw const FormatException(
            'Исходная цитата повторно присвоена нескольким решениям.');
      }
      source[part.setupEventId] = accept.id;
      source[part.outcomeEventId] = honor.id;
      final entryId = scenes.containsKey(prefix + 'source_encounter')
          ? prefix + 'source_encounter' : part.entrySituationId;
      entries.add(entryId);
      if (!scenes.containsKey(entryId)) {
        throw const FormatException('Не найден вход в исходный акт.');
      }
      if (i == 0 && plan.entrySituationId != entryId) {
        throw const FormatException('Игра пропускает начало первого акта.');
      }
      if (i == draft.parts.length - 1) continue;

      final nextPrefix = 'act_${i + 2}_';
      final next = scenes.containsKey(nextPrefix + 'source_encounter')
          ? nextPrefix + 'source_encounter'
          : draft.parts[i + 1].entrySituationId;
      for (final (kind, opposite) in [
        ('original', 'alternate'), ('alternate', 'original'),
      ]) {
        final node = scenes[prefix + kind + '_ending'];
        final id = prefix + 'continue_' + kind;
        final choices = node?.decisions.where((d) => d.id == id).toList();
        if (node == null || node.terminal ||
            choices == null || choices.length != 1) {
          throw FormatException('Нет перехода из ' + prefix + kind + '_ending');
        }
        final choice = choices.single;
        if (choice.nextSituationId != next ||
            !scenes.containsKey(next) ||
            !choice.requires.contains(prefix + kind + '_outcome') ||
            !choice.forbids.contains(prefix + opposite + '_outcome') ||
            (rolling && !choice.removes.toSet()
                .containsAll(BookwideStoryPlanComposer.rollingFlags))) {
          throw FormatException(
              'Нарушена граница акта или не сброшены временные состояния: ' +
              id);
        }
        bridges.add(id);
      }
    }
    if (source.length != reviewedInteractiveEventIds.length +
            2 * draft.parts.length ||
        bridges.length != 2 * (draft.parts.length - 1) ||
        source.values.toSet().length != source.length ||
        [...source.values, ...bridges].toSet().length !=
            source.length + bridges.length) {
      throw const FormatException(
          'Не все события и границы актов имеют уникальные решения.');
    }
    return BookwideCampaignContract._(
      sourceDecisions: source,
      bridgeDecisions: bridges,
      actEntryScenes: entries,
    );
  }

  /// Only genuine, hash-chained and replayable StoryWorld.apply proofs count.
  void verifyWitnesses(CampaignCausalReport report) {
    if (!report.playable || !report.exhaustive) {
      throw const FormatException(
          'Кампания не прошла полную причинную проверку.');
    }
    for (final choiceId in requiredChoiceIds) {
      final witness = report.choiceWitnesses[choiceId];
      if (witness == null || witness.isEmpty ||
          witness.last.choiceId != choiceId) {
        throw FormatException(
            'Нет воспроизводимого пути к решению ' + choiceId);
      }
    }
  }
}
