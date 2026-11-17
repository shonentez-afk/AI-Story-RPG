import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'story_plan.dart';

/// A bounded, LOCAL inventory of all reachable StoryPlan states and all
/// source events that the *reachable* game graph actually uses.
///
/// This is evidence for an independent literary reviewer, NOT that review.
/// No network calls, BookWorld writes, campaign mutations or literary CANON.
class WholeStoryLiteraryEvidenceManifest {
  WholeStoryLiteraryEvidenceManifest._({
    required this.sourceFingerprint,
    required this.planSha256,
    required this.approvalDigest,
    required this.sourceEventsTotal,
    required this.reachableSourceEvents,
    required this.uncoveredSourceEvents,
    required this.reachableStates,
    required this.reachableTransitions,
    required this.reachableEndings,
    required this.disabledDecisions,
    required this.claimsWithVerifiedQuotes,
    required this.claimsWithoutVerifiedQuotes,
    required String encoded,
  }) : _encoded = encoded;

  static const format = 'ai_story_whole_literary_evidence_m2h8g1a_v1';
  static const maxStates = 2500;
  static const maxTransitions = 10000;
  static const maxBytes = 4 * 1024 * 1024;

  final String sourceFingerprint, planSha256, approvalDigest;
  final int sourceEventsTotal, reachableSourceEvents, uncoveredSourceEvents;
  final int reachableStates, reachableTransitions, reachableEndings;
  final int disabledDecisions, claimsWithVerifiedQuotes;
  final int claimsWithoutVerifiedQuotes;
  final String _encoded;

  bool get provesBookCausality => false;
  bool get verifiesCharacterMotivation => false;
  bool get verifiesWorldChronology => false;
  bool get verifiesLiteraryCanon => false;
  bool get mayChangeBookWorld => false;
  bool get maySendToCloudWithoutSeparateConsent => false;

  /// A detached copy: callers cannot alter the SHA-locked stored report.
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(_encoded) as Map);
  String encode() => _encoded;

  static WholeStoryLiteraryEvidenceManifest build({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    SourceEvidenceGraph? claimEvidence,
  }) {
    if (index.sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        index.title != book.title || plan.title != book.title ||
        !book.analysisComplete ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        !plan.validate(book).isStructurallySound) {
      throw const FormatException(
          'Для проверки всей истории нужна одна полностью индексированная '
          'книга и формально допустимый игровой план.');
    }

    final events = <String, NarrativeEvent>{};
    for (final event in book.events) {
      if (events.containsKey(event.id)) {
        throw const FormatException('Повторный ID исходного события.');
      }
      event.source.validate(index);
      events[event.id] = event;
    }
    final scenes = {for (final s in plan.situations) s.id: s};
    final everyDecision = {
      for (final s in plan.situations)
        for (final d in s.decisions) d.id,
    };
    final usedDecisions = <String>{};
    final usedEvents = <String>{};
    final coveredChapters = <int>{};

    void reference(String? eventId) {
      if (eventId == null) return;
      final event = events[eventId];
      if (event == null) {
        throw const FormatException('Неизвестное исходное событие.');
      }
      usedEvents.add(eventId);
      coveredChapters.add(event.source.chapterIndex);
    }

    // Claims are model proposals, even when the exact cited words were
    // verified and a user has reviewed a candidate. Missing evidence is NOT
    // silently upgraded to a narrator's statement.
    if (book.claims.isNotEmpty &&
        (claimEvidence == null ||
         claimEvidence.sourceFingerprint != index.sourceFingerprint)) {
      throw const FormatException(
          'Для литературных утверждений требуется исходный граф цитат.');
    }
    final evidenceById = {
      for (final record in claimEvidence?.records ?? <SourceEvidence>[])
        record.id: record,
    };
    final claimSummaries = <Map<String, Object?>>[];
    var backedClaims = 0;
    var missingClaims = 0;
    for (final claim in book.claims) {
      if (claim.citationIds.isEmpty ||
          claim.citationIds.toSet().length != claim.citationIds.length) {
        throw const FormatException('У утверждения нет точных источников.');
      }
      var backed = true;
      for (final citationId in claim.citationIds) {
        final record = evidenceById[citationId];
        if (record == null || record.status == EvidenceStatus.rejected) {
          backed = false;
          break;
        }
        record.validate(index);
      }
      if (backed) {
        backedClaims++;
      } else {
        missingClaims++;
      }
      final perspective = switch (claim.voice) {
        AssertionVoice.narratorCandidate =>
          'NARRATOR_PROPOSAL_NOT_WORLD_TRUTH',
        AssertionVoice.reported =>
          'REPORTED_SPEECH_NOT_WORLD_TRUTH',
        AssertionVoice.uncertain =>
          'UNCERTAIN_INTERPRETATION',
      };
      claimSummaries.add({
        'claim_id': claim.id,
        'source_evidence_ids': claim.citationIds,
        'quote_spans_revalidated': backed,
        'voice': perspective,
        'polarity': claim.polarity.name,
        'time': claim.time.name,
        'world_time_inferred': false,
        'is_canon': false,
      });
    }

    // Breadth-first replay retains the shortest known witness for each
    // scene+flags state; no chapter order is used as fictional world time.
    final sortedFlags = plan.flags.toList()..sort();
    final bitFor = <String, int>{
      for (var i = 0; i < sortedFlags.length; i++)
        sortedFlags[i]: 1 << i,
    };
    int mask(Iterable<String> flags) =>
        flags.fold<int>(0, (m, flag) => m | bitFor[flag]!);
    List<String> active(int bits) => [
      for (final flag in sortedFlags)
        if ((bits & bitFor[flag]!) != 0) flag,
    ];
    final queue = <(String, int, List<String>)>[
      (plan.entrySituationId, mask(plan.initialFlags), <String>[]),
    ];
    final seen = <String>{
      plan.entrySituationId + ':' + mask(plan.initialFlags).toString(),
    };
    final transitions = <Map<String, Object?>>[];
    final terminalPaths = <String, Map<String, Object?>>{};

    for (var i = 0; i < queue.length; i++) {
      if (queue.length > maxStates) {
        throw const FormatException(
            'Слишком много состояний для литературного аудита.');
      }
      final node = queue[i];
      final scene = scenes[node.$1]!;
      reference(scene.sourceEventId);
      if (scene.terminal) {
        terminalPaths.putIfAbsent(scene.id, () => {
          'terminal_scene_id': scene.id,
          'choice_ids': node.$3,
          'terminal_flags': active(node.$2),
          'literary_canon': 'NOT_VERIFIED',
        });
        continue;
      }
      for (final choice in scene.decisions) {
        final requires = mask(choice.requires);
        final forbids = mask(choice.forbids);
        if ((node.$2 & requires) != requires ||
            (node.$2 & forbids) != 0) continue;
        usedDecisions.add(choice.id);
        reference(choice.sourceEventId);
        final next = (node.$2 | mask(choice.adds)) &
            ~mask(choice.removes);
        final witness = <String>[...node.$3, choice.id];
        transitions.add({
          'scene_id': scene.id,
          'chapter_index_in_book': scene.chapterIndex,
          'choice_id': choice.id,
          'next_scene_id': choice.nextSituationId,
          'scene_source_event_id': scene.sourceEventId,
          'choice_source_event_id': choice.sourceEventId,
          'declared_route': choice.route.name,
          'flags_before': active(node.$2),
          'flags_after': active(next),
          'witness_choice_ids': witness,
          'meaning_verified': false,
          'literary_causation_verified': false,
        });
        if (transitions.length > maxTransitions) {
          throw const FormatException(
              'Слишком много переходов для литературного аудита.');
        }
        final stateKey = choice.nextSituationId + ':' + next.toString();
        if (seen.add(stateKey)) {
          queue.add((choice.nextSituationId, next, witness));
        }
      }
    }

    if (terminalPaths.length < 2) {
      throw const FormatException('Нет двух различных полных ветвей.');
    }
    final notUsed = [
      for (final e in book.events)
        if (!usedEvents.contains(e.id)) e.id,
    ];
    final disabled = everyDecision.difference(usedDecisions).toList()..sort();
    final sourceAnchors = [
      for (final event in book.events)
        if (usedEvents.contains(event.id))
          {
            'event_id': event.id,
            'chapter_index': event.source.chapterIndex,
            'chunk_id': event.source.chunkId,
            'start_utf16': event.source.startUtf16,
            'end_utf16': event.source.endUtf16,
            'exact_quote_sha256':
                sha256.convert(utf8.encode(event.source.quote)).toString(),
          },
    ];

    final data = <String, Object?>{
      'format': format,
      'status': 'LITERARY_REVIEW_REQUIRED',
      'source_fingerprint': index.sourceFingerprint,
      'plan_sha256': sha256.convert(utf8.encode(plan.encode())).toString(),
      'events_found_in_book': book.events.length,
      'events_referenced_by_reachable_game': usedEvents.length,
      'events_not_used_by_game': notUsed,
      'chapters_in_book': book.chapterCount,
      'chapters_with_reachable_source_events': coveredChapters.length,
      'source_anchors_without_quote_text': sourceAnchors,
      'reachable_state_count': seen.length,
      'reachable_transition_count': transitions.length,
      'all_reachable_transitions': transitions,
      'two_shortest_complete_routes':
          terminalPaths.values.take(2).toList(growable: false),
      'reachable_distinct_endings': terminalPaths.length,
      'decisions_never_enabled': disabled,
      'source_claims': claimSummaries,
      'claims_with_valid_source_spans': backedClaims,
      'claims_without_valid_source_spans': missingClaims,
      'whole_book_meaning_verified': false,
      'character_motivation_verified': false,
      'npc_knowledge_verified': false,
      'world_chronology_verified': false,
      'literary_canon_verified': false,
      'may_modify_bookworld': false,
      'cloud_consent_granted': false,
    };
    final encoded = jsonEncode(data);
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException(
          'Литературный отчёт превышает безопасный локальный лимит.');
    }
    final digest = sha256.convert(utf8.encode(encoded)).toString();
    return WholeStoryLiteraryEvidenceManifest._(
      sourceFingerprint: index.sourceFingerprint,
      planSha256: data['plan_sha256']! as String,
      approvalDigest: digest,
      sourceEventsTotal: book.events.length,
      reachableSourceEvents: usedEvents.length,
      uncoveredSourceEvents: notUsed.length,
      reachableStates: seen.length,
      reachableTransitions: transitions.length,
      reachableEndings: terminalPaths.length,
      disabledDecisions: disabled.length,
      claimsWithVerifiedQuotes: backedClaims,
      claimsWithoutVerifiedQuotes: missingClaims,
      encoded: encoded,
    );
  }

  /// Rebuilds against the CURRENT book/plan rather than trusting a stored hash.
  void verifyUnchanged({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    SourceEvidenceGraph? claimEvidence,
  }) {
    final fresh = build(
      index: index, book: book, plan: plan, claimEvidence: claimEvidence);
    if (sourceFingerprint != fresh.sourceFingerprint ||
        planSha256 != fresh.planSha256 ||
        approvalDigest != fresh.approvalDigest) {
      throw const FormatException(
          'Изменена редакция книги, сюжетный план или исходные утверждения.');
    }
  }
}
