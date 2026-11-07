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
import 'src/zip_v1.dart';

/// A private, source-bound, offline CLASSIC package. No permission to publish.
class VerifiedRichPrivateBookworld {
  const VerifiedRichPrivateBookworld({
    required this.blueprint,
    required this.sourceFingerprint,
    required this.archiveSha256,
    required this.provenanceSha256,
    required this.presentation,
    this.npcSocialRulebook,
  });
  final StoryBlueprint blueprint;
  final String sourceFingerprint, archiveSha256, provenanceSha256;
  final Map<String, dynamic> presentation;
  final NpcSocialRulebook? npcSocialRulebook;
  String get bookworldId => blueprint.bookId;
  bool get canDistributePublicly => false;
  bool get requiresNetwork => false;
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

  void _provenance(Map<String, dynamic> source, StoryBlueprint blueprint) {
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
    if (originalScenes == 0 || adaptations == 0) throw const FormatException('Нет оригинала или альтернативного пути');
  }

  bool _shaId(Object? value) => value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

  void _manifest(Map<String, dynamic> manifest, StoryBlueprint blueprint,
      Map<String, dynamic> provenance, Map<String, Uint8List> files) {
    const keys = {
      'format', 'format_version', 'bookworld_id', 'source_fingerprint', 'title', 'author',
      'languages', 'engine_min_version', 'scenario_format', 'scenario_format_version',
      'content_capabilities', 'build_status', 'hashes', 'sizes', 'build_tool',
      'model_provenance', 'rights_status', 'blueprint_sha256',
    };
    _fields(manifest, keys, 'manifest');
    if (manifest['format'] != 'ai_story_bookworld' || manifest['format_version'] != 2 ||
        manifest['bookworld_id'] != blueprint.bookId || manifest['source_fingerprint'] != blueprint.sourceFingerprint ||
        manifest['title'] != blueprint.title || manifest['author'] != provenance['source_author'] ||
        !_same(manifest['languages'], ['ru']) || manifest['engine_min_version'] != '0.1.0' ||
        manifest['scenario_format'] != 'ai_story_blueprint_v1' || manifest['scenario_format_version'] != 1 ||
        !_same(manifest['content_capabilities'], {
          'roles': ['PROTAGONIST'], 'plots': ['ALTER_FATE'], 'interactions': ['CLASSIC'],
        }) || manifest['build_status'] != 'private_classic_structural' ||
        manifest['rights_status'] != 'private_use_only' || manifest['blueprint_sha256'] != blueprint.blueprintHash ||
        !_same(manifest['build_tool'], {'name': 'ai_story_private_bookworld', 'version': '2.0'}) ||
        !_same(manifest['model_provenance'], {'provider': 'none', 'model_id': null})) {
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
  void _causality(StoryBlueprint blueprint) {
    if (blueprint.scenes.length < 3 || blueprint.scenes.length > 192 ||
        blueprint.items.length > 32 || blueprint.facts.length > 64 ||
        blueprint.initial.stats.length > 8 || blueprint.initial.flags.length > 32 ||
        blueprint.actors.length > 16 || !blueprint.actors.contains('player') ||
        blueprint.initial.inventory.isNotEmpty ||
        blueprint.initial.knowledge.length != blueprint.actors.length ||
        !blueprint.initial.knowledge.keys.toSet().containsAll(blueprint.actors) ||
        blueprint.initial.knowledge.values.any((facts) => facts.isNotEmpty) ||
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
            default: throw const FormatException('Недопустимый эффект RPG v3');
          }
        }
      }
    }
    if (!seenItemGrants.containsAll(blueprint.items) || !seenFactGrants.containsAll(blueprint.facts)) {
      throw const FormatException('Каталог не связан с игровыми действиями');
    }
    final start = (
      blueprint.entrySceneId,
      blueprint.initial.flags.entries.where((e) => e.value).map((e) => e.key).toSet(),
      <String>{}, Map<String, int>.of(blueprint.initial.stats),
      {for (final actor in blueprint.actors) actor: <String>{}},
    );
    String keyOf((String, Set<String>, Set<String>, Map<String, int>, Map<String, Set<String>>) state) => canonicalJson({
      'scene': state.$1, 'flags': state.$2.toList()..sort(),
      'inventory': state.$3.toList()..sort(), 'stats': state.$4,
      'knowledge': {for (final actor in blueprint.actors) actor: state.$5[actor]!.toList()..sort()},
    });
    final seen = <String>{keyOf(start)}, visited = <String>{};
    final parent = <String, Set<String>>{};
    final terminals = <String>{}, endings = <String>{};
    final queue = [start];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (seen.length > 2500) throw const FormatException('Превышено число состояний RPG v3');
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
            _ => false,
          };
          if (!meets) { allowed = false; break; }
        }
        if (!allowed) continue;
        choicesAvailable++;
        final flags = Set<String>.of(s.$2), items = Set<String>.of(s.$3);
        final stats = Map<String, int>.of(s.$4);
        final facts = s.$5.map((actor, known) => MapEntry(actor, Set<String>.of(known)));
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
            default: throw const FormatException('Непредусмотренный игровой эффект');
          }
        }
        final next = (choice.nextSceneId, flags, items, stats, facts);
        final dest = keyOf(next);
        parent.putIfAbsent(dest, () => <String>{}).add(here);
        if (seen.add(dest)) queue.add(next);
      }
      if (choicesAvailable == 0) throw const FormatException('Тупик без доступного действия');
    }
    if (endings.length < 2 || visited.length != blueprint.scenes.length) throw const FormatException('Недостижимые игровые сцены или финалы');
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
    if ((!isOpenAI && !isZai && !unattested && !noAI) || !_same(manifest['model_provenance'], model)) {
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

  VerifiedRichPrivateBookworld inspect(Uint8List data) {
    final files = BworldZipV1.readPrivate(data);
    final bpRaw = _object(files['scenario/blueprint.json']!, 'blueprint');
    final blueprint = StoryBlueprint.fromJson(bpRaw);
    if (blueprint.rightsStatus != 'private_adaptation' || blueprint.sourceFingerprint == null) throw const FormatException('Не является приватной RPG по книге');
    _causality(blueprint);
    final source = _object(files['source/provenance.json']!, 'provenance');
    final hasGameplayReview = source.containsKey('gameplay_review');
    final knownSource = Map<String, dynamic>.of(source)
      ..remove('gameplay_review')..remove('npc_knowledge')..remove('npc_social');
    _fields(knownSource, {'format', 'bookworld_id', 'source_fingerprint', 'source_title',
      'source_author', 'source_chapters_total', 'source_chapters_indexed',
      'semantic_catalog_sha256', 'intermediate_draft_sha256', 'rights_status',
      'publication_authorized', 'model_provenance', 'scene_origins', 'presentation'}, 'source provenance v3');
    if (source['format'] != 'ai_story_private_provenance_v2') throw const FormatException('Неверная версия происхождения v3');
    final manifest = _object(files['manifest.json']!, 'manifest');
    if (manifest['format_version'] != 3 || manifest['build_status'] != 'private_rich_structural' ||
        !_same(manifest['build_tool'], {'name': 'ai_story_private_rich_bookworld', 'version': '3.0'})) {
      throw const FormatException('Неподдерживаемая версия RPG v3');
    }
    _model(source, manifest);
    final socialRulebook = RichNpcSocialContract.inspect(source, manifest, blueprint);
    final presentation = _presentation(source, blueprint, socialRules: socialRulebook);
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
      ..remove('presentation')..remove('gameplay_review')..remove('npc_knowledge')..remove('npc_social');
    originV2['format'] = 'ai_story_private_provenance_v1';
    originV2['model_provenance'] = {'provider': 'none', 'model_id': null};
    _provenance(originV2, blueprint);
    final manifestV2 = Map<String, dynamic>.of(manifest)
      ..remove('npc_knowledge_format')..remove('npc_social_format');
    manifestV2['format_version'] = 2;
    manifestV2['build_status'] = 'private_classic_structural';
    manifestV2['build_tool'] = {'name': 'ai_story_private_bookworld', 'version': '2.0'};
    manifestV2['model_provenance'] = {'provider': 'none', 'model_id': null};
    _manifest(manifestV2, blueprint, originV2, files);
    BworldSqliteV1.inspect(files['world.sqlite']!, blueprint, bpRaw);
    return VerifiedRichPrivateBookworld(
      blueprint: blueprint, sourceFingerprint: blueprint.sourceFingerprint!,
      archiveSha256: sha256.convert(data).toString(),
      provenanceSha256: sha256.convert(files['source/provenance.json']!).toString(),
      presentation: presentation, npcSocialRulebook: socialRulebook,
    );
  }
}
