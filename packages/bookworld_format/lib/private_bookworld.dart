import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'src/sqlite_v1.dart';
import 'src/zip_v1.dart';

/// A *private*, source-bound, offline CLASSIC package. It carries no original
/// full text, credentials, remote provider or permission to republish.
class VerifiedPrivateBookworld {
  const VerifiedPrivateBookworld({
    required this.blueprint,
    required this.sourceFingerprint,
    required this.archiveSha256,
    required this.provenanceSha256,
  });

  final StoryBlueprint blueprint;
  final String sourceFingerprint;
  final String archiveSha256;
  final String provenanceSha256;
  String get bookworldId => blueprint.bookId;
  bool get canDistributePublicly => false;
  bool get requiresNetwork => false;
}

/// M2d/v2 deliberately does NOT relax BookworldImporter v1, which remains
/// original_demo-only. This independent entrance validates ZIP, JSON,
/// provenance, manifest AND SQLite before giving any rules to story_core.
class PrivateBookworldImporter {
  const PrivateBookworldImporter();

  static const _payloadPaths = {
    'scenario/blueprint.json', 'source/provenance.json', 'world.sqlite',
  };
  static final _sha = RegExp(r'^[a-f0-9]{64}$');

  Map<String, dynamic> _object(Uint8List bytes, String part) {
    final Object? object;
    try {
      object = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      throw FormatException('Некорректный JSON $part');
    }
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
      'rights_status', 'publication_authorized', 'model_provenance',
      'scene_origins',
    };
    _fields(source, fields, 'provenance');
    if (source['format'] != 'ai_story_private_provenance_v1' ||
        source['bookworld_id'] != blueprint.bookId ||
        source['source_fingerprint'] != blueprint.sourceFingerprint ||
        source['source_title'] is! String ||
        (source['source_title'] as String).trim().isEmpty ||
        (source['source_title'] as String).length > 256 ||
        source['source_author'] is! String ||
        (source['source_author'] as String).length > 256 ||
        source['semantic_catalog_sha256'] is! String ||
        !_sha.hasMatch(source['semantic_catalog_sha256'] as String) ||
        source['intermediate_draft_sha256'] is! String ||
        !_sha.hasMatch(source['intermediate_draft_sha256'] as String) ||
        source['rights_status'] != 'private_use_only' ||
        source['publication_authorized'] != false ||
        !_same(source['model_provenance'],
            {'provider': 'none', 'model_id': null})) {
      throw const FormatException('Подмена прав или привязки источника');
    }
    final total = source['source_chapters_total'];
    final indexed = source['source_chapters_indexed'];
    if (total is! int || indexed is! int || total < 1 ||
        total > 10000 || indexed < 1 || indexed > total) {
      throw const FormatException('Неверный охват исходной книги');
    }
    final origins = source['scene_origins'];
    if (origins is! List || origins.length != blueprint.scenes.length) {
      throw const FormatException('Нет происхождения игровых сцен');
    }
    final compiledScenes = blueprint.scenes.keys.toList();
    final sceneIds = <String>{};
    var originalScenes = 0;
    var adaptations = 0;
    for (var i = 0; i < origins.length; i++) {
      final entry = origins[i];
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Некорректная запись происхождения');
      }
      _fields(entry,
          {'scene_id', 'chapter_index', 'origin', 'assertion_ids',
           'source_refs'}, 'scene provenance');
      final sceneId = entry['scene_id'];
      final chapter = entry['chapter_index'];
      final origin = entry['origin'];
      final claims = entry['assertion_ids'];
      final refs = entry['source_refs'];
      if (sceneId != compiledScenes[i] || !sceneIds.add(sceneId as String) ||
          chapter is! int || chapter < 0 || chapter >= total ||
          (origin != 'SOURCE_PASSAGE' &&
              origin != 'EXPLICIT_ADAPTATION') ||
          claims is! List || claims.length > 24 ||
          claims.any((v) => v is! String || !_shaId(v)) ||
          claims.toSet().length != claims.length ||
          refs is! List || refs.length > 72) {
        throw const FormatException('Несовместимое происхождение игровой сцены');
      }
      if (origin == 'SOURCE_PASSAGE') {
        originalScenes++;
        if (claims.isEmpty || refs.isEmpty) {
          throw const FormatException('Каноническая сцена без доказательств');
        }
      } else {
        adaptations++;
      }
      final usedRefs = <String>{};
      for (final raw in refs) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Некорректный источник сцены');
        }
        _fields(raw, {
          'id', 'chunk_id', 'chapter_id', 'chapter_index',
          'block_index', 'start_utf16', 'end_utf16',
          'quote_sha256', 'visible_after_chapter',
        }, 'source ref');
        final citationId = raw['id'];
        final chunkId = raw['chunk_id'];
        final chapterId = raw['chapter_id'];
        final index = raw['chapter_index'];
        final visible = raw['visible_after_chapter'];
        final start = raw['start_utf16'];
        final end = raw['end_utf16'];
        if (citationId is! String || !_shaId(citationId) ||
            !usedRefs.add(citationId) ||
            chunkId is! String || chunkId.isEmpty || chunkId.length > 120 ||
            chapterId is! String || chapterId.isEmpty ||
            chapterId.length > 120 ||
            index is! int || index < 0 || index >= total ||
            index > chapter || raw['block_index'] is! int ||
            (raw['block_index'] as int) < 0 ||
            visible is! int || visible < index || visible > chapter ||
            start is! int || start < 0 ||
            end is! int || end <= start || end - start > 180 ||
            raw['quote_sha256'] is! String ||
            !_sha.hasMatch(raw['quote_sha256'] as String)) {
          throw const FormatException('Подмена диапазона или спойлер источника');
        }
      }
    }
    if (originalScenes == 0 || adaptations == 0) {
      throw const FormatException('Нет оригинала или альтернативного пути');
    }
  }

  bool _shaId(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

  void _manifest(Map<String, dynamic> manifest,
      StoryBlueprint blueprint, Map<String, dynamic> provenance,
      Map<String, Uint8List> files) {
    const keys = {
      'format', 'format_version', 'bookworld_id', 'source_fingerprint',
      'title', 'author', 'languages', 'engine_min_version',
      'scenario_format', 'scenario_format_version', 'content_capabilities',
      'build_status', 'hashes', 'sizes', 'build_tool', 'model_provenance',
      'rights_status', 'blueprint_sha256',
    };
    _fields(manifest, keys, 'manifest');
    if (manifest['format'] != 'ai_story_bookworld' ||
        manifest['format_version'] != 2 ||
        manifest['bookworld_id'] != blueprint.bookId ||
        manifest['source_fingerprint'] != blueprint.sourceFingerprint ||
        manifest['title'] != blueprint.title ||
        manifest['author'] != provenance['source_author'] ||
        !_same(manifest['languages'], ['ru']) ||
        manifest['engine_min_version'] != '0.1.0' ||
        manifest['scenario_format'] != 'ai_story_blueprint_v1' ||
        manifest['scenario_format_version'] != 1 ||
        !_same(manifest['content_capabilities'], {
          'roles': ['PROTAGONIST'],
          'plots': ['ALTER_FATE'],
          'interactions': ['CLASSIC'],
        }) ||
        manifest['build_status'] != 'private_classic_structural' ||
        manifest['rights_status'] != 'private_use_only' ||
        manifest['blueprint_sha256'] != blueprint.blueprintHash ||
        !_same(manifest['build_tool'], {
          'name': 'ai_story_private_bookworld', 'version': '2.0',
        }) ||
        !_same(manifest['model_provenance'], {
          'provider': 'none', 'model_id': null,
        })) {
      throw const FormatException('Формат частной адаптации не подтверждён');
    }
    final sizes = manifest['sizes'];
    final hashes = manifest['hashes'];
    if (sizes is! Map<String, dynamic> ||
        hashes is! Map<String, dynamic> ||
        sizes.length != _payloadPaths.length ||
        hashes.length != _payloadPaths.length ||
        !sizes.keys.toSet().containsAll(_payloadPaths) ||
        !hashes.keys.toSet().containsAll(_payloadPaths)) {
      throw const FormatException('Отсутствует контроль вложений .bworld');
    }
    for (final path in _payloadPaths) {
      final bytes = files[path]!;
      if (sizes[path] is! int || sizes[path] != bytes.length ||
          hashes[path] != sha256.convert(bytes).toString()) {
        throw FormatException('Размер или SHA-256 не совпадает: $path');
      }
    }
  }

  /// Re-check state reachability in the imported, executable DSL, not only
  /// the intermediate draft. This also rejects malicious archives that
  /// recompute every SHA but contain deadlocks or unavailable endings.
  /// Exact finite-state validation for private classic scenarios.
  /// Both flags and per-actor knowledge affect reachability. No prose, AI
  /// prompts, or executable book content participates in this simulation.
  void _causality(StoryBlueprint blueprint) {
    if (blueprint.scenes.length < 3 || blueprint.scenes.length > 192 ||
        blueprint.initial.flags.length > 32) {
      throw const FormatException('Небезопасный размер частного сценария');
    }

    final flags = blueprint.initial.flags.keys.toList()..sort();
    final flagBit = <String, int>{
      for (var i = 0; i < flags.length; i++) flags[i]: 1 << i,
    };
    var initialFlags = 0;
    for (final flag in flags) {
      if (blueprint.initial.flags[flag] == true) {
        initialFlags |= flagBit[flag]!;
      }
    }

    // A fact catalog may contain opaque IDs only. Existing flag-only worlds
    // retain exactly the same rules and validation path, with K=0.
    final npcId = RegExp(r'^npc_[a-f0-9]{20}$');
    final factId = RegExp(r'^fact_[a-f0-9]{24}$');
    final usesKnowledge = blueprint.facts.isNotEmpty ||
        blueprint.actors.length > 1;
    if (usesKnowledge &&
        (blueprint.facts.isEmpty || blueprint.facts.length > 128 ||
        blueprint.actors.length > 257 ||
        blueprint.actors.any((actor) =>
            actor != 'player' && !npcId.hasMatch(actor)) ||
        blueprint.facts.any((fact) => !factId.hasMatch(fact)) ||
        blueprint.initial.knowledge.keys.toSet()
            .difference(blueprint.actors).isNotEmpty ||
        blueprint.actors.difference(
            blueprint.initial.knowledge.keys.toSet()).isNotEmpty ||
        blueprint.initial.knowledge.values.any((facts) => facts.isNotEmpty))) {
      throw const FormatException('Недопустимый каталог знаний частной RPG');
    }

    // Pre-validate *all* rules, including choices that may be unreachable.
    // This prevents invalid effects hiding behind an impossible condition.
    String slot(String actor, String fact) => '$actor|$fact';
    final grantedSlots = <String>{};
    final requiredSlots = <String>{};
    final grantedFacts = <String>{};
    var grants = 0;
    var gates = 0;
    for (final scene in blueprint.scenes.values) {
      for (final choice in scene.choices) {
        for (final rule in choice.conditions) {
          if (rule.op == 'flag_is') {
            if (rule.id == null || rule.value == null ||
                !flagBit.containsKey(rule.id)) {
              throw const FormatException('Недопустимое условие частного мира');
            }
          } else if (rule.op == 'knows_fact') {
            if (!usesKnowledge || rule.id == null || rule.actor == null ||
                !factId.hasMatch(rule.id!) ||
                (rule.actor != 'player' && !npcId.hasMatch(rule.actor!)) ||
                !blueprint.facts.contains(rule.id) ||
                !blueprint.actors.contains(rule.actor)) {
              throw const FormatException('Недопустимое условие знания NPC');
            }
            gates++;
            requiredSlots.add(slot(rule.actor!, rule.id!));
          } else {
            throw const FormatException('Недопустимое условие частного мира');
          }
        }
        for (final effect in choice.effects) {
          if (effect.op == 'set_flag') {
            if (effect.id == null || effect.value == null ||
                !flagBit.containsKey(effect.id)) {
              throw const FormatException('Недопустимый игровой эффект');
            }
          } else if (effect.op == 'learn_fact') {
            if (!usesKnowledge || effect.id == null || effect.actor == null ||
                !factId.hasMatch(effect.id!) ||
                (effect.actor != 'player' &&
                    !npcId.hasMatch(effect.actor!)) ||
                !blueprint.facts.contains(effect.id) ||
                !blueprint.actors.contains(effect.actor)) {
              throw const FormatException('Недопустимое правило знания NPC');
            }
            grants++;
            grantedFacts.add(effect.id!);
            grantedSlots.add(slot(effect.actor!, effect.id!));
          } else {
            throw const FormatException('Недопустимый игровой эффект');
          }
        }
      }
    }
    if (usesKnowledge && (grants == 0 || grants > 128 || gates > 128 ||
        grantedSlots.length > 128 ||
        grantedFacts.length != blueprint.facts.length ||
        !grantedFacts.containsAll(blueprint.facts) ||
        !grantedSlots.containsAll(requiredSlots))) {
      throw const FormatException(
          'Знание или условие не имеет подтверждённого игрового источника');
    }

    // BigInt avoids overflows when 128 independent grants are present.
    // Store only actor+fact pairs actually granted by a choice. A known fact
    // for one NPC cannot satisfy a condition for another NPC or the player.
    final orderedSlots = grantedSlots.toList()..sort();
    final knowledgeBit = <String, BigInt>{
      for (var i = 0; i < orderedSlots.length; i++)
        orderedSlots[i]: BigInt.one << i,
    };

    String stateKey(String sceneId, int flagMask, BigInt knownMask) =>
        '$sceneId:' + flagMask.toRadixString(16) + ':' +
        knownMask.toRadixString(16);

    final initialKey = stateKey(
        blueprint.entrySceneId, initialFlags, BigInt.zero);
    final queue = <(String, int, BigInt)>[
      (blueprint.entrySceneId, initialFlags, BigInt.zero),
    ];
    final discovered = <String>{initialKey};
    final seenScenes = <String>{};
    final predecessors = <String, Set<String>>{};
    final terminalStates = <String>{};
    final endings = <String>{};

    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (queue.length > 2500) {
        throw const FormatException('Превышен лимит причинной симуляции');
      }
      final current = queue[cursor];
      final scene = blueprint.scenes[current.$1]!;
      final state = stateKey(current.$1, current.$2, current.$3);
      seenScenes.add(scene.id);
      if (scene.terminal) {
        terminalStates.add(state);
        endings.add(scene.id);
        continue;
      }

      var available = 0;
      for (final choice in scene.choices) {
        var allowed = true;
        for (final condition in choice.conditions) {
          if (condition.op == 'flag_is') {
            final enabled =
                (current.$2 & flagBit[condition.id!]!) != 0;
            if (enabled != condition.value!) {
              allowed = false;
              break;
            }
          } else {
            final bit = knowledgeBit[slot(
                condition.actor!, condition.id!)]!;
            if ((current.$3 & bit) == BigInt.zero) {
              allowed = false;
              break;
            }
          }
        }
        if (!allowed) continue;
        available++;

        var nextFlags = current.$2;
        var nextKnowledge = current.$3;
        for (final effect in choice.effects) {
          if (effect.op == 'set_flag') {
            if (effect.value!) {
              nextFlags |= flagBit[effect.id!]!;
            } else {
              nextFlags &= ~flagBit[effect.id!]!;
            }
          } else {
            nextKnowledge |= knowledgeBit[slot(
                effect.actor!, effect.id!)]!;
          }
        }
        final destination = stateKey(
            choice.nextSceneId, nextFlags, nextKnowledge);
        predecessors.putIfAbsent(destination, () => <String>{})
            .add(state);
        if (discovered.add(destination)) {
          queue.add((choice.nextSceneId, nextFlags, nextKnowledge));
        }
      }
      if (available == 0) {
        throw const FormatException(
            'Есть игровой тупик без доступных действий');
      }
    }

    if (endings.length < 2 || seenScenes.length != blueprint.scenes.length) {
      throw const FormatException(
          'Недоступные сцены или альтернативные финалы');
    }
    final escapable = <String>{...terminalStates};
    final stack = terminalStates.toList();
    while (stack.isNotEmpty) {
      final state = stack.removeLast();
      for (final predecessor in predecessors[state] ?? const <String>{}) {
        if (escapable.add(predecessor)) stack.add(predecessor);
      }
    }
    if (escapable.length != discovered.length) {
      throw const FormatException('Игровая ветка зациклена без выхода');
    }
  }

  VerifiedPrivateBookworld inspect(Uint8List data) {
    final files = BworldZipV1.readPrivate(data);
    final bpRaw = _object(files['scenario/blueprint.json']!, 'blueprint');
    final blueprint = StoryBlueprint.fromJson(bpRaw);
    _causality(blueprint);
    if (blueprint.rightsStatus != 'private_adaptation' ||
        blueprint.sourceFingerprint == null) {
      throw const FormatException('Не является частной адаптацией книги');
    }
    final source = _object(files['source/provenance.json']!, 'provenance');
    _provenance(source, blueprint);
    final manifest = _object(files['manifest.json']!, 'manifest');
    _manifest(manifest, blueprint, source, files);
    BworldSqliteV1.inspect(files['world.sqlite']!, blueprint, bpRaw);
    return VerifiedPrivateBookworld(
      blueprint: blueprint,
      sourceFingerprint: blueprint.sourceFingerprint!,
      archiveSha256: sha256.convert(data).toString(),
      provenanceSha256:
          sha256.convert(files['source/provenance.json']!).toString(),
    );
  }
}
