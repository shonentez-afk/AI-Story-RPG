import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_locked_prose_checkpoint_store.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_prose_preview.dart';

/// Advanced, OPT-IN preview. Never generates in initState, never installs an
/// AI scene into BookWorld, and never replaces an existing SQLite campaign.
class SourceLockedProsePreviewPage extends StatefulWidget {
  const SourceLockedProsePreviewPage({
    super.key,
    required this.index,
    required this.book,
    required this.plan,
    this.store,
    this.previewService,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final SourceLockedProseCheckpointStore? store;
  final ZaiSourceLockedProsePreviewService? previewService;

  @override
  State<SourceLockedProsePreviewPage> createState() =>
      _SourceLockedProsePreviewPageState();
}

class _SourceLockedProsePreviewPageState
    extends State<SourceLockedProsePreviewPage> {
  late final SourceLockedProseCheckpointStore _store;
  late final ZaiSourceLockedProsePreviewService _service;
  String? _sceneId;
  SourceLockedProseDraft? _draft;
  ZaiPreviewCancellation? _requestToken;
  bool _approved = false, _working = false, _loading = true;
  bool _storageBlocked = false;
  String? _error, _progress;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SourceLockedProseCheckpointStore();
    _service = widget.previewService ??
        ZaiSourceLockedProsePreviewService();
    _sceneId = widget.plan.situations.isNotEmpty
        ? widget.plan.situations.first.id : null;
    _loadExisting();
  }

  @override
  void dispose() {
    // An already-sent HTTP POST may finish; no further retries are queued.
    _requestToken?.cancel();
    super.dispose();
  }

  SourceLockedProseContext _context() =>
      SourceLockedProseContext.forSituation(
        index: widget.index,
        book: widget.book,
        plan: widget.plan,
        situationId: _sceneId ?? '',
      );

  Future<void> _loadExisting() async {
    final sceneId = _sceneId;
    setState(() {
      _approved = false;
      _draft = null;
      _loading = true;
      _error = null;
      _progress = null;
      _storageBlocked = false;
    });
    try {
      final context = _context();
      final saved = await _store.read(context);
      if (!mounted || _sceneId != sceneId) return;
      setState(() => _draft = saved);
    } catch (_) {
      if (!mounted || _sceneId != sceneId) return;
      setState(() {
        _storageBlocked = true;
        _error = 'Не удалось проверить локальный черновик. '
          'Для безопасности повторная отправка заблокирована, '
          'пока хранилище не будет исправлено.';
      });
    } finally {
      if (mounted && _sceneId == sceneId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generate() async {
    if (_working || _loading || !_approved || _sceneId == null ||
        _storageBlocked || _error != null || _draft != null) return;
    final sceneId = _sceneId!;
    setState(() {
      _working = true;
      _progress = 'Проверяем согласие и локальный checkpoint';
      _error = null;
    });
    SourceLockedProseDraft? result;
    try {
      final context = _context();
      // Cache-first: a new POST must not be made if this exact edition,
      // plan revision and scene already have a finished private draft.
      try {
        result = await _store.read(context);
      } catch (_) {
        _storageBlocked = true;
        rethrow;
      }
      if (result == null) {
        final cancellation = ZaiPreviewCancellation();
        _requestToken = cancellation;
        result = await _service.preview(
          context: context,
          approvedContextDigest: context.approvalDigest,
          userReviewedExactContext: _approved,
          cancellation: cancellation,
          onProgress: (attempt, total, status) {
            if (mounted && _sceneId == sceneId) {
              setState(() => _progress =
                  '$status ($attempt из $total)');
            }
          },
        );
        if (!mounted || _sceneId != sceneId) return;
        // Show already received text even if local persistence later fails.
        setState(() => _draft = result);
        await _store.save(context: context, draft: result);
      }
      if (!mounted || _sceneId != sceneId) return;
      setState(() {
        _draft = result;
        _progress = 'Черновик сохранён в частном хранилище устройства';
      });
    } catch (_) {
      if (!mounted || _sceneId != sceneId) return;
      setState(() {
        // A fresh manually confirmed tap can retry after a network error.
        // Never submit another paid request automatically after exhaustion.
        _approved = false;
        _error = _draft == null
          ? 'Черновик не создан. Проверьте настройки Z.ai, '
              'согласие и доступность сети. Существующая игра не изменена.'
          : 'Текст получен, но не удалось сохранить локально. '
              'Скопируйте его перед закрытием, повторно отправлять '
              'запрос автоматически не будем.';
      });
    } finally {
      _requestToken = null;
      if (mounted && _sceneId == sceneId) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _delete() async {
    if (_working || _loading || _draft == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить художественный черновик?'),
        content: const Text('Будет удалён только текст этой сцены '
            'в локальном хранилище. Книга и игровые сохранения останутся. '
            'Повторная генерация может потребовать нового запроса к Z.ai.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
          FilledButton(
            key: const Key('prose-scene-confirm-delete'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить черновик')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _working = true);
    try {
      await _store.delete(_context());
      if (!mounted) return;
      setState(() {
        _draft = null;
        _approved = false;
        _error = null;
        _progress = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Не удалось удалить локальный черновик. Игра не изменена.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SourceLockedProseContext? snapshot;
    try {
      snapshot = _context();
    } catch (_) {
      // Bad source/edition/plan: show an error, not a cloud request.
    }
    final current = snapshot;
    final selected = current?.situation;
    return Scaffold(
      appBar: AppBar(title: const Text('Художественный черновик сцены')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text('Дополнительная функция: сцена ещё не '
                'включается в игру и не считается каноном книги. '
                'Генерация происходит только после отдельного '
                'подтверждения. Игра и сохранения не затрагиваются.'),
            const SizedBox(height: 14),
            if (widget.plan.situations.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('prose-scene-selector'),
                initialValue: _sceneId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Игровая ситуация для черновика',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final scene in widget.plan.situations)
                    DropdownMenuItem(
                      value: scene.id,
                      child: Text(scene.goal,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _working || _loading
                    ? null
                    : (value) {
                      if (value == null || value == _sceneId) return;
                      setState(() => _sceneId = value);
                      _loadExisting();
                    },
              ),
            const SizedBox(height: 12),
            if (selected == null)
              const Text('Ситуация или исходная цитата не прошли проверку.')
            else ...[
              Text('Отправляемый контекст',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('ID: ' + selected.id),
              Text('Маршрут: ' + selected.route.name),
              Text('Цель: ' + selected.goal),
              Text('Конфликт: ' + selected.conflict),
              if (current!.sourceEvent != null) ...[
                const SizedBox(height: 8),
                const Text('Дословный отрывок из выбранной редакции:'),
                SelectableText('«' + current.sourceEvent!.source.quote + '»'),
              ] else
                const Text('Исходной цитаты нет. '
                    'Это явно вымышленная ситуация игры.'),
              const SizedBox(height: 8),
              Text('Доступные игровые варианты: ' +
                  selected.decisions.length.toString()),
              for (final choice in selected.decisions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(choice.id + ': ' + choice.intent),
                      Text('Требует: ' + choice.requires.join(', ') +
                          '; запрещено: ' + choice.forbids.join(', ') +
                          '; добавляет: ' + choice.adds.join(', ') +
                          '; убирает: ' + choice.removes.join(', '),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Этот контекст может быть передан в Z.ai '
                  '(GLM 4.7 Flash), если вы дадите согласие. '
                  'Возможны платные запросы; при временных сбоях '
                  'до трёх попыток с одинаковыми данными. '
                  'Название книги, весь файл и сохранения не отправляются.'),
              CheckboxListTile(
                key: const Key('prose-scene-approved'),
                contentPadding: EdgeInsets.zero,
                value: _approved,
                onChanged: _working || _loading || _draft != null ||
                        _storageBlocked
                    ? null
                    : (value) => setState(() {
                        _approved = value == true;
                        _error = null;
                        _progress = null;
                      }),
                title: const Text('Разрешаю отправить именно показанный '
                    'контекст ОДНОЙ сцены для художественного черновика'),
              ),
              FilledButton.icon(
                key: const Key('prose-scene-generate'),
                onPressed: _working || _loading ||
                        !_approved || _draft != null ||
                        _error != null || _storageBlocked
                    ? null : _generate,
                icon: const Icon(Icons.auto_stories),
                label: const Text('Создать художественный черновик'),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                Text(_progress!),
              ],
              if (_loading || _working)
                const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    key: const Key('prose-scene-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              ],
              if (_draft != null) ...[
                const Divider(height: 30),
                Text('Локальный художественный черновик',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(_draft!.text,
                    key: const Key('prose-scene-draft-text')),
                const SizedBox(height: 8),
                Text('Что остаётся проверить: ' + _draft!.uncertainty),
                const SizedBox(height: 8),
                const Text('Текст не включён в BookWorld. '
                    'Он не доказывает факты и не изменяет выборы.'),
                OutlinedButton.icon(
                  key: const Key('prose-scene-delete'),
                  onPressed: _working || _loading ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить только этот черновик'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
