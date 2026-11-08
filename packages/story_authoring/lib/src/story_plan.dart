import 'dart:convert';

import 'intermediate_story_blueprint.dart';
import 'narrative_book_model.dart';

/// M2g3b: a typed, NON-EXECUTABLE planning contract.
/// Meaning and causal claims from an AI are hypotheses until independently
/// checked. A structurally valid plan is never automatically a playable game.
enum StoryRoute { canonicalProposal, adaptationFiction }

class StoryDecision {
  StoryDecision({
    required this.id,
    required this.intent,
    required this.nextSituationId,
    this.sourceEventId,
    this.route = StoryRoute.adaptationFiction,
    List<String> requires = const [],
    List<String> forbids = const [],
    List<String> adds = const [],
    List<String> removes = const [],
  }) : requires = List.unmodifiable(requires),
       forbids = List.unmodifiable(forbids),
       adds = List.unmodifiable(adds),
       removes = List.unmodifiable(removes);

  final String id;
  final String intent;
  final String nextSituationId;
  final String? sourceEventId;
  final StoryRoute route;
  final List<String> requires, forbids, adds, removes;

  Map<String, Object?> toJson() => {
    'id': id, 'intent': intent, 'next_situation_id': nextSituationId,
    'source_event_id': sourceEventId, 'route': route.name,
    'requires': requires, 'forbids': forbids, 'adds': adds, 'removes': removes,
  };
}

class StorySituation {
  StorySituation({
    required this.id,
    required this.goal,
    required this.conflict,
    required this.chapterIndex,
    this.sourceEventId,
    this.route = StoryRoute.adaptationFiction,
    required this.terminal,
    required List<StoryDecision> decisions,
  }) : decisions = List.unmodifiable(decisions);

  final String id;
  final String goal;
  final String conflict;
  final int chapterIndex;
  final String? sourceEventId;
  final StoryRoute route;
  final bool terminal;
  final List<StoryDecision> decisions;

  Map<String, Object?> toJson() => {
    'id': id, 'goal': goal, 'conflict': conflict,
    'chapter_index': chapterIndex, 'source_event_id': sourceEventId,
    'route': route.name, 'terminal': terminal,
    'decisions': [for (final d in decisions) d.toJson()],
  };
}

class StoryPlanReport {
  const StoryPlanReport({
    required this.reachableSituations,
    required this.reachableStates,
    required this.terminalSituations,
    required this.branchChangesState,
    required this.blockers,
  });

  final int reachableSituations, reachableStates, terminalSituations;
  final bool branchChangesState;
  final List<String> blockers;
  bool get isStructurallySound => blockers.isEmpty;
  bool get isSemanticallyApproved => false;
  bool get isReadyToPlay => false;
}

/// Draft-only plan that can be translated into the existing M2c representation.
/// No direct BookWorld creation, SQLite mutation, or model-selected side effects.
class StoryPlan {
  StoryPlan({
    required this.sourceFingerprint,
    required this.title,
    required this.entrySituationId,
    required List<String> flags,
    required List<String> initialFlags,
    required List<StorySituation> situations,
  }) : flags = List.unmodifiable(flags),
       initialFlags = List.unmodifiable(initialFlags),
       situations = List.unmodifiable(situations);

  static const format = 'ai_story_story_plan_m2g3b_v1';
  static const maxBytes = 1024 * 1024;
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  final String sourceFingerprint, title, entrySituationId;
  final List<String> flags, initialFlags;
  final List<StorySituation> situations;

  bool get isPlayable => false;
  bool get hasVerifiedCausality => false;
  bool get canPublish => false;

  Map<String, Object?> toJson() => {
    'format': format, 'source_fingerprint': sourceFingerprint,
    'title': title, 'entry_situation_id': entrySituationId,
    'flags': flags, 'initial_flags': initialFlags,
    'situations': [for (final s in situations) s.toJson()],
    'status': 'DRAFT_ONLY', 'is_playable': false,
  };

  String encode() {
    final result = jsonEncode(toJson());
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('Слишком большой StoryPlan');
    }
    return result;
  }

  static void _fields(Map<String, dynamic> map, Set<String> allowed) {
    if (map.keys.toSet().length != allowed.length ||
        !map.keys.toSet().containsAll(allowed)) {
      throw const FormatException('Неверные поля StoryPlan');
    }
  }

  static List<String> _strings(dynamic raw) =>
      (raw as List).map((item) => item as String).toList();

  static StoryRoute _route(dynamic raw) =>
      StoryRoute.values.firstWhere((route) => route.name == raw);

  factory StoryPlan.decode(String encoded) {
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('Слишком большой StoryPlan');
    }
    try {
      final json = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      _fields(json, {
        'format', 'source_fingerprint', 'title', 'entry_situation_id',
        'flags', 'initial_flags', 'situations', 'status', 'is_playable',
      });
      if (json['format'] != format || json['status'] != 'DRAFT_ONLY' ||
          json['is_playable'] != false) {
        throw const FormatException('Нельзя выдавать план за игру');
      }
      final situations = <StorySituation>[];
      for (final raw in json['situations'] as List) {
        final s = Map<String, dynamic>.from(raw as Map);
        _fields(s, {'id', 'goal', 'conflict', 'chapter_index',
          'source_event_id', 'route', 'terminal', 'decisions'});
        final decisions = <StoryDecision>[];
        for (final item in s['decisions'] as List) {
          final d = Map<String, dynamic>.from(item as Map);
          _fields(d, {'id', 'intent', 'next_situation_id',
            'source_event_id', 'route', 'requires', 'forbids', 'adds', 'removes'});
          decisions.add(StoryDecision(
            id: d['id'] as String, intent: d['intent'] as String,
            nextSituationId: d['next_situation_id'] as String,
            sourceEventId: d['source_event_id'] as String?,
            route: _route(d['route']),
            requires: _strings(d['requires']), forbids: _strings(d['forbids']),
            adds: _strings(d['adds']), removes: _strings(d['removes']),
          ));
        }
        situations.add(StorySituation(
          id: s['id'] as String, goal: s['goal'] as String,
          conflict: s['conflict'] as String,
          chapterIndex: s['chapter_index'] as int,
          sourceEventId: s['source_event_id'] as String?,
          route: _route(s['route']), terminal: s['terminal'] as bool,
          decisions: decisions,
        ));
      }
      return StoryPlan(
        sourceFingerprint: json['source_fingerprint'] as String,
        title: json['title'] as String,
        entrySituationId: json['entry_situation_id'] as String,
        flags: _strings(json['flags']), initialFlags: _strings(json['initial_flags']),
        situations: situations,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён или неизвестен формат StoryPlan');
    }
  }

  static void _text(String text, int limit) {
    if (text.trim().isEmpty || text.length > limit ||
        _controls.hasMatch(text)) {
      throw const FormatException('Неверный текст StoryPlan');
    }
  }

  /// Bounded state exploration. Source text order is NEVER treated as
  /// causal proof; semantics and NPC knowledge require later M2g3c checks.
  StoryPlanReport validate(NarrativeBookModel book, {bool expanded = false}) {
    if (!book.analysisComplete ||
        book.sourceFingerprint != sourceFingerprint ||
        book.title != title ||
        !_id.hasMatch(entrySituationId) ||
        situations.isEmpty || situations.length > (expanded ? 1024 : 192) ||
        flags.length > (expanded ? 64 : 32) || flags.toSet().length != flags.length ||
        initialFlags.toSet().length != initialFlags.length ||
        flags.any((f) => !_id.hasMatch(f)) ||
        initialFlags.any((f) => !flags.contains(f)) ||
        initialFlags.toSet().length != initialFlags.length) {
      throw const FormatException('План не соответствует исходной книге');
    }
    encode();
    final events = {for (final e in book.events) e.id: e};
    final byId = <String, StorySituation>{};
    final decisionIds = <String>{};
    for (final s in situations) {
      _text(s.goal, 400);
      _text(s.conflict, 800);
      if (!_id.hasMatch(s.id) || byId.containsKey(s.id) ||
          s.chapterIndex < 0 || s.chapterIndex >= book.chapterCount ||
          s.decisions.length > 16 ||
          s.terminal == s.decisions.isNotEmpty) {
        throw const FormatException('Неверная ситуация');
      }
      if (s.sourceEventId != null &&
          (events[s.sourceEventId] == null ||
           events[s.sourceEventId]!.source.chapterIndex != s.chapterIndex)) {
        throw const FormatException('Ситуация ссылается на чужое событие');
      }
      for (final d in s.decisions) {
        _text(d.intent, 300);
        if (!_id.hasMatch(d.id) || !decisionIds.add(d.id) ||
            !_id.hasMatch(d.nextSituationId) ||
            (d.sourceEventId != null && !events.containsKey(d.sourceEventId))) {
          throw const FormatException('Некорректное решение');
        }
        for (final set in [d.requires, d.forbids, d.adds, d.removes]) {
          if (set.length > 32 || set.toSet().length != set.length ||
              set.any((v) => !flags.contains(v))) {
            throw const FormatException('Неизвестное состояние решения');
          }
        }
        if (d.requires.toSet().intersection(d.forbids.toSet()).isNotEmpty ||
            d.adds.toSet().intersection(d.removes.toSet()).isNotEmpty) {
          throw const FormatException('Противоречивое решение');
        }
      }
      byId[s.id] = s;
    }
    if (!byId.containsKey(entrySituationId) ||
        situations.any((s) => s.decisions.any(
            (d) => !byId.containsKey(d.nextSituationId)))) {
      throw const FormatException('Решение ведёт в отсутствующую ситуацию');
    }

    final keys = flags.toList()..sort();
    final bits = <String, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: 1 << i,
    };
    int mask(List<String> active) =>
        active.fold(0, (n, v) => n | bits[v]!);
    final queue = <(String, int)>[(entrySituationId, mask(initialFlags))];
    final visited = <String>{};
    final sceneIds = <String>{};
    final terminals = <String>{};
    final previous = <String, Set<String>>{};
    bool changedState = false;
    for (var i = 0; i < queue.length; i++) {
      if (queue.length > (expanded ? 8000 : 2500)) {
        throw const FormatException('Превышен лимит проверки состояний');
      }
      final node = queue[i];
      final key = '${node.$1}:${node.$2}';
      if (!visited.add(key)) continue;
      final situation = byId[node.$1]!;
      sceneIds.add(situation.id);
      if (situation.terminal) {
        terminals.add(key);
        continue;
      }
      var count = 0;
      for (final d in situation.decisions) {
        if ((node.$2 & mask(d.requires)) != mask(d.requires) ||
            (node.$2 & mask(d.forbids)) != 0) continue;
        count++;
        final next = (node.$2 | mask(d.adds)) & ~mask(d.removes);
        if (next != node.$2) changedState = true;
        final target = '${d.nextSituationId}:$next';
        previous.putIfAbsent(target, () => <String>{}).add(key);
        if (!visited.contains(target)) queue.add((d.nextSituationId, next));
      }
      if (count == 0) {
        throw const FormatException('Игра попадает в тупик без решений');
      }
    }
    final endIds = {
      for (final key in terminals) key.split(':').first,
    };
    if (endIds.length < 2 || sceneIds.length != situations.length) {
      throw const FormatException('Нет двух достижимых концовок или есть недостижимые сцены');
    }
    final escapable = <String>{...terminals};
    final stack = terminals.toList();
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      for (final predecessor in previous[key] ?? <String>{}) {
        if (escapable.add(predecessor)) stack.add(predecessor);
      }
    }
    if (escapable.length != visited.length) {
      throw const FormatException('Существует цикл без выхода');
    }
    final blockers = <String>[
      if (!changedState) 'Выборы не меняют состояние мира',
    ];
    return StoryPlanReport(
      reachableSituations: sceneIds.length,
      reachableStates: visited.length,
      terminalSituations: endIds.length,
      branchChangesState: changedState,
      blockers: List.unmodifiable(blockers),
    );
  }

  /// Deliberately DRAFT_ONLY. Existing M2c validation and private compiler
  /// remain separate, mandatory steps; no semantic acceptance is implied.
  IntermediateStoryBlueprint toIntermediateDraft(
      NarrativeBookModel book, {PreparationRights rights = PreparationRights.unknown,
      bool expanded = false}) {
    final report = validate(book, expanded: expanded);
    if (!report.isStructurallySound) {
      throw FormatException(report.blockers.join('; '));
    }
    return IntermediateStoryBlueprint(
      sourceFingerprint: sourceFingerprint,
      title: title,
      entrySceneId: entrySituationId,
      rights: rights,
      flags: flags,
      initialFlags: initialFlags,
      scenes: [
        for (final s in situations)
          DraftScene(
            id: s.id,
            chapterIndex: s.chapterIndex,
            text: '${s.goal}\n\n${s.conflict}\n\n'
                'Черновик адаптации: события и причинность требуют проверки.',
            origin: DraftSceneOrigin.explicitAdaptation,
            assertionIds: const [],
            terminal: s.terminal,
            choices: [
              for (final d in s.decisions)
                DraftChoice(
                  id: d.id, label: d.intent, nextSceneId: d.nextSituationId,
                  requires: d.requires, forbids: d.forbids,
                  adds: d.adds, removes: d.removes,
                ),
            ],
          ),
      ],
    );
  }
}
