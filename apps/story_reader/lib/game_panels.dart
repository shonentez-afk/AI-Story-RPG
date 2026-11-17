import 'package:flutter/material.dart';
import 'game_progress.dart';

/// M1.4 shell. These panels do not invent character attributes or loot:
/// they describe only capabilities actually present in the pilot runtime.
enum GamePanel { character, inventory, journal, npc }

class GameInfoSheet extends StatelessWidget {
  const GameInfoSheet({
    super.key,
    required this.panel,
    required this.currentScene,
    this.journalEntries = const [],
    this.progress = const GameProgress(),
  });

  final GamePanel panel;
  final String currentScene;
  final List<String> journalEntries;
  final GameProgress progress;

  @override
  Widget build(BuildContext context) {
    final heading = switch (panel) {
      GamePanel.character => 'Персонаж',
      GamePanel.inventory => 'Инвентарь',
      GamePanel.journal => 'Журнал',
      GamePanel.npc => 'Персонажи',
    };
    final icon = switch (panel) {
      GamePanel.character => Icons.person_outline,
      GamePanel.inventory => Icons.backpack_outlined,
      GamePanel.journal => Icons.auto_stories_outlined,
      GamePanel.npc => Icons.people_outline,
    };
    final message = switch (panel) {
      GamePanel.character =>
        'Смелость: ${progress.courage}   •   Наблюдательность: ${progress.insight}',
      GamePanel.inventory => progress.items.isEmpty
        ? 'Пока нет найденных предметов. Исследуйте комнаты особняка.'
        : 'Найденные предметы:',
      GamePanel.journal => journalEntries.isEmpty
        ? 'Текущая сцена: $currentScene. Решений в этом сеансе пока нет.'
        : 'Текущая сцена: $currentScene.',
      GamePanel.npc => 'Для этой пробной истории карточки NPC не заданы.',
    };
    final rows = panel == GamePanel.inventory
        ? progress.items.map((item) =>
            '• ${GameProgress.itemNames[item] ?? item}').toList()
        : panel == GamePanel.journal
            ? journalEntries.map((entry) => '• $entry').toList()
            : <String>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(child: Text(heading,
                  style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 8),
              Text(message),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                Flexible(child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(rows[index]),
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GameQuickBar extends StatelessWidget {
  const GameQuickBar({
    super.key, required this.onOpen, this.color, this.showNpc = false,
  });
  final ValueChanged<GamePanel> onOpen;
  final Color? color;
  /// Only source-verified WorldPlay exposes replayed NPC relations.
  /// The original pilot retains its familiar three-button bar.
  final bool showNpc;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: LayoutBuilder(builder: (context, constraints) {
            final actions = <({IconData icon, String name, GamePanel panel})>[
              (icon: Icons.person_outline, name: 'Герой', panel: GamePanel.character),
              (icon: Icons.backpack_outlined, name: 'Предметы', panel: GamePanel.inventory),
              (icon: Icons.menu_book_outlined, name: 'Журнал', panel: GamePanel.journal),
              if (showNpc)
                (icon: Icons.people_outline, name: 'NPC', panel: GamePanel.npc),
            ];
            // Four 72dp minimum buttons must not overflow on narrow devices.
            if (constraints.maxWidth < (showNpc ? 336 : 260) ||
                MediaQuery.textScalerOf(context).scale(12) > 18) {
              final width = (constraints.maxWidth - 4) / 2;
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 4, runSpacing: 2,
                children: [
                  for (final action in actions)
                    SizedBox(width: width, child: _item(context,
                        action.icon, action.name, action.panel)),
                ],
              );
            }
            return Row(children: [
              for (final action in actions)
                Expanded(child: _item(context,
                    action.icon, action.name, action.panel)),
            ]);
          }),
        ),
      );

  Widget _item(BuildContext context, IconData icon, String name, GamePanel panel) =>
      Semantics(
        button: true,
        label: name,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(panel),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21, color: color),
                  const SizedBox(height: 2),
                  Text(name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
