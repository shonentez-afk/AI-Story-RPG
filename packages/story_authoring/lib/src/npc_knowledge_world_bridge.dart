import 'dart:convert';

import 'package:story_core/story_core.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

class NpcKnowledgeBlueprintPreview {
  const NpcKnowledgeBlueprintPreview({
    required this.blueprint,
    required this.actorIds,
    required this.factIds,
    required this.story,
  });

  final Map<String, dynamic> blueprint;
  final Map<String, String> actorIds;
  final Map<String, String> factIds;
  final StoryBlueprint story;

  bool get containsOriginalNoteText => false;
  bool get sendsTextToCloud => false;
}

/// Explicitly overlays verified, editor-approved learn_fact effects onto the
/// already accepted private CLASSIC runtime schema; does not invent a second
/// rules interpreter or change story_core/story_engine/save formats.
class NpcKnowledgeWorldBridge {
  const NpcKnowledgeWorldBridge._();

  static NpcKnowledgeBlueprintPreview preview({
    required BookSourceIndex index,
    required SourceCharacterDossierIndex dossiers,
    required SourceEvidenceGraph graph,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required NpcEditorialNotebook notebook,
    required IntermediateStoryBlueprint scenario,
    required NpcKnowledgeRulebook rulebook,
    required Map<String, dynamic> originalBlueprint,
  }) {
    rulebook.validate(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial,
      notebook: notebook, scenario: scenario,
    );
    if (rulebook.rules.isEmpty ||
        originalBlueprint['source_fingerprint'] != index.sourceFingerprint ||
        originalBlueprint['rights_status'] != 'private_adaptation' ||
        jsonEncode(originalBlueprint['actors']) != '["player"]' ||
        jsonEncode(originalBlueprint['facts']) != '[]') {
      throw const FormatException(
          'Для NPC нужен исходный принятый частный сценарий с правилами');
    }

    // Deep copy: the original compiler path and other campaigns stay untouched.
    final result = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(originalBlueprint)) as Map);
    final groups = {for (final d in dossiers.dossiers) d.id: d};
    final profiles = {for (final p in notebook.profiles) p.dossierId: p};
    final actorIds = <String, String>{
      for (final profile in notebook.profiles)
        profile.dossierId: NpcKnowledgeRulebook.profileActorId(
            profile, groups[profile.dossierId]!, index.sourceFingerprint),
    };
    if (actorIds.values.toSet().length != actorIds.length ||
        actorIds.values.contains('player')) {
      throw const FormatException('Конфликт ID игровых актёров');
    }
    final scenes = {
      for (final item in result['scenes'] as List)
        (item as Map<String, dynamic>)['id'] as String: item,
    };
    final choices = <String, Map<String, dynamic>>{};
    for (final entry in scenes.values) {
      for (final item in entry['choices'] as List) {
        final choice = item as Map<String, dynamic>;
        final id = choice['id'] as String;
        if (choices.containsKey(id)) {
          throw const FormatException('Повторный ID выбора при сборке');
        }
        choices[id] = choice;
      }
    }
    final factIds = <String, String>{};
    for (final rule in rulebook.rules) {
      final source = profiles[rule.dossierId]!;
      final note = source.notes.singleWhere((n) => n.id == rule.noteId);
      final factId = NpcKnowledgeRulebook.factId(
          index.sourceFingerprint, rule.groupDigest, note);
      final key = '${rule.dossierId}|${rule.noteId}';
      final previous = factIds[key];
      if (previous != null && previous != factId) {
        throw const FormatException('Несовместимые ссылки на знание NPC');
      }
      factIds[key] = factId;
      final actor = rule.recipient == KnowledgeRecipient.player
          ? 'player' : actorIds[rule.dossierId]!;
      final choice = choices[rule.choiceId];
      if (choice == null) {
        throw const FormatException('Нет выбранного перехода сценария');
      }
      (choice['effects'] as List).add(<String, String>{
        'op': 'learn_fact', 'id': factId, 'actor': actor,
      });
    }
    // Conditions attach only to previously reviewed grants and are resolved
    // from the same opaque actor/fact catalog. Runtime checks know-before-act.
    // Full state-space reachability is independently checked by the ZIP
    // importer before this private world may be installed or played.
    for (final gate in rulebook.gates) {
      final grant = rulebook.rules.singleWhere(
          (rule) => rule.id == gate.grantRuleId);
      final fact = factIds['${grant.dossierId}|${grant.noteId}'];
      final actor = grant.recipient == KnowledgeRecipient.player
          ? 'player' : actorIds[grant.dossierId];
      final choice = choices[gate.choiceId];
      if (fact == null || actor == null || choice == null) {
        throw const FormatException(
            'Недействительная привязка условия знания NPC');
      }
      (choice['conditions'] as List).add(<String, String>{
        'op': 'knows_fact', 'id': fact, 'actor': actor,
      });
    }
    result['actors'] = <String>[
      'player', ...(actorIds.values.toList()..sort()),
    ];
    result['facts'] = factIds.values.toSet().toList()..sort();
    final initial = result['initial_state'] as Map<String, dynamic>;
    final knowledge = initial['knowledge'] as Map<String, dynamic>;
    for (final actor in actorIds.values) {
      knowledge[actor] = <String>[];
    }

    // New rules imply a different private world identity. A campaign for the
    // old version cannot silently load the modified world or its fact catalog.
    final oldId = originalBlueprint['book_id'] as String;
    // A newly assigned permanent actor changes the ID namespace even if
    // the exact same knowledge rules are reused. Otherwise an older
    // campaign could load against a distinct actor under the same book ID.
    // Preserve the existing identity for old profiles with NO card; they
    // are not silently migrated into a new world.
    final hasPermanentNpcIds =
        notebook.profiles.any((profile) => profile.characterId != null);
    final identityMaterial = hasPermanentNpcIds
        ? jsonEncode({
            'rules': rulebook.encode(),
            'actor_ids': actorIds.values.toList()..sort(),
          })
        : rulebook.encode();
    final suffix = NpcKnowledgeRulebook.digest(identityMaterial)
        .substring(0, 12);
    result['book_id'] = '${oldId}_$suffix';

    final canonical = StoryBlueprint.fromJson(result);
    if (canonical.sourceFingerprint != index.sourceFingerprint ||
        canonical.actors.length != actorIds.length + 1 ||
        canonical.facts.length != factIds.values.toSet().length) {
      throw const FormatException('Не удалось проверить игровой каталог NPC');
    }

    // Privacy gate: only opaque IDs cross the runtime boundary.
    final serialized = jsonEncode(result);
    for (final profile in notebook.profiles) {
      for (final note in profile.notes) {
        if (note.text.isNotEmpty && serialized.contains(note.text)) {
          throw const FormatException('Раскрыт авторский текст в игровом мире');
        }
      }
    }

    return NpcKnowledgeBlueprintPreview(
      blueprint: result,
      actorIds: Map.unmodifiable(actorIds),
      factIds: Map.unmodifiable(factIds),
      story: canonical,
    );
  }
}
