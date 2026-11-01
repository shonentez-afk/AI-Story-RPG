import 'package:flutter/material.dart';

import 'campaign_store.dart';
import 'main.dart' show StoryReaderPage;

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
    if (item.damaged || _busy) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryReaderPage(resume: true, campaignId: item.id),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _delete(CampaignSummary item) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
    appBar: AppBar(title: const Text('Мои прохождения')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _campaigns.isEmpty
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Пока нет сохранённых прохождений. '
                  'Начните историю из главного меню.'),
              ))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _campaigns.length,
                itemBuilder: (context, index) {
                  final item = _campaigns[index];
                  final date = item.savedAt.toLocal();
                  final subtitle = item.isLegacy
                      ? 'Совместимое старое сохранение'
                      : item.damaged
                          ? 'Данные повреждены: загрузка недоступна'
                          : 'Последняя сцена: ${item.sceneTitle} · '
                            '${date.day}.${date.month}.${date.year}';
                  return Card(child: ListTile(
                    leading: Icon(item.damaged
                        ? Icons.warning_amber_outlined
                        : Icons.auto_stories_outlined),
                    title: Text(item.isLegacy
                        ? 'Старое прохождение'
                        : 'Тайна особняка · ${index + 1}'),
                    subtitle: Text(subtitle),
                    onTap: _busy || item.damaged ? null : () => _open(item),
                    trailing: IconButton(
                      tooltip: 'Удалить прохождение',
                      onPressed: _busy ? null : () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ));
                },
              ),
      ),
    ),
  );
}
