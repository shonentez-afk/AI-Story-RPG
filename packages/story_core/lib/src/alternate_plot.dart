import 'blueprint.dart';
import 'codec.dart';
import 'engine.dart';
import 'freeform_action.dart';

/// One executable noncanonical beat proposed by a client/model. The words
/// remain fiction, while objective, participants and outstanding obligations
/// are checked by the same immutable story_core event chain on every client.
final class AlternateStoryBeat {
  const AlternateStoryBeat._({
    required this.beatId, required this.threadId, required this.previousBeatId,
    required this.leadActorId, required this.objectiveId,
    required this.participantActorIds, required this.openedObligationIds,
    required this.resolvedObligationIds, required this.route,
  });

  static const format = 'ai_story_alternate_beat_v1';
  static final _gm = RegExp(r'^gm_[a-z0-9_]{1,59}$');
  final String beatId, threadId, leadActorId, objectiveId, route;
  final String? previousBeatId;
  final List<String> participantActorIds;
  final List<String> openedObligationIds;
  final List<String> resolvedObligationIds;

  factory AlternateStoryBeat.fromJson(Object? raw) {
    final data = jsonObject(raw, 'alternate_beat');
    const fields = {
      'format', 'beat_id', 'thread_id', 'previous_beat_id',
      'lead_actor_id', 'objective_id', 'participant_actor_ids',
      'opened_obligation_ids', 'resolved_obligation_ids', 'route',
    };
    assertFields(data, 'alternate_beat', fields, fields);
    if (data['format'] != format) {
      throw const FormatException('Unrecognized alternative scene plan');
    }
    String gm(String key) {
      final val = data[key];
      if (val is! String || !_gm.hasMatch(val)) {
        throw FormatException('Invalid alternate beat $key');
      }
      return val;
    }
    List<String> ids(String key, int maximum) {
      final list = jsonArray(data[key], key);
      if (list.length > maximum || list.any((value) =>
          value is! String || value.isEmpty ||
          value.runes.length > 64) ||
          list.toSet().length != list.length) {
        throw FormatException('Invalid alternate beat $key');
      }
      return List.unmodifiable(list.cast<String>());
    }
    final prev = data['previous_beat_id'];
    if (prev != null && (prev is! String || !_gm.hasMatch(prev))) {
      throw const FormatException('Invalid previous alternative beat');
    }
    final lead = jsonId(data['lead_actor_id'], 'alternate lead');
    final people = ids('participant_actor_ids', 8);
    final opened = ids('opened_obligation_ids', 4);
    final resolved = ids('resolved_obligation_ids', 4);
    if (!people.contains(lead) ||
        opened.any((id) => !_gm.hasMatch(id)) ||
        resolved.any((id) => !_gm.hasMatch(id)) ||
        opened.toSet().intersection(resolved.toSet()).isNotEmpty ||
        !{'investigate', 'negotiate', 'protect', 'confront',
          'recover', 'resolve', 'travel'}.contains(data['route'])) {
      throw const FormatException('Invalid alternate route or obligations');
    }
    return AlternateStoryBeat._(
      beatId: gm('beat_id'), threadId: gm('thread_id'),
      previousBeatId: prev as String?,
      leadActorId: lead, objectiveId: gm('objective_id'),
      participantActorIds: people,
      openedObligationIds: opened, resolvedObligationIds: resolved,
      route: data['route'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'beat_id': beatId,
    'thread_id': threadId,
    'previous_beat_id': previousBeatId,
    'lead_actor_id': leadActorId,
    'objective_id': objectiveId,
    'participant_actor_ids': participantActorIds,
    'opened_obligation_ids': openedObligationIds,
    'resolved_obligation_ids': resolvedObligationIds,
    'route': route,
  };
}

/// The alternative story plan is replayed from authenticated WorldEvents,
/// never stored as a second mutable save or guessed from AI dialogue.
final class AlternatePlotSnapshot {
  const AlternatePlotSnapshot({
    required this.threadId, required this.lastBeatId,
    required this.lastObjectiveId, required this.lastLeadActorId,
    required this.beatCount, required this.openObligations,
  });
  final String? threadId, lastBeatId, lastObjectiveId, lastLeadActorId;
  final int beatCount;
  final List<String> openObligations;

  bool get active => lastBeatId != null;

  Map<String, Object?> toJson() => {
    'thread_id': threadId,
    'last_beat_id': lastBeatId,
    'last_objective_id': lastObjectiveId,
    'last_lead_actor_id': lastLeadActorId,
    'beat_count': beatCount,
    'open_obligation_ids': openObligations,
    'next_directions': [
      if (openObligations.isNotEmpty)
        for (final obligation in openObligations.take(4))
          {'kind': 'resolve_obligation', 'obligation_id': obligation},
      if (openObligations.isEmpty)
        {'kind': 'develop_objective',
         'objective_id': lastObjectiveId ?? 'gm_new_goal'},
    ],
  };
}

abstract final class AlternatePlotLedger {
  /// Recompute history once, enforcing linear continuation of each new beat.
  /// Legacy actions without a beat are still readable; once structured
  /// planning begins, every further freeform event must continue that plan.
  static AlternatePlotSnapshot replay(Iterable<WorldEvent> events) {
    String? thread, last, objective, lead;
    final created = <String>{};
    final open = <String>{};
    final beats = <String>{};
    var count = 0;
    for (final event in events) {
      final draft = event.freeform;
      if (draft == null) continue;
      final beat = draft.plotBeat;
      if (beat == null) {
        if (count != 0) {
          throw const FormatException('Alternative history lost its plan');
        }
        continue;
      }
      if (count >= 512 || !beats.add(beat.beatId) ||
          (count == 0 && beat.previousBeatId != null) ||
          (count != 0 &&
              (beat.previousBeatId != last || beat.threadId != thread))) {
        throw const FormatException('Disconnected alternative story');
      }
      if (beat.openedObligationIds.any(created.contains) ||
          !open.containsAll(beat.resolvedObligationIds)) {
        throw const FormatException('Repeated or imaginary plot obligation');
      }
      open.removeAll(beat.resolvedObligationIds);
      open.addAll(beat.openedObligationIds);
      created.addAll(beat.openedObligationIds);
      thread = beat.threadId;
      last = beat.beatId;
      objective = beat.objectiveId;
      lead = beat.leadActorId;
      count++;
      if (draft.plotIntent == 'end' && open.isNotEmpty) {
        throw const FormatException('Unresolved ending obligations');
      }
    }
    return AlternatePlotSnapshot(
      threadId: thread, lastBeatId: last, lastObjectiveId: objective,
      lastLeadActorId: lead, beatCount: count,
      openObligations: List.unmodifiable(open.toList()..sort()),
    );
  }

  /// Read-only structural permission check; a model cannot make future cast
  /// visible or skip an unresolved promise merely by writing persuasive prose.
  static String? checkProposal({
    required AlternateStoryBeat? beat,
    required AlternatePlotSnapshot previous,
    required StoryBlueprint blueprint,
    required String sceneId,
    required bool diverged,
    required String plotIntent,
    required Set<String> encounteredActorIds,
    required String? currentLeadGoal,
    required String? offeredLeadGoal,
  }) {
    if (beat == null) {
      return previous.active ? 'alternate_plot_plan_required' : null;
    }
    if (!diverged) return 'alternate_plan_requires_alter_fate';
    if (previous.beatCount >= 512) return 'alternate_plot_budget_exceeded';
    if ((previous.active &&
            (previous.threadId != beat.threadId ||
             previous.lastBeatId != beat.previousBeatId)) ||
        (!previous.active && beat.previousBeatId != null)) {
      return 'alternate_plot_wrong_predecessor';
    }
    if (beat.participantActorIds.any((id) =>
            !blueprint.actors.contains(id) ||
            (id != 'player' && !encounteredActorIds.contains(id))) ||
        !blueprint.actors.contains(beat.leadActorId)) {
      return 'alternate_plot_unknown_participant';
    }
    if (beat.leadActorId != 'player' &&
        currentLeadGoal != beat.objectiveId &&
        offeredLeadGoal != beat.objectiveId) {
      return 'alternate_plot_npc_goal_unjustified';
    }
    if (!previous.openObligations.toSet()
            .containsAll(beat.resolvedObligationIds) ||
        beat.openedObligationIds.any(previous.openObligations.contains)) {
      return 'alternate_plot_unverified_obligation';
    }
    final remaining = previous.openObligations.toSet()
      ..removeAll(beat.resolvedObligationIds)
      ..addAll(beat.openedObligationIds);
    if (plotIntent == 'end' && remaining.isNotEmpty) {
      return 'alternate_plot_unfinished_obligations';
    }
    return null;
  }
}
