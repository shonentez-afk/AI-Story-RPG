import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:story_core/story_core.dart';

import 'whole_book_npc_campaign.dart';

String _digest(Object value) => sha256.convert(utf8.encode(canonicalJson(value))).toString();

/// Data-only isolate: the archive is independently imported before the real
/// story_core traversal. No book file, key, network, save or live UI is used.
String _inspectInventory(Map<String, dynamic> input) {
  final game = const RichPrivateBookworldImporter().inspect(input['archive'] as Uint8List);
  final ids = (input['scenes'] as List).cast<String>();
  final evidence = StoryInventoryRouteAudit.inspect(
    blueprint: game.blueprint, sceneIds: ids, socialRulebook: game.npcSocialRulebook,
  );
  final names = game.presentation['item_names'] as Map;
  final items = game.blueprint.items.toList()..sort();
  final itemNames = <String, String>{};
  for (final id in items) {
    final name = names[id];
    if (name is! String || name.trim().isEmpty || name.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException('Предмет не имеет проверенной подписи.');
    }
    itemNames[id] = name;
  }
  return canonicalJson({
    'header': {
      'format': 'ai_story_npc_inventory_context_v1',
      'scope': 'reviewed_base_routes_before_npc_overlay',
      'archive_sha256': game.archiveSha256,
      'blueprint_sha256': evidence.blueprintHash,
      'source_fingerprint': game.sourceFingerprint,
      'describes_current_save': false,
      'grants_npc_knowledge': false,
      'literary_canon_verified': false,
      'item_names': itemNames,
    },
    'scenes': {for (final id in ids) id: {
      'scene_id': id,
      'always_present': evidence.scenes[id]!.alwaysPresent.toList()..sort(),
      'branch_dependent': evidence.scenes[id]!.possiblyPresent
          .difference(evidence.scenes[id]!.alwaysPresent).toList()..sort(),
      'never_present': evidence.scenes[id]!.neverPresent.toList()..sort(),
    }},
  });
}

/// Only constructed from a strictly imported, exact author-approved base.
/// It is not a Map supplied by a model. JSON getters return detached copies.
/// The base-route scope is explicit: social dialogue gates are applied later.
final class NpcInventoryWritingContext {
  NpcInventoryWritingContext._(this._json, this.sourceFingerprint,
      this.planDigest, this.heroDigest, this.archiveSha256, this.blueprintSha256,
      Map<String, String> bindings)
      : _bindings = Map.unmodifiable(bindings),
        digest = _digest({'report': _json, 'plan': planDigest,
          'hero': heroDigest, 'conversations': bindings});

  final String _json;
  final String sourceFingerprint, planDigest, heroDigest;
  final String archiveSha256, blueprintSha256, digest;
  final Map<String, String> _bindings;

  static String _binding(BookwideNpcConversationCandidate c) => _digest({
    'id': c.id, 'actor': c.role.characterId, 'group': c.role.groupDigest,
    'name': c.role.displayName, 'first_scene': c.firstSceneId,
    'response_scene': c.responseSceneId,
    'first_quote': c.firstEvent.source.quote, 'response_quote': c.responseEvent.source.quote,
    'first_exit': c.firstExitChoiceId, 'response_exit': c.responseExitChoiceId,
  });

  void validateSource(WholeBookNpcSourcePlan source) {
    if (source.index.sourceFingerprint != sourceFingerprint ||
        source.planDigest != planDigest || source.heroReviewDigest != heroDigest ||
        sha256.convert(utf8.encode(source.plan.encode())).toString() != planDigest) {
      throw const FormatException('Инвентарь проверен для другой книги, роли или сценария.');
    }
  }

  void assertCurrent({required WholeBookNpcSourcePlan source,
    required Uint8List reviewedArchive}) {
    validateSource(source);
    if (sha256.convert(reviewedArchive).toString() != archiveSha256) {
      throw const FormatException('После согласия изменился вариант игры с предметами.');
    }
  }

  Map<String, dynamic> get cloudHeader => {
    ...Map<String, dynamic>.from((jsonDecode(_json) as Map)['header'] as Map),
    'context_sha256': digest,
  };

  Map<String, dynamic> forConversation(BookwideNpcConversationCandidate candidate) {
    if (_bindings[candidate.id] != _binding(candidate)) {
      throw const FormatException('Встреча или карточка NPC не входит в проверенный инвентарь.');
    }
    final scenes = (jsonDecode(_json) as Map)['scenes'] as Map;
    return {
      'first_scene': scenes[candidate.firstSceneId],
      'response_scene': scenes[candidate.responseSceneId],
    };
  }

  static Future<NpcInventoryWritingContext> prepare({
    required WholeBookNpcSourcePlan source,
    required Uint8List reviewedArchive,
    required Iterable<BookwideNpcConversationCandidate> conversations,
  }) async {
    // Freeze bytes before yielding. A caller cannot swap the reviewed archive
    // while the isolate is building the report.
    final bytes = Uint8List.fromList(reviewedArchive);
    final selected = List<BookwideNpcConversationCandidate>.unmodifiable(conversations);
    if (selected.isEmpty || selected.length > 32 ||
        selected.map((c) => c.id).toSet().length != selected.length) {
      throw const FormatException('Неверный набор разговоров для проверки инвентаря.');
    }
    final game = const RichPrivateBookworldImporter().inspect(bytes);
    source.verifyArchiveHero(game);
    if (game.sourceFingerprint != source.index.sourceFingerprint ||
        game.blueprint.actors.length != 1 || !game.blueprint.actors.contains('player') ||
        game.npcSocialRulebook != null || game.requiresNetwork || game.canDistributePublicly ||
        game.blueprint.scenes.keys.toSet().difference(source.plan.situations.map((s) => s.id).toSet()).isNotEmpty ||
        source.plan.situations.any((s) => !game.blueprint.scenes.containsKey(s.id))) {
      throw const FormatException('Нужна проверенная исходная кампания до добавления NPC.');
    }
    final targets = <String>{};
    final bindings = <String, String>{};
    for (final c in selected) {
      c.firstEvent.source.validate(source.index);
      c.responseEvent.source.validate(source.index);
      if (c.role.sourceFingerprint != source.index.sourceFingerprint ||
          c.role.characterId == source.selectedHeroRole?.characterId) {
        throw const FormatException('Чужая личность или разговор героя с самим собой.');
      }
      for (final part in [
        (c.firstSceneId, c.firstExitChoiceId, c.firstEvent.source.quote),
        (c.responseSceneId, c.responseExitChoiceId, c.responseEvent.source.quote),
      ]) {
        final scene = game.blueprint.scenes[part.$1];
        final exits = scene?.choices.where((choice) => choice.id == part.$2).toList();
        if (scene == null || scene.terminal || !scene.text.contains(part.$3) ||
            exits == null || exits.length != 1 ||
            exits.single.conditions.isNotEmpty || exits.single.effects.isNotEmpty) {
          throw const FormatException('NPC-встреча обходит предметный эффект или не соответствует цитате.');
        }
        targets.add(part.$1);
      }
      bindings[c.id] = _binding(c);
    }
    final json = await compute(_inspectInventory, <String, dynamic>{
      'archive': bytes, 'scenes': targets.toList()..sort(),
    });
    final result = NpcInventoryWritingContext._(json, source.index.sourceFingerprint,
      source.planDigest, source.heroReviewDigest, game.archiveSha256,
      game.blueprint.blueprintHash, bindings);
    result.assertCurrent(source: source, reviewedArchive: bytes);
    return result;
  }
}
