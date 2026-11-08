import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';

/// A source-proven opportunity in an EXISTING private source encounter.
///
/// The character's ID is editor-verified and its mention overlaps the exact
/// quotation that the user has chosen to include in the trial. This evidence
/// proves the words exist, NOT that a literary hero knows any secret.
class ReviewedHeroSourceOpportunity {
  const ReviewedHeroSourceOpportunity({
    required this.observeSceneId,
    required this.recallSceneId,
    required this.eventId,
    required this.evidenceId,
    required this.observeBaseChoiceId,
    required this.recallBaseChoiceId,
  });

  final String observeSceneId, recallSceneId;
  final String eventId, evidenceId;
  final String observeBaseChoiceId, recallBaseChoiceId;
}

/// Opt-in ROLE -> OBSERVE -> RECALL with real story_core conditions, not
/// another game engine, story format, pseudo-knowledge or NPC dialogue path.
///
/// The initial 'player_is_npc_<permanent_id>' flag is granted ONLY by the
/// separately verified protagonist selector. In the first encounter an extra
/// choice requires this flag and records a fact about PLAYER ACTION only:
/// 'hero_source_observed'. At the next source encounter a recall choice
/// requires BOTH flags. A free hero or someone who skipped the observation
/// cannot use either permission. Default pass/examine routes stay available.
/// Ordinary NPC secrets and literary facts remain unmodified.
class ReviewedHeroSourceAction {
  const ReviewedHeroSourceAction._();

  static const observedFlag = 'hero_source_observed';

  static String _observeId(String sceneId) => '${sceneId}_hero_observe';
  static String _recallId(String sceneId) => '${sceneId}_hero_recall';

  static StoryDecision? _pass(StorySituation scene) {
    for (final d in scene.decisions) {
      if (d.id.contains('_pass_source') &&
          d.requires.isEmpty && d.forbids.isEmpty &&
          d.adds.isEmpty && d.removes.isEmpty) {
        return d;
      }
    }
    return null;
  }

  /// Never accepts a generated name/role label as evidence of identity.
  /// Verify against the ORIGINAL bytes/offsets of the loaded book.
  static bool _mentionOverlaps(ReviewedHeroRole role,
      NarrativeCitation citation, BookSourceIndex index,
      {String? sourceEvidenceId}) {
    citation.validate(index);
    for (final mention in role.confirmedMentions) {
      if (sourceEvidenceId != null && mention.id != sourceEvidenceId) continue;
      mention.validate(index);
      if (mention.sourceFingerprint == index.sourceFingerprint &&
          mention.kind == EvidenceKind.character &&
          mention.status == EvidenceStatus.confirmed &&
          mention.chunkId == citation.chunkId &&
          mention.startUtf16 < citation.endUtf16 &&
          citation.startUtf16 < mention.endUtf16) {
        return true;
      }
    }
    return false;
  }

  /// An opportunity exists ONLY for TWO successive source-locked encounter
  /// scenes, the first containing an independently checked literal mention
  /// of the selected character. Its reviewer already saw both exact quotes.
  ///
  /// A single selected event or unrelated same-name text in another chapter
  /// cannot create a source-proven role action.
  static ReviewedHeroSourceOpportunity? find({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required ReviewedHeroRole role,
  }) {
    if (index.sourceFingerprint != book.sourceFingerprint ||
        role.sourceFingerprint != index.sourceFingerprint ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        !plan.initialFlags.contains(role.playerIdentityFlag)) {
      throw const FormatException(
          'Ролевая игровая возможность относится к другой книге или герою.');
    }
    final events = {for (final event in book.events) event.id: event};
    final scenes = {for (final scene in plan.situations) scene.id: scene};
    for (final scene in plan.situations) {
      if (!scene.id.contains('_source_encounter') ||
          scene.sourceEventId == null ||
          scene.decisions.length >= 16) continue;
      final event = events[scene.sourceEventId];
      if (event == null) continue;
      final base = _pass(scene);
      if (base == null) continue;
      final next = scenes[base.nextSituationId];
      if (next == null ||
          !next.id.contains('_source_encounter') ||
          next.decisions.length >= 16) continue;
      final followup = _pass(next);
      if (followup == null) continue;
      for (final mention in role.confirmedMentions) {
        if (_mentionOverlaps(role, event.source, index,
            sourceEvidenceId: mention.id)) {
          return ReviewedHeroSourceOpportunity(
            observeSceneId: scene.id,
            recallSceneId: next.id,
            eventId: event.id,
            evidenceId: mention.id,
            observeBaseChoiceId: base.id,
            recallBaseChoiceId: followup.id,
          );
        }
      }
    }
    return null;
  }

  /// Exact same overlay is used for the displayed/AI-consented plan and the
  /// final compiler. A user must opt in; an unreviewed identity or missing
  /// second quote cannot silently create executable story choices.
  static StoryPlan attach({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required ReviewedHeroRole role,
    required bool explicitlyConfirmedPrivateGameFiction,
  }) {
    if (!explicitlyConfirmedPrivateGameFiction ||
        plan.flags.contains(observedFlag) ||
        plan.flags.length >= 32) {
      throw const FormatException(
          'Ролевое действие не подтверждено или превышен лимит состояний.');
    }
    final opportunity = find(
        index: index, book: book, plan: plan, role: role);
    if (opportunity == null) {
      throw const FormatException(
          'Нужны два последовательных выбранных события, первое с '
          'дословным подтверждённым упоминанием героя.');
    }
    if (plan.situations.any((scene) => scene.decisions.any((d) =>
        d.id == _observeId(opportunity.observeSceneId) ||
        d.id == _recallId(opportunity.recallSceneId) ||
        d.adds.contains(observedFlag) ||
        d.removes.contains(observedFlag)))) {
      throw const FormatException('Ролевая игровая память уже занята.');
    }
    final output = <StorySituation>[];
    for (final scene in plan.situations) {
      final additions = <StoryDecision>[];
      if (scene.id == opportunity.observeSceneId) {
        final pass = scene.decisions.singleWhere(
            (d) => d.id == opportunity.observeBaseChoiceId);
        additions.add(StoryDecision(
          id: _observeId(scene.id),
          intent: 'Отметить своё подтверждённое упоминание в цитате',
          nextSituationId: pass.nextSituationId,
          sourceEventId: opportunity.eventId,
          route: StoryRoute.adaptationFiction,
          requires: [role.playerIdentityFlag],
          adds: [observedFlag],
        ));
      }
      if (scene.id == opportunity.recallSceneId) {
        final pass = scene.decisions.singleWhere(
            (d) => d.id == opportunity.recallBaseChoiceId);
        additions.add(StoryDecision(
          id: _recallId(scene.id),
          intent: 'Использовать выполненную мной проверку цитаты',
          nextSituationId: pass.nextSituationId,
          route: StoryRoute.adaptationFiction,
          requires: [role.playerIdentityFlag, observedFlag],
        ));
      }
      output.add(StorySituation(
        id: scene.id,
        goal: scene.goal,
        conflict: scene.conflict,
        chapterIndex: scene.chapterIndex,
        sourceEventId: scene.sourceEventId,
        route: scene.route,
        terminal: scene.terminal,
        decisions: [...scene.decisions, ...additions],
      ));
    }
    final result = StoryPlan(
      sourceFingerprint: plan.sourceFingerprint,
      title: plan.title,
      entrySituationId: plan.entrySituationId,
      flags: [...plan.flags, observedFlag],
      initialFlags: plan.initialFlags,
      situations: output,
    );
    final audit = result.validate(book);
    if (!audit.isStructurallySound ||
        audit.terminalSituations < 2 ||
        !audit.branchChangesState ||
        audit.reachableSituations != plan.situations.length) {
      throw const FormatException(
          'Ролевое действие нарушает проверенный маршрут.');
    }
    return result;
  }
}
