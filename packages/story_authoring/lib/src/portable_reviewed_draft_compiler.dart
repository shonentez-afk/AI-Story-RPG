import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';

import 'authoring_engine.dart';
import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'private_adaptation_preflight.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_relation_review.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';

/// One portable, source-locked, user-reviewed bundle. Its SHA-based
/// checkpoints detect corruption and foreign editions, not literary truth.
/// AI cannot set this bundle's game-state effects without a separate author
/// review and the existing strict v3 compiler verification.
class PortableReviewedDraftCompiler {
  const PortableReviewedDraftCompiler();
  static const format = 'ai_story_portable_reviewed_draft_v1';

  Future<Uint8List> build({
    required SourceLockedBook source,
    required Map<String, dynamic> review,
  }) async {
    if (!source.hasCompleteText) {
      throw const FormatException('Не вся исходная книга проиндексирована');
    }
    const fields = {
      'format', 'source_fingerprint', 'evidence', 'catalog',
      'editorial', 'draft', 'hero_name',
    };
    final keys = review.keys.toSet();
    if (!keys.containsAll(fields) ||
        keys.difference({...fields, 'npc'}).isNotEmpty ||
        review['format'] != format ||
        review['source_fingerprint'] != source.index.sourceFingerprint ||
        review['evidence'] is! String ||
        review['catalog'] is! String ||
        review['editorial'] is! String ||
        review['draft'] is! String ||
        review['hero_name'] is! String) {
      throw const FormatException('Неверная редакция или комплект проверок');
    }
    final hero = review['hero_name'] as String;
    if (hero.trim().isEmpty || hero.length > 120 ||
        hero != hero.trim() ||
        hero.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Некорректное имя героя');
    }
    final index = source.index;
    final evidenceCheckpoint =
        StoryEvidenceReviewSession.decode(index, review['evidence'] as String);
    if (evidenceCheckpoint.scannedChunks != index.chunks.length) {
      throw const FormatException('Проверка исходного текста не завершена');
    }
    final graph = evidenceCheckpoint.graph;
    final catalog = SourceSemanticCatalog.decode(
        index, graph, review['catalog'] as String);
    final editorial = SemanticEditorialReviewSession.decode(
        index, graph, catalog, review['editorial'] as String);
    final draft = IntermediateStoryBlueprint.decode(
        review['draft'] as String);
    final preflight = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, editorial, draft);
    if (!preflight.isStructurallyReady) {
      throw const FormatException(
          'Нет подтверждённого частного игрового сценария');
    }

    late final Uint8List bytes;
    if (review['npc'] == null) {
      bytes = await compileReviewedRichPrivateBookworldInWorker(
          index, graph, catalog, editorial, draft, heroName: hero);
    } else {
      final npc = review['npc'];
      if (npc is! Map<String, dynamic>) {
        throw const FormatException('Пакет NPC должен быть объектом');
      }
      const npcKeys = {
        'relations', 'notebook', 'rules',
        'source_quotes_by_rule_id', 'user_confirmed',
        'reviewed_npc_social', 'reviewed_book_items',
        'reviewed_dialogue_turns', 'reviewed_speaker_bindings',
      };
      if (npc.keys.toSet().difference(npcKeys).isNotEmpty ||
          npc['user_confirmed'] != true ||
          npc['notebook'] is! String ||
          npc['rules'] is! String ||
          npc['source_quotes_by_rule_id'] is! Map ||
          (npc['relations'] != null && npc['relations'] is! String)) {
        throw const FormatException(
            'NPC требует явного подтверждения, карточек и цитат');
      }
      final relations = npc['relations'] == null
          ? SourceRelationReviewSession.create(index, graph)
          : SourceRelationReviewSession.decode(
              index, graph, npc['relations'] as String);
      final dossiers = SourceCharacterDossierIndex.build(
          index, graph, relations, catalog, editorial);
      final notebook = NpcEditorialNotebook.decode(
          index, dossiers, graph, catalog, editorial,
          npc['notebook'] as String);
      final rules = NpcKnowledgeRulebook.decode(
          index: index, dossiers: dossiers, graph: graph,
          catalog: catalog, editorial: editorial,
          notebook: notebook, scenario: draft,
          raw: npc['rules'] as String);
      final quotes = Map<String, String>.from(
          npc['source_quotes_by_rule_id'] as Map);
      final rawSocial = npc['reviewed_npc_social'];
      final rawItems = npc['reviewed_book_items'];
      final rawTurns = npc['reviewed_dialogue_turns'];
      final rawBindings = npc['reviewed_speaker_bindings'];
      if (rawSocial != null && rawSocial is! Map ||
          rawItems != null && rawItems is! List ||
          rawTurns != null && rawTurns is! Map ||
          rawBindings != null && rawBindings is! Map) {
        throw const FormatException('Некорректный проверенный пакет NPC');
      }
      final items = <Map<String, dynamic>>[
        if (rawItems is List)
          for (final item in rawItems)
            Map<String, dynamic>.from(item as Map),
      ];
      final turns = <String, List<Map<String, dynamic>>>{
        if (rawTurns is Map)
          for (final entry in rawTurns.entries)
            entry.key as String: [
              for (final turn in entry.value as List)
                Map<String, dynamic>.from(turn as Map),
            ],
      };
      bytes = await compileReviewedNpcRichPrivateBookworldInWorker(
        index, graph, catalog, editorial, draft,
        npcRules: rules, npcNotebook: notebook, npcDossiers: dossiers,
        sourceQuoteByRuleId: quotes, userConfirmed: true,
        heroName: hero,
        reviewedNpcSocial: rawSocial == null ? null :
            Map<String, dynamic>.from(rawSocial as Map),
        reviewedBookItems: items,
        reviewedDialogueTurns: turns,
        reviewedSpeakerBindings: rawBindings == null
            ? const <String, String>{}
            : Map<String, String>.from(rawBindings as Map),
      );
    }
    // A different, strict importer is the final authority; no "accepted"
    // or "AI completed" flag from the bundle overrides the game engine.
    final verified = const RichPrivateBookworldImporter().inspect(bytes);
    if (verified.sourceFingerprint != index.sourceFingerprint ||
        verified.blueprint.scenes.length != draft.scenes.length ||
        verified.canDistributePublicly || verified.requiresNetwork) {
      throw const FormatException(
          'Пакет не совпадает с проверенной частной редакцией');
    }
    return bytes;
  }
}
