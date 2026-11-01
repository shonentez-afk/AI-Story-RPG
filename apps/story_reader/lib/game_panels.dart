import 'package:flutter/material.dart';

/// M1.4 shell. These panels do not invent character attributes or loot:
/// they describe only capabilities actually present in the pilot runtime.
enum GamePanel { character, inventory, journal }

class GameInfoSheet extends StatelessWidget {
  const GameInfoSheet({
    super.key,
    required this.panel,
    required this.currentScene,
    this.journalEntries = const [],
  });

  final GamePanel panel;
  final String currentScene;
  final List<String> journalEntries;

  @override
  Widget build(BuildContext context) {
    final heading = switch (panel) {
      GamePanel.character => 'Персонаж',
      GamePanel.inventory => 'Инвентарь',
      GamePanel.journal => 'Журнал',
    };
    final icon = switch (panel) {
      GamePanel.character => Icons.person_outline,
      GamePanel.inventory => Icons.backpack_outlined,
      GamePanel.journal => Icons.auto_stories_outlined,
    };
    final message = switch (panel) {
      GamePanel.character =>
        'В демонстрационной истории характеристики героя пока не заданы. '
        'Параметры персонажа появятся при подключении игрового мира.',
      GamePanel.inventory =>
        'Предметы пока не доступны: демонстрационный сюжет не содержит '
        'инвентаря. Здесь будут найденные вещи, документы и иллюстрации.',
      GamePanel.journal => journalEntries.isEmpty
        ? 'Текущая сцена: $currentScene. Решений в этом сеансе пока нет.'
        : 'Текущая сцена: $currentScene.',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(heading, style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message),
            if (panel == GamePanel.journal && journalEntries.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final entry in journalEntries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('• $entry'),
                ),
              Text('Записи показывают текущий сеанс. Сохранение истории решений будет подключено отдельно.',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class GameQuickBar extends StatelessWidget {
  const GameQuickBar({super.key, required this.onOpen, this.color});
  final ValueChanged<GamePanel> onOpen;
  final Color? color;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _item(context, Icons.person_outline, 'Герой', GamePanel.character),
              _item(context, Icons.backpack_outlined, 'Предметы', GamePanel.inventory),
              _item(context, Icons.menu_book_outlined, 'Журнал', GamePanel.journal),
            ],
          ),
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
                  Text(name, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
                ],
              ),
            ),
          ),
        ),
      );
}
