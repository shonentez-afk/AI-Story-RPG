import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'source_semantic_provider.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency.dart';
import 'zai_semantic_review_queue.dart';

/// This is NOT the game's M2c IntermediateStoryBlueprint. An event can
/// appear in this private source-backed storyboard without proving it true.
class ZaiSourceScene {
  ZaiSourceScene({
    required this.id,
    required this.title,
    required this.notes,
    required this.chapterIndex,
    required List<String> eventIds,
  }) : eventIds = List.unmodifiable(eventIds);

  final String id;
  final String title;
  final String notes;
  final int chapterIndex;
  final List<String> eventIds;

  bool get isPlayable => false;
  bool get hasVerifiedCausality => false;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'chapter_index': chapterIndex,
    'event_ids': eventIds,
    'status': 'PRIVATE_SOURCE_SCENE_DRAFT',
  };
}

/// The reader classifies the *source of a statement*, not world truth.
/// Even narratorText does NOT establish that the narrator is reliable.
enum ZaiClaimContext { narratorText, characterSpeech, disputed, unknown }

class ZaiClaimContextNote {
  const ZaiClaimContextNote({
    required this.candidateId,
    required this.context,
    required this.note,
  });

  final String candidateId;
  final ZaiClaimContext context;
  final String note;

  bool get isVerifiedWorldTruth => false;

  Map<String, Object> toJson() => {
    'candidate_id': candidateId,
    'context': context.name,
    'note': note,
    'status': 'SOURCE_CONTEXT_ONLY',
  };
}

/// M2f3d - isolated private scene planning over M2f3a/b retained quotes.
/// It cannot publish BookWorld and cannot rewrite existing RPG saves.
class ZaiSourceSceneBoard {
  ZaiSourceSceneBoard._(
    this.graph,
    List<ZaiSourceScene> scenes,
    Map<String, ZaiClaimContextNote> contexts,
  ) : scenes = List.unmodifiable(scenes),
      contexts = Map.unmodifiable(contexts);

  static const format = 'ai_story_zai_source_scenes_m2f3d_v1';
  static const maxBytes = 512 * 1024;
  static const maxScenes = 192;
  static const maxEventsPerScene = 8;
  static const maxContexts = 800;
  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  final ZaiCrossWindowEvidenceGraph graph;
  final List<ZaiSourceScene> scenes;
  final Map<String, ZaiClaimContextNote> contexts;

  factory ZaiSourceSceneBoard.empty(ZaiCrossWindowEvidenceGraph graph) =>
      ZaiSourceSceneBoard._(graph, const [], const {});

  bool get canPublishBookworld => false;
  bool get canStartRpg => false;
  bool get hasVerifiedWorldFacts => false;
  bool get isOnlyPrivateDraft => true;

  static String _digest(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  static String _id(String fingerprint, List<String> ids) =>
      _digest('$fingerprint|${ids.join('|')}').substring(0, 32);

  static void _checkText(String value, int minLength, int maxLength) {
    if (value != value.trim() ||
        value.length < minLength || value.length > maxLength ||
        _controls.hasMatch(value)) {
      throw const FormatException('Недопустимое название или пояснение сцены');
    }
  }

  Map<String, ZaiAnchoredFinding> get _byId =>
      {for (final f in graph.reviewed) f.id: f};

  void _checkScene(ZaiSourceScene scene) {
    _checkText(scene.title, 3, 120);
    _checkText(scene.notes, 0, 320);
    if (scene.eventIds.isEmpty ||
        scene.eventIds.length > maxEventsPerScene ||
        scene.eventIds.toSet().length != scene.eventIds.length ||
        scene.id != _id(graph.index.sourceFingerprint, scene.eventIds)) {
      throw const FormatException('Сцена содержит неверные ID событий');
    }
    final byId = _byId;
    for (final id in scene.eventIds) {
      final finding = byId[id];
      if (finding == null ||
          finding.category != SemanticCategory.event ||
          finding.chapterIndex != scene.chapterIndex) {
        throw const FormatException(
            'Сцена смешивает главы или непроверенные события');
      }
    }
  }

  void _checkContext(ZaiClaimContextNote note) {
    _checkText(note.note, 8, 240);
    final source = _byId[note.candidateId];
    if (source == null ||
        (source.category != SemanticCategory.fact &&
         source.category != SemanticCategory.state)) {
      throw const FormatException('Контекст не относится к актуальной цитате');
    }
  }

  ZaiSourceSceneBoard addScene(
      List<String> eventIds, String title, String notes) {
    final ids = List<String>.unmodifiable(eventIds);
    final source = _byId[ids.isNotEmpty ? ids.first : ''];
    if (source == null) {
      throw const FormatException('Нет доступного события для сцены');
    }
    final scene = ZaiSourceScene(
      id: _id(graph.index.sourceFingerprint, ids),
      chapterIndex: source.chapterIndex,
      title: title.trim(), notes: notes.trim(), eventIds: ids,
    );
    _checkScene(scene);
    if (scenes.length >= maxScenes ||
        scenes.any((e) => e.id == scene.id) ||
        scenes.any((e) =>
            e.eventIds.any((id) => scene.eventIds.contains(id)))) {
      throw const FormatException('Событие уже есть в черновике или превышен предел');
    }
    return ZaiSourceSceneBoard._(graph, [...scenes, scene], contexts);
  }

  ZaiSourceSceneBoard removeScene(String id) {
    if (!scenes.any((scene) => scene.id == id)) {
      throw const FormatException('Сцена не найдена');
    }
    return ZaiSourceSceneBoard._(
        graph, scenes.where((scene) => scene.id != id).toList(), contexts);
  }

  /// Reorders only the editorial STORYBOARD, not the text or story time.
  ZaiSourceSceneBoard moveScene(String id, int toIndex) {
    final from = scenes.indexWhere((scene) => scene.id == id);
    if (from < 0 || toIndex < 0 || toIndex >= scenes.length) {
      throw const FormatException('Недопустимая перестановка сцены');
    }
    final reordered = [...scenes];
    reordered.insert(toIndex, reordered.removeAt(from));
    return ZaiSourceSceneBoard._(graph, reordered, contexts);
  }

  ZaiSourceSceneBoard noteContext(String candidateId,
      ZaiClaimContext context, String note) {
    final entry = ZaiClaimContextNote(
      candidateId: candidateId, context: context, note: note.trim(),
    );
    _checkContext(entry);
    if (!contexts.containsKey(candidateId) && contexts.length >= maxContexts) {
      throw const FormatException('Превышен предел контекстных заметок');
    }
    return ZaiSourceSceneBoard._(
        graph, scenes, {...contexts, candidateId: entry});
  }

  ZaiSourceSceneBoard removeContext(String candidateId) {
    if (!contexts.containsKey(candidateId)) {
      throw const FormatException('Контекстная заметка не найдена');
    }
    final next = Map<String, ZaiClaimContextNote>.from(contexts);
    next.remove(candidateId);
    return ZaiSourceSceneBoard._(graph, scenes, next);
  }

  void _validate() {
    if (scenes.length > maxScenes || contexts.length > maxContexts ||
        scenes.map((scene) => scene.id).toSet().length != scenes.length) {
      throw const FormatException('Избыток или дублирование сцен');
    }
    final allEvents = <String>{};
    for (final scene in scenes) {
      _checkScene(scene);
      for (final id in scene.eventIds) {
        if (!allEvents.add(id)) {
          throw const FormatException('Событие включено в несколько сцен');
        }
      }
    }
    for (final entry in contexts.entries) {
      if (entry.key != entry.value.candidateId) {
        throw const FormatException('Контекст привязан к другому факту');
      }
      _checkContext(entry.value);
    }
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': graph.index.sourceFingerprint,
    'status': 'PRIVATE_DRAFT_NOT_RPG',
    'can_publish_bookworld': false,
    'scenes': [for (final scene in scenes) scene.toJson()],
    'contexts': [
      for (final key in contexts.keys.toList()..sort())
        contexts[key]!.toJson(),
    ],
  };

  String encode() {
    _validate();
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _digest(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой черновик сцен');
    }
    return raw;
  }

  static ZaiSourceSceneBoard decode(
      ZaiCrossWindowEvidenceGraph graph, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой черновик сцен');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const rootKeys = {'format', 'payload', 'sha256'};
      if (root.keys.toSet().difference(rootKeys).isNotEmpty ||
          root.length != rootKeys.length || root['format'] != format) {
        throw const FormatException('Неизвестный формат черновика сцен');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const keys = {'source_fingerprint', 'status',
        'can_publish_bookworld', 'scenes', 'contexts'};
      if (payload.length != keys.length ||
          payload.keys.toSet().difference(keys).isNotEmpty ||
          payload['source_fingerprint'] != graph.index.sourceFingerprint ||
          payload['status'] != 'PRIVATE_DRAFT_NOT_RPG' ||
          payload['can_publish_bookworld'] != false ||
          root['sha256'] != _digest(jsonEncode(payload))) {
        throw const FormatException('Черновик повреждён или относится к другой книге');
      }
      final rawScenes = payload['scenes'] as List<dynamic>;
      final rawContexts = payload['contexts'] as List<dynamic>;
      if (rawScenes.length > maxScenes || rawContexts.length > maxContexts) {
        throw const FormatException('Превышены пределы сохранённого черновика');
      }
      final scenes = <ZaiSourceScene>[];
      for (final entry in rawScenes) {
        final data = Map<String, dynamic>.from(entry as Map);
        const sceneKeys = {'id', 'title', 'notes', 'chapter_index',
          'event_ids', 'status'};
        if (data.length != sceneKeys.length ||
            data.keys.toSet().difference(sceneKeys).isNotEmpty ||
            data['status'] != 'PRIVATE_SOURCE_SCENE_DRAFT') {
          throw const FormatException('Подменена сцена или статус');
        }
        scenes.add(ZaiSourceScene(
          id: data['id'] as String,
          title: data['title'] as String,
          notes: data['notes'] as String,
          chapterIndex: data['chapter_index'] as int,
          eventIds: (data['event_ids'] as List).cast<String>(),
        ));
      }
      final contexts = <String, ZaiClaimContextNote>{};
      for (final entry in rawContexts) {
        final data = Map<String, dynamic>.from(entry as Map);
        const contextKeys = {'candidate_id','context','note','status'};
        if (data.length != contextKeys.length ||
            data.keys.toSet().difference(contextKeys).isNotEmpty ||
            data['status'] != 'SOURCE_CONTEXT_ONLY') {
          throw const FormatException('Подменён контекст утверждения');
        }
        final note = ZaiClaimContextNote(
          candidateId: data['candidate_id'] as String,
          context: ZaiClaimContext.values.byName(data['context'] as String),
          note: data['note'] as String,
        );
        if (contexts.containsKey(note.candidateId)) {
          throw const FormatException('Дублирован контекст утверждения');
        }
        contexts[note.candidateId] = note;
      }
      final decoded = ZaiSourceSceneBoard._(graph, scenes, contexts);
      if (decoded.encode() != raw) {
        throw const FormatException('Черновик неканонический или подменён');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Не удалось восстановить черновик сцен');
    }
  }
}

/// Source evidence checks for a LATER compiler. PASS here NEVER authorizes
/// export: choices, causal state, legal rights, AI policy and spoilers still
/// need separate explicit preflight and human approval.
enum ZaiSceneGateIssue {
  noScenes,
  unfinishedWindows,
  unreviewedCandidates,
  uncoveredEvents,
  unclassifiedStatements,
  openConsistencyQuestions,
  openPossibleDiscrepancies,
  sceneOrderVsProposedTimeline,
  missingCausalChoices,
  productionCompilerDisconnected,
}

class ZaiSceneGateFinding {
  const ZaiSceneGateFinding(this.issue, this.description);
  final ZaiSceneGateIssue issue;
  final String description;
}

class ZaiScenePreflight {
  const ZaiScenePreflight._(this.findings,
      this.sceneCount, this.coveredEvents, this.totalEvents);

  final List<ZaiSceneGateFinding> findings;
  final int sceneCount;
  final int coveredEvents;
  final int totalEvents;

  bool get canPublishBookworld => false;
  bool get canStartPlayableRpg => false;
  bool get isCompilerConnected => false;

  double get eventCoverage => totalEvents == 0 ?
      0 : coveredEvents / totalEvents;

  factory ZaiScenePreflight.assess(
      ZaiWindowReviewQueue queue,
      ZaiSourceSceneBoard board, {
      ZaiEditorialConsistencyNotebook? consistency,
    }) {
    final current = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    if (board.graph.index.sourceFingerprint !=
        current.index.sourceFingerprint ||
        board.graph.reviewed.length != current.reviewed.length ||
        !board.graph.reviewed.asMap().entries.every((e) =>
            e.value.id == current.reviewed[e.key].id)) {
      throw const FormatException('Черновик не соответствует текущим решениям по цитатам');
    }
    if (consistency != null) {
      if (consistency.graph.index.sourceFingerprint !=
              current.index.sourceFingerprint ||
          consistency.graph.reviewed.length != current.reviewed.length ||
          !consistency.graph.reviewed.asMap().entries.every((e) =>
              e.value.id == current.reviewed[e.key].id)) {
        throw const FormatException('Чужие редакторские вопросы');
      }
    }
    final findings = <ZaiSceneGateFinding>[];
    void warn(ZaiSceneGateIssue issue, String message) =>
        findings.add(ZaiSceneGateFinding(issue, message));
    if (board.scenes.isEmpty) {
      warn(ZaiSceneGateIssue.noScenes,
          'Нет ни одной сцены с точным событием из исходной книги.');
    }
    if (queue.pendingCount > 0) {
      warn(ZaiSceneGateIssue.unfinishedWindows,
          'Не проанализировано окон книги: ${queue.pendingCount}. '
          'Каждое новое окно требует отдельного согласия на передачу.');
    }
    if (queue.pendingReviewCount > 0) {
      warn(ZaiSceneGateIssue.unreviewedCandidates,
          'Не принято редакторских решений по ${queue.pendingReviewCount} предложениям.');
    }
    final events = current.textOrderedEvents.toList();
    final used = <String>{
      for (final scene in board.scenes) ...scene.eventIds,
    };
    if (used.length != events.length) {
      warn(ZaiSceneGateIssue.uncoveredEvents,
          'В сцены включено ${used.length} из ${events.length} '
          'оставленных для проверки событий.');
    }
    final claims = current.statedFactsAndStates.toList();
    if (claims.length != board.contexts.length) {
      warn(ZaiSceneGateIssue.unclassifiedStatements,
          'Указан контекст для ${board.contexts.length} из ${claims.length} '
          'оставленных утверждений (это не проверка истины).');
    }
    if (consistency != null && consistency.questions.isNotEmpty) {
      warn(ZaiSceneGateIssue.openConsistencyQuestions,
          'Открытых вопросов алиасов, отношений, расхождений '
          'и времени: ${consistency.questions.length}.');
    }
    final cues = ZaiConsistencyHints.reviewCues(current).length;
    if (cues > 0) {
      warn(ZaiSceneGateIssue.openPossibleDiscrepancies,
          'Возможных текстовых расхождений для проверки: $cues.');
    }
    final byScene = <String, int>{
      for (final entry in board.scenes.indexed)
        for (final id in entry.$2.eventIds) id: entry.$1,
    };
    var disagreements = 0;
    for (final question in consistency?.questions ??
        const <ZaiConsistencyQuestion>[]) {
      if (question.kind != ZaiConsistencyKind.possibleBefore) continue;
      final first = byScene[question.firstId];
      final second = byScene[question.secondId];
      if (first != null && second != null && first >= second) {
        disagreements++;
      }
    }
    if (disagreements > 0) {
      warn(ZaiSceneGateIssue.sceneOrderVsProposedTimeline,
          'Черновой порядок сцен не совпадает с $disagreements '
          'предположениями о времени событий. Это не доказанный конфликт.');
    }
    // No invented choices or state changes are inserted into a user's book.
    warn(ZaiSceneGateIssue.missingCausalChoices,
        'В черновике ещё нет проверенных альтернатив, последствий выбора '
        'и переходов между сценами.');
    warn(ZaiSceneGateIssue.productionCompilerDisconnected,
        'Этот локальный граф не экспортируется в BookWorld. '
        'Полные права, сюжетные факты, знания NPC и причинность требуют '
        'отдельной проверки перед компилятором.');
    return ZaiScenePreflight._(
        List.unmodifiable(findings), board.scenes.length,
        used.length, events.length);
  }
}
