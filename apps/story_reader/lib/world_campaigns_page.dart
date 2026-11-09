import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rpg_api/rpg_api.dart' show RpgWorldIntakePreview;

import 'world_backup_actions.dart';
import 'world_library_gateway.dart';
import 'world_save_import_flow.dart';
import 'world_play_page.dart';
import 'world_import_review_worker.dart';

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
  bool _opening = false;
  String? _failure;
  RpgWorldIntakePreview? _reviewedCapabilities;

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_loadCapabilities());
  }

  /// A world title alone carries no provenance. Read the installed archive
  /// through the same native importer before describing CANON / ALTER_FATE.
  Future<void> _loadCapabilities() async {
    try {
      final bytes = await widget.gateway.exportWorld(widget.world.archiveHash);
      final checked = await reviewImportedWorldInWorker(bytes, null);
      if (checked.archiveHash != widget.world.archiveHash ||
          checked.bookworldId != widget.world.bookworldId) {
        throw const FormatException('Подмена метаданных игрового мира');
      }
      if (mounted) {
        setState(() => _reviewedCapabilities = checked);
      }
    } catch (_) {
      // Reading optional capability descriptions must not block an already
      // installed offline campaign, nor fall back to an invented game mode.
    }
  }

  String get _gameType {
    final review = _reviewedCapabilities;
    if (review == null) {
      return 'Доступные режимы и герой определяются самим '
          'проверенным игровым пакетом.';
    }
    if (review.sourceCausalReviewVerified) {
      return 'Полная книжная RPG: проверенные причины исходного CANON '
          'и возможный ALTER_FATE после реальных действий.';
    }
    if (review.sourceLiteralCanonVerified) {
      return 'Буквальный CANON всей книги: исходный текст сохранён, '
          'но литературная причинность всех событий не проверена.';
    }
    return review.isPrivate
        ? 'Частная подготовленная RPG с проверенными игровыми правилами.'
        : 'Классическая офлайн-RPG с проверенными правилами.';
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
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(
          gateway: widget.gateway,
          campaignId: id,
        ),
      ));
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        // Release the navigation lock before potentially slow disk refresh.
        unawaited(_refresh());
      }
    }
  }

  Future<void> _start({String? parentCampaignId}) async {
    if (_busy || _opening) return;
    setState(() => _busy = true);
    try {
      final id = await widget.gateway.start(
        widget.world.archiveHash,
        parentCampaignId: parentCampaignId,
      );
      if (!mounted) return;
      // Creating a campaign has finished. Do not leave the busy animation
      // active under the entire game route.
      setState(() => _busy = false);
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
      final importedId = await WorldSaveImportFlow.confirmAndImport(
        context: context,
        gateway: widget.gateway,
        world: widget.world,
        payload: payload,
      );
      if (importedId == null) return;
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
        title: Text(widget.world.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
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
            Text(_gameType,
                key: const Key('world-campaign-capabilities')),
            if (_reviewedCapabilities != null) ...[
              const SizedBox(height: 6),
              Text('Сцен: ${_reviewedCapabilities!.sceneCount}, '
                  'NPC: ${_reviewedCapabilities!.npcActorCount}, '
                  'предметов: ${_reviewedCapabilities!.itemCount}.'),
              if (_reviewedCapabilities!.heroName != null)
                Text('Герой: ${_reviewedCapabilities!.heroName}. '
                    'Роль закреплена подготовленным миром.'),
              if (_reviewedCapabilities!.sourceCausalReviewVerified)
                const Text('Персонажи, обязательства и причинные '
                    'ограничения подтверждены исходной редакцией '
                    'и исполняются автономным движком.'),
              if (_reviewedCapabilities!.dynamicAiActionsAvailable)
                const Text('Свободные действия ИИ поддерживаются '
                    'движком; каждый новый ход требует проверки '
                    'и подтверждения пользователя.'),
            ],
            const Text('Прохождения сохраняются независимо. '
                'Герой и правила определены установленным миром; '
                'запуск не отправляет книгу в облако.'),
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
                onTap: _busy || _opening ? null : () => _open(item.id),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия с прохождением',
                  enabled: !_busy && !_opening,
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
