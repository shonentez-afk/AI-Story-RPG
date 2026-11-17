import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'multi_scene_draft_workbench.dart';

/// Source-safe graph structure of an unfinished multi-scene draft.
/// Static links are NOT equivalent to the existing state/flag causal preflight.
enum DraftGraphFindingKind {
  danglingChoice,
  unreachableByLinks,
  emptyText,
  terminalMismatch,
  selfLoop,
  backwardsChapter,
}

class DraftGraphFinding {
  const DraftGraphFinding({
    required this.kind,
    required this.sceneId,
    this.targetId,
  });

  final DraftGraphFindingKind kind;
  final String sceneId;
  final String? targetId;

  String get explanation => switch (kind) {
    DraftGraphFindingKind.danglingChoice =>
      'Выбор из $sceneId ведёт в отсутствующую сцену $targetId.',
    DraftGraphFindingKind.unreachableByLinks =>
      'Сцена $sceneId недостижима даже без учёта игровых условий.',
    DraftGraphFindingKind.emptyText =>
      'У сцены $sceneId ещё нет текста.',
    DraftGraphFindingKind.terminalMismatch =>
      'У сцены $sceneId противоречие между финалом и выходами.',
    DraftGraphFindingKind.selfLoop =>
      'Сцена $sceneId возвращается сама в себя: проверьте наличие выхода.',
    DraftGraphFindingKind.backwardsChapter =>
      'Переход $sceneId → $targetId возвращается к ранней главе. '
          'Это может быть авторский флешбэк.',
  };
}

class DraftGraphEdge {
  const DraftGraphEdge(this.fromId, this.choice);
  final String fromId;
  final DraftChoice choice;
  String get toId => choice.nextSceneId;
  bool get hasConditions =>
      choice.requires.isNotEmpty || choice.forbids.isNotEmpty;
  bool get changesState =>
      choice.adds.isNotEmpty || choice.removes.isNotEmpty;
}

class DraftGraphNode {
  const DraftGraphNode({
    required this.scene,
    required this.outgoing,
    required this.incomingCount,
    required this.reachableByLinks,
  });

  final DraftScene scene;
  final List<DraftGraphEdge> outgoing;
  final int incomingCount;
  final bool reachableByLinks;
}

class DraftSceneGraphOverview {
  const DraftSceneGraphOverview._(
      this.sourceFingerprint, this.nodes, this.findings);

  final String sourceFingerprint;
  final List<DraftGraphNode> nodes;
  final List<DraftGraphFinding> findings;

  int get totalChoices => nodes.fold<int>(
      0, (sum, node) => sum + node.outgoing.length);
  int get staticallyReachable =>
      nodes.where((node) => node.reachableByLinks).length;
  bool get isCausallyVerified => false;
  bool get canCompileBookworld => false;

  static DraftSceneGraphOverview inspect(
      BookSourceIndex index, IntermediateStoryBlueprint draft) {
    MultiSceneDraftWorkbench.checkSafeCheckpoint(index, draft);
    final byId = {for (final scene in draft.scenes) scene.id: scene};
    final incoming = <String, int>{
      for (final scene in draft.scenes) scene.id: 0,
    };
    final outgoing = <String, List<DraftGraphEdge>>{
      for (final scene in draft.scenes) scene.id: [],
    };
    final findings = <DraftGraphFinding>[];

    for (final scene in draft.scenes) {
      if (scene.text.trim().isEmpty) {
        findings.add(DraftGraphFinding(
          kind: DraftGraphFindingKind.emptyText, sceneId: scene.id));
      }
      if (scene.terminal == scene.choices.isNotEmpty) {
        findings.add(DraftGraphFinding(
          kind: DraftGraphFindingKind.terminalMismatch,
          sceneId: scene.id));
      }
      for (final choice in scene.choices) {
        outgoing[scene.id]!.add(DraftGraphEdge(scene.id, choice));
        final target = byId[choice.nextSceneId];
        if (target == null) {
          findings.add(DraftGraphFinding(
              kind: DraftGraphFindingKind.danglingChoice,
              sceneId: scene.id, targetId: choice.nextSceneId));
          continue;
        }
        incoming[target.id] = incoming[target.id]! + 1;
        if (target.id == scene.id) {
          findings.add(DraftGraphFinding(
              kind: DraftGraphFindingKind.selfLoop, sceneId: scene.id));
        }
        if (target.chapterIndex < scene.chapterIndex) {
          findings.add(DraftGraphFinding(
              kind: DraftGraphFindingKind.backwardsChapter,
              sceneId: scene.id, targetId: target.id));
        }
      }
    }

    // Static reachability is a cheap early hint; actual conditional
    // reachability and infinite cycles still require draft.validate().
    final visited = <String>{draft.entrySceneId};
    final queue = <String>[draft.entrySceneId];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      final id = queue[cursor];
      for (final edge in outgoing[id] ?? const <DraftGraphEdge>[]) {
        if (byId.containsKey(edge.toId) && visited.add(edge.toId)) {
          queue.add(edge.toId);
        }
      }
    }
    for (final scene in draft.scenes) {
      if (!visited.contains(scene.id)) {
        findings.add(DraftGraphFinding(
            kind: DraftGraphFindingKind.unreachableByLinks,
            sceneId: scene.id));
      }
    }
    return DraftSceneGraphOverview._(
      draft.sourceFingerprint,
      List.unmodifiable([
        for (final scene in draft.scenes)
          DraftGraphNode(
            scene: scene,
            outgoing: List.unmodifiable(outgoing[scene.id]!),
            incomingCount: incoming[scene.id]!,
            reachableByLinks: visited.contains(scene.id),
          ),
      ]),
      List.unmodifiable(findings),
    );
  }
}
