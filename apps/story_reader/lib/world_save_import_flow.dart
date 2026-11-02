import 'package:flutter/material.dart';

import 'world_library_gateway.dart';

/// The same verified BookWorld v2 save confirmation is used from the global
/// "Мои прохождения" screen and from a particular BookWorld's details.
/// Neither preview nor cancel creates or replaces a campaign.
class WorldSaveImportFlow {
  const WorldSaveImportFlow._();

  static Future<String?> confirmAndImport({
    required BuildContext context,
    required WorldLibraryGateway gateway,
    required WorldLibraryItem world,
    required String payload,
  }) async {
    final preview = await gateway.previewSave(
      payload, expectedWorldHash: world.archiveHash,
    );
    if (!context.mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Импортировать прохождение?'),
        content: Text(
          'Мир: ${world.title}\n'
          'Ходов: ${preview.revision}\n'
          'Состояние: ${preview.isTerminal
              ? 'история завершена' : 'можно продолжать'}\n'
          'Код мира: ${preview.worldHash.substring(0, 12)}…\n'
          'Код состояния: ${preview.stateHash.substring(0, 12)}…\n\n'
          'Контрольная сумма и весь журнал проверены. '
          'Импорт создаст отдельное прохождение; существующие '
          'игры и книги не изменятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return null;
    // Native import repeats replay/hash validation immediately before INSERT.
    return gateway.importSave(payload, expectedWorldHash: world.archiveHash);
  }
}
