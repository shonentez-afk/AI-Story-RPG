import 'dart:convert';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'source_semantic_window.dart';
import 'zai_semantic_preview.dart';
import 'ai_connection.dart';

/// The isolated M2f2a pilot: review ONE complete chunk and permit ONE
/// intentional cloud request. No automatic analysis of the full book,
/// checkpoint writes, world compilation, or in-game AI.
class ZaiSemanticPreviewPage extends StatefulWidget {
  const ZaiSemanticPreviewPage({
    super.key,
    required this.index,
    this.service,
  });

  final BookSourceIndex index;
  final ZaiSemanticPreviewService? service;

  @override
  State<ZaiSemanticPreviewPage> createState() =>
      _ZaiSemanticPreviewPageState();
}

class _ZaiSemanticPreviewPageState extends State<ZaiSemanticPreviewPage> {
  late final ZaiSemanticPreviewService _service =
      widget.service ?? ZaiSemanticPreviewService();

  int _position = 0;
  bool _busy = false;
  bool _confirming = false;
  ZaiPreviewCancellation? _cancellation;
  String? _progress;
  ZaiSemanticPreviewResult? _result;
  String? _error;

  late final List<SourceSemanticWindow> _windows =
      SourceSemanticWindowPlanner.plan(widget.index);
  SourceSemanticWindow get _window => _windows[_position];

  @override
  void dispose() {
    // Leaving the preview revokes permission for ALL not-yet-sent retries.
    _cancellation?.cancel();
    super.dispose();
  }

  void _stopRetries() {
    _cancellation?.cancel();
    if (mounted) {
      setState(() => _progress =
          'Остановка запрошена. Новых попыток отправки не будет.');
    }
  }

  void _move(int direction) {
    if (_busy || _confirming) return;
    final next = _position + direction;
    if (next < 0 || next >= _windows.length) return;
    setState(() {
      _position = next;
      _result = null;
      _error = null;
      _progress = null;
    });
  }

  Future<bool> _confirmSource(SourceSemanticWindow window) async {
    // This is a new, non-persistent consent for this particular excerpt,
    // independent of the prior synthetic connection-test permission.
    var checked = false;
    final decision = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(window.chunks.length == 1
              ? 'Передать этот фрагмент в Z.ai?'
              : 'Передать это смысловое окно в Z.ai?'),
          scrollable: true,
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('На Z.ai будут отправлены ТОЛЬКО название книги '
                    'и все показанные ниже исходные абзацы этого окна. '
                    'Для точной проверки цитат передаются также '
                    'служебные идентификаторы и типы абзацев. '
                    'Название используется как контекст, но не доказывает '
                    'события и факты: ИИ обязан сверять их по цитатам. '
                    'Ключ передаётся Z.ai для авторизации. '
                    'Автор, остальные главы, библиотека, '
                    'NPC и игровые сохранения не отправляются. '
                    'При временном сбое соединения, HTTP 429 или ошибке '
                    'сервера разрешены до двух автоматических повторов '
                    'ТОГО ЖЕ фрагмента (всего не более трёх попыток). '
                    'Модель может получить одинаковый текст повторно, '
                    'если предыдущий ответ потерялся. '
                    'Повторы можно остановить; другие главы не передаются.'),
                const SizedBox(height: 12),
                const Text('Название книги (будет передано):'),
                const SizedBox(height: 4),
                SelectableText(
                  widget.index.title.trim(),
                  key: const Key('zai-consent-book-title'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text('Глава ' + (window.chapterIndex + 1).toString() +
                    ' · исходных частей: ' +
                    window.chunks.length.toString() +
                    ' · ' + window.utf8Length.toString() +
                    ' байт показанного текста'),
                const SizedBox(height: 4),
                const Text('Прочитайте фрагмент и прокрутите диалог вниз, '
                    'чтобы подтвердить отправку.'),
                const SizedBox(height: 8),
                SelectableText(
                  window.displayText,
                  key: const Key('zai-consent-exact-excerpt'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('zai-consent-exact-checkbox'),
                  value: checked,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) =>
                      setDialogState(() => checked = value == true),
                  title: const Text('Разрешаю отправить название книги '
                      'и все показанные исходные абзацы этого окна в Z.ai '
                      'с максимум двумя автоматическими повторами '
                      'при временных ошибках'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('zai-consent-confirm'),
              onPressed: checked
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Отправить выбранное окно'),
            ),
          ],
        ),
      ),
    );
    return decision == true;
  }

  Future<void> _analyze() async {
    if (_busy || _confirming) return;
    final window = _window;
    final chunk = window.chunks.first;
    if (!window.hasNarrativeText ||
        window.utf16Length > SourceSemanticWindowPlanner.maxWindowUtf16 ||
        window.utf8Length > SourceSemanticWindowPlanner.maxWindowUtf8) {
      setState(() => _error = 'Окно пустое или слишком большое '
          'для проверочной отправки. Выберите другое.');
      return;
    }
    setState(() => _confirming = true);
    bool approved = false;
    try {
      approved = await _confirmSource(window);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!approved || !mounted) return;
    final cancellation = ZaiPreviewCancellation();
    setState(() {
      _busy = true;
      _cancellation = cancellation;
      _progress = null;
      _result = null;
      _error = null;
    });
    try {
      final result = await _service.preview(
        index: widget.index,
        chunk: chunk,
        window: window.chunks.length > 1 ? window : null,
        consentForThisChunk: true,
        consentForBookTitle: true,
        cancellation: cancellation,
        onProgress: (attempt, total, status) {
          if (mounted && _cancellation == cancellation) {
            setState(() => _progress = status);
          }
        },
      );
      if (mounted && identical(_window, window)) {
        setState(() => _result = result);
      }
    } on AiSetupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error =
          'Предпросмотр не завершён. '
          'Исходная книга, редакторы и сохранения не изменены.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _cancellation = null;
        });
      }
    }
  }

  static String _categoryLabel(String name) => switch (name) {
    'character' => 'Персонаж',
    'alias' => 'Псевдоним',
    'location' => 'Место',
    'event' => 'Событие',
    'state' => 'Состояние',
    'fact' => 'Факт / намерение',
    'dependency' => 'Причинная связь',
    _ => 'Другое',
  };

  @override
  Widget build(BuildContext context) {
    final windows = _windows;
    final window = _window;
    final size = window.utf8Length;
    final title = widget.index.title.trim();
    final validTitle = title.isNotEmpty &&
        title.length <= ZaiSemanticPreviewService.maxBookTitleUtf16 &&
        utf8.encode(title).length <=
            ZaiSemanticPreviewService.maxBookTitleUtf8;
    final allowed = validTitle && window.hasNarrativeText &&
        window.utf16Length <= SourceSemanticWindowPlanner.maxWindowUtf16 &&
        size <= SourceSemanticWindowPlanner.maxWindowUtf8;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Предложения ИИ по цитатам'),
        actions: [
          if (_busy)
            IconButton(
              key: const Key('zai-cancel-retries'),
              tooltip: 'Остановить дальнейшие попытки',
              onPressed: _cancellation == null ||
                      _cancellation!.isCancelled
                  ? null : _stopRetries,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                Text('Z.ai · GLM-4.7-Flash',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('Язык описаний: русский. '
                    'Цитаты и имена собственные сохраняются '
                    'на языке оригинала.'),
                const SizedBox(height: 8),
                const Text('Экспериментальный просмотр. ИИ изучает '
                    'одно смысловое окно из соседних абзацев одной главы '
                    'и предлагает персонажей, места, действия, '
                    'состояния и факты. Результат не сохраняется, '
                    'не подтверждает канон и не создаёт RPG. '
                    'Каждое окно отправляется только после согласия; '
                    'временные сбои могут вызвать до двух повторов.'),
                const SizedBox(height: 12),
                Text('Книга: ${widget.index.title}',
                    key: const Key('zai-preview-book-title'),
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      key: const Key('zai-previous-chunk'),
                      tooltip: 'Предыдущий фрагмент',
                      onPressed: !_busy && !_confirming && _position > 0
                          ? () => _move(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Окно ' + (_position + 1).toString() +
                        ' из ' + windows.length.toString() +
                        ' · глава ' + (window.chapterIndex + 1).toString() +
                        ' · частей ' + window.chunks.length.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      key: const Key('zai-next-chunk'),
                      tooltip: 'Следующий фрагмент',
                      onPressed: !_busy && !_confirming &&
                              _position + 1 < windows.length
                          ? () => _move(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Текст смыслового окна · ' + size.toString() +
                    ' байт. Включены только соседние части одной главы, '
                    'цитаты сохраняют исходные ссылки.'),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      window.displayText,
                      key: const Key('zai-chunk-text'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('zai-send-single-chunk'),
                  onPressed: _busy || _confirming || !allowed ? null : _analyze,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Проверить этот фрагмент с ИИ'),
                ),
                if (!validTitle)
                  const Text('Название книги отсутствует или слишком '
                      'длинное. Для передачи требуется корректное название; '
                      'никакие данные не отправлены.')
                else if (!allowed)
                  const Text('Окно без текста повествования или слишком '
                      'большое. Ничего не отправлено.'),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  Text(
                    _progress ?? 'Ожидаем ответ GLM-4.7-Flash…',
                    key: const Key('zai-retry-status'),
                  ),
                  const Text('Анализируется только выбранное окно. '
                      'Книги, RPG и сохранения не изменяются.'),
                  const Text('Остановить новые попытки можно значком '
                      '«Стоп» в верхней панели.'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: const Key('zai-preview-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                if (_result != null) ...[
                  const Divider(height: 32),
                  Text('Неподтверждённые предложения',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('Получено: ' +
                      _result!.totalSuggestions.toString() +
                      '. Проверено по исходным цитатам: ' +
                      _result!.batch.candidates.length.toString() +
                      '. Отброшено: ' + _result!.rejectedCount.toString() +
                      ' (не на русском: ' +
                      _result!.rejectedNonRussian.toString() +
                      '). Это только предварительные гипотезы. '
                      'Цитаты сохранены на языке оригинала.'),
                  if (_result!.batch.candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Проверяемых предложений нет. '
                          'Повтор не выполнялся автоматически.'),
                    ),
                  for (final candidate in _result!.batch.candidates)
                    Card(
                      child: ListTile(
                        title: Text(candidate.label),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Категория: ' +
                                _categoryLabel(candidate.category.name)),
                            const SizedBox(height: 4),
                            SelectableText('Цитата: ' + candidate.quote),
                            const SizedBox(height: 4),
                            Text('Исходный фрагмент: ' + candidate.chunkId),
                            const SizedBox(height: 4),
                            Text('Проверить: ' + candidate.uncertainty),
                          ],
                        ),
                        leading: const Icon(Icons.fact_check_outlined),
                      ),
                    ),
                  if (_result!.rejectionReasons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Причины отклонения предложений:'),
                    for (final reason in _result!.rejectionReasons)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text('• ' + reason),
                      ),
                  ],
                  const SizedBox(height: 8),
                  const Text('Ни одна находка не перенесена в редакторы, '
                      'канон, кампанию или BookWorld. '
                      'Включение в RPG будет отдельным проверяемым шагом.'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
