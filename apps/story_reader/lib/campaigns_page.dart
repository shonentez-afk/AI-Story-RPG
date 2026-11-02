import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'campaign_store.dart';
import 'pilot_save_codec.dart';
import 'world_backup_actions.dart';
import 'world_library_gateway.dart';
import 'world_save_import_flow.dart';
import 'world_play_page.dart';
import 'world_campaigns_page.dart';
import 'main.dart' show StoryReaderPage, makePilotStory;

/// Campaigns and source books are deliberately separate navigations.
class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key, this.worldGateway});

  final WorldLibraryGateway? worldGateway;

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  final CampaignStore _store = CampaignStore();
  List<CampaignSummary> _campaigns = const [];
  List<WorldCampaignItem> _worldCampaigns = const [];
  Map<String, WorldLibraryItem> _worldCatalog = const {};
  bool _worldError = false;
  bool _worldLoading = false;
  bool _busy = false;
  bool _opening = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.worldGateway != null) {
      _worldLoading = true;
      unawaited(_refreshWorlds());
    }
  }

  void _retryWorlds() {
    if (_worldLoading) return;
    setState(() {
      _worldLoading = true;
      _worldError = false;
    });
    unawaited(_refreshWorlds());
  }

  Future<void> _refreshWorlds() async {
    final gateway = widget.worldGateway;
    if (gateway == null) return;
    try {
      final worlds = await gateway.worlds()
          .timeout(const Duration(seconds: 8));
      final campaigns = await gateway.campaigns()
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() {
        _worldCatalog = {
          for (final world in worlds) world.archiveHash: world,
        };
        _worldCampaigns = campaigns;
        _worldError = false;
      });
    } catch (_) {
      // Existing pilot M1.6 slots must not disappear when a separate
      // BookWorld database is unavailable or damaged.
      if (mounted) setState(() => _worldError = true);
    } finally {
      if (mounted) setState(() => _worldLoading = false);
    }
  }

  Future<void> _openWorld(WorldCampaignItem item) async {
    if (_busy || _opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorldPlayPage(
          gateway: widget.worldGateway!,
          campaignId: item.id,
        ),
      ));
      if (mounted) await _refreshWorlds();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openWorldDetail(WorldCampaignItem item) async {
    final world = _worldCatalog[item.worldHash];
    if (world == null || _busy || _opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorldCampaignsPage(
          gateway: widget.worldGateway!,
          world: world,
        ),
      ));
      if (mounted) await _refreshWorlds();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _deleteWorldCampaign(WorldCampaignItem item) async {
    if (_busy || _opening) return;
    setState(() => _busy = true);
    try {
      final removed = await WorldBackupActions.deleteCampaignWithBackup(
        context, widget.worldGateway!, item,
      );
      if (removed && mounted) {
        await _refreshWorlds();
        _error('Резервная копия сохранена, прохождение удалено');
      }
    } catch (error) {
      _error('Удаление отменено: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final campaigns = await _store.all();
      if (mounted) setState(() => _campaigns = campaigns);
    } catch (error) {
      _error('Не удалось прочитать прохождения: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _open(CampaignSummary item) async {
    if (item.damaged || _busy || _opening) return;
    // Navigation is not a storage operation; keep the busy progress bar off
    // while another route is on top (important for pumpAndSettle and battery).
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StoryReaderPage(resume: true, campaignId: item.id),
      ));
      if (mounted) await _refresh();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _export(CampaignSummary item) async {
    if (_busy || item.damaged) return;
    setState(() => _busy = true);
    try {
      final game = await _store.read(item.id);
      if (game == null) throw StateError('Прохождение не найдено');
      // Validate the engine snapshot and hash before opening the system
      // save dialog. file_picker writes provided bytes on Android/Windows.
      final bytes = PilotSaveCodec.encode(
        sourceCampaignId: item.id,
        game: game,
        project: makePilotStory(),
      );
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт игрового прохождения',
        fileName: 'AI-Story-RPG-${item.id}.bwsave',
        type: FileType.custom,
        allowedExtensions: const ['bwsave'],
        bytes: bytes,
      );
      if (destination == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Прохождение экспортировано в .bwsave'),
      ));
    } catch (error) {
      _error('Не удалось экспортировать прохождение: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['bwsave'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      if (file.size > PilotSaveCodec.maxFileBytes) {
        throw const FormatException('Файл сохранения слишком большой');
      }
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException(
          'Не удалось получить байты файла через системный выбор',
        );
      }
      // One system picker accepts both .bwsave v1 (pilot) and v2 (BookWorld).
      // The format comes from the verified envelope, never the filename.
      final dynamic envelope;
      try {
        envelope = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      } on FormatException {
        throw const FormatException('Сохранение не является корректным UTF-8 JSON');
      }
      if (envelope is Map && envelope['format'] == 'ai_story_bwsave_v2') {
        final gateway = widget.worldGateway;
        if (gateway == null) {
          throw const FormatException(
            'Подготовленные игровые миры недоступны в этом режиме',
          );
        }
        if (file.size > 2 * 1024 * 1024) {
          throw const FormatException('Сохранение BookWorld больше 2 МБ');
        }
        final worldHash = envelope['world_sha256'];
        if (worldHash is! String) {
          throw const FormatException('В сохранении не указан игровой мир');
        }
        final worlds = await gateway.worlds();
        final matches = worlds.where(
          (world) => world.archiveHash == worldHash,
        ).toList();
        if (matches.isEmpty) {
          throw const FormatException(
            'Для этого прохождения сначала добавьте соответствующий '
            '.bworld через Библиотеку. Существующие данные не изменены.',
          );
        }
        final importedId = await WorldSaveImportFlow.confirmAndImport(
          context: context,
          gateway: gateway,
          world: matches.single,
          payload: utf8.decode(bytes, allowMalformed: false),
        );
        if (importedId == null || !mounted) return;
        await _refreshWorlds();
        _error('BookWorld-прохождение импортировано как новый слот');
        return;
      }
      // Legacy v1 still uses exactly the existing runtime verifier and store.
      final imported = PilotSaveCodec.decode(bytes, project: makePilotStory());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Импортировать прохождение?'),
          content: Text(
            'История: Тайна особняка\n'
            'Последняя сцена: ${imported.sceneTitle}\n'
            'Решений и событий журнала: ${imported.game.journal.length}\n\n'
            'Будет создано новое независимое прохождение. '
            'Существующие сохранения и книги останутся без изменений.',
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
      if (confirmed != true || !mounted) return;
      await _store.importNew(imported.game, sceneTitle: imported.sceneTitle);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Прохождение импортировано как новая кампания'),
      ));
    } catch (error) {
      _error('Не удалось импортировать .bwsave: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CampaignSummary item) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: const Text('Удалить прохождение?'),
        content: Text(
          'Сохранённая кампания «${item.sceneTitle}» будет удалена. '
          'Другие прохождения и импортированные книги останутся без изменений. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.delete(item.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Прохождение удалено')),
        );
      }
    } catch (error) {
      _error('Не удалось удалить прохождение: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Мои прохождения'),
      actions: [
        IconButton(
          tooltip: 'Импортировать сохранение (.bwsave)',
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.file_download_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_worldLoading) const LinearProgressIndicator(minHeight: 2),
        if (_worldError) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Игровые миры пока недоступны. '
                   'Старые прохождения не затронуты.',
                  style: Theme.of(context).textTheme.bodySmall),
              TextButton.icon(
                onPressed: _retryWorlds,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить загрузку миров'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _campaigns.isEmpty && _worldCampaigns.isEmpty
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_stories_outlined, size: 44),
                              const SizedBox(height: 12),
                              const Text('Пока нет сохранённых прохождений. '
                                  'Начните новую историю или импортируйте .bwsave.',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _busy ? null : _import,
                                icon: const Icon(Icons.file_download_outlined),
                                label: const Text('Импортировать .bwsave'),
                              ),
                            ],
                          ),
                        ))
                      : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _campaigns.length + _worldCampaigns.length,
                itemBuilder: (context, index) {
                  if (index < _worldCampaigns.length) {
                    final worldCampaign = _worldCampaigns[index];
                    final world = _worldCatalog[worldCampaign.worldHash];
                    return Card(child: ListTile(
                      key: ValueKey('all-world-campaign-' + worldCampaign.id),
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(world?.title ?? 'Подготовленный мир'),
                      subtitle: Text('BookWorld · ' +
                          worldCampaign.revision.toString() +
                          ' ходов · сохранение SQLite'),
                      onTap: _busy ? null : () => _openWorld(worldCampaign),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Действия с BookWorld-прохождением',
                        enabled: !_busy,
                        onSelected: (action) {
                          if (action == 'details') {
                            _openWorldDetail(worldCampaign);
                          } else if (action == 'delete') {
                            _deleteWorldCampaign(worldCampaign);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'details',
                            enabled: world != null,
                            child: const Text('Открыть игровой мир'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить с резервной копией'),
                          ),
                        ],
                      ),
                    ));
                  }
                  final item = _campaigns[index - _worldCampaigns.length];
                  final date = item.savedAt.toLocal();
                  final narrow = MediaQuery.sizeOf(context).width < 480 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  final title = item.isLegacy
                      ? 'Старое прохождение'
                      : item.damaged
                          ? 'Повреждённое сохранение'
                          : item.sceneTitle.isEmpty
                              ? 'Тайна особняка'
                              : item.sceneTitle;
                  final subtitle = item.isLegacy
                      ? 'Совместимое старое сохранение'
                      : item.damaged
                          ? 'Данные повреждены: загрузка недоступна'
                          : 'Тайна особняка · Сохранено: '
                              '${date.day.toString().padLeft(2, '0')}.'
                              '${date.month.toString().padLeft(2, '0')} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                  return Card(child: ListTile(
                    leading: Icon(item.damaged
                        ? Icons.warning_amber_outlined
                        : Icons.auto_stories_outlined),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    onTap: _busy || item.damaged ? null : () => _open(item),
                    trailing: narrow
                        ? PopupMenuButton<String>(
                            tooltip: 'Действия с прохождением',
                            enabled: !_busy,
                            icon: const Icon(Icons.more_vert),
                            onSelected: (action) {
                              if (action == 'export') {
                                _export(item);
                              } else if (action == 'delete') {
                                _delete(item);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'export',
                                enabled: !item.damaged,
                                child: const Text('Экспортировать .bwsave'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Удалить прохождение'),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Экспортировать прохождение',
                                onPressed: _busy || item.damaged
                                    ? null : () => _export(item),
                                icon: const Icon(Icons.file_upload_outlined),
                              ),
                              IconButton(
                                tooltip: 'Удалить прохождение',
                                onPressed: _busy ? null : () => _delete(item),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                  ));
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
