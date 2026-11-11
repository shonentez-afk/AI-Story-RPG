import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'src/sqlite_v1.dart';
import 'private_gameplay_review.dart';
import 'rich_scene_dialogue.dart';
import 'npc_dialogue_knowledge.dart';
import 'npc_dialogue_responses.dart';
import 'npc_social_contract.dart';
import 'canon_causal_contract.dart';
import 'src/zip_v1.dart';

/// A private, source-bound, offline CLASSIC package. No permission to publish.
class VerifiedRichPrivateBookworld {
  const VerifiedRichPrivateBookworld({
    required this.blueprint,
    required this.sourceFingerprint,
    required this.archiveSha256,
    required this.provenanceSha256,
    required this.presentation,
    this.sourceTitle = '',
    this.sourceChaptersTotal = 0,
    this.sourceChaptersIndexed = 0,
    this.sceneOrigins = const {},
    this.npcSocialRulebook,
    this.formatVersion = 3,
  });
  final StoryBlueprint blueprint;
  final String sourceFingerprint, archiveSha256, provenanceSha256;
  final Map<String, dynamic> presentation;
  /// Exact source fields checked against signed manifest and ZIP.
  final String sourceTitle;
  final int sourceChaptersTotal, sourceChaptersIndexed;
  final Map<String, VerifiedBookSceneOrigin> sceneOrigins;
  final NpcSocialRulebook? npcSocialRulebook;
  /// v3/v4 are alternative fiction; v5 is full-source literal CANON.
  final int formatVersion;
  bool get sourceLiteralCanonVerified =>
      formatVersion == 5 && blueprint.isReviewedCanon;
  String get bookworldId => blueprint.bookId;
  bool get canDistributePublicly => false;
  bool get requiresNetwork => false;
}

/// Canonically verified provenance of ONE signed book scene.
final class VerifiedBookSceneOrigin {
  const VerifiedBookSceneOrigin({
    required this.sceneId, required this.chapterIndex,
    required this.origin,
    this.sourceQuoteSha256,
  });
  final String sceneId, origin;
  /// Verified opening quotation of this scene; for authoring only.
  final String? sourceQuoteSha256;
  final int chapterIndex;
  bool get isSourcePassage => origin == 'SOURCE_PASSAGE';
}

/// Strict rich-v3 reader. Existing source/manifest/causal checks remain
/// authoritative; composition joins independently checked effect coverage.
class RichPrivateBookworldImporter {
  const RichPrivateBookworldImporter();
  static const _payloadPaths = {
    'scenario/blueprint.json', 'source/provenance.json', 'world.sqlite',
  };
  static final _sha = RegExp(r'^[a-f0-9]{64}$');

  Map<String, dynamic> _object(Uint8List bytes, String part) {
    final Object? object;
    try {
      object = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (_) { throw FormatException('Некорректный JSON $part'); }
    if (object is! Map<String, dynamic>) {
      throw FormatException('$part должен быть объектом');
    }
    if (canonicalJson(object) != utf8.decode(bytes, allowMalformed: false)) {
      throw FormatException('Неоднозначный или неканонический JSON $part');
    }
    return object;
  }

  bool _same(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);
  void _fields(Map<String, dynamic> m, Set<String> fields, String part) {
    if (m.length != fields.length || !m.keys.toSet().containsAll(fields)) {
      throw FormatException('$part: неизвестные или отсутствующие поля');
    }
  }

  void _provenance(Map<String, dynamic> source, StoryBlueprint blueprint,
      {bool literalCanon = false}) {
    const fields = {
      'format', 'bookworld_id', 'source_fingerprint', 'source_title',
      'source_author', 'source_chapters_total', 'source_chapters_indexed',
      'semantic_catalog_sha256', 'intermediate_draft_sha256',
      'rights_status', 'publication_authorized', 'model_provenance', 'scene_origins',
    };
    _fields(source, fields, 'provenance');
    if (source['format'] != 'ai_story_private_provenance_v1' ||
        source['bookworld_id'] != blueprint.bookId ||
        source['source_fingerprint'] != blueprint.sourceFingerprint ||
        source['source_title'] is! String ||
        (source['source_title'] as String).trim().isEmpty ||
        (source['source_title'] as String).length > 256 ||
        source['source_author'] is! String || (source['source_author'] as String).length > 256 ||
        source['semantic_catalog_sha256'] is! String || !_sha.hasMatch(source['semantic_catalog_sha256'] as String) ||
        source['intermediate_draft_sha256'] is! String || !_sha.hasMatch(source['intermediate_draft_sha256'] as String) ||
        source['rights_status'] != 'private_use_only' || source['publication_authorized'] != false ||
        !_same(source['model_provenance'], {'provider': 'none', 'model_id': null})) {
      throw const FormatException('Подмена прав или привязки источника');
    }
    final total = source['source_chapters_total'];
    final indexed = source['source_chapters_indexed'];
    if (total is! int || indexed is! int || total < 1 || total > 10000 || indexed < 1 || indexed > total) {
      throw const FormatException('Неверный охват исходной книги');
    }
    final origins = source['scene_origins'];
    if (origins is! List || origins.length != blueprint.scenes.length) {
      throw const FormatException('Нет происхождения игровых сцен');
    }
    final compiledScenes = blueprint.scenes.keys.toList();
    final sceneIds = <String>{};
    var originalScenes = 0, adaptations = 0;
    for (var i = 0; i < origins.length; i++) {
      final entry = origins[i];
      if (entry is! Map<String, dynamic>) throw const FormatException('Некорректная запись происхождения');
      _fields(entry, {'scene_id', 'chapter_index', 'origin', 'assertion_ids', 'source_refs'}, 'scene provenance');
      final sceneId = entry['scene_id'];
      final chapter = entry['chapter_index'];
      final origin = entry['origin'];
      final claims = entry['assertion_ids'];
      final refs = entry['source_refs'];
      if (sceneId != compiledScenes[i] || !sceneIds.add(sceneId as String) ||
          chapter is! int || chapter < 0 || chapter >= total ||
          (origin != 'SOURCE_PASSAGE' && origin != 'EXPLICIT_ADAPTATION') ||
          claims is! List || claims.length > 24 || claims.any((v) => v is! String || !_shaId(v)) ||
          claims.toSet().length != claims.length || refs is! List || refs.length > 72) {
        throw const FormatException('Несовместимое происхождение игровой сцены');
      }
      if (origin == 'SOURCE_PASSAGE') {
        originalScenes++;
        if (claims.isEmpty || refs.isEmpty) throw const FormatException('Каноническая сцена без доказательств');
      } else { adaptations++; }
      final usedRefs = <String>{};
      for (final raw in refs) {
        if (raw is! Map<String, dynamic>) throw const FormatException('Некорректный источник сцены');
        _fields(raw, {
          'id', 'chunk_id', 'chapter_id', 'chapter_index', 'block_index',
          'start_utf16', 'end_utf16', 'quote_sha256', 'visible_after_chapter',
        }, 'source ref');
        final citationId = raw['id'];
        final chunkId = raw['chunk_id'];
        final chapterId = raw['chapter_id'];
        final index = raw['chapter_index'];
        final visible = raw['visible_after_chapter'];
        final start = raw['start_utf16'];
        final end = raw['end_utf16'];
        if (citationId is! String || !_shaId(citationId) || !usedRefs.add(citationId) ||
            chunkId is! String || chunkId.isEmpty || chunkId.length > 120 ||
            chapterId is! String || chapterId.isEmpty || chapterId.length > 120 ||
            index is! int || index < 0 || index >= total || index > chapter ||
            raw['block_index'] is! int || (raw['block_index'] as int) < 0 ||
            visible is! int || visible < index || visible > chapter ||
            start is! int || start < 0 || end is! int || end <= start || end - start > 180 ||
            raw['quote_sha256'] is! String || !_sha.hasMatch(raw['quote_sha256'] as String)) {
          throw const FormatException('Подмена диапазона или спойлер источника');
        }
      }
    }
    if (originalScenes == 0 ||
        (literalCanon ? adaptations != 0 : adaptations == 0)) {
      throw const FormatException('Invalid source/alternative scene mixture');
    }
  }

  bool _shaId(Object? value) => value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

  void _manifest(Map<String, dynamic> manifest, StoryBlueprint blueprint,
      Map<String, dynamic> provenance, Map<String, Uint8List> files,
      {bool literalCanon = false}) {
    const keys = {
      'format', 'format_version', 'bookworld_id', 'source_fingerprint', 'title', 'author',
      'languages', 'engine_min_version', 'scenario_format', 'scenario_format_version',
      'content_capabilities', 'build_status', 'hashes', 'sizes', 'build_tool',
      'model_provenance', 'rights_status', 'blueprint_sha256',
    };
    _fields(manifest, {
      ...keys,
      if (literalCanon) 'canon_review_format',
      if (literalCanon && manifest.containsKey('canon_causality_format'))
        'canon_causality_format',
    }, 'manifest');
    if (manifest['format'] != 'ai_story_bookworld' ||
        manifest['format_version'] != (literalCanon ? 5 : 2) ||
        manifest['bookworld_id'] != blueprint.bookId || manifest['source_fingerprint'] != blueprint.sourceFingerprint ||
        manifest['title'] != blueprint.title || manifest['author'] != provenance['source_author'] ||
        !_same(manifest['languages'], ['ru']) || manifest['engine_min_version'] != '0.1.0' ||
        manifest['scenario_format'] != 'ai_story_blueprint_v1' || manifest['scenario_format_version'] != 1 ||
        !_same(manifest['content_capabilities'], literalCanon ? {
          'roles': ['PROTAGONIST'], 'plots': ['CANON'],
          'interactions': ['AI_FREEFORM'],
        } : {
          'roles': ['PROTAGONIST'], 'plots': ['ALTER_FATE'],
          'interactions': ['CLASSIC'],
        }) || manifest['build_status'] !=
            (literalCanon ? 'private_literal_canon_reviewed' :
                'private_classic_structural') ||
        manifest['rights_status'] != 'private_use_only' || manifest['blueprint_sha256'] != blueprint.blueprintHash ||
        !_same(manifest['build_tool'], literalCanon
            ? {'name': 'ai_story_literal_canon_bookworld', 'version': '5.0'}
            : {'name': 'ai_story_private_bookworld', 'version': '2.0'}) ||
        (literalCanon && manifest['canon_review_format'] !=
            'ai_story_literal_canon_review_v1') ||
        !_same(manifest['model_provenance'], literalCanon
            ? provenance['model_provenance']
            : {'provider': 'none', 'model_id': null})) {
      throw const FormatException('Формат частной адаптации не подтверждён');
    }
    final sizes = manifest['sizes'], hashes = manifest['hashes'];
    if (sizes is! Map<String, dynamic> || hashes is! Map<String, dynamic> ||
        sizes.length != _payloadPaths.length || hashes.length != _payloadPaths.length ||
        !sizes.keys.toSet().containsAll(_payloadPaths) || !hashes.keys.toSet().containsAll(_payloadPaths)) {
      throw const FormatException('Отсутствует контроль вложений .bworld');
    }
    for (final path in _payloadPaths) {
      final bytes = files[path]!;
      if (sizes[path] is! int || sizes[path] != bytes.length || hashes[path] != sha256.convert(bytes).toString()) {
        throw FormatException('Размер или SHA-256 не совпадает: $path');
      }
    }
  }

  /// Exact bounded state exploration includes each actor's knowledge and
  /// inventory. It also rejects closed loops through reverse reachability.
  void _causality(StoryBlueprint blueprint,
      {bool expanded = false, bool literalCanon = false}) {
    if (blueprint.scenes.length < (literalCanon ? 1 : 3) ||
        blueprint.scenes.length > (literalCanon ? 5000 : (expanded ? 1024 : 192)) ||
        blueprint.items.length > (expanded ? 96 : 32) ||
        blueprint.facts.length > (expanded ? 128 : 64) ||
        blueprint.initial.stats.length > (expanded ? 16 : 8) ||
        blueprint.initial.flags.length > (expanded ? 64 : 32) ||
        blueprint.actors.length > 16 || !blueprint.actors.contains('player') ||
        (!expanded && blueprint.initial.inventory.isNotEmpty) ||
        (!expanded && blueprint.initial.tick != 0) ||
        blueprint.initial.knowledge.length != blueprint.actors.length ||
        !blueprint.initial.knowledge.keys.toSet().containsAll(blueprint.actors) ||
        (!expanded && blueprint.initial.knowledge.values.any((facts) => facts.isNotEmpty)) ||
        blueprint.initial.stats.values.any((v) => v < 0 || v > 1000)) {
      throw const FormatException('Некорректные каталоги RPG v3');
    }
    final seenItemGrants = <String>{}, seenFactGrants = <String>{};
    for (final scene in blueprint.scenes.values) {
      for (final choice in scene.choices) {
        if (choice.conditions.length > 32 || choice.effects.length > 32) throw const FormatException('Слишком сложные правила RPG v3');
        for (final condition in choice.conditions) {
          switch (condition.op) {
            case 'flag_is':
              if (!blueprint.initial.flags.containsKey(condition.id)) throw const FormatException('Неизвестный сюжетный флаг');
            case 'has_item':
              if (!blueprint.items.contains(condition.id)) throw const FormatException('Неизвестный требуемый предмет');
            case 'stat_at_least':
              if (!blueprint.initial.stats.containsKey(condition.id)) throw const FormatException('Неизвестная характеристика');
            case 'knows_fact':
              if (!blueprint.facts.contains(condition.id) || !blueprint.actors.contains(condition.actor)) throw const FormatException('Чужое знание нельзя использовать');
            case 'tick_at_least':
              if (!expanded || condition.amount == null || condition.amount! < 0 || condition.amount! > 100000000) throw const FormatException('Недопустимое игровое время');
            default: throw const FormatException('Недопустимое условие RPG v3');
          }
        }
        for (final effect in choice.effects) {
          switch (effect.op) {
            case 'set_flag':
              if (!blueprint.initial.flags.containsKey(effect.id)) throw const FormatException('Неизвестный флаг эффекта');
            case 'grant_item':
              if (!blueprint.items.contains(effect.id)) throw const FormatException('Несуществующий предмет');
              seenItemGrants.add(effect.id!);
            case 'consume_item':
              if (!blueprint.items.contains(effect.id)) throw const FormatException('Несуществующий предмет');
            case 'stat_delta':
              if (!blueprint.initial.stats.containsKey(effect.id) || effect.amount == null || effect.amount == 0 ||
                  effect.amount! < -20 || effect.amount! > 20) throw const FormatException('Недопустимое изменение героя');
            case 'learn_fact':
              if (!blueprint.facts.contains(effect.id) || !blueprint.actors.contains(effect.actor)) throw const FormatException('Непроверенное знание');
              seenFactGrants.add(effect.id!);
            case 'advance_time':
              if (!expanded || effect.amount == null || effect.amount! < 1 || effect.amount! > 1000) throw const FormatException('Недопустимое продвижение времени');
            default: throw const FormatException('Недопустимый эффект RPG v3');
          }
        }
      }
    }
    final reserved = literalCanon
        ? <String>{...blueprint.items.where((id) => id.startsWith('gm_')),
                   ...blueprint.facts.where((id) => id.startsWith('gm_'))}
        : <String>{};
    if (!seenItemGrants.union(expanded ? blueprint.initial.inventory : const <String>{})
            .union(reserved).containsAll(blueprint.items) ||
        !seenFactGrants.union(expanded ? blueprint.initial.knowledge.values.expand((known) => known).toSet() : const <String>{})
            .union(reserved).containsAll(blueprint.facts)) {
      throw const FormatException('Каталог не связан с игровыми действиями');
    }
    // An action advances clock time by one even without an explicit effect.
    // Saturate the search key at the highest threshold that ANY decision
    // reads. Later ticks are logically indistinguishable for predicates;
    // enumerating absolute time in a wait-loop would never terminate.
    final relevantTick = expanded ? blueprint.scenes.values
        .expand((scene) => scene.choices)
        .expand((choice) => choice.conditions)
        .where((condition) => condition.op == 'tick_at_least')
        .fold<int>(0, (maxValue, c) =>
            c.amount! > maxValue ? c.amount! : maxValue) : 0;
    final futureFlags = expanded
        ? FutureFlagLiveness.fromBlueprint(blueprint) : null;
    final start = (
      blueprint.entrySceneId,
      blueprint.initial.flags.entries.where((e) => e.value).map((e) => e.key).toSet(),
      expanded ? Set<String>.of(blueprint.initial.inventory) : <String>{},
      Map<String, int>.of(blueprint.initial.stats),
      {for (final actor in blueprint.actors) actor: expanded ? Set<String>.of(blueprint.initial.knowledge[actor] ?? const <String>{}) : <String>{}},
      expanded ? blueprint.initial.tick : 0,
    );
    String keyOf((String, Set<String>, Set<String>, Map<String, int>, Map<String, Set<String>>, int) state) => canonicalJson({
      'scene': state.$1,
      // Proof-only projection: source-backed WorldState keeps ALL outcomes.
      'flags': (futureFlags == null ? state.$2 :
          state.$2.intersection(futureFlags.at(state.$1))).toList()..sort(),
      'inventory': state.$3.toList()..sort(), 'stats': state.$4,
      'knowledge': {for (final actor in blueprint.actors) actor: state.$5[actor]!.toList()..sort()},
      'tick': expanded && state.$6 < relevantTick ? state.$6 : relevantTick,
    });
    final seen = <String>{keyOf(start)}, visited = <String>{};
    final parent = <String, Set<String>>{};
    final terminals = <String>{}, endings = <String>{};
    final queue = [start];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (seen.length > (expanded ? 8000 : 2500)) throw const FormatException('Превышено число игровых состояний');
      final s = queue[cursor];
      final scene = blueprint.scenes[s.$1]!;
      final here = keyOf(s);
      visited.add(s.$1);
      if (scene.terminal) { terminals.add(here); endings.add(s.$1); continue; }
      var choicesAvailable = 0;
      for (final choice in scene.choices) {
        var allowed = true;
        for (final condition in choice.conditions) {
          final meets = switch (condition.op) {
            'flag_is' => s.$2.contains(condition.id) == condition.value,
            'has_item' => s.$3.contains(condition.id),
            'stat_at_least' => s.$4[condition.id!]! >= condition.amount!,
            'knows_fact' => s.$5[condition.actor!]!.contains(condition.id),
            'tick_at_least' => expanded && s.$6 >= condition.amount!,
            _ => false,
          };
          if (!meets) { allowed = false; break; }
        }
        if (!allowed) continue;
        choicesAvailable++;
        final flags = Set<String>.of(s.$2), items = Set<String>.of(s.$3);
        final stats = Map<String, int>.of(s.$4);
        final facts = s.$5.map((actor, known) => MapEntry(actor, Set<String>.of(known)));
        var tick = s.$6 + 1;
        if (tick > 100000000) throw const FormatException('Переполнение времени');
        for (final effect in choice.effects) {
          switch (effect.op) {
            case 'set_flag':
              if (effect.value!) { flags.add(effect.id!); } else { flags.remove(effect.id!); }
            case 'grant_item': items.add(effect.id!);
            case 'consume_item':
              if (!items.remove(effect.id)) throw const FormatException('Действие расходует отсутствующий предмет');
            case 'stat_delta':
              final updated = stats[effect.id!]! + effect.amount!;
              if (updated < 0 || updated > 1000000) throw const FormatException('Характеристика вне границ');
              stats[effect.id!] = updated;
            case 'learn_fact': facts[effect.actor!]!.add(effect.id!);
            case 'advance_time':
              if (!expanded || tick + effect.amount! > 100000000) throw const FormatException('Переполнение игрового времени');
              tick += effect.amount!;
            default: throw const FormatException('Непредусмотренный игровой эффект');
          }
        }
        final next = (choice.nextSceneId, flags, items, stats, facts, tick);
        final dest = keyOf(next);
        parent.putIfAbsent(dest, () => <String>{}).add(here);
        if (seen.add(dest)) queue.add(next);
      }
      if (choicesAvailable == 0) throw const FormatException('Тупик без доступного действия');
    }
    if (endings.length < (literalCanon ? 1 : 2) ||
        visited.length != blueprint.scenes.length) {
      throw const FormatException('Missing reachable ending or canonical chunk');
    }
    final escapable = <String>{...terminals};
    final work = terminals.toList();
    while (work.isNotEmpty) {
      final current = work.removeLast();
      for (final p in parent[current] ?? const <String>{}) { if (escapable.add(p)) work.add(p); }
    }
    if (escapable.length != seen.length) throw const FormatException('Зацикленный путь без финала');
  }

  static const npcKnowledgeFormat = 'ai_story_npc_knowledge_grants_v1';

  /// Return only the precise scene/choice/actor/fact grants whose complete
  /// existing NPC contract has passed. No review flag alone grants coverage.
  Set<String> _npcKnowledge(Map<String, dynamic> source,
      Map<String, dynamic> manifest, StoryBlueprint blueprint) {
    final npcs = blueprint.actors.difference({'player'});
    // Signed v5 causal NPC witnesses authorize identities and memories;
    // they do NOT silently introduce legacy NPC knowledge grants.
    if (blueprint.isReviewedCanon &&
        source.containsKey('canon_causality') &&
        {CanonCausalContract.format, CanonCausalContract.graphFormat}
            .contains(manifest['canon_causality_format'])) {
      if (source.containsKey('npc_knowledge') ||
          manifest.containsKey('npc_knowledge_format')) {
        throw const FormatException('Mixed NPC source authority');
      }
      return const <String>{};
    }
    final extension = source['npc_knowledge'];
    if (npcs.isEmpty) {
      if (extension != null || manifest.containsKey('npc_knowledge_format')) throw const FormatException('NPC marker without NPC actors');
      return const <String>{};
    }
    if (npcs.length > 15 || npcs.any((actor) => !CharacterId.isValidNpc(actor)) ||
        manifest['npc_knowledge_format'] != npcKnowledgeFormat || extension is! Map<String, dynamic>) {
      throw const FormatException('Missing versioned NPC knowledge review');
    }
    _fields(extension, {'format', 'review_scope', 'source_fingerprint', 'user_confirmed', 'literary_canon_verified', 'grants'}, 'NPC knowledge');
    if (extension['format'] != npcKnowledgeFormat || extension['review_scope'] != 'user_declared_private_game_fiction' ||
        extension['source_fingerprint'] != blueprint.sourceFingerprint || extension['user_confirmed'] != true ||
        extension['literary_canon_verified'] != false) throw const FormatException('Unapproved or unrelated NPC grant review');
    final grants = extension['grants'];
    if (grants is! List || grants.isEmpty || grants.length > 128) throw const FormatException('No reviewed NPC grant evidence');
    final scenes = blueprint.scenes;
    final origins = <String, Map<String, dynamic>>{};
    if (source['scene_origins'] is! List) throw const FormatException('Missing NPC scene provenance');
    for (final value in source['scene_origins'] as List) {
      if (value is! Map<String, dynamic>) throw const FormatException('Malformed source scene provenance');
      final id = value['scene_id'];
      if (id is! String || origins.containsKey(id)) throw const FormatException('Duplicate NPC source origin');
      origins[id] = value;
    }
    String checkedId(Object? value, String name) {
      if (value is! String || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)) throw FormatException('Invalid NPC $name');
      return value;
    }
    final reviewed = <String>{};
    for (final value in grants) {
      if (value is! Map<String, dynamic>) throw const FormatException('Malformed reviewed NPC grant');
      _fields(value, {'scene_id', 'choice_id', 'actor_id', 'fact_id', 'source_quote_sha256'}, 'NPC grant');
      final sceneId = checkedId(value['scene_id'], 'scene_id');
      final choiceId = checkedId(value['choice_id'], 'choice_id');
      final actorId = checkedId(value['actor_id'], 'actor_id');
      final factId = checkedId(value['fact_id'], 'fact_id');
      final quote = value['source_quote_sha256'];
      final key = '$sceneId|$choiceId|$actorId|$factId';
      if (!npcs.contains(actorId) || !blueprint.facts.contains(factId) || quote is! String || !_sha.hasMatch(quote) || !reviewed.add(key)) {
        throw const FormatException('Invalid or duplicate reviewed NPC grant');
      }
      final scene = scenes[sceneId];
      final matches = scene?.choices.where((c) => c.id == choiceId).toList();
      if (matches == null || matches.length != 1 || matches.single.effects.where((rule) =>
          rule.op == 'learn_fact' && rule.actor == actorId && rule.id == factId).length != 1) {
        throw const FormatException('NPC grant has no matching world action');
      }
      final origin = origins[sceneId];
      final refs = origin?['source_refs'];
      if (origin?['origin'] != 'SOURCE_PASSAGE' || refs is! List ||
          !refs.any((raw) => raw is Map && raw['quote_sha256'] == quote &&
              raw['visible_after_chapter'] is int && raw['chapter_index'] is int &&
              (raw['visible_after_chapter'] as int) <= (origin?['chapter_index'] as int) &&
              (raw['chapter_index'] as int) <= (origin?['chapter_index'] as int))) {
        throw const FormatException('NPC grant lacks prior source witness');
      }
    }
    final expected = <String>{};
    for (final scene in scenes.values) {
      for (final choice in scene.choices) {
        for (final effect in choice.effects) {
          if (effect.op == 'learn_fact' && effect.actor != 'player') {
            expected.add('${scene.id}|${choice.id}|${effect.actor}|${effect.id}');
          }
        }
      }
    }
    if (expected.length != reviewed.length || !expected.containsAll(reviewed)) throw const FormatException('Unreviewed or missing NPC knowledge action');
    return Set<String>.unmodifiable(reviewed);
  }


  static const initialStateReviewFormat = 'ai_story_private_initial_state_review_v1';

  /// Exactly source-witnessed, explicitly confirmed INITIAL possession and
  /// actor-specific knowledge. Review cannot assert literary canon.
  void _initialReview(Map<String, dynamic> source,
      Map<String, dynamic> manifest, StoryBlueprint bp,
      {required bool expanded}) {
    final init = bp.initial;
    final knowledge = <String>{
      for (final entry in init.knowledge.entries)
        for (final fact in entry.value) entry.key + '|' + fact,
    };
    final needsReview = init.inventory.isNotEmpty ||
        knowledge.isNotEmpty || init.tick != 0;
    final review = source['initial_state_review'];
    if (!expanded || !needsReview) {
      if (review != null || manifest.containsKey('initial_state_review_format')) {
        throw const FormatException('Неожиданная редактура исходного состояния');
      }
      return;
    }
    if (review is! Map<String, dynamic> ||
        manifest['initial_state_review_format'] != initialStateReviewFormat) {
      throw const FormatException('Начальные предметы и знания требуют редакторской приёмки');
    }
    _fields(review, {
      'format', 'source_fingerprint', 'review_scope', 'user_confirmed',
      'literary_canon_verified', 'initial_tick', 'item_grants', 'fact_grants',
    }, 'initial v4 review');
    if (review['format'] != initialStateReviewFormat ||
        review['source_fingerprint'] != bp.sourceFingerprint ||
        review['review_scope'] != 'user_declared_private_game_fiction' ||
        review['user_confirmed'] != true ||
        review['literary_canon_verified'] != false ||
        review['initial_tick'] != init.tick ||
        review['item_grants'] is! List || review['fact_grants'] is! List) {
      throw const FormatException('Начальное состояние не подтверждено');
    }
    // The authoring writer already verifies exact UTF-16 text for every
    // scene quote. Only original passage quotes visible at start qualify.
    final hashes = <String>{};
    for (final o in source['scene_origins'] as List) {
      if (o is! Map || o['origin'] != 'SOURCE_PASSAGE' ||
          o['chapter_index'] != 0) continue;
      for (final q in o['source_refs'] as List) {
        if (q is Map && q['chapter_index'] == 0 &&
            q['visible_after_chapter'] == 0 &&
            q['quote_sha256'] is String) {
          hashes.add(q['quote_sha256'] as String);
        }
      }
    }
    final itemIds = <String>{};
    for (final g in review['item_grants'] as List) {
      if (g is! Map<String, dynamic>) throw const FormatException('Некорректный исходный предмет');
      _fields(g, {'item_id', 'source_quote_sha256'}, 'initial item');
      final id = g['item_id'];
      if (id is! String || !init.inventory.contains(id) ||
          !itemIds.add(id) || !hashes.contains(g['source_quote_sha256'])) {
        throw const FormatException('Чужое исходное владение');
      }
    }
    final factIds = <String>{};
    for (final g in review['fact_grants'] as List) {
      if (g is! Map<String, dynamic>) throw const FormatException('Некорректное исходное знание');
      _fields(g, {'actor_id', 'fact_id', 'source_quote_sha256'}, 'initial fact');
      final actor = g['actor_id'];
      final fact = g['fact_id'];
      if (actor is! String || fact is! String ||
          !factIds.add(actor + '|' + fact) ||
          !knowledge.contains(actor + '|' + fact) ||
          !hashes.contains(g['source_quote_sha256'])) {
        throw const FormatException('Чужое или преждевременное знание');
      }
    }
    if (itemIds.length != init.inventory.length ||
        factIds.length != knowledge.length ||
        !itemIds.containsAll(init.inventory) ||
        !factIds.containsAll(knowledge)) {
      throw const FormatException('Не все исходные предметы и знания проверены');
    }
  }

  void _model(Map<String, dynamic> source, Map<String, dynamic> manifest) {
    final model = source['model_provenance'];
    if (model is! Map<String, dynamic>) throw const FormatException('Нет происхождения игрового текста');
    _fields(model, {'provider', 'model_id', 'model_id_status', 'tool', 'method'}, 'actual model');
    final isOpenAI = model['provider'] == 'openai' && (model['model_id'] == null || model['model_id'] == 'gpt-6') &&
        model['model_id_status'] == (model['model_id'] == null ? 'not_attested' : 'user_declared') &&
        model['tool'] == 'ChatGPT' && model['method'] == 'external';
    final isZai = _same(model, {'provider': 'zai', 'model_id': 'glm-4.7-flash',
      'model_id_status': 'requested', 'tool': 'AI Story RPG', 'method': 'built_in'});
    final unattested = _same(model, {'provider': 'unknown', 'model_id': null,
      'model_id_status': 'not_attested', 'tool': 'AI Story RPG', 'method': 'reviewed_local_compilation'});
    final noAI = _same(model, {'provider': 'none', 'model_id': null,
      'model_id_status': 'not_applicable', 'tool': 'none', 'method': 'local_fixture'});
    final literal = _same(model, {'provider': 'none', 'model_id': null,
      'model_id_status': 'not_applicable',
      'tool': 'AI Story RPG', 'method': 'source_literal_compilation'});
    if ((!isOpenAI && !isZai && !unattested && !noAI && !literal) ||
        !_same(manifest['model_provenance'], model)) {
      throw const FormatException('Некорректное происхождение v3');
    }
  }

  Map<String, dynamic> _presentation(Map<String, dynamic> source, StoryBlueprint blueprint,
      {NpcSocialRulebook? socialRules}) {
    final data = source['presentation'];
    if (data is! Map<String, dynamic>) throw const FormatException('Отсутствуют сведения героя и предметов');
    final hasDialogues = data.containsKey('scene_dialogues');
    final hasKnowledgeReview = data.containsKey('scene_dialogue_knowledge');
    final hasResponses = data.containsKey('scene_dialogue_responses');
    _fields(data, {
      'hero', 'item_names', 'item_descriptions', 'stat_names', 'fact_names', 'scene_names',
      if (hasDialogues) 'scene_dialogues', if (hasKnowledgeReview) 'scene_dialogue_knowledge',
      if (hasResponses) 'scene_dialogue_responses',
    }, 'rich presentation');
    final hero = data['hero'];
    if (hero is! Map<String, dynamic>) throw const FormatException('Не указан герой');
    _fields(hero, {'name', 'description'}, 'hero');
    bool label(Object? value, int max) => value is String && value.trim().isNotEmpty && value.length <= max;
    if (!label(hero['name'], 120) || !label(hero['description'], 1200)) throw const FormatException('Имя или описание героя недопустимо');
    void names(Object? value, Set<String> keys, int max) {
      if (value is! Map<String, dynamic> || value.keys.toSet().difference(keys).isNotEmpty ||
          keys.difference(value.keys.toSet()).isNotEmpty || value.values.any((v) => !label(v, max))) {
        throw const FormatException('Неполные названия игровых сущностей');
      }
    }
    names(data['item_names'], blueprint.items, 100);
    names(data['item_descriptions'], blueprint.items, 400);
    names(data['stat_names'], blueprint.initial.stats.keys.toSet(), 100);
    names(data['fact_names'], blueprint.facts, 180);
    names(data['scene_names'], blueprint.scenes.keys.toSet(), 120);
    if (hasDialogues) {
      final dialogs = data['scene_dialogues'];
      if (dialogs is! Map<String, dynamic> || dialogs.length > blueprint.scenes.length ||
          dialogs.keys.any((id) => !blueprint.scenes.containsKey(id))) throw const FormatException('Неизвестная сцена в диалогах .bworld');
      for (final row in dialogs.entries) { RichSceneDialogue.verify(row.value, blueprint.scenes[row.key]!.text); }
      for (final scene in blueprint.scenes.values) {
        final known = RichSceneDialogue.presentationFor(scene.text);
        if ((known == null) != !dialogs.containsKey(scene.id)) throw const FormatException('Подписанные реплики сцены потеряны');
      }
    }
    final allDialogues = data['scene_dialogues'];
    final knowledgeReview = data['scene_dialogue_knowledge'];
    final origins = <String, dynamic>{};
    final rawOrigins = source['scene_origins'];
    if (rawOrigins is! List) throw const FormatException('Missing dialogue source origins');
    for (final entry in rawOrigins) {
      if (entry is! Map<String, dynamic> || entry['scene_id'] is! String || origins.containsKey(entry['scene_id'])) throw const FormatException('Invalid dialogue source origin');
      origins[entry['scene_id'] as String] = entry;
    }
    RichNpcDialogueKnowledge.validate(
      knowledgeReview is Map<String, dynamic> ? knowledgeReview : null,
      blueprint, allDialogues is Map<String, dynamic> ? allDialogues : null,
      socialRules: socialRules, sceneOrigins: origins,
    );
    final responseReview = data['scene_dialogue_responses'];
    if (hasResponses && responseReview is! Map<String, dynamic>) throw const FormatException('Malformed NPC dialogue response mapping');
    RichNpcDialogueResponses.validate(
      responseReview is Map<String, dynamic> ? responseReview : null, blueprint,
      allDialogues is Map<String, dynamic> ? allDialogues : null,
      knowledgeReview is Map<String, dynamic> ? knowledgeReview : null,
      origins, socialRules: socialRules,
    );
    if (hasKnowledgeReview && knowledgeReview is! Map<String, dynamic>) throw const FormatException('Wrong NPC line review map');
    return Map.unmodifiable(data);
  }

  /// Independent v5 certificate: exact literal scene text for EVERY
  /// listed source chunk, no reordering, side branches, skipped chapters or
  /// AI-authored canonical narration. This proves textual fidelity only.
  void _verifyLiteralCanon(Map<String, dynamic> source,
      Map<String, dynamic> manifest, StoryBlueprint bp) {
    final raw = source['canon_review'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Missing v5 literal CANON review');
    }
    _fields(raw, {
      'format', 'scope', 'source_fingerprint', 'source_index_sha256',
      'source_chapters_total', 'source_chunks_total', 'user_confirmed',
      'literary_truth_scope', 'route',
    }, 'literal CANON');
    if (raw['format'] != 'ai_story_literal_canon_review_v1' ||
        raw['scope'] != 'exact_complete_source_text' ||
        raw['source_fingerprint'] != bp.sourceFingerprint ||
        raw['source_index_sha256'] is! String ||
        !_sha.hasMatch(raw['source_index_sha256'] as String) ||
        raw['source_chapters_total'] != source['source_chapters_total'] ||
        raw['user_confirmed'] != true ||
        raw['literary_truth_scope'] != 'verbatim_text_and_order_only' ||
        bp.roleMode != 'PROTAGONIST' || !bp.isReviewedCanon ||
        !bp.supportsFreeform ||
        !_same(bp.items.toList()..sort(), ['gm_keepsake']) ||
        !_same(bp.facts.toList()..sort(), ['gm_impression']) ||
        (!source.containsKey('canon_causality') &&
            !_same(bp.actors.toList()..sort(), ['player'])) ||
        !_same(bp.initial.flags, {'gm_noted': false}) ||
        !_same(bp.initial.stats, {'gm_resolve': 50}) ||
        bp.initial.inventory.isNotEmpty ||
        bp.initial.knowledge['player']?.isNotEmpty == true ||
        bp.initial.tick != 0 ||
        manifest['canon_review_format'] != raw['format']) {
      throw const FormatException('CANON v5 is not a sealed literal edition');
    }
    final route = raw['route'];
    final chapters = raw['source_chapters_total'];
    if (route is! List || route.length != bp.scenes.length ||
        raw['source_chunks_total'] != route.length ||
        chapters is! int || chapters < 1 || chapters > 10000) {
      throw const FormatException('Incomplete CANON source route');
    }
    final seenChunks = <String>{}, chaptersSeen = <int>{};
    final sourceOrigins = source['scene_origins'];
    if (sourceOrigins is! List || sourceOrigins.length != route.length) {
      throw const FormatException('Missing canonical source origins');
    }
    final scenes = bp.scenes.values.toList(growable: false);
    var previousChapter = 0;
    for (var i = 0; i < route.length; i++) {
      final row = route[i];
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid canonical route row');
      }
      _fields(row, {
        'scene_id', 'chunk_id', 'chapter_index',
        'start_utf16', 'end_utf16', 'source_sha256',
      }, 'CANON route');
      final scene = scenes[i];
      final origin = sourceOrigins[i];
      final ch = row['chapter_index'], start = row['start_utf16'];
      final end = row['end_utf16'], id = row['chunk_id'];
      if (row['scene_id'] != scene.id ||
          scene.id != 'canon_' + i.toString().padLeft(5, '0') ||
          id is! String || !seenChunks.add(id) ||
          ch is! int || ch < previousChapter || ch >= chapters ||
          start is! int || end is! int || start < 0 ||
          end - start != scene.text.length ||
          row['source_sha256'] !=
            sha256.convert(utf8.encode(scene.text)).toString() ||
          origin is! Map<String, dynamic> ||
          origin['scene_id'] != scene.id ||
          origin['chapter_index'] != ch ||
          origin['origin'] != 'SOURCE_PASSAGE' ||
          origin['source_refs'] is! List ||
          (origin['source_refs'] as List).length != 1) {
        throw const FormatException('CANON text or scene order changed');
      }
      previousChapter = ch;
      chaptersSeen.add(ch);
      final cite = (origin['source_refs'] as List).single;
      if (cite is! Map<String, dynamic> ||
          cite['chunk_id'] != id ||
          cite['chapter_index'] != ch ||
          cite['visible_after_chapter'] != ch ||
          cite['start_utf16'] is! int ||
          cite['end_utf16'] is! int ||
          (cite['start_utf16'] as int) < start ||
          (cite['end_utf16'] as int) > end ||
          (cite['end_utf16'] as int) <= (cite['start_utf16'] as int)) {
        throw const FormatException('CANON quotation does not cite its chunk');
      }
      final sample = scene.text.substring(
          (cite['start_utf16'] as int) - start,
          (cite['end_utf16'] as int) - start);
      if (sample.trim().isEmpty ||
          cite['quote_sha256'] !=
              sha256.convert(utf8.encode(sample)).toString()) {
        throw const FormatException('Canonical quote does not match scene text');
      }
      if (i + 1 == route.length) {
        if (!scene.terminal || scene.choices.isNotEmpty) {
          throw const FormatException('CANON has a false final ending');
        }
      } else {
        if (scene.terminal || scene.choices.length != 1 ||
            scene.choices.single.id !=
                'canon_next_' + i.toString().padLeft(5, '0') ||
            scene.choices.single.nextSceneId != scenes[i + 1].id ||
            scene.choices.single.conditions.isNotEmpty ||
            scene.choices.single.effects.isNotEmpty) {
          throw const FormatException('CANON cannot branch or change book events');
        }
      }
    }
    if (chaptersSeen.length != chapters ||
        !chaptersSeen.containsAll(Iterable<int>.generate(chapters))) {
      throw const FormatException('A book chapter was omitted from CANON');
    }
  }

  VerifiedRichPrivateBookworld inspect(Uint8List data) {
    final files = BworldZipV1.readPrivate(data);
    final bpRaw = _object(files['scenario/blueprint.json']!, 'blueprint');
    final manifest = _object(files['manifest.json']!, 'manifest');
    final version = manifest['format_version'];
    if (version != 3 && version != 4 && version != 5) {
      throw const FormatException('Неподдерживаемая версия игры');
    }
    final literalCanon = version == 5;
    final blueprint = StoryBlueprint.fromJson(
        bpRaw, allowReviewedCanon: literalCanon);
    if (blueprint.rightsStatus != 'private_adaptation' ||
        blueprint.sourceFingerprint == null ||
        blueprint.isReviewedCanon != literalCanon) {
      throw const FormatException('Частная версия CANON не подтверждена');
    }
    final expanded = version == 4 || literalCanon;
    _causality(blueprint, expanded: expanded,
        literalCanon: literalCanon);
    final source = _object(files['source/provenance.json']!, 'provenance');
    final hasGameplayReview = source.containsKey('gameplay_review');
    final knownSource = Map<String, dynamic>.of(source)
      ..remove('gameplay_review')..remove('npc_knowledge')..remove('npc_social')
      ..remove('initial_state_review')..remove('canon_review')
      ..remove('canon_causality');
    _fields(knownSource, {'format', 'bookworld_id', 'source_fingerprint', 'source_title',
      'source_author', 'source_chapters_total', 'source_chapters_indexed',
      'semantic_catalog_sha256', 'intermediate_draft_sha256', 'rights_status',
      'publication_authorized', 'model_provenance', 'scene_origins', 'presentation'}, 'source provenance v3');
    if (source['format'] != 'ai_story_private_provenance_v2') throw const FormatException('Неверная версия происхождения v3');
    if (manifest['build_status'] != (literalCanon
            ? 'private_literal_canon_reviewed'
            : (expanded ? 'private_extended_structural' : 'private_rich_structural')) ||
        !_same(manifest['build_tool'], literalCanon
            ? {'name': 'ai_story_literal_canon_bookworld', 'version': '5.0'}
            : (expanded
                ? {'name': 'ai_story_private_extended_bookworld', 'version': '4.0'}
                : {'name': 'ai_story_private_rich_bookworld', 'version': '3.0'}))) {
      throw const FormatException('Неподдерживаемая версия RPG v3');
    }
    _model(source, manifest);
    final sourceCausal = CanonCausalContract.inspect(source,
        manifest, blueprint);
    if (literalCanon) _verifyLiteralCanon(source, manifest, blueprint);
    _initialReview(source, manifest, blueprint, expanded: expanded);
    final legacySocial = RichNpcSocialContract.inspect(
        source, manifest, blueprint);
    if (legacySocial != null && sourceCausal != null) {
      throw const FormatException('Mixed legacy and causal NPC contracts');
    }
    final socialRulebook = sourceCausal?.rulebook ?? legacySocial;
    final basePresentation = _presentation(source, blueprint,
        socialRules: socialRulebook);
    final presentation = <String, dynamic>{
      ...basePresentation,
      if (sourceCausal != null)
        'npc_display_names': sourceCausal.names,
    };
    final verifiedNpcGrants = _npcKnowledge(source, manifest, blueprint);
    if (hasGameplayReview) {
      final review = source['gameplay_review'];
      if (review is! Map<String, dynamic>) throw const FormatException('Некорректная редакторская приёмка');
      // Coverage is a strict union: ordinary item/player effects must be
      // covered by gameplay_review; only the exact already-validated NPC
      // learn_fact tuple can be covered by npc_knowledge instead. Neither
      // document can authorize the other actor or an unreviewed operation.
      PrivateGameplayReview.verify(review, blueprint, source,
          verifiedNpcGrants: verifiedNpcGrants);
    }
    final originV2 = Map<String, dynamic>.of(source)
      ..remove('presentation')..remove('gameplay_review')..remove('npc_knowledge')..remove('npc_social')
      ..remove('initial_state_review')..remove('canon_review')
      ..remove('canon_causality');
    originV2['format'] = 'ai_story_private_provenance_v1';
    originV2['model_provenance'] = {'provider': 'none', 'model_id': null};
    _provenance(originV2, blueprint, literalCanon: literalCanon);
    final manifestV2 = Map<String, dynamic>.of(manifest)
      ..remove('npc_knowledge_format')..remove('npc_social_format')
      ..remove('initial_state_review_format');
    if (literalCanon) {
      _manifest(manifest, blueprint, source, files,
          literalCanon: true);
    } else {
      manifestV2['format_version'] = 2;
      manifestV2['build_status'] = 'private_classic_structural';
      manifestV2['build_tool'] = {'name': 'ai_story_private_bookworld', 'version': '2.0'};
      manifestV2['model_provenance'] = {'provider': 'none', 'model_id': null};
      _manifest(manifestV2, blueprint, originV2, files);
    }
    BworldSqliteV1.inspect(files['world.sqlite']!, blueprint, bpRaw);
    return VerifiedRichPrivateBookworld(
      blueprint: blueprint, sourceFingerprint: blueprint.sourceFingerprint!,
      archiveSha256: sha256.convert(data).toString(),
      provenanceSha256: sha256.convert(files['source/provenance.json']!).toString(),
      presentation: presentation, npcSocialRulebook: socialRulebook,
      sourceTitle: source['source_title'] as String,
      sourceChaptersTotal: source['source_chapters_total'] as int,
      sourceChaptersIndexed: source['source_chapters_indexed'] as int,
      sceneOrigins: Map.unmodifiable({
        for (final raw in source['scene_origins'] as List)
          (raw as Map<String, dynamic>)['scene_id'] as String:
              VerifiedBookSceneOrigin(
                sceneId: raw['scene_id'] as String,
                chapterIndex: raw['chapter_index'] as int,
                origin: raw['origin'] as String,
                sourceQuoteSha256: raw['source_refs'] is List &&
                        (raw['source_refs'] as List).isNotEmpty
                    ? ((raw['source_refs'] as List).first as Map)['quote_sha256']
                        as String?
                    : null,
              ),
      }),
      formatVersion: version as int,
    );
  }
}
