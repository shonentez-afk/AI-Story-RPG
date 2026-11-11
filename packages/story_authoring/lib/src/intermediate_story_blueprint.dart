import 'dart:convert';

import 'package:story_core/story_core.dart'
    show FutureFlagEdge, FutureFlagLiveness;

import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';

/// M2c preparation ONLY. No compiled .bworld or execution of natural text.
/// The rules form a bounded, typed causal state graph that can be verified
/// before any AI provider is connected.
enum PreparationRights { unknown, privateUse, publicDomain, licensed }
enum DraftSceneOrigin { sourcePassage, explicitAdaptation }

class DraftChoice {
  DraftChoice({
    required this.id,
    required this.label,
    required this.nextSceneId,
    List<String> requires = const [],
    List<String> forbids = const [],
    List<String> adds = const [],
    List<String> removes = const [],
  }) : requires = List.unmodifiable(requires),
       forbids = List.unmodifiable(forbids),
       adds = List.unmodifiable(adds),
       removes = List.unmodifiable(removes);

  final String id;
  final String label;
  final String nextSceneId;
  final List<String> requires;
  final List<String> forbids;
  final List<String> adds;
  final List<String> removes;

  Map<String, Object> toJson() => {
    'id': id, 'label': label, 'next_scene_id': nextSceneId,
    'requires': requires, 'forbids': forbids,
    'adds': adds, 'removes': removes,
  };

  factory DraftChoice.fromJson(Map<String, dynamic> map) {
    _checkFields(map, {'id', 'label', 'next_scene_id',
        'requires', 'forbids', 'adds', 'removes'});
    try {
      return DraftChoice(
        id: map['id'] as String,
        label: map['label'] as String,
        nextSceneId: map['next_scene_id'] as String,
        requires: (map['requires'] as List).cast<String>(),
        forbids: (map['forbids'] as List).cast<String>(),
        adds: (map['adds'] as List).cast<String>(),
        removes: (map['removes'] as List).cast<String>(),
      );
    } catch (_) {
      throw const FormatException('Неверное действие сценария');
    }
  }
}

class DraftScene {
  DraftScene({
    required this.id,
    required this.chapterIndex,
    required this.text,
    required this.origin,
    required List<String> assertionIds,
    required this.terminal,
    required List<DraftChoice> choices,
  }) : assertionIds = List.unmodifiable(assertionIds),
       choices = List.unmodifiable(choices);

  final String id;
  final int chapterIndex;
  final String text;
  final DraftSceneOrigin origin;
  final List<String> assertionIds;
  final bool terminal;
  final List<DraftChoice> choices;

  Map<String, Object> toJson() => {
    'id': id, 'chapter_index': chapterIndex,
    'text': text, 'origin': origin.name.toUpperCase(),
    'assertion_ids': assertionIds, 'terminal': terminal,
    'choices': choices.map((choice) => choice.toJson()).toList(),
  };

  factory DraftScene.fromJson(Map<String, dynamic> map) {
    _checkFields(map, {'id', 'chapter_index', 'text',
        'origin', 'assertion_ids', 'terminal', 'choices'});
    try {
      return DraftScene(
        id: map['id'] as String,
        chapterIndex: map['chapter_index'] as int,
        text: map['text'] as String,
        origin: DraftSceneOrigin.values.firstWhere(
            (value) => value.name.toUpperCase() == map['origin']),
        assertionIds: (map['assertion_ids'] as List).cast<String>(),
        terminal: map['terminal'] as bool,
        choices: (map['choices'] as List).map((choice) =>
            DraftChoice.fromJson(Map<String, dynamic>.from(choice as Map)))
            .toList(),
      );
    } catch (_) {
      throw const FormatException('Неверная сцена промежуточного сценария');
    }
  }
}

void _checkFields(Map<String, dynamic> map, Set<String> keys) {
  if (map.length != keys.length || !map.keys.toSet().containsAll(keys)) {
    throw const FormatException('Лишнее или отсутствующее поле сценария');
  }
}

class CausalPreflight {
  const CausalPreflight({
    required this.reachableScenes,
    required this.reachableEndings,
    required this.reachableStates,
    required this.canExportPublic,
    required this.blockers,
  });

  final int reachableScenes;
  final int reachableEndings;
  final int reachableStates;
  final bool canExportPublic;
  final List<String> blockers;

  /// The paths pass structural causality checks even if semantic and
  /// packaging acceptance is still blocked by separate compiler gates.
  bool get isCausallyComplete =>
      reachableScenes > 0 && reachableEndings >= 2 && reachableStates > 0;
  bool get canPublishBookworld => false;
}

class IntermediateStoryBlueprint {
  IntermediateStoryBlueprint({
    required this.sourceFingerprint,
    required this.title,
    required this.entrySceneId,
    required this.rights,
    required List<String> flags,
    required List<String> initialFlags,
    required List<DraftScene> scenes,
  }) : flags = List.unmodifiable(flags),
       initialFlags = List.unmodifiable(initialFlags),
       scenes = List.unmodifiable(scenes);

  static const format = 'ai_story_intermediate_blueprint_m2c_v1';
  static const maxDraftBytes = 2 * 1024 * 1024;
  static const maxScenes = 192;
  static const maxStates = 2500;

  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  final String sourceFingerprint;
  final String title;
  final String entrySceneId;
  final PreparationRights rights;
  final List<String> flags;
  final List<String> initialFlags;
  final List<DraftScene> scenes;

  /// Only a compiler with separate legal, semantic and package acceptance
  /// may ever turn this untrusted intermediate draft into a playable world.
  bool get canPublishBookworld => false;
  double get gameplayCoverage => 0;

  Map<String, Object> toJson() => {
    'format': format,
    'source_fingerprint': sourceFingerprint,
    'title': title,
    'entry_scene_id': entrySceneId,
    'rights': rights.name.toUpperCase(),
    'flags': flags,
    'initial_flags': initialFlags,
    'scenes': scenes.map((scene) => scene.toJson()).toList(),
    'status': 'DRAFT_ONLY',
    'gameplay_coverage': 0,
    'can_publish_bookworld': false,
  };

  factory IntermediateStoryBlueprint.fromJson(
      Map<String, dynamic> map) {
    const keys = {'format', 'source_fingerprint', 'title',
      'entry_scene_id', 'rights', 'flags', 'initial_flags', 'scenes',
      'status', 'gameplay_coverage', 'can_publish_bookworld'};
    _checkFields(map, keys);
    if (map['format'] != format || map['status'] != 'DRAFT_ONLY' ||
        map['gameplay_coverage'] != 0 ||
        map['can_publish_bookworld'] != false) {
      throw const FormatException('Нельзя выдавать черновик за готовую RPG');
    }
    try {
      return IntermediateStoryBlueprint(
        sourceFingerprint: map['source_fingerprint'] as String,
        title: map['title'] as String,
        entrySceneId: map['entry_scene_id'] as String,
        rights: PreparationRights.values.firstWhere(
            (value) => value.name.toUpperCase() == map['rights']),
        flags: (map['flags'] as List).cast<String>(),
        initialFlags: (map['initial_flags'] as List).cast<String>(),
        scenes: (map['scenes'] as List).map((raw) =>
            DraftScene.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList(),
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Неверная схема чернового сценария');
    }
  }

  String encode({bool expanded = false}) {
    final raw = jsonEncode(toJson());
    if (utf8.encode(raw).length > (expanded ? 4 * maxDraftBytes : maxDraftBytes)) {
      throw const FormatException('Слишком большой черновик сценария');
    }
    return raw;
  }

  static IntermediateStoryBlueprint decode(String raw,
      {bool expanded = false}) {
    if (utf8.encode(raw).length > (expanded ? 4 * maxDraftBytes : maxDraftBytes)) {
      throw const FormatException('Слишком большой черновик сценария');
    }
    try {
      return IntermediateStoryBlueprint.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неправильный JSON черновика');
    }
  }

  /// Exhaustive bounded state exploration, not just static scene links.
  /// An alternate choice that prevents a required event cannot keep routing
  /// into the canonical scene. A dead state or loop with no exit is rejected.
  CausalPreflight validate(BookSourceIndex index,
      SourceEvidenceGraph evidence, SourceSemanticCatalog catalog,
      {bool expanded = false}) {
    if (index.sourceFingerprint != sourceFingerprint ||
        evidence.sourceFingerprint != sourceFingerprint ||
        catalog.sourceFingerprint != sourceFingerprint ||
        title.trim().isEmpty || title.length > 256 ||
        scenes.isEmpty || scenes.length > (expanded ? 1024 : maxScenes) ||
        flags.length > (expanded ? 64 : 32) || flags.toSet().length != flags.length ||
        initialFlags.toSet().length != initialFlags.length ||
        !_id.hasMatch(entrySceneId)) {
      throw const FormatException('Несовместимый источник или размер сценария');
    }
    if (utf8.encode(jsonEncode(toJson())).length >
        (expanded ? 4 * maxDraftBytes : maxDraftBytes)) {
      throw const FormatException('Черновик превышает безопасный размер');
    }
    final declared = flags.toSet();
    if (declared.any((value) => !_id.hasMatch(value)) ||
        initialFlags.any((value) => !declared.contains(value))) {
      throw const FormatException('Недопустимые состояния сценария');
    }
    final evidenceById = {for (final e in evidence.records) e.id: e};
    final claimsById = {for (final c in catalog.assertions) c.id: c};
    final byScene = <String, DraftScene>{};
    final allChoices = <String>{};
    for (final scene in scenes) {
      if (!_id.hasMatch(scene.id) || byScene.containsKey(scene.id) ||
          scene.chapterIndex < 0 || scene.chapterIndex >= index.chapterCount ||
          scene.text.trim().isEmpty || scene.text.length > 6000 ||
          scene.choices.length > 16 ||
          scene.terminal == scene.choices.isNotEmpty ||
          scene.assertionIds.length > 24 ||
          scene.assertionIds.toSet().length != scene.assertionIds.length ||
          (scene.origin == DraftSceneOrigin.sourcePassage &&
              scene.assertionIds.isEmpty)) {
        throw const FormatException('Некорректная игровая сцена');
      }
      for (final assertionId in scene.assertionIds) {
        final claim = claimsById[assertionId];
        if (claim == null) {
          throw const FormatException('В сцене выдумана ссылка на утверждение');
        }
        for (final evidenceId in claim.evidenceIds) {
          final ref = evidenceById[evidenceId];
          if (ref == null || ref.status == EvidenceStatus.rejected ||
              ref.spoilerGate != EvidenceSpoilerGate.chapter ||
              ref.visibleAfterChapter > scene.chapterIndex) {
            throw const FormatException('Сцена раскрывает неподтверждённый источник или спойлер');
          }
          ref.validate(index);
        }
      }
      for (final choice in scene.choices) {
        if (!_id.hasMatch(choice.id) || !allChoices.add(choice.id) ||
            !_id.hasMatch(choice.nextSceneId) ||
            choice.label.trim().isEmpty || choice.label.length > 300) {
          throw const FormatException('Дублирующийся или неверный выбор');
        }
        final sets = [choice.requires, choice.forbids,
            choice.adds, choice.removes];
        for (final values in sets) {
          if (values.length > 32 || values.toSet().length != values.length ||
              values.any((value) => !declared.contains(value))) {
            throw const FormatException('Неизвестная причинная зависимость');
          }
        }
        if (choice.requires.toSet().intersection(
                choice.forbids.toSet()).isNotEmpty ||
            choice.adds.toSet().intersection(
                choice.removes.toSet()).isNotEmpty) {
          throw const FormatException('Противоречащие условия выбора');
        }
      }
      byScene[scene.id] = scene;
    }
    if (!byScene.containsKey(entrySceneId)) {
      throw const FormatException('Отсутствует начальная сцена');
    }
    for (final scene in scenes) {
      for (final choice in scene.choices) {
        if (!byScene.containsKey(choice.nextSceneId)) {
          throw const FormatException('Выбор ведёт в отсутствующую сцену');
        }
      }
    }

    final flagsInOrder = flags.toList()..sort();
    int mask(Set<String> active) {
      var bits = 0;
      for (var i = 0; i < flagsInOrder.length; i++) {
        if (active.contains(flagsInOrder[i])) bits |= 1 << i;
      }
      return bits;
    }

    final bitByFlag = <String, int>{
      for (var i = 0; i < flagsInOrder.length; i++)
        flagsInOrder[i]: 1 << i,
    };
    int sumBits(List<String> values) =>
        values.fold(0, (result, value) => result | bitByFlag[value]!);
    // The proof can merge histories with different dormant flags, but no
    // actual initial flags or committed game events are deleted.
    final projection = expanded ? FutureFlagLiveness.derive(
      scenes: byScene.keys,
      edges: [
        for (final scene in scenes)
          for (final choice in scene.choices)
            FutureFlagEdge(
              from: scene.id, to: choice.nextSceneId,
              reads: [...choice.requires, ...choice.forbids],
              writes: [...choice.adds, ...choice.removes],
            ),
      ],
    ) : null;
    final relevance = expanded
        ? {for (final scene in byScene.keys)
            scene: projection!.bitMask(scene, bitByFlag)}
        : const <String, int>{};
    String keyOf(String scene, int bits) => scene + ':' +
        (expanded ? (bits & relevance[scene]!) : bits).toString();

    final start = keyOf(entrySceneId, mask(initialFlags.toSet()));
    final queue = <(String, int)>[
      (entrySceneId, mask(initialFlags.toSet())),
    ];
    final discovered = <String>{start};
    final seenScenes = <String>{};
    final endScenes = <String>{};
    final predecessors = <String, Set<String>>{};
    final terminals = <String>{};

    for (var cursor = 0; cursor < queue.length; cursor++) {
      if (queue.length > (expanded ? 8000 : maxStates)) {
        throw const FormatException('Превышен лимит симуляции причинности');
      }
      final current = queue[cursor];
      final id = keyOf(current.$1, current.$2);
      final scene = byScene[current.$1]!;
      seenScenes.add(scene.id);
      if (scene.terminal) {
        terminals.add(id);
        endScenes.add(scene.id);
        continue;
      }
      var available = 0;
      for (final action in scene.choices) {
        final required = sumBits(action.requires);
        final forbidden = sumBits(action.forbids);
        if ((current.$2 & required) != required ||
            (current.$2 & forbidden) != 0) continue;
        available++;
        final nextBits = (current.$2 | sumBits(action.adds)) &
            ~sumBits(action.removes);
        final to = keyOf(action.nextSceneId, nextBits);
        predecessors.putIfAbsent(to, () => <String>{}).add(id);
        if (discovered.add(to)) {
          queue.add((action.nextSceneId, nextBits));
        }
      }
      if (available == 0) {
        throw const FormatException('Достижимое состояние без доступных действий');
      }
    }
    if (endScenes.length < 2 || seenScenes.length != scenes.length) {
      throw const FormatException(
          'Не проверены две альтернативные концовки или имеются недостижимые сцены');
    }
    final canEscape = <String>{...terminals};
    final stack = terminals.toList();
    while (stack.isNotEmpty) {
      final state = stack.removeLast();
      for (final previous in predecessors[state] ?? <String>{}) {
        if (canEscape.add(previous)) stack.add(previous);
      }
    }
    if (canEscape.length != discovered.length) {
      throw const FormatException('Существует цикл без достижимой развязки');
    }
    final blockers = <String>[
      'Это черновик: нет принятого компилятора пользовательских .bworld',
      'Нет верифицированной семантической истинности всех утверждений',
    ];
    if (rights == PreparationRights.unknown) {
      blockers.add('Не определены права на использование и адаптацию');
    }
    if (catalog.assertions.isEmpty) {
      blockers.add('Не извлечены смысловые утверждения из книги');
    }
    return CausalPreflight(
      reachableScenes: seenScenes.length,
      reachableEndings: endScenes.length,
      reachableStates: discovered.length,
      canExportPublic: false,
      blockers: List.unmodifiable(blockers),
    );
  }
}
