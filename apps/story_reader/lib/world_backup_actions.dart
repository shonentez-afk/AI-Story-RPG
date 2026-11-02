import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'world_library_gateway.dart';

/// A destructive UI operation is only allowed after a user-approved backup.
/// SQLite repeats revision and foreign-key checks before committing a DELETE.
class WorldBackupActions {
  const WorldBackupActions._();

  static Future<bool> saveWorld(
    WorldLibraryGateway gateway, WorldLibraryItem world,
  ) async {
    final bytes = await gateway.exportWorld(world.archiveHash);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить резервную копию игрового мира',
      fileName: 'AI-Story-RPG-' +
          world.archiveHash.substring(0, 12) + '.bworld',
      type: FileType.custom,
      allowedExtensions: const ['bworld'],
      bytes: bytes,
    );
    return path != null;
  }

  static Future<bool> deleteWorldWithBackup(
    BuildContext context,
    WorldLibraryGateway gateway,
    WorldLibraryItem world,
  ) async {
    final campaigns = await gateway.campaigns(worldHash: world.archiveHash);
    if (campaigns.isNotEmpty) {
      throw StateError(
        'У мира есть сохранённые прохождения. '
        'Сначала экспортируйте и удалите каждое прохождение.',
      );
    }
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Удалить игровой мир?'),
        content: Text(
          '«' + world.title + '» будет удалён из библиотеки. '
          'Перед удалением сохраните исходный .bworld. '
          'Отмена системного сохранения отменяет удаление. '
          'Пользовательские книги TXT/FB2 не затрагиваются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить копию и удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    if (!await saveWorld(gateway, world) || !context.mounted) return false;
    await gateway.deleteWorld(world.archiveHash);
    return true;
  }

  static Future<bool> deleteCampaignWithBackup(
    BuildContext context,
    WorldLibraryGateway gateway,
    WorldCampaignItem campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Удалить прохождение?'),
        content: Text(
          'Будет удалено прохождение с ' +
          campaign.revision.toString() +
          ' ходами. Сначала сохраните резервную копию .bwsave v2. '
          'Отмена системного сохранения отменяет удаление. '
          'Другие прохождения и независимые ответвления сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить копию и удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    final payload = await gateway.exportSave(campaign.id);
    final dynamic decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'ai_story_bwsave_v2' ||
        decoded['source_campaign_id'] != campaign.id ||
        decoded['world_sha256'] != campaign.worldHash ||
        decoded['checkpoint'] is! Map ||
        (decoded['checkpoint'] as Map)['revision'] != campaign.revision) {
      throw const FormatException(
        'Прохождение изменилось с момента открытия. Обновите список.',
      );
    }
    if (!context.mounted) return false;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Резервная копия прохождения перед удалением',
      fileName: 'AI-Story-RPG-' + campaign.id + '.bwsave',
      type: FileType.custom,
      allowedExtensions: const ['bwsave'],
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
    if (path == null || !context.mounted) return false;
    await gateway.deleteCampaign(
      campaign.id, expectedRevision: campaign.revision,
    );
    return true;
  }
}
