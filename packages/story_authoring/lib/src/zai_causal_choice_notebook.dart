import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'intermediate_story_blueprint.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_provider.dart';
import 'zai_editorial_consistency.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';

/// A manually written choice of the user, NOT inferred from a book.
/// M2f3e only previews M2c graph contracts; it never installs a BookWorld.
class ZaiCausalChoice {
  ZaiCausalChoice({
    required this.id,
    required this.fromSceneId,
    required this.toSceneId,
    required this.label,
    required this.reason,
    required List<String> requires,
    required List<String> forbids,
    required List<String> adds,
    required List<String> removes,
    this.npcFindingId,
    this.knowledgeFindingId,
  }) : requires = List.unmodifiable(requires),
       forbids = List.unmodifiable(forbids),
       adds = List.unmodifiable(adds),
       removes = List.unmodifiable(removes);

  final String id;
  final String fromSceneId;
  final String toSceneId;
  final String label;
  final String reason;
  final List<String> requires;
  final List<String> forbids;
  final List<String> adds;
  final List<String> removes;

  /// Both IDs must be from live retained citations, never inferred NPC
  /// identity or canonical knowledge. This is an editorial risk flag ONLY.
  final String? npcFindingId;
  final String? knowledgeFindingId;

  bool get knowsThisFact => false;
  bool get isVerifiedCausality => false;
  bool get canPublishBookworld => false;

  Map<String, Object?> toJson() => {
    'id': id,
    'from_scene_id': fromSceneId,
    'to_scene_id': toSceneId,
    'label': label,
    'reason': reason,
    'requires': requires,
    'forbids': forbids,
    'adds': adds,
    'removes': removes,
    'npc_finding_id': npcFindingId,
    'knowledge_finding_id': knowledgeFindingId,
    'status': 'PRIVATE_AUTHORED_HYPOTHESIS',
  };
}

/// Stored separately from M2f3a-d and M2c. A changed M2f3d scene board
/// invalidates the WHOLE notebook; the reader must review/rebuild choices.
class ZaiCausalChoiceNotebook {
  ZaiCausalChoiceNotebook._(
    this.board,
    List<String> flags,
    List<String> initiallyActive,
    List<ZaiCausalChoice> choices,
  ) : flags = List.unmodifiable(flags),
      initiallyActive = List.unmodifiable(initiallyActive),
      choices = List.unmodifiable(choices);

  static const format = 'ai_story_zai_causal_choices_m2f3e_v1';
  static const maxUtf8Bytes = 512 * 1024;
  static const maxFlags = 16;
  static const maxChoices = 256;
  static final RegExp _safeId = RegExp(r'^[a-z][a-z0-9_]{0,31}$');
  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  final ZaiSourceSceneBoard board;
  final List<String> flags;
  final List<String> initiallyActive;
  final List<ZaiCausalChoice> choices;

  factory ZaiCausalChoiceNotebook.empty(ZaiSourceSceneBoard board) =>
      ZaiCausalChoiceNotebook._(board, const [], const [], const []);

  bool get canPublishBookworld => false;
  bool get canStartPlayableRpg => false;
  bool get hasVerifiedCausality => false;
  bool get establishesNpcKnowledge => false;

  static String _sha(String s) => sha256.convert(utf8.encode(s)).toString();
  String get boardSignature => _sha(board.encode());

  static void _text(String text, int min, int max) {
    if (text != text.trim() || text.length < min ||
        text.length > max || _controls.hasMatch(text)) {
      throw const FormatException('Недопустимый текст редакторского выбора');
    }
  }

  static String m2cSceneId(String id) => 'scene_$id';
  static String m2cChoiceId(String id) => 'choice_$id';

  void _validateChoice(ZaiCausalChoice choice) {
    final scenes = {for (final s in board.scenes) s.id: s};
    final from = scenes[choice.fromSceneId];
    final to = scenes[choice.toSceneId];
    if (from == null || to == null ||
        choice.id != _sha('$boardSignature|${choice.fromSceneId}|'
            '${choice.toSceneId}|${choice.label}').substring(0, 32)) {
      throw const FormatException('Выбор ссылается на чужие или изменённые сцены');
    }
    _text(choice.label, 3, 140);
    _text(choice.reason, 8, 240);
    if ((choice.npcFindingId == null) !=
        (choice.knowledgeFindingId == null)) {
      throw const FormatException('Для NPC нужны цитаты персонажа и знания');
    }
    final sets = [
      choice.requires, choice.forbids, choice.adds, choice.removes,
    ];
    for (final set in sets) {
      if (set.length > maxFlags || set.length != set.toSet().length ||
          set.any((id) => !flags.contains(id))) {
        throw const FormatException('Неизвестный или повторный флаг состояния');
      }
    }
    if (choice.requires.toSet().intersection(
            choice.forbids.toSet()).isNotEmpty ||
        choice.adds.toSet().intersection(
            choice.removes.toSet()).isNotEmpty) {
      throw const FormatException('Противоречащие друг другу условия выбора');
    }
    if (choice.npcFindingId != null) {
      final findings = {for (final f in board.graph.reviewed) f.id: f};
      final npc = findings[choice.npcFindingId];
      final knowledge = findings[choice.knowledgeFindingId];
      if (npc == null || knowledge == null ||
          npc.category != SemanticCategory.character ||
          (knowledge.category != SemanticCategory.fact &&
              knowledge.category != SemanticCategory.state &&
              knowledge.category != SemanticCategory.event) ||
          npc.chapterIndex > from.chapterIndex ||
          knowledge.chapterIndex > from.chapterIndex) {
        throw const FormatException(
            'Знания NPC нельзя привязать к будущей или чужой цитате');
      }
    }
  }

  void _validate() {
    board.encode(); // Recheck M2f3d exact source anchors before any save.
    if (flags.length > maxFlags || flags.length != flags.toSet().length ||
        flags.any((id) => !_safeId.hasMatch(id)) ||
        initiallyActive.toSet().length != initiallyActive.length ||
        initiallyActive.any((id) => !flags.contains(id)) ||
        choices.length > maxChoices ||
        choices.map((e) => e.id).toSet().length != choices.length) {
      throw const FormatException('Повреждён набор флагов или переходов');
    }
    final perScene = <String, int>{};
    for (final choice in choices) {
      _validateChoice(choice);
      perScene.update(choice.fromSceneId, (v) => v + 1,
          ifAbsent: () => 1);
      if (perScene[choice.fromSceneId]! > 16) {
        throw const FormatException('Больше 16 решений из одной сцены');
      }
    }
  }

  ZaiCausalChoiceNotebook addFlag(String id, {bool active = false}) {
    if (!_safeId.hasMatch(id) ||
        flags.contains(id) || flags.length >= maxFlags) {
      throw const FormatException(
          'Новый флаг: латинские буквы, цифры, _, до 32 символов');
    }
    return ZaiCausalChoiceNotebook._(board, [...flags, id],
        [...initiallyActive, if (active) id], choices);
  }

  ZaiCausalChoiceNotebook setInitiallyActive(String id, bool value) {
    if (!flags.contains(id)) {
      throw const FormatException('Неизвестное состояние');
    }
    return ZaiCausalChoiceNotebook._(board, flags, [
      for (final flag in flags)
        if ((flag == id && value) ||
            (flag != id && initiallyActive.contains(flag))) flag,
    ], choices);
  }

  ZaiCausalChoiceNotebook removeFlag(String id) {
    if (!flags.contains(id) ||
        choices.any((e) => [
          ...e.requires, ...e.forbids, ...e.adds, ...e.removes,
        ].contains(id))) {
      throw const FormatException('Нельзя удалить используемое состояние');
    }
    return ZaiCausalChoiceNotebook._(board,
        flags.where((x) => x != id).toList(),
        initiallyActive.where((x) => x != id).toList(), choices);
  }

  ZaiCausalChoiceNotebook addChoice({
    required String from,
    required String to,
    required String label,
    required String reason,
    List<String> requires = const [],
    List<String> forbids = const [],
    List<String> adds = const [],
    List<String> removes = const [],
    String? npcFindingId,
    String? knowledgeFindingId,
  }) {
    final title = label.trim();
    final choice = ZaiCausalChoice(
      id: _sha('$boardSignature|$from|$to|$title').substring(0, 32),
      fromSceneId: from, toSceneId: to, label: title,
      reason: reason.trim(), requires: requires,
      forbids: forbids, adds: adds, removes: removes,
      npcFindingId: npcFindingId, knowledgeFindingId: knowledgeFindingId,
    );
    _validateChoice(choice);
    if (choices.length >= maxChoices ||
        choices.any((item) => item.id == choice.id)) {
      throw const FormatException('Повторное решение или лимит переходов');
    }
    final result = ZaiCausalChoiceNotebook._(
        board, flags, initiallyActive, [...choices, choice]);
    result._validate();
    return result;
  }

  ZaiCausalChoiceNotebook removeChoice(String id) {
    if (!choices.any((item) => item.id == id)) {
      throw const FormatException('Решение не найдено');
    }
    return ZaiCausalChoiceNotebook._(board, flags, initiallyActive,
        choices.where((item) => item.id != id).toList());
  }

  /// Bridge ONLY the typed M2c graph grammar. Its scenes are explicitly
  /// authored ADAPTATIONS with ZERO canon assertion IDs. A successful
  /// causal simulation cannot prove events, NPC identity or publication rights.
  IntermediateStoryBlueprint toM2cStructuralPreview() {
    _validate();
    if (board.scenes.isEmpty) {
      throw const FormatException('Нет ни одной исходной сцены');
    }
    return IntermediateStoryBlueprint(
      sourceFingerprint: board.graph.index.sourceFingerprint,
      title: board.graph.index.title,
      entrySceneId: m2cSceneId(board.scenes.first.id),
      rights: PreparationRights.unknown,
      flags: flags,
      initialFlags: initiallyActive,
      scenes: [
        for (final scene in board.scenes)
          DraftScene(
            id: m2cSceneId(scene.id),
            chapterIndex: scene.chapterIndex,
            text: 'Редакторский план: ${scene.title}',
            origin: DraftSceneOrigin.explicitAdaptation,
            assertionIds: const [],
            terminal: !choices.any((e) => e.fromSceneId == scene.id),
            choices: [
              for (final choice in choices)
                if (choice.fromSceneId == scene.id)
                  DraftChoice(
                    id: m2cChoiceId(choice.id),
                    label: choice.label,
                    nextSceneId: m2cSceneId(choice.toSceneId),
                    requires: choice.requires,
                    forbids: choice.forbids,
                    adds: choice.adds,
                    removes: choice.removes,
                  ),
            ],
          ),
      ],
    );
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': board.graph.index.sourceFingerprint,
    'source_scene_sha256': boardSignature,
    'status': 'PRIVATE_CAUSAL_DRAFT_NOT_RPG',
    'can_publish_bookworld': false,
    'flags': flags,
    'initially_active': initiallyActive,
    'choices': [for (final choice in choices) choice.toJson()],
  };

  String encode() {
    _validate();
    final payload = _payload();
    final encoded = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(encoded).length > maxUtf8Bytes) {
      throw const FormatException('Превышен размер черновика переходов');
    }
    return encoded;
  }

  static ZaiCausalChoiceNotebook decode(
      ZaiSourceSceneBoard board, String raw) {
    if (utf8.encode(raw).length > maxUtf8Bytes) {
      throw const FormatException('Превышен размер черновика переходов');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const rootKeys = {'format', 'payload', 'sha256'};
      if (root.length != rootKeys.length ||
          root.keys.toSet().difference(rootKeys).isNotEmpty ||
          root['format'] != format) {
        throw const FormatException('Чужой формат редакторских решений');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const keys = {'source_fingerprint', 'source_scene_sha256',
        'status', 'can_publish_bookworld', 'flags', 'initially_active',
        'choices'};
      if (payload.length != keys.length ||
          payload.keys.toSet().difference(keys).isNotEmpty ||
          payload['source_fingerprint'] !=
              board.graph.index.sourceFingerprint ||
          payload['source_scene_sha256'] != _sha(board.encode()) ||
          payload['status'] != 'PRIVATE_CAUSAL_DRAFT_NOT_RPG' ||
          payload['can_publish_bookworld'] != false ||
          root['sha256'] != _sha(jsonEncode(payload))) {
        throw const FormatException('Черновик не соответствует текущим сценам');
      }
      final rawFlags = payload['flags'] as List<dynamic>;
      final rawInitial = payload['initially_active'] as List<dynamic>;
      final rawChoices = payload['choices'] as List<dynamic>;
      if (rawFlags.length > maxFlags ||
          rawInitial.length > maxFlags || rawChoices.length > maxChoices) {
        throw const FormatException('Превышен предел причинных правил');
      }
      final choices = <ZaiCausalChoice>[];
      for (final rawChoice in rawChoices) {
        final value = Map<String, dynamic>.from(rawChoice as Map);
        const expected = {'id', 'from_scene_id', 'to_scene_id', 'label',
          'reason', 'requires', 'forbids', 'adds', 'removes',
          'npc_finding_id', 'knowledge_finding_id', 'status'};
        if (value.length != expected.length ||
            value.keys.toSet().difference(expected).isNotEmpty ||
            value['status'] != 'PRIVATE_AUTHORED_HYPOTHESIS') {
          throw const FormatException('Подменён тип или статус решения');
        }
        choices.add(ZaiCausalChoice(
          id: value['id'] as String,
          fromSceneId: value['from_scene_id'] as String,
          toSceneId: value['to_scene_id'] as String,
          label: value['label'] as String,
          reason: value['reason'] as String,
          requires: (value['requires'] as List).cast<String>(),
          forbids: (value['forbids'] as List).cast<String>(),
          adds: (value['adds'] as List).cast<String>(),
          removes: (value['removes'] as List).cast<String>(),
          npcFindingId: value['npc_finding_id'] as String?,
          knowledgeFindingId: value['knowledge_finding_id'] as String?,
        ));
      }
      final result = ZaiCausalChoiceNotebook._(
        board, rawFlags.cast<String>(), rawInitial.cast<String>(), choices);
      if (result.encode() != raw) {
        throw const FormatException('Неканонический или повреждённый файл');
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Не удалось восстановить причинный черновик');
    }
  }
}

/// Read-only causal dry run reuses the existing M2c simulation. No engine
/// changes, no fictitious confirmed citations, no private BookWorld install.
enum ZaiCausalBlocker {
  emptySourceScenes,
  noAuthoredChoices,
  missingConsequences,
  unresolvedEditorQuestions,
  unfinishedSourceReview,
  sourceDiscrepancies,
  futureChapterDisclosure,
  npcKnowledgeUnverified,
  causalSimulationFailed,
  missingSemanticAcceptance,
  notPublishedOrPlayable,
}

class ZaiCausalPreflight {
  const ZaiCausalPreflight._(
      this.blockers, this.reachableScenes, this.reachableEndings,
      this.reachableStates);

  final Map<ZaiCausalBlocker, String> blockers;
  final int reachableScenes;
  final int reachableEndings;
  final int reachableStates;

  bool get isStructurallyCausal => reachableScenes > 0 &&
      reachableEndings >= 2 && reachableStates > 0 &&
      !blockers.containsKey(ZaiCausalBlocker.causalSimulationFailed);
  bool get canCompileBookworld => false;
  bool get canPublishBookworld => false;
  bool get canStartPlayableRpg => false;

  factory ZaiCausalPreflight.assess(
      ZaiWindowReviewQueue queue, ZaiCausalChoiceNotebook notebook, {
      ZaiEditorialConsistencyNotebook? consistency,
    }) {
    final board = notebook.board;
    final source = ZaiScenePreflight.assess(
        queue, board, consistency: consistency);
    notebook._validate();
    final messages = <ZaiCausalBlocker, String>{};
    void block(ZaiCausalBlocker id, String note) {
      messages[id] = note;
    }

    if (board.scenes.isEmpty) {
      block(ZaiCausalBlocker.emptySourceScenes,
          'Нет сцен с привязанными к книге событиями.');
    }
    if (notebook.choices.isEmpty) {
      block(ZaiCausalBlocker.noAuthoredChoices,
          'Не добавлены альтернативные решения редактора.');
    }
    if (!notebook.choices.any((c) =>
        c.adds.isNotEmpty || c.removes.isNotEmpty)) {
      block(ZaiCausalBlocker.missingConsequences,
          'Нет ни одного выбора, изменяющего проверяемое игровое состояние.');
    }
    if (consistency != null && consistency.questions.isNotEmpty) {
      block(ZaiCausalBlocker.unresolvedEditorQuestions,
          'Есть открытые редакторские вопросы: ${consistency.questions.length}. '
          'Предположения не разрешаются автоматически.');
    }
    if (source.findings.any((f) => [
      ZaiSceneGateIssue.unfinishedWindows,
      ZaiSceneGateIssue.unreviewedCandidates,
      ZaiSceneGateIssue.uncoveredEvents,
      ZaiSceneGateIssue.unclassifiedStatements,
    ].contains(f.issue))) {
      block(ZaiCausalBlocker.unfinishedSourceReview,
          'Не завершены исходные окна, отметки, охват событий '
          'или разбор утверждений.');
    }
    if (source.findings.any((f) =>
        f.issue == ZaiSceneGateIssue.openPossibleDiscrepancies)) {
      block(ZaiCausalBlocker.sourceDiscrepancies,
          'Встречены возможные расхождения текста, требуется проверка.');
    }
    final byScene = {for (final scene in board.scenes) scene.id: scene};
    if (notebook.choices.any((choice) =>
        byScene[choice.toSceneId]!.chapterIndex >
            byScene[choice.fromSceneId]!.chapterIndex)) {
      block(ZaiCausalBlocker.futureChapterDisclosure,
          'Есть переходы в более поздние главы. '
          'Показывать их без проверки спойлеров нельзя.');
    }
    if (notebook.choices.any((choice) =>
        choice.npcFindingId != null)) {
      block(ZaiCausalBlocker.npcKnowledgeUnverified,
          'Предполагаемые знания NPC ещё не подтверждены независимыми '
          'правилами знаний и раскрытия.');
    }
    var reachedScenes = 0;
    var reachedEndings = 0;
    var reachedStates = 0;
    try {
      final preview = notebook.toM2cStructuralPreview();
      final emptyEvidence = SourceEvidenceGraph.empty(queue.index);
      final emptyCatalog = SourceSemanticCatalog.checked(
          queue.index, emptyEvidence, const []);
      final simulation = preview.validate(
          queue.index, emptyEvidence, emptyCatalog);
      reachedScenes = simulation.reachableScenes;
      reachedEndings = simulation.reachableEndings;
      reachedStates = simulation.reachableStates;
    } on FormatException catch (e) {
      block(ZaiCausalBlocker.causalSimulationFailed,
          'M2c: ${e.message}.');
    }
    block(ZaiCausalBlocker.missingSemanticAcceptance,
        'Цитаты keepForReview и персонажи не являются '
        'подтверждённым игровым каноном, правила знаний NPC не приняты.');
    block(ZaiCausalBlocker.notPublishedOrPlayable,
        'Это предварительная схема M2c, НЕ собранная RPG: '
        'нет публикации, импорта BookWorld и готовых сохранений.');
    return ZaiCausalPreflight._(
        Map.unmodifiable(messages), reachedScenes,
        reachedEndings, reachedStates);
  }
}
