import 'book_source_index.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'book_event_outline.dart';

/// M2g3a: a source-locked INTERMEDIATE representation between a book-wide
/// semantic scan and a future causal StoryPlan. It never grants world truth,
/// NPC identity or gameplay permissions to model output.
enum NarrativeProvenance {
  /// Exact words and UTF-16 offsets were independently checked.
  exactText,
  /// An AI or rule suggested what these words might mean.
  unverifiedInterpretation,
}

/// Book position is known; chronology of events inside the story is not.
/// A flashback can make chapter order differ from in-world time.
enum NarrativeTemporalStatus { narrativeOrderOnly, timeUnresolved }

class NarrativeCitation {
  const NarrativeCitation({
    required this.chunkId,
    required this.chapterIndex,
    required this.blockIndex,
    required this.startUtf16,
    required this.endUtf16,
    required this.quote,
  });

  final String chunkId;
  final int chapterIndex;
  final int blockIndex;
  final int startUtf16;
  final int endUtf16;
  final String quote;

  void validate(BookSourceIndex index) {
    final chunks = index.chunks.where((c) => c.id == chunkId).toList();
    if (chunks.length != 1) {
      throw const FormatException('Исходный отрывок не найден.');
    }
    _validateAgainstChunk(chunks.single);
  }

  void _validateAgainstChunk(SourceChunk chunk) {
    if (chunk.id != chunkId ||
        chapterIndex != chunk.chapterIndex ||
        blockIndex != chunk.blockIndex ||
        startUtf16 < chunk.startUtf16 ||
        endUtf16 > chunk.endUtf16 ||
        endUtf16 <= startUtf16 ||
        quote.isEmpty ||
        endUtf16 - startUtf16 != quote.length ||
        endUtf16 - startUtf16 > 180 ||
        chunk.text.substring(startUtf16 - chunk.startUtf16,
            endUtf16 - chunk.startUtf16) != quote) {
      throw const FormatException('Цитата не совпадает с исходной книгой.');
    }
    // A quote must never split the halves of a supplementary Unicode rune.
    final begin = startUtf16 - chunk.startUtf16;
    final end = endUtf16 - chunk.startUtf16;
    if (begin > 0 && _lowSurrogate(chunk.text.codeUnitAt(begin)) ||
        end < chunk.text.length && _lowSurrogate(chunk.text.codeUnitAt(end))) {
      throw const FormatException('Цитата повреждает Unicode-символ.');
    }
  }

  static bool _lowSurrogate(int value) =>
      value >= 0xdc00 && value <= 0xdfff;

  Map<String, Object> toJson() => {
    'chunk_id': chunkId,
    'chapter_index': chapterIndex,
    'block_index': blockIndex,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'quote': quote,
  };
}

class NarrativeEvent {
  const NarrativeEvent({
    required this.id,
    required this.suggestedLabel,
    required this.source,
    required this.narrativePosition,
  });

  final String id;
  final String suggestedLabel;
  final NarrativeCitation source;

  /// Position in the BOOK, not an asserted in-world chronological position.
  final int narrativePosition;

  NarrativeProvenance get sourceProvenance => NarrativeProvenance.exactText;
  NarrativeProvenance get meaningProvenance =>
      NarrativeProvenance.unverifiedInterpretation;
  NarrativeTemporalStatus get timeStatus =>
      NarrativeTemporalStatus.timeUnresolved;

  bool get meaningIsCanon => false;
  bool get isCausallyValidated => false;
  bool get isPlayableChoice => false;

  Map<String, Object> toJson() => {
    'id': id,
    'suggested_label': suggestedLabel,
    'source': source.toJson(),
    'narrative_position': narrativePosition,
    'time_status': timeStatus.name,
    'meaning_confirmed': false,
    'causality_confirmed': false,
  };
}

/// Next-in-TEXT adjacency never implies an in-world timeline, cause,
/// or a permitted game transition. These edges help the next stage identify
/// which source events it needs to reason about.
class NarrativeTextAdjacency {
  const NarrativeTextAdjacency(this.fromEventId, this.toEventId);

  final String fromEventId;
  final String toEventId;

  bool get establishesWorldTime => false;
  bool get establishesCausation => false;

  Map<String, Object> toJson() => {
    'from_event_id': fromEventId,
    'to_event_id': toEventId,
    'meaning': 'NEXT_IN_SOURCE_TEXT_ONLY',
    'establishes_world_time': false,
    'establishes_causation': false,
  };
}

/// Reuses the reviewed identity grouping already performed by
/// SourceCharacterDossierIndex. Merely sharing a name never joins actors.
class NarrativeCharacter {
  const NarrativeCharacter({
    required this.mentionGroupId,
    required this.labels,
    required this.citationIds,
    required this.firstChapter,
    required this.lastChapter,
    required this.identityHintsResolved,
  });

  /// Stable evidence-group ID, NOT a story_core NPC/actor ID.
  final String mentionGroupId;
  final List<String> labels;
  final List<String> citationIds;
  final int firstChapter;
  final int lastChapter;
  final bool identityHintsResolved;

  bool get isWorldActor => false;
  bool get knowsAnyUnrevealedFact => false;

  Map<String, Object> toJson() => {
    'mention_group_id': mentionGroupId,
    'labels': labels,
    'citation_ids': citationIds,
    'first_chapter': firstChapter,
    'last_chapter': lastChapter,
    'identity_hints_resolved': identityHintsResolved,
    'is_world_actor': false,
  };
}

/// An assertion records what the text MAY say. Even the existing editorial
/// CANON_CANDIDATE verdict is not sufficient to prove world truth.
class NarrativeClaim {
  const NarrativeClaim({
    required this.id,
    required this.kind,
    required this.subject,
    required this.predicate,
    required this.object,
    required this.voice,
    required this.polarity,
    required this.time,
    required this.uncertainty,
    required this.citationIds,
    required this.verdict,
  });

  final String id;
  final SemanticAssertionKind kind;
  final String subject;
  final String predicate;
  final String object;
  final AssertionVoice voice;
  final AssertionPolarity polarity;
  final AssertionTime time;
  final String uncertainty;
  final List<String> citationIds;
  final SemanticEditorialVerdict? verdict;

  bool get establishesWorldTruth => false;
  bool get establishesIdentity => false;
  bool get establishesActorKnowledge => false;
  bool get provesCausation => false;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'subject': subject,
    'predicate': predicate,
    'object': object,
    'voice': voice.name,
    'polarity': polarity.name,
    'time': time.name,
    'uncertainty': uncertainty,
    'citation_ids': citationIds,
    'verdict': verdict?.name ?? 'unreviewed',
    'establishes_world_truth': false,
  };
}

/// This is NOT an alternate story engine, database or automatic canon.
/// All existing source checks, M2c preflight, SQLite and story_core remain
/// authoritative at later steps.
class NarrativeBookModel {
  NarrativeBookModel._({
    required this.sourceFingerprint,
    required this.title,
    required this.chapterCount,
    required this.analysisComplete,
    required this.chaptersWithEventProposals,
    required List<NarrativeEvent> events,
    required List<NarrativeCharacter> characters,
    required List<NarrativeClaim> claims,
  }) : events = List.unmodifiable(events),
       textAdjacency = List.unmodifiable([
         for (var i = 1; i < events.length; i++)
           NarrativeTextAdjacency(events[i - 1].id, events[i].id),
       ]),
       characters = List.unmodifiable(characters),
       claims = List.unmodifiable(claims);

  static const format = 'ai_story_narrative_book_model_m2g3a_v1';
  static const maxEvents = 32768;
  static const maxCharacters = 6000;

  final String sourceFingerprint;
  final String title;
  final int chapterCount;
  final bool analysisComplete;
  final int chaptersWithEventProposals;
  final List<NarrativeEvent> events;
  final List<NarrativeTextAdjacency> textAdjacency;
  final List<NarrativeCharacter> characters;
  final List<NarrativeClaim> claims;

  /// These must be authored/validated by the next strict causal stage;
  /// none can be inferred merely from chapter order or AI labels.
  bool get hasProvenChronology => false;
  bool get hasCausalGraph => false;
  bool get hasNPCWorldTruth => false;
  bool get isPlayableScenario => false;
  bool get canPublishPublicly => false;

  List<String> get issues => List.unmodifiable([
    if (!analysisComplete)
      'Анализ книги не завершён. Сценарий строить нельзя.',
    if (events.isEmpty)
      'Не найдено ни одного предложения события.',
    if (chaptersWithEventProposals < chapterCount)
      'Не для всех глав найдены предложения событий.',
    if (characters.any((c) => !c.identityHintsResolved))
      'Не все возможные личности персонажей проверены.',
    'Порядок текста не доказывает время события; флешбеки не разрешены.',
    'Связи причин, условия и последствия решений ещё не доказаны.',
    'Реплики персонажей не могут раскрывать неопознанные знания.',
  ]);

  Map<String, Object> toJson() => {
    'format': format,
    'source_fingerprint': sourceFingerprint,
    'title': title,
    'chapter_count': chapterCount,
    'analysis_complete': analysisComplete,
    'chapters_with_event_proposals': chaptersWithEventProposals,
    'events': [for (final e in events) e.toJson()],
    'text_adjacency': [for (final edge in textAdjacency) edge.toJson()],
    'characters': [for (final a in characters) a.toJson()],
    'claims': [for (final c in claims) c.toJson()],
    'has_proven_chronology': false,
    'has_causal_graph': false,
    'is_playable_scenario': false,
    'can_publish_publicly': false,
  };

  static NarrativeBookModel fromExisting({
    required BookSourceIndex index,
    required BookEventOutline outline,
    SourceCharacterDossierIndex? dossiers,
    SourceSemanticCatalog? catalog,
    SourceEvidenceGraph? evidence,
    SemanticEditorialReviewSession? editorial,
    bool permitIncompleteAnalysisForReview = false,
  }) {
    if (outline.sourceFingerprint != index.sourceFingerprint ||
        outline.totalChapters != index.chapterCount ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        (!permitIncompleteAnalysisForReview && !outline.analysisComplete) ||
        outline.events.length > maxEvents ||
        (dossiers != null &&
            (dossiers.sourceFingerprint != index.sourceFingerprint ||
             dossiers.dossiers.length > maxCharacters)) ||
        (catalog != null && (evidence == null ||
            evidence.sourceFingerprint != index.sourceFingerprint ||
            catalog.sourceFingerprint != index.sourceFingerprint)) ||
        (editorial != null && (catalog == null ||
            !editorial.matches(index, catalog)))) {
      throw const FormatException(
          'Не удалось подтвердить источник или полноту модели книги.');
    }
    if (catalog != null) {
      // The existing catalog is the authority for meaning proposal validation.
      SourceSemanticCatalog.checked(index, evidence!, catalog.assertions);
    }
    final byChunkId = {
      for (final chunk in index.chunks) chunk.id: chunk,
    };
    if (byChunkId.length != index.chunks.length) {
      throw const FormatException('Нарушена уникальность исходных фрагментов.');
    }
    final eventIds = <String>{};
    final events = <NarrativeEvent>[];
    for (final item in outline.events) {
      if (!eventIds.add(item.id) ||
          item.label.trim().isEmpty ||
          item.label.length > 240) {
        throw const FormatException('Повторное или некорректное событие.');
      }
      final chunk = byChunkId[item.chunkId];
      if (chunk == null) {
        throw const FormatException('Событие ссылается на чужую книгу.');
      }
      final citation = NarrativeCitation(
        chunkId: item.chunkId,
        chapterIndex: item.chapterIndex,
        blockIndex: item.blockIndex,
        startUtf16: item.startUtf16,
        endUtf16: item.startUtf16 + item.quote.length,
        quote: item.quote,
      );
      citation._validateAgainstChunk(chunk);
      events.add(NarrativeEvent(
        id: item.id,
        suggestedLabel: item.label,
        source: citation,
        narrativePosition: events.length,
      ));
    }
    // The outline is already sorted by book order; verify it again so a
    // future imported/forged outline cannot reverse narrative chronology.
    for (var i = 1; i < events.length; i++) {
      final a = events[i - 1].source;
      final b = events[i].source;
      if (a.chapterIndex > b.chapterIndex ||
          a.chapterIndex == b.chapterIndex && a.blockIndex > b.blockIndex ||
          a.chapterIndex == b.chapterIndex &&
              a.blockIndex == b.blockIndex &&
              a.startUtf16 > b.startUtf16) {
        throw const FormatException('События расположены не по тексту.');
      }
    }

    final actorIds = <String>{};
    final characters = <NarrativeCharacter>[];
    for (final dossier in dossiers?.dossiers ??
        const <SourceCharacterDossier>[]) {
      if (!actorIds.add(dossier.id) || dossier.mentions.isEmpty) {
        throw const FormatException('Повторная или пустая карточка персонажа.');
      }
      for (final mention in dossier.mentions) {
        mention.validate(index);
        if (mention.kind != EvidenceKind.character ||
            mention.status == EvidenceStatus.rejected) {
          throw const FormatException('Чужое упоминание персонажа.');
        }
      }
      characters.add(NarrativeCharacter(
        mentionGroupId: dossier.id,
        labels: List.unmodifiable(dossier.labels),
        citationIds: List.unmodifiable(dossier.mentions.map((m) => m.id)),
        firstChapter: dossier.firstChapter,
        lastChapter: dossier.lastChapter,
        identityHintsResolved: dossier.identityIsFullyResolved,
      ));
    }

    final claims = <NarrativeClaim>[];
    for (final proposal in catalog?.assertions ??
        const <SourceSemanticAssertion>[]) {
      final verdict = editorial?.verdicts[proposal.id];
      // Keep rejected/disputed statements visible for diagnostics; NEVER
      // turn them into world facts or compile them as valid choices.
      claims.add(NarrativeClaim(
        id: proposal.id,
        kind: proposal.kind,
        subject: proposal.subject,
        predicate: proposal.predicate,
        object: proposal.object,
        voice: proposal.voice,
        polarity: proposal.polarity,
        time: proposal.time,
        uncertainty: proposal.uncertainty,
        citationIds: List.unmodifiable(proposal.evidenceIds),
        verdict: verdict,
      ));
    }
    return NarrativeBookModel._(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      chapterCount: index.chapterCount,
      analysisComplete: outline.analysisComplete,
      chaptersWithEventProposals: outline.chaptersWithEventProposals,
      events: events,
      characters: characters,
      claims: claims,
    );
  }
}
