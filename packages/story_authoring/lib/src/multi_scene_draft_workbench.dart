import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'private_adaptation_preflight.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// Immutable changes to the existing, causal M2c draft format.
/// Work-in-progress can be saved but never compiled without full preflight.
class MultiSceneDraftWorkbench {
  const MultiSceneDraftWorkbench._();
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  static IntermediateStoryBlueprint copy(
    IntermediateStoryBlueprint draft, {
    List<DraftScene>? scenes,
    List<String>? flags,
    List<String>? initialFlags,
  }) => IntermediateStoryBlueprint(
    sourceFingerprint: draft.sourceFingerprint,
    title: draft.title,
    entrySceneId: draft.entrySceneId,
    rights: draft.rights,
    scenes: scenes ?? draft.scenes,
    flags: flags ?? draft.flags,
    initialFlags: initialFlags ?? draft.initialFlags,
  );

  static DraftScene sceneCopy(DraftScene scene, {
    int? chapterIndex, String? text, bool? terminal,
    List<DraftChoice>? choices,
  }) => DraftScene(
    id: scene.id, chapterIndex: chapterIndex ?? scene.chapterIndex,
    text: text ?? scene.text, origin: scene.origin,
    assertionIds: scene.assertionIds,
    terminal: terminal ?? scene.terminal,
    choices: choices ?? scene.choices,
  );

  static DraftChoice choiceCopy(DraftChoice choice, {
    String? label, String? nextSceneId,
    List<String>? requires, List<String>? forbids,
    List<String>? adds, List<String>? removes,
  }) => DraftChoice(
    id: choice.id, label: label ?? choice.label,
    nextSceneId: nextSceneId ?? choice.nextSceneId,
    requires: requires ?? choice.requires,
    forbids: forbids ?? choice.forbids,
    adds: adds ?? choice.adds, removes: removes ?? choice.removes,
  );

  static String _nextId(Set<String> used, String prefix) {
    for (var n = 1; n <= 100000; n++) {
      final candidate = prefix + '_' + n.toString();
      if (!used.contains(candidate)) return candidate;
    }
    throw const FormatException('Исчерпаны идентификаторы сценария');
  }

  /// The original short draft is COPIED, never moved or overwritten.
  static IntermediateStoryBlueprint fromReviewedShortDraft(
    BookSourceIndex index, SourceEvidenceGraph evidence,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
    IntermediateStoryBlueprint shortDraft,
  ) {
    if (shortDraft.sourceFingerprint != index.sourceFingerprint ||
        shortDraft.rights != PreparationRights.privateUse ||
        shortDraft.scenes.length != 3 ||
        !PrivateAdaptationPreflight.evaluate(
            index, evidence, catalog, editorial, shortDraft)
            .isStructurallyReady) {
      throw const FormatException(
          'Короткая адаптация устарела или не прошла проверку источника');
    }
    return IntermediateStoryBlueprint.decode(shortDraft.encode());
  }

  /// Never promote unreviewed regex results into source-backed scenes.
  static IntermediateStoryBlueprint addSourceScene(
    IntermediateStoryBlueprint draft,
    BookSourceIndex index, SourceEvidenceGraph evidence,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial, String assertionId,
  ) {
    if (draft.sourceFingerprint != index.sourceFingerprint ||
        !editorial.matches(index, catalog) ||
        evidence.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Изменился исходный текст или проверка');
    }
    final claims = catalog.assertions
        .where((a) => a.id == assertionId).toList();
    if (claims.length != 1 ||
        (claims.single.kind != SemanticAssertionKind.event &&
         claims.single.kind != SemanticAssertionKind.fact) ||
        editorial.verdicts[assertionId] !=
            SemanticEditorialVerdict.canonCandidate) {
      throw const FormatException('Нужно подтверждённое событие или факт');
    }
    final sources = {for (final e in evidence.records) e.id: e};
    var chapter = 0;
    final snippets = <String>[];
    for (final id in claims.single.evidenceIds) {
      final ref = sources[id];
      if (ref == null || ref.status != EvidenceStatus.confirmed ||
          ref.spoilerGate != EvidenceSpoilerGate.chapter ||
          ref.visibleAfterChapter != ref.chapterIndex) {
        throw const FormatException('Непроверенная цитата или спойлер');
      }
      ref.validate(index);
      if (ref.chapterIndex > chapter) chapter = ref.chapterIndex;
      snippets.add(ref.label);
    }
    if (snippets.isEmpty ||
        draft.scenes.length >= IntermediateStoryBlueprint.maxScenes) {
      throw const FormatException('Нет цитат или превышен лимит сцен');
    }
    final newId = _nextId({for (final s in draft.scenes) s.id}, 'scene');
    return copy(draft, scenes: [
      ...draft.scenes,
      DraftScene(
        id: newId, chapterIndex: chapter,
        text: snippets.join(' '),
        origin: DraftSceneOrigin.sourcePassage,
        assertionIds: [assertionId],
        terminal: true, choices: const [],
      ),
    ]);
  }

  static IntermediateStoryBlueprint addAuthoredScene(
    IntermediateStoryBlueprint draft, {required int chapterIndex}) {
    if (chapterIndex < 0 ||
        draft.scenes.length >= IntermediateStoryBlueprint.maxScenes) {
      throw const FormatException('Недопустимая глава или лимит сцен');
    }
    final id = _nextId({for (final s in draft.scenes) s.id}, 'scene');
    return copy(draft, scenes: [
      ...draft.scenes,
      DraftScene(
        id: id, chapterIndex: chapterIndex, text: '',
        origin: DraftSceneOrigin.explicitAdaptation,
        assertionIds: const [], terminal: true, choices: const [],
      ),
    ]);
  }

  static IntermediateStoryBlueprint replaceScene(
      IntermediateStoryBlueprint draft, DraftScene replacement) {
    final position = draft.scenes.indexWhere((s) => s.id == replacement.id);
    if (position < 0 ||
        replacement.origin != draft.scenes[position].origin ||
        replacement.assertionIds.join('|') !=
            draft.scenes[position].assertionIds.join('|')) {
      throw const FormatException('Запрещена подмена источника сцены');
    }
    final scenes = draft.scenes.toList()..[position] = replacement;
    return copy(draft, scenes: scenes);
  }

  static IntermediateStoryBlueprint removeScene(
      IntermediateStoryBlueprint draft, String id) {
    if (id == draft.entrySceneId ||
        !draft.scenes.any((s) => s.id == id)) {
      throw const FormatException('Нельзя удалить начальную или чужую сцену');
    }
    if (draft.scenes.any((s) => s.choices.any(
        (choice) => choice.nextSceneId == id))) {
      throw const FormatException('Сначала измените входящие переходы');
    }
    return copy(draft, scenes: [
      for (final s in draft.scenes) if (s.id != id) s,
    ]);
  }

  static IntermediateStoryBlueprint addChoice(
      IntermediateStoryBlueprint draft, String from, String to) {
    final sources = draft.scenes.where((s) => s.id == from).toList();
    if (sources.length != 1 ||
        !draft.scenes.any((s) => s.id == to) ||
        sources.single.choices.length >= 16) {
      throw const FormatException('Не найдена сцена или достигнут лимит');
    }
    final id = _nextId({
      for (final s in draft.scenes)
        for (final choice in s.choices) choice.id,
    }, 'choice');
    return replaceScene(draft, sceneCopy(sources.single,
      terminal: false,
      choices: [
        ...sources.single.choices,
        DraftChoice(id: id, label: '', nextSceneId: to),
      ],
    ));
  }

  static IntermediateStoryBlueprint replaceChoice(
      IntermediateStoryBlueprint draft, String sceneId,
      DraftChoice replacement) {
    final matches = draft.scenes.where((s) => s.id == sceneId).toList();
    if (matches.length != 1 ||
        !draft.scenes.any((s) => s.id == replacement.nextSceneId)) {
      throw const FormatException('Выбор ведёт в отсутствующую сцену');
    }
    final position = matches.single.choices.indexWhere(
        (c) => c.id == replacement.id);
    if (position < 0) throw const FormatException('Выбор не найден');
    final next = matches.single.choices.toList()..[position] = replacement;
    return replaceScene(draft, sceneCopy(
        matches.single, terminal: false, choices: next));
  }

  static IntermediateStoryBlueprint removeChoice(
      IntermediateStoryBlueprint draft, String sceneId, String choiceId) {
    final matches = draft.scenes.where((s) => s.id == sceneId).toList();
    if (matches.length != 1 ||
        !matches.single.choices.any((c) => c.id == choiceId)) {
      throw const FormatException('Выбор не найден');
    }
    final choices = matches.single.choices
        .where((c) => c.id != choiceId).toList();
    return replaceScene(draft, sceneCopy(
        matches.single, terminal: choices.isEmpty, choices: choices));
  }

  static IntermediateStoryBlueprint addFlag(
      IntermediateStoryBlueprint draft, String id) {
    if (!_id.hasMatch(id) ||
        draft.flags.contains(id) || draft.flags.length >= 32) {
      throw const FormatException('Флаг: латинские буквы, цифры, _; без повторов');
    }
    return copy(draft, flags: [...draft.flags, id]);
  }

  static IntermediateStoryBlueprint setInitiallyActive(
      IntermediateStoryBlueprint draft, String flag, bool active) {
    if (!draft.flags.contains(flag)) {
      throw const FormatException('Флаг не объявлен');
    }
    final next = {...draft.initialFlags};
    if (active) { next.add(flag); } else { next.remove(flag); }
    return copy(draft, initialFlags: [
      for (final f in draft.flags) if (next.contains(f)) f,
    ]);
  }

  static IntermediateStoryBlueprint removeFlag(
      IntermediateStoryBlueprint draft, String flag) {
    if (draft.scenes.any((scene) => scene.choices.any(
        (choice) => [
          ...choice.requires, ...choice.forbids,
          ...choice.adds, ...choice.removes,
        ].contains(flag)))) {
      throw const FormatException('Сначала уберите использующие флаг действия');
    }
    return copy(draft,
        flags: draft.flags.where((v) => v != flag).toList(),
        initialFlags: draft.initialFlags.where((v) => v != flag).toList());
  }

  /// Save is intentionally weaker than full causal game validation:
  /// intermediate, incomplete edits may persist. Compiler remains fail-closed.
  static void checkSafeCheckpoint(
      BookSourceIndex index, IntermediateStoryBlueprint draft) {
    if (draft.sourceFingerprint != index.sourceFingerprint ||
        draft.rights != PreparationRights.privateUse ||
        draft.title != index.title ||
        draft.scenes.isEmpty ||
        draft.scenes.length > IntermediateStoryBlueprint.maxScenes ||
        !_id.hasMatch(draft.entrySceneId) ||
        !draft.scenes.any((s) => s.id == draft.entrySceneId) ||
        draft.flags.length > 32 ||
        draft.flags.toSet().length != draft.flags.length ||
        draft.flags.any((v) => !_id.hasMatch(v)) ||
        draft.initialFlags.any((v) => !draft.flags.contains(v))) {
      throw const FormatException('Чужой или небезопасный черновик');
    }
    final ids = <String>{};
    final choices = <String>{};
    for (final scene in draft.scenes) {
      if (!_id.hasMatch(scene.id) || !ids.add(scene.id) ||
          scene.chapterIndex < 0 ||
          scene.chapterIndex >= index.chapterCount ||
          scene.text.length > 6000 ||
          scene.text.contains('\u0000') ||
          scene.choices.length > 16 ||
          scene.assertionIds.length > 24 ||
          scene.assertionIds.toSet().length != scene.assertionIds.length ||
          (scene.origin == DraftSceneOrigin.sourcePassage &&
              scene.assertionIds.isEmpty)) {
        throw const FormatException('Повреждена сцена черновика');
      }
      for (final choice in scene.choices) {
        if (!_id.hasMatch(choice.id) || !choices.add(choice.id) ||
            !_id.hasMatch(choice.nextSceneId) ||
            choice.label.length > 300 ||
            choice.label.contains('\u0000')) {
          throw const FormatException('Повреждён выбор черновика');
        }
        if ([
          ...choice.requires, ...choice.forbids,
          ...choice.adds, ...choice.removes,
        ].any((f) => !draft.flags.contains(f))) {
          throw const FormatException('Выбор ссылается на чужой флаг');
        }
      }
    }
    if (IntermediateStoryBlueprint.decode(draft.encode())
            .sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Ошибка контрольной точки сценария');
    }
  }
}
