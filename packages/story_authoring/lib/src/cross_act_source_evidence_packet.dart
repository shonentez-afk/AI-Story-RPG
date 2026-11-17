import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// M2h7c6a: a bounded, independently replayed TWO-PATH evidence packet.
///
/// Unlike a single-scene preview, this is a linked view of two COMPLETE
/// reachable story paths, including verified source excerpts and real
/// before/after flags for each decision. It does NOT invent character
/// motives, book chronology, item ownership, literary causation or canon.
///
/// This stage prepares exact data for a future separately consented GLM
/// cross-act critique. It never sends the packet or writes gameplay state.
class CrossActSourceEvidencePacket {
  CrossActSourceEvidencePacket._({
    required this.sourceFingerprint,
    required this.planSha256,
    required this.approvalDigest,
    required this.sentContext,
    required this.referencedSourceEvents,
    required this.crossedChapters,
    required this.inputBytes,
  });

  static const format = 'ai_story_crossact_evidence_packet_m2h7c6a_v1';
  static const maxPaths = 2;
  static const maxChoicesPerPath = 24;
  static const maxSourceExcerpts = 16;
  static const maxUserBytes = 24 * 1024;

  final String sourceFingerprint;
  final String planSha256;
  final String approvalDigest;
  final Map<String, Object?> sentContext;
  final int referencedSourceEvents, crossedChapters, inputBytes;

  bool get sourceQuotesVerified => referencedSourceEvents >= 2;
  bool get establishesWorldTime => false;
  bool get provesBookCausation => false;
  bool get provesActorKnowledge => false;
  bool get establishesLiteraryCanon => false;
  bool get mayAutomaticallyModifyGame => false;

  /// Both paths must start at the true game entry and finish at reachable
  /// terminal scenes. Each supplied decision ID must be legal in the
  /// *actual* state before that choice; no model-proposed transitions.
  static CrossActSourceEvidencePacket fromCompletePaths({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required List<List<String>> choicePaths,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        plan.title != book.title ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        !plan.validate(book).isStructurallySound ||
        choicePaths.length != maxPaths ||
        choicePaths.any((x) =>
            x.isEmpty || x.length > maxChoicesPerPath)) {
      throw const FormatException(
          'Нужны две законченные ветви этой проверенной редакции.');
    }

    final scenes = {for (final s in plan.situations) s.id: s};
    final events = {for (final event in book.events) event.id: event};
    final excerpts = <String, Map<String, Object?>>{};
    final runs = <Map<String, Object?>>[];
    final visitedChapterIds = <int>{};

    void recordSource(String? sourceEventId, int sceneChapter) {
      if (sourceEventId == null) return;
      final event = events[sourceEventId];
      if (event == null) {
        throw const FormatException(
            'Путь ссылается на неизвестный исходный фрагмент.');
      }
      event.source.validate(index);
      if (event.source.chapterIndex != sceneChapter) {
        throw const FormatException(
            'Исходная цитата привязана к чужой главе.');
      }
      excerpts.putIfAbsent(sourceEventId, () => {
        'event_id': sourceEventId,
        'chapter_index': event.source.chapterIndex,
        'block_index': event.source.blockIndex,
        'start_utf16': event.source.startUtf16,
        'end_utf16': event.source.endUtf16,
        'quote': event.source.quote,
        'evidence_status': 'EXACT_WORDS_ONLY_NOT_CAUSAL_PROOF',
      });
      if (excerpts.length > maxSourceExcerpts) {
        throw const FormatException('Слишком много исходных фрагментов.');
      }
    }

    for (var branch = 0; branch < choicePaths.length; branch++) {
      final path = choicePaths[branch];
      var sceneId = plan.entrySituationId;
      final flags = plan.initialFlags.toSet();
      final steps = <Map<String, Object?>>[];
      final chaptersInPath = <int>{};
      for (final choiceId in path) {
        final scene = scenes[sceneId];
        if (scene == null || scene.terminal) {
          throw const FormatException(
              'Путь продолжен после завершения или ведёт в пустоту.');
        }
        final matches = scene.decisions.where(
            (choice) => choice.id == choiceId).toList();
        if (matches.length != 1) {
          throw const FormatException(
              'Выбор недоступен в указанной ситуации.');
        }
        final choice = matches.single;
        if (!flags.containsAll(choice.requires) ||
            choice.forbids.any(flags.contains)) {
          throw const FormatException(
              'Решение запрещено ранее полученным состоянием.');
        }
        recordSource(scene.sourceEventId, scene.chapterIndex);
        recordSource(choice.sourceEventId, scene.chapterIndex);
        chaptersInPath.add(scene.chapterIndex);
        visitedChapterIds.add(scene.chapterIndex);
        final before = flags.toList()..sort();
        flags.removeAll(choice.removes);
        flags.addAll(choice.adds);
        final after = flags.toList()..sort();
        steps.add({
          'scene_id': scene.id,
          'chapter_index': scene.chapterIndex,
          'route': scene.route.name,
          'goal': scene.goal,
          'source_event_id': scene.sourceEventId,
          'choice_id': choice.id,
          'choice_intent': choice.intent,
          'decision_source_event_id': choice.sourceEventId,
          'requires': choice.requires,
          'forbids': choice.forbids,
          'adds': choice.adds,
          'removes': choice.removes,
          'flags_before': before,
          'flags_after': after,
          'next_scene_id': choice.nextSituationId,
        });
        sceneId = choice.nextSituationId;
      }
      final terminal = scenes[sceneId];
      if (terminal == null || !terminal.terminal) {
        throw const FormatException(
            'Переданная ветвь не закончена.');
      }
      recordSource(terminal.sourceEventId, terminal.chapterIndex);
      chaptersInPath.add(terminal.chapterIndex);
      visitedChapterIds.add(terminal.chapterIndex);
      if (chaptersInPath.length < 2) {
        throw const FormatException(
            'Нет проверенного перехода между главами.');
      }
      final endFlags = flags.toList()..sort();
      runs.add({
        'route_id': 'path_' + (branch + 1).toString(),
        'entry_scene_id': plan.entrySituationId,
        'steps': steps,
        'terminal_scene_id': terminal.id,
        'terminal_flags': endFlags,
      });
    }
    if (jsonEncode(choicePaths[0]) == jsonEncode(choicePaths[1]) ||
        excerpts.length < 2 ||
        visitedChapterIds.length < 2) {
      throw const FormatException(
          'Нужны две разные ветви с буквальными фрагментами '
          'из нескольких глав.');
    }

    final userContext = <String, Object?>{
      'review_kind': 'POSSIBLE_CROSS_ACT_CONTRADICTIONS_ONLY',
      'source_excerpt_limit': maxSourceExcerpts,
      'source_evidence': excerpts.values.toList(growable: false),
      'complete_game_paths': runs,
      'source_chapter_order_is_world_time': false,
      'npc_knowledge_unless_flag_granted': 'UNKNOWN',
      'book_causality': 'NOT_PROVEN',
      'literary_canon': 'NOT_VERIFIED',
    };
    final serialized = jsonEncode(userContext);
    final size = utf8.encode(serialized).length;
    if (size > maxUserBytes) {
      throw const FormatException('Пакет двух ветвей слишком велик.');
    }
    final planHash =
        sha256.convert(utf8.encode(plan.encode())).toString();
    final consent = sha256.convert(utf8.encode(jsonEncode({
      'format': format,
      'source_fingerprint': index.sourceFingerprint,
      'plan_sha256': planHash,
      'sent_context': userContext,
    }))).toString();
    return CrossActSourceEvidencePacket._(
      sourceFingerprint: index.sourceFingerprint,
      planSha256: planHash,
      approvalDigest: consent,
      sentContext: userContext,
      referencedSourceEvents: excerpts.length,
      crossedChapters: visitedChapterIds.length,
      inputBytes: size,
    );
  }
}
