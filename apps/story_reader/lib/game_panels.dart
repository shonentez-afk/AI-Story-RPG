import 'package:flutter/material.dart';

/// M1.4 shell. These panels do not invent character attributes or loot:
/// they describe only capabilities actually present in the pilot runtime.
enum GamePanel { character, inventory, journal }

class GameInfoSheet extends StatelessWidget {
  const GameInfoSheet({
    super.key,
    required this.panel,
    required this.currentScene,
  });

  final GamePanel panel;
  final String currentScene;

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
      GamePanel.journal =>
        'Текущая сцена: $currentScene. '
        'Подробная история решений появится вместе с журналом событий.',
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
          ],
        ),
      ),
    );
  }
}

class GameQuickBar extends StatelessWidget {
  const GameQuickBar({super.key, required this.onOpen});
  final ValueChanged<GamePanel> onOpen;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () => onOpen(GamePanel.character),
                icon: const Icon(Icons.person_outline),
                label: const Text('Герой'),
              ),
              TextButton.icon(
                onPressed: () => onOpen(GamePanel.inventory),
                icon: const Icon(Icons.backpack_outlined),
                label: const Text('Предметы'),
              ),
              TextButton.icon(
                onPressed: () => onOpen(GamePanel.journal),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Журнал'),
              ),
            ],
          ),
        ),
      );
}
