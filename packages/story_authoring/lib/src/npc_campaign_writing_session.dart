import 'dart:convert';
import 'package:story_core/story_core.dart' show canonicalJson;
import 'package:crypto/crypto.dart';
import 'npc_inventory_writing_context.dart';
import 'whole_book_npc_campaign.dart';

String npcWritingHash(Object value) => sha256.convert(utf8.encode(canonicalJson(value))).toString();

/// Exact authoring inputs. Legacy per-act catalogs keep their original
/// hashes/addresses; accepted story text has a separate explicit binding.
class NpcWritingCatalog {
  NpcWritingCatalog._(this.source, this.candidates, this.digest, this.storageKey);
  final WholeBookNpcSourcePlan source;
  final Map<String, BookwideNpcConversationCandidate> candidates;
  final String digest, storageKey;

  factory NpcWritingCatalog({required WholeBookNpcSourcePlan source,
    required List<BookwideNpcConversationCandidate> candidates}) {
    final sorted = [...candidates]..sort((a, b) => a.id.compareTo(b.id));
    if (sorted.map((c) => c.id).toSet().length != sorted.length) {
      throw const FormatException('Повторён разговор NPC.');
    }
    final narrative = source.narrative;
    if (narrative != null) source.verifyCurrentHero(narrative.context.roles);
    for (final c in sorted) {
      c.firstEvent.source.validate(source.index); c.responseEvent.source.validate(source.index);
      if (c.role.sourceFingerprint != source.index.sourceFingerprint ||
          c.role.characterId == source.selectedHeroRole?.characterId) {
        throw const FormatException('NPC относится к другой книге или совпадает с героем.');
      }
      if (narrative != null) {
        final roles = narrative.context.roles.where((role) => role.characterId == c.role.characterId).toList();
        if (roles.length != 1 || WholeBookNpcSourcePlan.roleDigest(roles.single) !=
            WholeBookNpcSourcePlan.roleDigest(c.role)) {
          throw const FormatException('Карточка собеседника не совпала с принятой историей.');
        }
        narrative.forConversation(characterId: c.role.characterId,
          firstEventId: c.firstEvent.id, responseEventId: c.responseEvent.id);
      }
    }
    final digest = npcWritingHash({
      'format': 'npc_writing_catalog_v1',
      'source': source.index.sourceFingerprint, 'plan': source.planDigest,
      if (source.selectedHeroRole != null) 'hero_review': source.heroReviewDigest,
      if (narrative != null) 'accepted_story_review': narrative.reviewDigest,
      'candidates': [for (final c in sorted) {
        'id': c.id, 'actor': c.role.characterId, 'name': c.role.displayName,
        'group': c.role.groupDigest, 'first_scene': c.firstSceneId, 'response_scene': c.responseSceneId,
        'first_quote': c.firstEvent.source.quote, 'response_quote': c.responseEvent.source.quote,
      }],
    });
    return NpcWritingCatalog._(source,
      Map.unmodifiable({for (final c in sorted) c.id: c}), digest,
      npcWritingHash({'scope': 'npc_authoring_v1',
        'source': source.index.sourceFingerprint, 'plan': source.planDigest,
        if (narrative != null) 'accepted_story_review': narrative.reviewDigest}),
    );
  }
}

class NpcWritingEdit {
  NpcWritingEdit({required this.id, this.playerLine = '', this.npcLine = '',
    Iterable<String> dependencies = const [], this.uncertainty = '',
    this.origin = 'manual', this.noSuggestion = false})
      : dependencies = List.unmodifiable(dependencies);
  final String id, playerLine, npcLine, uncertainty, origin;
  final List<String> dependencies;
  final bool noSuggestion;
  bool get isBlank => playerLine.isEmpty && npcLine.isEmpty && !noSuggestion;
  bool get complete => !noSuggestion && playerLine.trim().length >= 4 && npcLine.trim().length >= 4;
  NpcCampaignDialogueDraft toDraft() => NpcCampaignDialogueDraft(
    candidateId: id, playerLine: playerLine.trim(), npcLine: npcLine.trim(), requiresCandidateIds: dependencies);
  Map<String, dynamic> toJson() => {
    'id': id, 'player_line': playerLine, 'npc_line': npcLine,
    'dependencies': dependencies.toList()..sort(),
    'uncertainty': uncertainty, 'origin': origin, 'no_suggestion': noSuggestion,
  };
}

class NpcWritingSession {
  NpcWritingSession._(this.catalogDigest, this.revision, Iterable<NpcWritingEdit> edits)
      : edits = Map.unmodifiable({for (final e in edits) e.id: e});
  final String catalogDigest;
  final int revision;
  final Map<String, NpcWritingEdit> edits;
  /// Only a validated, exact-catalog editor state may be restored.
  factory NpcWritingSession.verified(NpcWritingCatalog catalog,
      int revision, Iterable<NpcWritingEdit> values) {
    if (revision < 0 || revision > 100000) {
      throw const FormatException('Недопустимая ревизия диалога NPC.');
    }
    final edits = List<NpcWritingEdit>.unmodifiable(values);
    NpcWritingDraftRules.validateEdits(catalog, edits);
    return NpcWritingSession._(catalog.digest, revision, edits);
  }

  bool get canInstallDirectly => false;
  bool get cloudConsent => false;
  bool get literaryCanon => false;
  String get snapshotDigest => npcWritingHash({
    'catalog': catalogDigest, 'revision': revision,
    'edits': edits.map((id, edit) => MapEntry(id, edit.toJson())),
  });
}

/// Deterministic NPC dependency graph and author text gate.
class NpcWritingDraftRules {
  const NpcWritingDraftRules._();
  static void validateEdits(NpcWritingCatalog catalog, Iterable<NpcWritingEdit> values) {
    final rows = values.toList(), byId = {for (final e in values) e.id: e};
    if (rows.length > 32 || byId.length != rows.length) {
      throw const FormatException('Слишком много или повторены разговоры.');
    }
    for (final e in rows) {
      if (!catalog.candidates.containsKey(e.id) ||
          e.playerLine.length > 400 || e.npcLine.length > 400 || e.uncertainty.length > 350 ||
          !const ['manual', 'ai_draft'].contains(e.origin) || e.dependencies.length > 8 ||
          e.dependencies.toSet().length != e.dependencies.length ||
          e.dependencies.any((id) => id == e.id || !byId.containsKey(id)) ||
          (e.noSuggestion && (e.origin != 'ai_draft' || e.playerLine.isNotEmpty || e.npcLine.isNotEmpty)) ||
          [e.playerLine, e.npcLine, e.uncertainty].any((text) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(text))) {
        throw const FormatException('Черновик содержит чужие или неверные данные.');
      }
    }
    final visiting = <String>{}, checked = <String>{};
    void visit(String id) {
      if (checked.contains(id)) return;
      if (!visiting.add(id)) throw const FormatException('Круговая зависимость разговоров.');
      for (final dependency in byId[id]!.dependencies) { visit(dependency); }
      visiting.remove(id); checked.add(id);
    }
    for (final id in byId.keys) { visit(id); }
  }

}

/// Only blank selected conversations are transmitted. Inventory AND accepted
/// story context are present in the exact displayed bytes and approval hash.
class NpcWritingRequest {
  NpcWritingRequest._(this.catalogDigest, this.revision, this.batches,
      this.approvalDigest, this.candidateCount, this.inventoryContext, this.storyReviewDigest);
  final String catalogDigest, approvalDigest;
  final int revision, candidateCount;
  final List<String> batches;
  final NpcInventoryWritingContext? inventoryContext;
  final String? storyReviewDigest;
  bool get hasStoryContext => storyReviewDigest != null;
  int get requestCount => batches.length;
  int get maximumAttempts => requestCount * 3;
  String get shownText => batches.map((b) =>
      const JsonEncoder.withIndent('  ').convert(jsonDecode(b))).join('\n\n');

  static NpcWritingRequest prepare(NpcWritingCatalog catalog,
      NpcWritingSession session, {int perRequest = 3, NpcInventoryWritingContext? inventoryContext}) {
    if (session.catalogDigest != catalog.digest || perRequest < 1 || perRequest > 4) {
      throw const FormatException('Неверная редакция подготовки NPC.');
    }
    inventoryContext?.validateSource(catalog.source);
    NpcWritingDraftRules.validateEdits(catalog, session.edits.values);
    final narrative = catalog.source.narrative;
    final pending = session.edits.values.where((e) => e.isBlank).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (pending.isEmpty) throw const FormatException('Нет пустых разговоров для ИИ. '
        'Готовые и вручную изменённые реплики сохранены.');
    final batches = <String>[];
    String encode(List<NpcWritingEdit> edits) {
      final rows = edits.map((edit) {
        final c = catalog.candidates[edit.id]!;
        return <String, dynamic>{
          'candidate_id': c.id, 'actor_id': c.role.characterId, 'speaker': c.role.displayName,
          'first_chapter': c.firstEvent.source.chapterIndex, 'response_chapter': c.responseEvent.source.chapterIndex,
          'first_quote': c.firstEvent.source.quote, 'response_quote': c.responseEvent.source.quote,
          'requires_episodes': edit.dependencies,
          if (inventoryContext != null) 'player_inventory_routes': inventoryContext.forConversation(c),
          if (narrative != null) 'story_guidance': narrative.forConversation(
            characterId: c.role.characterId, firstEventId: c.firstEvent.id, responseEventId: c.responseEvent.id),
          'game_rule': 'The NPC remembers only this approved private game meeting; '
              'do not invent source truth, objects, secrets, actions or new actors.',
        };
      }).toList();
      final payload = <String, dynamic>{
        'format': 'ai_story_npc_writing_request_v1',
        'status': 'UNTRUSTED_PRIVATE_GAME_FICTION',
        if (catalog.source.selectedHeroRole != null) 'player_role': catalog.source.heroCloudContext,
        if (inventoryContext != null) 'inventory_context': inventoryContext.cloudHeader,
        if (narrative != null) 'accepted_story_context': narrative.cloudHeader,
        'conversations': rows,
      };
      payload['batch_id'] = npcWritingHash({'catalog': catalog.digest, 'payload': payload});
      return canonicalJson(payload);
    }
    for (var offset = 0; offset < pending.length;) {
      var count = pending.length - offset < perRequest ? pending.length - offset : perRequest;
      var encoded = encode(pending.skip(offset).take(count).toList());
      // Split, never discard approved story, inventory, evidence or a speaker.
      while (utf8.encode(encoded).length > 10 * 1024 && count > 1) {
        count--; encoded = encode(pending.skip(offset).take(count).toList());
      }
      if (utf8.encode(encoded).length > 10 * 1024) {
        throw const FormatException('Передаваемые фрагменты превышают лимит запроса.');
      }
      batches.add(encoded); offset += count;
    }
    final immutable = List<String>.unmodifiable(batches);
    return NpcWritingRequest._(catalog.digest, session.revision, immutable,
      npcWritingHash({'format': 'npc_writing_consent_v1',
        'catalog': catalog.digest, 'revision': session.revision, 'batches': immutable}),
      pending.length, inventoryContext, narrative?.reviewDigest);
  }
}
