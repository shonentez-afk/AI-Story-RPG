import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';

/// An explicitly approved PRIVATE game-fantasy meeting with an EXISTING,
/// source-reviewed permanent NPC. Only the exact character mention and
/// book excerpts are source truth: the spoken lines are authored fiction.
///
/// Two successive source encounters share the existing story_core runtime:
/// talk -> committed NPC knowledge/memory -> conditional follow-up dialogue.
class BookwideNpcArc {
  BookwideNpcArc._({
    required this.role,
    required this.firstSceneId, required this.secondSceneId,
    required this.firstEventId, required this.secondEventId,
    required this.firstQuoteSha256, required this.secondQuoteSha256,
    required this.firstPassId, required this.secondPassId,
    required this.playerLine, required this.npcLine,
  });

  static const contactFlag = 'bookwide_npc_contact';
  static const factId = 'bookwide_npc_contact_fact';
  static const memoryId = 'bookwide_npc_witnessed_contact';
  final ReviewedHeroRole role;
  final String firstSceneId, secondSceneId, firstEventId, secondEventId;
  final String firstQuoteSha256, secondQuoteSha256, firstPassId, secondPassId;
  final String playerLine, npcLine;
  String get listenChoiceId => '${firstSceneId}_npc_listen';
  String get replyChoiceId => '${secondSceneId}_npc_reply';
  List<String> get requiredChoiceIds => [listenChoiceId, replyChoiceId];

  static BookwideNpcArc? review({
    required BookSourceIndex index, required NarrativeBookModel book,
    required StoryPlan plan, required ReviewedHeroRole role,
    required bool privateFictionConfirmed,
    required String playerLine, required String npcLine,
    bool expanded = false,
  }) {
    if (!privateFictionConfirmed ||
        index.sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        role.sourceFingerprint != index.sourceFingerprint ||
        !CharacterId.isValidNpc(role.characterId) ||
        role.confirmedMentions.isEmpty || plan.flags.contains(contactFlag) ||
        plan.flags.length >= (expanded ? 64 : 32)) {
      throw const FormatException('Не подтверждены NPC, книга или игровая встреча.');
    }
    if (!RegExp(r'^[А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}$',
            unicode: true).hasMatch(role.displayName) ||
        playerLine.isEmpty || npcLine.isEmpty ||
        playerLine != playerLine.trim() || npcLine != npcLine.trim() ||
        playerLine.length > 250 || npcLine.length > 250 ||
        playerLine.contains(RegExp(r'[\x00-\x1f\x7f«»]')) ||
        npcLine.contains(RegExp(r'[\x00-\x1f\x7f«»]'))) {
      throw const FormatException('Нужны две явно проверенные игровые реплики.');
    }
    final byEvent = {for (final e in book.events) e.id: e};
    final byScene = {for (final s in plan.situations) s.id: s};
    StoryDecision? pass(StorySituation s) {
      for (final d in s.decisions) {
        if (d.id.contains('_pass_source') &&
            d.requires.isEmpty && d.forbids.isEmpty &&
            d.adds.isEmpty && d.removes.isEmpty) return d;
      }
      return null;
    }

    for (final first in plan.situations) {
      if (!first.id.contains('_source_encounter') ||
          first.sourceEventId == null || first.decisions.length >= 16) continue;
      final event = byEvent[first.sourceEventId];
      final advance = pass(first);
      if (event == null || advance == null) continue;
      final second = byScene[advance.nextSituationId];
      if (second == null ||
          !second.id.contains('_source_encounter') ||
          second.sourceEventId == null ||
          second.decisions.length >= 16) continue;
      final again = pass(second);
      final nextEvent = byEvent[second.sourceEventId];
      if (again == null || nextEvent == null ||
          event.source.chapterIndex > nextEvent.source.chapterIndex) continue;
      event.source.validate(index);
      nextEvent.source.validate(index);
      final shown = role.confirmedMentions.any((m) {
        m.validate(index);
        return m.kind == EvidenceKind.character &&
            m.status == EvidenceStatus.confirmed &&
            m.chunkId == event.source.chunkId &&
            m.startUtf16 < event.source.endUtf16 &&
            event.source.startUtf16 < m.endUtf16;
      });
      if (!shown) continue;
      return BookwideNpcArc._(
        role: role, firstSceneId: first.id, secondSceneId: second.id,
        firstEventId: event.id, secondEventId: nextEvent.id,
        firstQuoteSha256:
            sha256.convert(utf8.encode(event.source.quote)).toString(),
        secondQuoteSha256:
            sha256.convert(utf8.encode(nextEvent.source.quote)).toString(),
        firstPassId: advance.id, secondPassId: again.id,
        playerLine: playerLine, npcLine: npcLine,
      );
    }
    return null;
  }

  StoryPlan attach(StoryPlan plan, NarrativeBookModel book,
      {bool expanded = false}) {
    if (role.sourceFingerprint != plan.sourceFingerprint ||
        plan.flags.length >= 32 || plan.flags.contains(contactFlag)) {
      throw const FormatException('NPC-версия сценария изменилась.');
    }
    final result = StoryPlan(
      sourceFingerprint: plan.sourceFingerprint, title: plan.title,
      entrySituationId: plan.entrySituationId,
      flags: [...plan.flags, contactFlag], initialFlags: plan.initialFlags,
      situations: [
        for (final scene in plan.situations)
          StorySituation(
            id: scene.id, goal: scene.goal, conflict: scene.conflict,
            chapterIndex: scene.chapterIndex, sourceEventId: scene.sourceEventId,
            route: scene.route, terminal: scene.terminal,
            decisions: [
              ...scene.decisions,
              if (scene.id == firstSceneId)
                StoryDecision(
                  id: listenChoiceId,
                  intent: 'Поговорить с персонажем (частная игра)',
                  nextSituationId: scene.decisions.singleWhere(
                    (d) => d.id == firstPassId).nextSituationId,
                  sourceEventId: firstEventId,
                  route: StoryRoute.adaptationFiction,
                  adds: [contactFlag],
                ),
              if (scene.id == secondSceneId)
                StoryDecision(
                  id: replyChoiceId,
                  intent: 'Продолжить разговор, если персонаж помнит встречу',
                  nextSituationId: scene.decisions.singleWhere(
                    (d) => d.id == secondPassId).nextSituationId,
                  sourceEventId: secondEventId,
                  route: StoryRoute.adaptationFiction,
                  requires: [contactFlag],
                ),
            ],
          ),
      ],
    );
    final audit = result.validate(book, expanded: expanded);
    if (!audit.isStructurallySound || !audit.branchChangesState ||
        audit.terminalSituations != 2) {
      throw const FormatException('Разговор NPC нарушает игровые маршруты.');
    }
    return result;
  }

  Map<String, dynamic> get writerReview => {
    'actor_id': role.characterId,
    'display_name': role.displayName,
    'first_scene_id': firstSceneId,
    'first_choice_id': listenChoiceId,
    'second_scene_id': secondSceneId,
    'second_choice_id': replyChoiceId,
    'first_quote_sha256': firstQuoteSha256,
    'second_quote_sha256': secondQuoteSha256,
    'player_line': playerLine,
    'npc_line': npcLine,
    'user_confirmed': true,
  };
}
