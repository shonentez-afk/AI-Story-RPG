import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'multi_scene_draft_workbench.dart';
import 'npc_editorial_notebook.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// A private, deterministic PREVIEW of possible actors and their continuity.
/// No story_core changes, no AI prompt, no player-visible secret disclosure.
enum NpcContinuityFindingKind {
  repeatedNameNotResolved,
  missingRole,
  competingRoles,
  competingMotivations,
  linkWithoutTargetProfile,
  noPossibleSceneAfterIntroduction,
  sourceKnowledgeBeyondDraft,
}

class NpcContinuityFinding {
  const NpcContinuityFinding({
    required this.kind, required this.dossierId, required this.message,
  });
  final NpcContinuityFindingKind kind;
  final String dossierId;
  final String message;
  bool get isProvenContradiction => false;
}

class NpcNoteGatePreview {
  const NpcNoteGatePreview({
    required this.noteId, required this.field,
    required this.isAuthorial, required this.earliestSourceChapter,
  });
  final String noteId;
  final NpcDraftField field;
  final bool isAuthorial;

  /// Null = author's invention without source chapter evidence.
  /// Even with a source threshold, no permission to disclose is inferred.
  final int? earliestSourceChapter;
  bool get isAutomaticallyPlayerVisible => false;
  bool get isWorldCanon => false;
  bool get requiresSeparateGameplayDisclosureRules => true;
  bool isSafeToRevealAutomaticallyAt(int chapter) => false;
}

class NpcStageActorPreview {
  const NpcStageActorPreview({
    required this.stagingId, required this.dossierId,
    required this.displayName, required this.firstSourceChapter,
    required this.mentionCount, required this.possibleSceneIds,
    required this.noteGates,
  });

  /// Reproducible *staging* reference, NOT a permanent gameplay Actor ID.
  final String stagingId;
  final String dossierId;
  final String displayName;
  final int firstSourceChapter;
  final int mentionCount;
  final List<String> possibleSceneIds;
  final List<NpcNoteGatePreview> noteGates;
  bool get isGameplayActor => false;
  bool get canInstallInWorld => false;
  bool get canSendToAi => false;
}

class NpcStageRelationPreview {
  const NpcStageRelationPreview({
    required this.noteId, required this.fromStagingId,
    required this.targetDossierId, required this.targetStagingId,
  });
  final String noteId;
  final String fromStagingId;
  final String targetDossierId;
  final String? targetStagingId;
  bool get isWorldRelationship => false;
}

class NpcContinuityAudit {
  const NpcContinuityAudit._({
    required this.sourceFingerprint, required this.actors,
    required this.relations, required this.findings,
    required this.scenarioLinked,
  });

  final String sourceFingerprint;
  final List<NpcStageActorPreview> actors;
  final List<NpcStageRelationPreview> relations;
  final List<NpcContinuityFinding> findings;
  final bool scenarioLinked;
  bool get canPublishNpcActors => false;
  bool get canRevealPlayerSecrets => false;
  bool get canCreateLlmContext => false;

  static String _normalized(String input) => input.trim().toLowerCase()
      .replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ');

  static String _stageId(
      String fingerprint, SourceCharacterDossier dossier) {
    final stable = '${fingerprint}|${NpcEditorialNotebook.mentionIds(dossier).join("|")}';
    return 'stage_npc_${sha256.convert(utf8.encode(stable)).toString().substring(0, 20)}';
  }

  /// Recheck the notebook, relation groups and all cited spans on EVERY call.
  static NpcContinuityAudit inspect({
    required BookSourceIndex index,
    required SourceCharacterDossierIndex dossiers,
    required SourceEvidenceGraph graph,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required NpcEditorialNotebook notebook,
    IntermediateStoryBlueprint? scenario,
  }) {
    notebook.validate(index, dossiers, graph, catalog, editorial);
    if (scenario != null) {
      MultiSceneDraftWorkbench.checkSafeCheckpoint(index, scenario);
    }
    final groups = {for (final d in dossiers.dossiers) d.id: d};
    final profiles = {for (final p in notebook.profiles) p.dossierId: p};
    final claims = {for (final a in catalog.assertions) a.id: a};
    final evidence = {for (final e in graph.records) e.id: e};
    final idByGroup = <String, String>{};
    for (final profile in notebook.profiles) {
      idByGroup[profile.dossierId] =
          _stageId(index.sourceFingerprint, groups[profile.dossierId]!);
    }
    final repeated = <String, Set<String>>{};
    for (final d in dossiers.dossiers) {
      for (final label in d.labels) {
        repeated.putIfAbsent(_normalized(label), () => {}).add(d.id);
      }
    }
    final findings = <NpcContinuityFinding>[];
    final actors = <NpcStageActorPreview>[];
    final links = <NpcStageRelationPreview>[];
    for (final profile in notebook.profiles) {
      final dossier = groups[profile.dossierId]!;
      final stageId = idByGroup[dossier.id]!;
      final possibleScenes = scenario == null
          ? const <String>[]
          : [
              for (final scene in scenario.scenes)
                if (scene.chapterIndex >= dossier.firstChapter) scene.id,
            ];
      final roles = profile.notes
          .where((n) => n.field == NpcDraftField.role)
          .map((n) => _normalized(n.text)).toSet();
      final motivations = profile.notes
          .where((n) => n.field == NpcDraftField.motivation)
          .map((n) => _normalized(n.text)).toSet();
      if (roles.isEmpty) {
        findings.add(NpcContinuityFinding(
          kind: NpcContinuityFindingKind.missingRole,
          dossierId: dossier.id,
          message: '${profile.displayName}: не определена игровая роль.',
        ));
      } else if (roles.length > 1) {
        findings.add(NpcContinuityFinding(
          kind: NpcContinuityFindingKind.competingRoles,
          dossierId: dossier.id,
          message: '${profile.displayName}: несколько разных записей роли. '
              'Проверьте развитие или конфликт.',
        ));
      }
      if (motivations.length > 1) {
        findings.add(NpcContinuityFinding(
          kind: NpcContinuityFindingKind.competingMotivations,
          dossierId: dossier.id,
          message: '${profile.displayName}: несколько мотивов. '
              'Согласуйте их до игровых правил.',
        ));
      }
      if (dossier.labels.any((name) =>
          (repeated[_normalized(name)]?.length ?? 0) > 1)) {
        findings.add(NpcContinuityFinding(
          kind: NpcContinuityFindingKind.repeatedNameNotResolved,
          dossierId: dossier.id,
          message: '${profile.displayName}: имя встречается в других '
              'необъединённых группах. Это не доказательство одной личности.',
        ));
      }
      if (scenario != null && possibleScenes.isEmpty) {
        findings.add(NpcContinuityFinding(
          kind: NpcContinuityFindingKind.noPossibleSceneAfterIntroduction,
          dossierId: dossier.id,
          message: '${profile.displayName}: в сценарии нет сцен в главе '
              '${dossier.firstChapter + 1} или позднее.',
        ));
      }
      final gates = <NpcNoteGatePreview>[];
      for (final note in profile.notes) {
        int? earliest;
        if (note.sourceAssertionId != null) {
          final claim = claims[note.sourceAssertionId]!;
          for (final sourceId in claim.evidenceIds) {
            final source = evidence[sourceId]!;
            if (earliest == null ||
                source.visibleAfterChapter > earliest) {
              earliest = source.visibleAfterChapter;
            }
          }
          if (scenario != null &&
              !scenario.scenes.any((scene) =>
                  scene.chapterIndex >= earliest!)) {
            findings.add(NpcContinuityFinding(
              kind: NpcContinuityFindingKind.sourceKnowledgeBeyondDraft,
              dossierId: dossier.id,
              message: '${profile.displayName}: источник заметки '
                  '${note.id} относится к главе ${earliest! + 1}, '
                  'которая пока не представлена в сценах.',
            ));
          }
        }
        gates.add(NpcNoteGatePreview(
          noteId: note.id,
          field: note.field,
          isAuthorial: note.isAuthorial,
          earliestSourceChapter: earliest,
        ));
        if (note.field == NpcDraftField.relationship) {
          final target = note.targetDossierId!;
          links.add(NpcStageRelationPreview(
            noteId: note.id,
            fromStagingId: stageId,
            targetDossierId: target,
            targetStagingId: idByGroup[target],
          ));
          if (!profiles.containsKey(target)) {
            findings.add(NpcContinuityFinding(
              kind: NpcContinuityFindingKind.linkWithoutTargetProfile,
              dossierId: dossier.id,
              message: '${profile.displayName}: связь из заметки '
                  '${note.id} направлена к персонажу без авторской карточки.',
            ));
          }
        }
      }
      actors.add(NpcStageActorPreview(
        stagingId: stageId,
        dossierId: dossier.id,
        displayName: profile.displayName,
        firstSourceChapter: dossier.firstChapter,
        mentionCount: dossier.mentions.length,
        possibleSceneIds: List.unmodifiable(possibleScenes),
        noteGates: List.unmodifiable(gates),
      ));
    }
    return NpcContinuityAudit._(
      sourceFingerprint: index.sourceFingerprint,
      actors: List.unmodifiable(actors),
      relations: List.unmodifiable(links),
      findings: List.unmodifiable(findings),
      scenarioLinked: scenario != null,
    );
  }
}
