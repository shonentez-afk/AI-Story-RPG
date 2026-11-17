import 'dart:convert';

import 'narrative_book_model.dart';
import 'story_plan.dart';

/// A proposed mechanic is NOT evidence of an event's meaning or causality.
enum StoryDilemmaKind { agreement, exchange, disclosure }

/// Untrusted, bounded and source-locked semantic input for M2g3b.
class StoryDilemmaProposal {
  const StoryDilemmaProposal({
    required this.sourceFingerprint,
    required this.setupEventId,
    required this.outcomeEventId,
    required this.kind,
    required this.dilemma,
    required this.acceptIntent,
    required this.refuseIntent,
    required this.followupGoal,
    required this.finishOriginalIntent,
    required this.originalEnding,
    required this.alternativeSearchGoal,
    required this.searchIntent,
    required this.alternativeDiscovery,
    required this.useDiscoveryIntent,
    required this.alternativeEnding,
  });

  static const format = 'ai_story_dilemma_proposal_m2g3b_v1';
  static const maxBytes = 16 * 1024;
  final String sourceFingerprint, setupEventId, outcomeEventId;
  final StoryDilemmaKind kind;
  final String dilemma, acceptIntent, refuseIntent, followupGoal;
  final String finishOriginalIntent, originalEnding;
  final String alternativeSearchGoal, searchIntent, alternativeDiscovery;
  final String useDiscoveryIntent, alternativeEnding;

  Map<String, Object> toJson() => {
    'format': format, 'status': 'UNREVIEWED_PROPOSAL',
    'source_fingerprint': sourceFingerprint,
    'setup_event_id': setupEventId, 'outcome_event_id': outcomeEventId,
    'kind': kind.name, 'dilemma': dilemma,
    'accept_intent': acceptIntent, 'refuse_intent': refuseIntent,
    'followup_goal': followupGoal,
    'finish_original_intent': finishOriginalIntent,
    'original_ending': originalEnding,
    'alternative_search_goal': alternativeSearchGoal,
    'search_intent': searchIntent,
    'alternative_discovery': alternativeDiscovery,
    'use_discovery_intent': useDiscoveryIntent,
    'alternative_ending': alternativeEnding,
  };

  String encode() {
    final raw = jsonEncode(toJson());
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большое предложение сценария.');
    }
    return raw;
  }

  static StoryDilemmaProposal decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большое предложение сценария.');
    }
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const allowed = {
        'format', 'status', 'source_fingerprint', 'setup_event_id',
        'outcome_event_id', 'kind', 'dilemma', 'accept_intent',
        'refuse_intent', 'followup_goal', 'finish_original_intent',
        'original_ending', 'alternative_search_goal', 'search_intent',
        'alternative_discovery', 'use_discovery_intent', 'alternative_ending',
      };
      if (map.keys.toSet().length != allowed.length ||
          !map.keys.toSet().containsAll(allowed) ||
          map['format'] != format ||
          map['status'] != 'UNREVIEWED_PROPOSAL') {
        throw const FormatException('Неверная схема сценарного предложения.');
      }
      return StoryDilemmaProposal(
        sourceFingerprint: map['source_fingerprint'] as String,
        setupEventId: map['setup_event_id'] as String,
        outcomeEventId: map['outcome_event_id'] as String,
        kind: StoryDilemmaKind.values.firstWhere(
            (value) => value.name == map['kind']),
        dilemma: map['dilemma'] as String,
        acceptIntent: map['accept_intent'] as String,
        refuseIntent: map['refuse_intent'] as String,
        followupGoal: map['followup_goal'] as String,
        finishOriginalIntent: map['finish_original_intent'] as String,
        originalEnding: map['original_ending'] as String,
        alternativeSearchGoal: map['alternative_search_goal'] as String,
        searchIntent: map['search_intent'] as String,
        alternativeDiscovery: map['alternative_discovery'] as String,
        useDiscoveryIntent: map['use_discovery_intent'] as String,
        alternativeEnding: map['alternative_ending'] as String,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён сценарный кандидат.');
    }
  }
}

/// Produces source-anchored alternative GAME STRUCTURE, not validated prose.
/// No automatic assumption that narrative adjacency proves a promise,
/// character identity, timeline or canonical outcome.
class StoryPlanDilemmaGenerator {
  const StoryPlanDilemmaGenerator._();

  static final RegExp _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static void _text(String value) {
    if (value != value.trim() || value.length < 8 ||
        value.length > 360 || _controls.hasMatch(value)) {
      throw const FormatException('Неверное смысловое предложение.');
    }
  }

  static StoryPlan propose(NarrativeBookModel book,
      StoryDilemmaProposal proposal) {
    if (!book.analysisComplete ||
        book.sourceFingerprint != proposal.sourceFingerprint ||
        proposal.setupEventId == proposal.outcomeEventId) {
      throw const FormatException('Неверная редакция или событие.');
    }
    for (final s in [
      proposal.dilemma, proposal.acceptIntent, proposal.refuseIntent,
      proposal.followupGoal, proposal.finishOriginalIntent,
      proposal.originalEnding, proposal.alternativeSearchGoal,
      proposal.searchIntent, proposal.alternativeDiscovery,
      proposal.useDiscoveryIntent, proposal.alternativeEnding,
    ]) {
      _text(s);
    }
    final eventById = {for (final event in book.events) event.id: event};
    final setup = eventById[proposal.setupEventId];
    final outcome = eventById[proposal.outcomeEventId];
    if (setup == null || outcome == null ||
        setup.narrativePosition >= outcome.narrativePosition) {
      // Only validate source text order, NOT world chronology or causation.
      throw const FormatException('Нет двух проверяемых событий книги.');
    }
    final prefix = switch (proposal.kind) {
      StoryDilemmaKind.agreement => 'agreement',
      StoryDilemmaKind.exchange => 'exchange',
      StoryDilemmaKind.disclosure => 'disclosure',
    };
    final accepted = prefix + '_accepted';
    final declined = prefix + '_declined';
    const discovered = 'alternative_found';
    const originalDone = 'original_outcome';
    const alternativeDone = 'alternate_outcome';

    StoryDecision decision(
      String id, String label, String next, {
      List<String> requires = const [],
      List<String> forbids = const [],
      List<String> adds = const [],
      String? event,
      StoryRoute route = StoryRoute.adaptationFiction,
    }) => StoryDecision(
      id: id, intent: label, nextSituationId: next,
      sourceEventId: event, route: route,
      requires: requires, forbids: forbids, adds: adds,
    );

    StorySituation situation(
      String id, String goal, String conflict, List<StoryDecision> actions, {
      required int chapter,
      String? event,
      StoryRoute route = StoryRoute.adaptationFiction,
      bool terminal = false,
    }) => StorySituation(
      id: id, goal: goal, conflict: conflict, chapterIndex: chapter,
      sourceEventId: event, route: route, terminal: terminal,
      decisions: actions,
    );

    final startChapter = setup.source.chapterIndex;
    final outcomeChapter = outcome.source.chapterIndex;
    final draft = StoryPlan(
      sourceFingerprint: book.sourceFingerprint, title: book.title,
      entrySituationId: 'turning_point',
      flags: [accepted, declined, discovered, originalDone, alternativeDone],
      initialFlags: const [],
      situations: [
        situation('turning_point', proposal.dilemma,
          'Источник: «' + setup.source.quote +
          '». Это предложенная трактовка, ещё не канон.',
          [
            decision('accept_offer', proposal.acceptIntent, 'accept_path',
              adds: [accepted], event: setup.id,
              route: StoryRoute.canonicalProposal),
            decision('refuse_offer', proposal.refuseIntent, 'search_path',
              adds: [declined]),
          ],
          chapter: startChapter, event: setup.id,
          route: StoryRoute.canonicalProposal,
        ),
        situation('accept_path', proposal.followupGoal,
          'Возможное последствие: «' + outcome.source.quote +
          '». Требуется независимая проверка причинности.',
          [
            decision('honor_condition', proposal.finishOriginalIntent,
              'original_ending', requires: [accepted],
              forbids: [declined], adds: [originalDone],
              event: outcome.id, route: StoryRoute.canonicalProposal),
          ],
          chapter: outcomeChapter, event: outcome.id,
          route: StoryRoute.canonicalProposal,
        ),
        situation('search_path', proposal.alternativeSearchGoal,
          'Новая сцена адаптации: отказ не создаёт обязательства.',
          [
            decision('explore', proposal.searchIntent, 'discovery_path',
              requires: [declined], forbids: [accepted],
              adds: [discovered]),
          ],
          chapter: startChapter,
        ),
        situation('discovery_path', proposal.alternativeDiscovery,
          'Альтернативное продолжение требует отдельного решения.',
          [
            decision('use_discovery', proposal.useDiscoveryIntent,
              'alternate_resolution', requires: [declined, discovered],
              forbids: [accepted], adds: [alternativeDone]),
          ],
          chapter: startChapter,
        ),
        situation('alternate_resolution', proposal.alternativeEnding,
          'Последствия адаптации нельзя выдавать за исходный текст.',
          [
            decision('end_alternative', 'Завершить альтернативный маршрут',
              'alternate_ending', requires: [declined, alternativeDone],
              forbids: [accepted]),
          ],
          chapter: startChapter,
        ),
        situation('original_ending', proposal.originalEnding,
          'Концовка лишь предложена: смысл требует проверки.',
          const [],
          chapter: outcomeChapter, event: outcome.id,
          route: StoryRoute.canonicalProposal, terminal: true,
        ),
        situation('alternate_ending', proposal.alternativeEnding,
          'Концовка адаптации, которой могло не быть в оригинале.',
          const [], chapter: startChapter, terminal: true,
        ),
      ],
    );
    final preflight = draft.validate(book);
    if (!preflight.isStructurallySound ||
        !preflight.branchChangesState ||
        preflight.terminalSituations != 2) {
      throw const FormatException('Предложенные ветки не прошли проверку.');
    }
    return draft;
  }
}
