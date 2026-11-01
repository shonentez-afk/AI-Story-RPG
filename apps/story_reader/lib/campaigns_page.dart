import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'campaign_store.dart';
import 'pilot_save_codec.dart';
import 'main.dart' show StoryReaderPage, makePilotStory;

/// Campaigns and source books are deliberately separate navigations.
class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key});

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  final CampaignStore _store = CampaignStore();
  List<CampaignSummary> _campaigns = const [];
  bool _busy = false;
  bool _opening = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
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
      // No local campaign is touched until the full checksum, schema,
      // pilot identity and story_engine restore contract have passed.
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
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _campaigns.isEmpty
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
                itemCount: _campaigns.length,
                itemBuilder: (context, index) {
                  final item = _campaigns[index];
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
