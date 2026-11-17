import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'intermediate_story_blueprint.dart';
import 'private_adaptation_preflight.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'zai_causal_choice_notebook.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';

/// M2f3f1: independent verification of the route from untrusted M2f3e
/// editorial suggestions into the *existing* M2c private adaptation model.
///
/// This is only a locally reviewed candidate. No SQLite writes, ZIP output,
/// cloud traffic, NPC disclosures, or implicit promotion of LLM hypotheses.
class ZaiM2cSourceBridgeReview {
  const ZaiM2cSourceBridgeReview._({
    required this.blockers,
    this.draft,
    this.acceptance,
  });

  final List<String> blockers;
  final IntermediateStoryBlueprint? draft;
  final PrivateAdaptationAcceptance? acceptance;

  bool get canStageForPrivateCompiler =>
      blockers.isEmpty && draft != null &&
      acceptance?.isStructurallyReady == true;

  bool get canPublishBookworld => false;
  bool get canDistributePublicly => false;
  bool get canStartPlayableRpg => false;
  bool get canSendToCloud => false;
}

/// The reader must independently link every original M2f3a event to one
/// confirmed, exact-offset M2c evidence citation and reviewed event assertion.
/// Deliberately NOT inferred from similar phrases, the title or an LLM score.
///
/// The user explicitly decides which scene is an original-source scene, which
/// is their authored alternative, and supplies full scene prose for both.
/// This version blocks NPC knowledge and future-chapter jumps until their
/// separate spoiler/identity permissions are implemented.
class ZaiM2cSourceBridge {
  const ZaiM2cSourceBridge._();

  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static ZaiM2cSourceBridgeReview review({
    required ZaiWindowReviewQueue queue,
    required ZaiCausalChoiceNotebook notebook,
    required ZaiEditorialConsistencyNotebook consistency,
    required SourceEvidenceGraph evidence,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required Set<String> sourceSceneIds,
    required Map<String, String> eventAssertionIds,
    required Map<String, String> authoredSceneTexts,
    required PreparationRights rights,
    required bool consentForPrivateCompilation,
  }) {
    final index = queue.index;
    final board = notebook.board;
    if (index.sourceFingerprint != board.graph.index.sourceFingerprint ||
        index.sourceFingerprint != consistency.graph.index.sourceFingerprint ||
        index.sourceFingerprint != evidence.sourceFingerprint ||
        index.sourceFingerprint != catalog.sourceFingerprint) {
      throw const FormatException('Черновик принадлежит другой книге');
    }

    // Re-check all persisted objects against the CURRENT edition and graph.
    board.encode();
    notebook.encode();
    final live = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    ZaiScenePreflight.assess(queue, board, consistency: consistency);
    ZaiEditorialConsistencyNotebook.decode(live, consistency.encode());
    SourceEvidenceGraph.decode(index, evidence.encode());
    SourceSemanticCatalog.decode(index, evidence, catalog.encode());
    SemanticEditorialReviewSession.decode(
        index, evidence, catalog, editorial.encode());

    final blockers = <String>[];
    void block(String reason) {
      if (!blockers.contains(reason)) blockers.add(reason);
    }

    if (!consentForPrivateCompilation) {
      block('Нет отдельного согласия на частную компиляцию.');
    }
    if (rights != PreparationRights.privateUse) {
      block('Подтвердите только частное использование: права на перевод и распространение не проверены.');
    }
    if (queue.pendingCount != 0 || queue.pendingReviewCount != 0) {
      block('Остались неразобранные исходные окна или ответы модели.');
    }
    if (consistency.questions.isNotEmpty ||
        ZaiConsistencyHints.reviewCues(live).isNotEmpty) {
      block('Нерешённые противоречия и редакторские вопросы.');
    }

    final causal = ZaiCausalPreflight.assess(
        queue, notebook, consistency: consistency);
    for (final item in causal.blockers.entries) {
      if (item.key != ZaiCausalBlocker.missingSemanticAcceptance &&
          item.key != ZaiCausalBlocker.notPublishedOrPlayable) {
        block(item.value);
      }
    }
    if (!causal.isStructurallyCausal) {
      block('Схема не проходит причинную проверку M2c с двумя исходами.');
    }
    if (notebook.choices.any((c) =>
        c.npcFindingId != null || c.knowledgeFindingId != null)) {
      block('Нужны отдельные проверенные правила знаний NPC.');
    }

    final sceneIds = {for (final scene in board.scenes) scene.id};
    if (sourceSceneIds.isEmpty ||
        sourceSceneIds.length >= sceneIds.length ||
        !sceneIds.containsAll(sourceSceneIds)) {
      block('Явно выберите исходные сцены и хотя бы одну авторскую альтернативу.');
    }
    if (authoredSceneTexts.length != sceneIds.length ||
        !authoredSceneTexts.keys.toSet().containsAll(sceneIds) ||
        authoredSceneTexts.values.any((text) =>
            text != text.trim() || text.length < 8 ||
            text.length > 6000 || _controls.hasMatch(text))) {
      block('Для каждой сцены нужен отдельный полный редакторский текст.');
    }

    final requiredEvents = {
      for (final scene in board.scenes)
        if (sourceSceneIds.contains(scene.id)) ...scene.eventIds,
    };
    if (requiredEvents.length != eventAssertionIds.length ||
        !requiredEvents.containsAll(eventAssertionIds.keys)) {
      block('Явно сопоставьте M2c утверждение каждому исходному событию.');
    }

    final findings = {for (final item in live.reviewed) item.id: item};
    final claims = {for (final item in catalog.assertions) item.id: item};
    final citations = {for (final item in evidence.records) item.id: item};
    final sceneAssertions = <String, List<String>>{};

    for (final scene in board.scenes) {
      if (!sourceSceneIds.contains(scene.id)) continue;
      final accepted = <String>[];
      for (final eventId in scene.eventIds) {
        final finding = findings[eventId];
        final claim = claims[eventAssertionIds[eventId]];
        if (finding == null || claim == null ||
            claim.kind != SemanticAssertionKind.event ||
            editorial.verdicts[claim.id] !=
                SemanticEditorialVerdict.canonCandidate ||
            claim.voice != AssertionVoice.narratorCandidate ||
            claim.polarity != AssertionPolarity.affirmative ||
            claim.time != AssertionTime.textOrderOnly) {
          block('Не принято независимое смысловое утверждение для исходного события.');
          continue;
        }
        final exactDigest = sha256.convert(
            utf8.encode(finding.quote)).toString();
        var exact = false;
        for (final id in claim.evidenceIds) {
          final citation = citations[id];
          if (citation == null ||
              citation.kind != EvidenceKind.event ||
              citation.status != EvidenceStatus.confirmed ||
              citation.spoilerGate != EvidenceSpoilerGate.chapter ||
              citation.visibleAfterChapter > scene.chapterIndex) {
            block('Цитата не подтверждена или защищена от спойлеров.');
            continue;
          }
          citation.validate(index);
          if (citation.chunkId == finding.candidate.chunkId &&
              citation.startUtf16 == finding.candidate.startUtf16 &&
              citation.endUtf16 == finding.candidate.endUtf16 &&
              citation.evidenceSha256 == exactDigest) {
            exact = true;
          }
        }
        if (!exact) {
          block('Не совпали точные цитаты и диапазоны M2f3a и M2c.');
        } else if (!accepted.contains(claim.id)) {
          accepted.add(claim.id);
        }
      }
      if (accepted.length != scene.eventIds.length) {
        block('Не все исходные события этой сцены прошли независимую проверку.');
      }
      sceneAssertions[scene.id] = accepted;
    }

    if (blockers.isNotEmpty) {
      return ZaiM2cSourceBridgeReview._(
          blockers: List.unmodifiable(blockers));
    }

    final preview = notebook.toM2cStructuralPreview();
    final draft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: preview.title,
      entrySceneId: preview.entrySceneId,
      rights: PreparationRights.privateUse,
      flags: preview.flags,
      initialFlags: preview.initialFlags,
      scenes: [
        for (var i = 0; i < board.scenes.length; i++)
          DraftScene(
            id: preview.scenes[i].id,
            chapterIndex: preview.scenes[i].chapterIndex,
            text: authoredSceneTexts[board.scenes[i].id]!,
            origin: sourceSceneIds.contains(board.scenes[i].id)
                ? DraftSceneOrigin.sourcePassage
                : DraftSceneOrigin.explicitAdaptation,
            assertionIds: sceneAssertions[board.scenes[i].id] ?? const [],
            terminal: preview.scenes[i].terminal,
            choices: preview.scenes[i].choices,
          ),
      ],
    );
    try {
      final acceptance = PrivateAdaptationPreflight.evaluate(
          index, evidence, catalog, editorial, draft);
      if (!acceptance.isStructurallyReady) {
        return ZaiM2cSourceBridgeReview._(
          blockers: List.unmodifiable(acceptance.userFacingBlockers),
          acceptance: acceptance,
        );
      }
      return ZaiM2cSourceBridgeReview._(
        blockers: const [], draft: draft, acceptance: acceptance);
    } on FormatException catch (error) {
      return ZaiM2cSourceBridgeReview._(
        blockers: List.unmodifiable(['Проверка M2c: ${error.message}']));
    }
  }
}
