import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_plan_quality_gate.dart';
import 'zai_story_dilemma_proposal.dart';

/// A playable but deliberately SHORT, private, FICTIONAL trial of a
/// source-locked causal plan. Not a complete book adaptation or canonical
/// literary interpretation, and never eligible for public distribution.
class StoryPlanTrialCompilation {
  const StoryPlanTrialCompilation({
    required this.archive,
    required this.sourceFingerprint,
    required this.bookworldId,
    required this.archiveSha256,
    required this.sceneCount,
    required this.sourceQuoteCount,
    this.sourceEventsTotal = 0,
    this.sourceEventsRepresented = 0,
    this.unrepresentedSourceEventIds = const [],
    this.uncoveredSourceChapters = const [],
    this.selectedHeroLabel = 'Игрок',
  });

  final Uint8List archive;
  final String sourceFingerprint, bookworldId, archiveSha256;
  final int sceneCount, sourceQuoteCount;
  /// Computed from this exact book/plan during compilation, NOT model claims.
  final int sourceEventsTotal, sourceEventsRepresented;
  final List<String> unrepresentedSourceEventIds;
  final List<int> uncoveredSourceChapters;
  /// User-approved display label for the player actor (not a verified NPC).
  final String selectedHeroLabel;
  bool get hasAllSourceEventsRepresented =>
      sourceEventsTotal > 0 && sourceEventsRepresented == sourceEventsTotal &&
      unrepresentedSourceEventIds.isEmpty && uncoveredSourceChapters.isEmpty;
  bool get isFullBookAdaptation => false;
  bool get sourceMeaningIsVerified => false;
  bool get isPrivateTrial => true;
  bool get canDistributePublicly => false;
  bool get requiresCloudToPlay => false;
}

/// Source quotations are independently checked, while all non-literal
/// interpretations are labeled as fictional adaptation. This reuses the
/// existing M2c/PrivateAdaptationPreflight, BookWorld compiler, ZIP importer
/// and SQLite runtime. It cannot mutate or replace an existing campaign.
class StoryPlanTrialCompiler {
  const StoryPlanTrialCompiler._();

  static Future<StoryPlanTrialCompilation> compile({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required ZaiStoryDilemmaPreview preview,
    required Set<String> sourceEventIdsReviewedByUser,
    required bool privateUseConfirmed,
    required bool fictionalTrialAcknowledged,
  }) async {
    if (!privateUseConfirmed || !fictionalTrialAcknowledged) {
      throw const FormatException(
          'Подтвердите частное использование и вымышленный характер игры.');
    }
    if (index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        index.indexedChapterCount != index.chapterCount) {
      throw const FormatException(
          'Для пробной RPG нужна полностью индексированная та же книга.');
    }
    final proposal = preview.proposal;
    if (proposal == null) {
      throw const FormatException('ИИ пока не предложил игровой сценарий.');
    }
    final ids = {proposal.setupEventId, proposal.outcomeEventId};
    if (sourceEventIdsReviewedByUser.length != ids.length ||
        !sourceEventIdsReviewedByUser.containsAll(ids)) {
      throw const FormatException(
          'Подтвердите обе исходные цитаты прежде чем создавать адаптацию.');
    }
    final quality = StoryPlanQualityGate.assess(
        book: book, preview: preview);
    if (!quality.passedFormalPreflight ||
        quality.repair.after.counterexamples.isNotEmpty) {
      throw const FormatException(
          'В сценарии остались противоречия. Компиляция запрещена.');
    }
    final events = <NarrativeEvent>[
      for (final id in [proposal.setupEventId, proposal.outcomeEventId])
        book.events.singleWhere((event) => event.id == id),
    ];
    final proposedEvidence = <SourceEvidence>[];
    for (final event in events) {
      final quote = event.source;
      quote.validate(index);
      final record = SourceEvidence.propose(
        index,
        chunkId: quote.chunkId,
        kind: EvidenceKind.fact,
        startUtf16: quote.startUtf16,
        endUtf16: quote.endUtf16,
      );
      if (record.label != quote.quote ||
          record.chapterIndex != quote.chapterIndex) {
        throw const FormatException(
            'Цитата изменилась после подтверждения пользователем.');
      }
      proposedEvidence.add(record);
    }
    var evidence = SourceEvidenceGraph.empty(index).addAll(
        index, proposedEvidence);
    for (final item in proposedEvidence) {
      evidence = evidence.review(index, item.id, EvidenceStatus.confirmed);
    }
    final assertions = <SourceSemanticAssertion>[];
    for (var i = 0; i < proposedEvidence.length; i++) {
      assertions.add(SourceSemanticAssertion.propose(
        index, evidence,
        kind: SemanticAssertionKind.fact,
        evidenceIds: [proposedEvidence[i].id],
        subject: 'Текст исходной книги',
        predicate: 'содержит дословный отрывок',
        object: 'Цитата ' + (i + 1).toString(),
        voice: AssertionVoice.narratorCandidate,
        polarity: AssertionPolarity.affirmative,
        time: AssertionTime.textOrderOnly,
        uncertainty: 'Подтверждено только наличие цитаты, НЕ '
            'литературный смысл или причинная связь.',
      ));
    }
    final catalog = SourceSemanticCatalog.checked(index, evidence,
        assertions);
    var editorial = SemanticEditorialReviewSession.create(index, catalog);
    for (final assertion in assertions) {
      // The user reviewed literal quote presence ONLY. No model-derived
      // promise or character fact appears in these accepted assertions.
      editorial = editorial.decide(catalog, assertion.id,
          SemanticEditorialVerdict.canonCandidate);
    }

    final evidenceForScene = <String, (String, String)>{
      proposal.setupEventId: (assertions[0].id, events[0].source.quote),
      proposal.outcomeEventId: (assertions[1].id, events[1].source.quote),
    };
    final scenes = <DraftScene>[];
    for (final scene in quality.plan.situations) {
      final sourceScene = scene.id == 'turning_point' ||
          scene.id == 'accept_path';
      final pair = sourceScene
          ? evidenceForScene[scene.sourceEventId] : null;
      if (sourceScene && pair == null) {
        throw const FormatException(
            'Исходная сцена не подтверждена конкретной цитатой.');
      }
      final body = sourceScene
          ? 'Дословная цитата книги:\n«' + pair!.$2 + '»\n\n'
              'Дальнейшее — НЕПРОВЕРЕННАЯ игровая интерпретация:\n' +
              scene.goal + '\n\n' + scene.conflict
          : 'ВЫМЫШЛЕННАЯ ИГРОВАЯ АДАПТАЦИЯ, не исходный текст:\n' +
              scene.goal + '\n\n' + scene.conflict;
      scenes.add(DraftScene(
        id: scene.id, chapterIndex: scene.chapterIndex,
        text: body,
        origin: sourceScene
            ? DraftSceneOrigin.sourcePassage
            : DraftSceneOrigin.explicitAdaptation,
        assertionIds: sourceScene ? [pair!.$1] : const [],
        terminal: scene.terminal,
        choices: [
          for (final d in scene.decisions)
            DraftChoice(
              id: d.id, label: d.intent,
              nextSceneId: d.nextSituationId,
              requires: d.requires, forbids: d.forbids,
              adds: d.adds, removes: d.removes,
            ),
        ],
      ));
    }
    final draft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      entrySceneId: quality.plan.entrySituationId,
      rights: PreparationRights.privateUse,
      flags: quality.plan.flags,
      initialFlags: quality.plan.initialFlags,
      scenes: scenes,
    );
    // Existing independent M2c/source/copyright/causal checks are mandatory.
    // The actual in-app trial now produces the unified rich v3 .bworld.
    // Hero, empty honest catalogs and Journal use the real SQLite game state.
    final archive = await compileReviewedRichPrivateBookworldInWorker(
        index, evidence, catalog, editorial, draft,
        sceneTitles: {
          for (final scene in quality.plan.situations) scene.id: scene.goal,
        });
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    if (inspected.sourceFingerprint != index.sourceFingerprint ||
        inspected.requiresNetwork ||
        inspected.canDistributePublicly ||
        inspected.blueprint.scenes.length != scenes.length) {
      throw const FormatException(
          'Пакет пробной RPG не прошёл независимую проверку.');
    }
    return StoryPlanTrialCompilation(
      archive: archive,
      sourceFingerprint: index.sourceFingerprint,
      bookworldId: inspected.bookworldId,
      archiveSha256: inspected.archiveSha256,
      sceneCount: inspected.blueprint.scenes.length,
      sourceQuoteCount: events.length,
    );
  }
}
