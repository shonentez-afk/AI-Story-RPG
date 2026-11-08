import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'npc_knowledge_world_bridge.dart';
import 'source_character_dossiers.dart';
import 'private_adaptation_preflight.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// Model-free, deterministic M2d *translation* of a reviewed causal draft.
///
/// Produces immutable JSON snapshots for a FUTURE independently verified
/// private .bworld compiler. It does not write ZIP/SQLite, overwrite saves,
/// publish a world or invoke a model. The old original_demo v1 format stays
/// untouched and will continue to reject these translated blueprints.
class PrivateClassicScenarioTranslation {
  const PrivateClassicScenarioTranslation._(
    this._blueprint,
    this._provenance,
    this.preflight,
  );

  final String _blueprint;
  final String _provenance;
  final PrivateAdaptationAcceptance preflight;

  /// Deep copies: callers cannot mutate the snapshots after validation.
  Map<String, dynamic> get blueprintJson =>
      Map<String, dynamic>.from(jsonDecode(_blueprint) as Map);
  Map<String, dynamic> get provenanceJson =>
      Map<String, dynamic>.from(jsonDecode(_provenance) as Map);

  String get blueprintSource => _blueprint;
  String get provenanceSource => _provenance;

  String get blueprintSha256 =>
      sha256.convert(utf8.encode(_blueprint)).toString();
  String get provenanceSha256 =>
      sha256.convert(utf8.encode(_provenance)).toString();

  /// A valid translation is not a compiled, playable package.
  bool get isPackageBuilt => false;
  bool get canPublishBookworld => false;
  bool get canDistributePublicly => false;
  bool get sendsTextToCloud => false;
}

class PrivateClassicScenarioTranslator {
  const PrivateClassicScenarioTranslator._();

  static final _digestPattern = RegExp(r'^[a-f0-9]{64}$');

  static PrivateClassicScenarioTranslation translate(
    BookSourceIndex index,
    SourceEvidenceGraph evidence,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
    IntermediateStoryBlueprint draft, {
    NpcKnowledgeRulebook? npcRules,
    NpcEditorialNotebook? npcNotebook,
    SourceCharacterDossierIndex? npcDossiers,
  }) {
    final acceptance = PrivateAdaptationPreflight.evaluate(
        index, evidence, catalog, editorial, draft);
    if (!acceptance.isStructurallyReady ||
        !_digestPattern.hasMatch(index.sourceFingerprint) ||
        !_digestPattern.hasMatch(editorial.catalogSha256) ||
        draft.rights != PreparationRights.privateUse) {
      throw const FormatException(
          'Черновик нельзя перевести в частную игровую схему: '
          'не проверены факты, причинность или права');
    }

    final draftHash = sha256.convert(utf8.encode(draft.encode())).toString();
    final bookId = 'book_${index.sourceFingerprint.substring(0,12)}_'
        '${draftHash.substring(0,12)}';
    final currentFlags = draft.initialFlags.toSet();
    final sortedFlags = draft.flags.toList()..sort();
    final assertions = {for (final a in catalog.assertions) a.id: a};
    final refs = {for (final e in evidence.records) e.id: e};

    final compiledScenes = <Map<String, dynamic>>[];
    final origins = <Map<String, dynamic>>[];
    for (final scene in draft.scenes) {
      final compiledChoices = <Map<String, dynamic>>[];
      for (final choice in scene.choices) {
        compiledChoices.add({
          'id': choice.id,
          'label': choice.label,
          'next_scene_id': choice.nextSceneId,
          'conditions': [
            for (final id in choice.requires)
              {'op': 'flag_is', 'id': id, 'value': true},
            for (final id in choice.forbids)
              {'op': 'flag_is', 'id': id, 'value': false},
          ],
          'effects': [
            for (final id in choice.adds)
              {'op': 'set_flag', 'id': id, 'value': true},
            for (final id in choice.removes)
              {'op': 'set_flag', 'id': id, 'value': false},
          ],
        });
      }
      compiledScenes.add({
        'id': scene.id,
        'text': scene.text,
        'terminal': scene.terminal,
        'choices': compiledChoices,
      });
      final sourceRefs = <Map<String, dynamic>>[];
      final seenRefIds = <String>{};
      for (final assertionId in scene.assertionIds) {
        final assertion = assertions[assertionId];
        if (assertion == null) {
          throw const FormatException('Сцена ссылается на чужое утверждение');
        }
        for (final evidenceId in assertion.evidenceIds) {
          final ref = refs[evidenceId];
          if (ref == null) {
            throw const FormatException('В сцене отсутствует источник цитаты');
          }
          if (ref.status != EvidenceStatus.confirmed ||
              ref.spoilerGate != EvidenceSpoilerGate.chapter ||
              ref.visibleAfterChapter > scene.chapterIndex) {
            throw const FormatException(
                'Сцена ссылается на непроверенную или будущую цитату');
          }
          ref.validate(index);
          if (seenRefIds.add(evidenceId)) {
            sourceRefs.add({
              'id': ref.id,
              'chunk_id': ref.chunkId,
              'chapter_id': ref.chapterId,
              'chapter_index': ref.chapterIndex,
              'block_index': ref.blockIndex,
              'start_utf16': ref.startUtf16,
              'end_utf16': ref.endUtf16,
              'quote_sha256': ref.evidenceSha256,
              'visible_after_chapter': ref.visibleAfterChapter,
            });
          }
        }
      }
      origins.add({
        'scene_id': scene.id,
        'chapter_index': scene.chapterIndex,
        'origin': scene.origin == DraftSceneOrigin.sourcePassage
            ? 'SOURCE_PASSAGE' : 'EXPLICIT_ADAPTATION',
        'assertion_ids': scene.assertionIds,
        'source_refs': sourceRefs,
      });
    }

    final blueprint = <String, dynamic>{
      'format': 'ai_story_blueprint_v1',
      'schema_version': 1,
      'book_id': bookId,
      'title': draft.title,
      'entry_scene_id': draft.entrySceneId,
      'rights_status': 'private_adaptation',
      'source_fingerprint': index.sourceFingerprint,
      'supported_modes': {
        'roles': ['PROTAGONIST'],
        'plots': ['ALTER_FATE'],
        'interactions': ['CLASSIC'],
      },
      'items': <String>[],
      'facts': <String>[],
      'actors': ['player'],
      'initial_state': {
        'scene_id': draft.entrySceneId,
        'revision': 0,
        'tick': 0,
        'stats': <String, int>{},
        'inventory': <String>[],
        'flags': {
          for (final flag in sortedFlags) flag: currentFlags.contains(flag),
        },
        'knowledge': {'player': <String>[]},
      },
      'scenes': compiledScenes,
    };
    final provenance = <String, dynamic>{
      'format': 'ai_story_private_provenance_v1',
      'bookworld_id': bookId,
      'source_fingerprint': index.sourceFingerprint,
      'source_title': index.title,
      'source_author': index.author,
      'source_chapters_total': index.chapterCount,
      'source_chapters_indexed': index.indexedChapterCount,
      'semantic_catalog_sha256': editorial.catalogSha256,
      'intermediate_draft_sha256': draftHash,
      'rights_status': 'private_use_only',
      'publication_authorized': false,
      'model_provenance': {'provider': 'none', 'model_id': null},
      'scene_origins': origins,
    };
    var finalBlueprint = blueprint;
    if (npcRules != null) {
      if (npcNotebook == null || npcDossiers == null) {
        throw const FormatException(
            'Нельзя включить знания NPC без проверенных карточек');
      }
      if (npcRules.rules.isEmpty) {
        throw const FormatException(
            'Для включения NPC нужны явные правила знаний');
      }
      final npcPreview = NpcKnowledgeWorldBridge.preview(
        index: index, dossiers: npcDossiers, graph: evidence,
        catalog: catalog, editorial: editorial,
        notebook: npcNotebook, scenario: draft, rulebook: npcRules,
        originalBlueprint: blueprint,
      );
      finalBlueprint = npcPreview.blueprint;
      provenance['bookworld_id'] = finalBlueprint['book_id'];
    }
    return PrivateClassicScenarioTranslation._(
        jsonEncode(finalBlueprint), jsonEncode(provenance), acceptance);
  }
}
