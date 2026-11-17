import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

void main() {
  final index = BookSourceIndexer.index(const ImportedBook(
    title: 'Карта развилок', author: 'Автор',
    chapters: ['Первая глава.', 'Вторая глава.', 'Третья.', 'Четвертая.'],
  ));

  IntermediateStoryBlueprint draft({
    int count = 5, bool dangling = false, bool empty = false,
    bool selfLoop = false,
  }) {
    final scenes = <DraftScene>[];
    for (var i = 0; i < count; i++) {
      final terminal = i == count - 1;
      scenes.add(DraftScene(
        id: 'node_$i',
        chapterIndex: i % index.chapterCount,
        text: empty && i == 1 ? '' : 'Сцена $i',
        origin: DraftSceneOrigin.explicitAdaptation,
        assertionIds: const [],
        terminal: terminal,
        choices: terminal ? const [] : [
          DraftChoice(
            id: 'choice_$i', label: 'Перейти дальше',
            nextSceneId: dangling && i == 0
                ? 'missing' : selfLoop && i == 1
                    ? 'node_1' : 'node_${i + 1}',
          ),
        ],
      ));
    }
    return IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: index.title,
      entrySceneId: 'node_0', rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [], scenes: scenes,
    );
  }

  test('static links never claim causal readiness', () {
    final g = DraftSceneGraphOverview.inspect(index, draft());
    expect(g.nodes.length, 5);
    expect(g.totalChoices, 4);
    expect(g.staticallyReachable, 5);
    expect(g.nodes.first.incomingCount, 0);
    expect(g.nodes[1].incomingCount, 1);
    expect(g.nodes.last.scene.terminal, true);
    expect(g.canCompileBookworld, false);
    expect(g.isCausallyVerified, false);
    expect(g.findings.map((f) => f.kind),
        contains(DraftGraphFindingKind.backwardsChapter));
  });

  test('unfinished scenes report orphan, broken link and missing text', () {
    final g = DraftSceneGraphOverview.inspect(
        index, draft(dangling: true, empty: true));
    expect(g.findings.map((f) => f.kind),
        contains(DraftGraphFindingKind.danglingChoice));
    expect(g.findings.map((f) => f.kind),
        contains(DraftGraphFindingKind.emptyText));
    expect(g.findings.map((f) => f.kind),
        contains(DraftGraphFindingKind.unreachableByLinks));
    expect(g.staticallyReachable, 1);
  });

  test('self-loop cannot be mistaken for validated causal graph', () {
    final g = DraftSceneGraphOverview.inspect(index, draft(selfLoop: true));
    expect(g.findings.map((f) => f.kind),
        contains(DraftGraphFindingKind.selfLoop));
    expect(g.nodes[1].outgoing.single.toId, 'node_1');
    expect(g.canCompileBookworld, false);
  });

  test('wrong book fails before rendering', () {
    final other = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая редакция', author: 'Автор',
      chapters: ['Иное событие.'],
    ));
    expect(() => DraftSceneGraphOverview.inspect(other, draft()),
        throwsFormatException);
  });

}
