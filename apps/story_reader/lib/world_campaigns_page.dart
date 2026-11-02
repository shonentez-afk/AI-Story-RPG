import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'world_backup_actions.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';

/// Detail of a verified RPG world within the ONE existing library.
class WorldCampaignsPage extends StatefulWidget {
  const WorldCampaignsPage({
    super.key, required this.world, required this.gateway,
  });

  final WorldLibraryItem world;
  final WorldLibraryGateway gateway;

  @override
  State<WorldCampaignsPage> createState() => _WorldCampaignsPageState();
}

class _WorldCampaignsPageState extends State<WorldCampaignsPage> {
  List<WorldCampaignItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _refresh() async {
    try {
      final items = await widget.gateway.campaigns(
        worldHash: widget.world.archiveHash,
      );
      if (mounted) setState(() {
        _items = items;
        _failure = null;
      });
    } catch (error) {
      if (mounted) setState(
        () => _failure = 'Не удалось открыть прохождения: $error',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WorldPlayPage(
        gateway: widget.gateway,
        campaignId: id,
      ),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _start({String? parentCampaignId}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await widget.gateway.start(
        widget.world.archiveHash,
        parentCampaignId: parentCampaignId,
      );
      if (!mounted) return;
      await _open(id);
    } catch (error) {
      _notice('Не удалось создать прохождение: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(WorldCampaignItem campaign) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final payload = await widget.gateway.exportSave(campaign.id);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт прохождения игрового мира',
        fileName: 'AI-Story-RPG-' + campaign.id + '.bwsave',
        type: FileType.custom,
        allowedExtensions: const ['bwsave'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );
      if (result != null) _notice('Сохранение .bwsave экспортировано');
    } catch (error) {
      _notice('Экспорт не выполнен: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selected = await FilePicker.platform.pickFiles(
        dialogTitle: 'Импорт сохранения подготовленного мира',
        type: FileType.custom,
        allowedExtensions: const ['bwsave'],
        withData: true,
      );
      if (selected == null || selected.files.length != 1) return;
      final file = selected.files.single;
      if (file.size > 2 * 1024 * 1024) {
        throw const FormatException('Сохранение больше 2 МБ');
      }
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Не удалось прочитать файл');
      final payload = utf8.decode(bytes, allowMalformed: false);
      // Real read-only replay/CRC/hash validation BEFORE confirmation.
      // A cancelled dialog must never add a campaign or overwrite a slot.
      final preview = await widget.gateway.previewSave(
        payload, expectedWorldHash: widget.world.archiveHash,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Импортировать прохождение?'),
          content: Text(
            'Мир: ' + widget.world.title + '\n'
            'Ходов: ' + preview.revision.toString() + '\n'
            'Состояние: ' + (preview.isTerminal
                ? 'история завершена' : 'можно продолжать') + '\n'
            'Код мира: ' + preview.worldHash.substring(0, 12) + '…\n'
            'Код состояния: ' + preview.stateHash.substring(0, 12) + '…\n\n'
            'Файл уже проверен: контрольная сумма и полный журнал '
            'совпадают с установленным игровым миром. '
            'После подтверждения проверка повторится, '
            'создастся новый независимый слот. '
            'Существующие прохождения не изменятся.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Импортировать'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.gateway.importSave(
        payload,
        expectedWorldHash: widget.world.archiveHash,
      );
      if (mounted) {
        await _refresh();
        _notice('Сохранение импортировано как новая кампания');
      }
    } catch (error) {
      _notice('Импорт .bwsave не выполнен: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCampaign(WorldCampaignItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final removed = await WorldBackupActions.deleteCampaignWithBackup(
        context, widget.gateway, item,
      );
      if (removed && mounted) {
        await _refresh();
        _notice('Резервная копия сохранена, прохождение удалено');
      }
    } catch (error) {
      _notice('Удаление отменено: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveWorld() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await WorldBackupActions.saveWorld(
        widget.gateway, widget.world,
      );
      if (saved) _notice('Копия .bworld сохранена');
    } catch (error) {
      _notice('Не удалось экспортировать мир: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteWorld() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final removed = await WorldBackupActions.deleteWorldWithBackup(
        context, widget.gateway, widget.world,
      );
      if (removed && mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _notice('Нельзя удалить мир: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.world.title),
        actions: [
          IconButton(
            tooltip: 'Импортировать .bwsave v2',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_download_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия с игровым миром',
            enabled: !_busy,
            onSelected: (action) {
              if (action == 'backup') {
                _saveWorld();
              } else if (action == 'remove') {
                _deleteWorld();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'backup', child: Text('Экспортировать .bworld'),
              ),
              PopupMenuItem(
                value: 'remove', child: Text('Удалить мир с резервной копией'),
              ),
            ],
          ),
        ],
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Подготовленный игровой мир',
                style: typography.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Классическая офлайн-RPG, а не чтение книги. '
              'Прохождения сохраняются независимо.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('world-start'),
              onPressed: _busy || _loading || _failure != null
                  ? null : () => _start(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Начать новое прохождение'),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 18),
            Text('Сохранённые прохождения',
                style: typography.titleMedium),
            if (_loading) const LinearProgressIndicator(),
            if (_failure != null) ...[
              const SizedBox(height: 10),
              Text(_failure!),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Повторить загрузку'),
              ),
            ] else if (!_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Здесь пока нет прохождений этого мира.'),
              ),
            for (final item in _items)
              Card(child: ListTile(
                key: ValueKey('world-campaign-' + item.id),
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text('Прохождение · ' +
                    item.revision.toString() + ' ходов'),
                subtitle: Text(item.parentId == null
                    ? 'Самостоятельная история'
                    : 'Ответвление другого прохождения'),
                onTap: _busy ? null : () => _open(item.id),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия с прохождением',
                  enabled: !_busy,
                  onSelected: (action) {
                    if (action == 'fork') {
                      _start(parentCampaignId: item.id);
                    } else if (action == 'export') {
                      _export(item);
                    } else if (action == 'delete') {
                      _deleteCampaign(item);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'fork', child: Text('Создать ответвление'),
                    ),
                    PopupMenuItem(
                      value: 'export', child: Text('Экспортировать .bwsave'),
                    ),
                    PopupMenuItem(
                      value: 'delete', child: Text('Удалить с резервной копией'),
                    ),
                  ],
                ),
              )),
          ],
        ),
      )),
    );
  }
}
