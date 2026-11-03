import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'draft_scene_graph_overview.dart';
import 'intermediate_story_blueprint.dart';

/// A responsive, spoiler-gated outline. The parent editor only inserts this
/// widget after the reader explicitly opens the book's scenes.
class DraftSceneGraphPanel extends StatefulWidget {
  const DraftSceneGraphPanel({
    super.key,
    required this.index,
    required this.draft,
    required this.onSelectScene,
    this.enabled = true,
  });

  final BookSourceIndex index;
  final IntermediateStoryBlueprint draft;
  final ValueChanged<String> onSelectScene;
  final bool enabled;

  @override
  State<DraftSceneGraphPanel> createState() => _DraftSceneGraphPanelState();
}

class _DraftSceneGraphPanelState extends State<DraftSceneGraphPanel> {
  static const pageSize = 8;
  int _page = 0;

  @override
  void didUpdateWidget(covariant DraftSceneGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.sourceFingerprint != widget.draft.sourceFingerprint ||
        oldWidget.draft.entrySceneId != widget.draft.entrySceneId) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = DraftSceneGraphOverview.inspect(
        widget.index, widget.draft);
    final pages = report.nodes.isEmpty
        ? 1 : (report.nodes.length + pageSize - 1) ~/ pageSize;
    final page = _page.clamp(0, pages - 1).toInt();
    final nodes = report.nodes.skip(page * pageSize).take(pageSize);

    return ExpansionTile(
      key: const Key('multi-graph-outline'),
      title: const Text('Карта переходов и диагностика сцен'),
      subtitle: Text('${report.nodes.length} сцен · '
          '${report.totalChoices} переходов · '
          '${report.findings.length} замечаний'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Показаны статические связи черновика. '
                  'Отсутствие замечаний НЕ доказывает достижимость '
                  'с учётом флагов и не разрешает сборку. '
                  'Для этого используйте «Проверить сюжет и причинность».'),
              const SizedBox(height: 8),
              Text('Статически достижимо: '
                  '${report.staticallyReachable} из ${report.nodes.length}'),
              if (report.findings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Что требует внимания',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final finding in report.findings.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${finding.explanation}'),
                  ),
                if (report.findings.length > 6)
                  Text('Ещё замечаний: ${report.findings.length - 6}. '
                      'Просмотрите соответствующие сцены ниже.'),
              ],
              const Divider(height: 16),
              for (final node in nodes)
                Card(
                  key: Key('graph-scene-${node.scene.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${node.scene.id} · глава ${node.scene.chapterIndex + 1}'
                          '${node.scene.id == widget.draft.entrySceneId ? " · вход" : ""}',
                          style: Theme.of(context).textTheme.titleSmall,
                          softWrap: true,
                        ),
                        const SizedBox(height: 4),
                        Text(node.scene.terminal
                            ? 'Финал · входящих связей: ${node.incomingCount}'
                            : 'Входящих: ${node.incomingCount} · '
                                'исходящих: ${node.outgoing.length}'),
                        if (!node.reachableByLinks)
                          const Text('Нет пути от начальной сцены '
                              'даже без условий.'),
                        if (node.outgoing.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          for (final link in node.outgoing)
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('${link.choice.label} → ${link.toId}'
                                    '${link.hasConditions ? " · условия" : ""}'
                                    '${link.changesState ? " · последствия" : ""}',
                                    softWrap: true),
                                TextButton(
                                  key: Key('graph-jump-${link.choice.id}'),
                                  onPressed: widget.enabled &&
                                      report.nodes.any((n) =>
                                          n.scene.id == link.toId)
                                      ? () => widget.onSelectScene(link.toId)
                                      : null,
                                  child: const Text('К сцене'),
                                ),
                              ],
                            ),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: Key('graph-edit-${node.scene.id}'),
                            onPressed: widget.enabled
                                ? () => widget.onSelectScene(node.scene.id)
                                : null,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Редактировать сцену'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (pages > 1)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const Key('graph-prev'),
                      onPressed: page == 0
                          ? null : () => setState(() => _page--),
                      child: const Text('Назад'),
                    ),
                    Text('Страница ${page + 1} из $pages'),
                    OutlinedButton(
                      key: const Key('graph-next'),
                      onPressed: page + 1 >= pages
                          ? null : () => setState(() => _page++),
                      child: const Text('Дальше'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
