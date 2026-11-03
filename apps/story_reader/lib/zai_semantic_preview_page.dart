import 'dart:convert';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'source_semantic_provider.dart';
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
  ZaiSemanticPreviewResult? _result;
  String? _error;

  SourceChunk get _chunk => widget.index.chunks[_position];

  void _move(int direction) {
    if (_busy || _confirming) return;
    final next = _position + direction;
    if (next < 0 || next >= widget.index.chunks.length) return;
    setState(() {
      _position = next;
      _result = null;
      _error = null;
    });
  }

  Future<bool> _confirmSource(SourceChunk chunk) async {
    // This is a new, non-persistent consent for this particular excerpt,
    // independent of the prior synthetic connection-test permission.
    var checked = false;
    final decision = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Передать этот фрагмент в Z.ai?'),
          scrollable: true,
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Будет отправлен только приведённый ниже текст. '
                    'Ключ передаётся Z.ai для авторизации. '
                    'Никакие остальные главы, автор, библиотека, '
                    'NPC или игровые сохранения не отправляются.'),
                const SizedBox(height: 12),
                Text('Глава ' + (chunk.chapterIndex + 1).toString() +
                    ' · ' + utf8.encode(chunk.text).length.toString() +
                    ' байт исходного текста'),
                const SizedBox(height: 8),
                SelectableText(
                  chunk.text,
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
                  title: const Text('Разрешаю однократную отправку '
                      'именно этого текста на Z.ai'),
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
              child: const Text('Отправить один фрагмент'),
            ),
          ],
        ),
      ),
    );
    return decision == true;
  }

  Future<void> _analyze() async {
    if (_busy || _confirming) return;
    final chunk = _chunk;
    if (chunk.text.length > ZaiSemanticPreviewService.maxChunkUtf16 ||
        utf8.encode(chunk.text).length >
            ZaiSemanticPreviewService.maxChunkUtf8Bytes) {
      setState(() => _error = 'Этот фрагмент слишком большой для '
          'одиночной проверочной отправки. Выберите другой.');
      return;
    }
    setState(() => _confirming = true);
    bool approved = false;
    try {
      approved = await _confirmSource(chunk);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await _service.preview(
        index: widget.index,
        chunk: chunk,
        consentForThisChunk: true,
      );
      if (mounted && _chunk.id == chunk.id) {
        setState(() => _result = result);
      }
    } on AiSetupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error =
          'Предпросмотр не завершён. '
          'Исходная книга, редакторы и сохранения не изменены.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chunks = widget.index.chunks;
    final chunk = _chunk;
    final size = utf8.encode(chunk.text).length;
    final allowed = chunk.text.length <=
            ZaiSemanticPreviewService.maxChunkUtf16 &&
        size <= ZaiSemanticPreviewService.maxChunkUtf8Bytes;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Предложения ИИ по цитатам')),
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
                const Text('Экспериментальный просмотр. '
                    'ИИ предлагает имена, места, события и факты '
                    'по одному выбранному фрагменту. '
                    'Результат не сохраняется, не подтверждает канон '
                    'и не создаёт RPG. Для каждой отправки '
                    'требуется новое согласие.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      key: const Key('zai-previous-chunk'),
                      tooltip: 'Предыдущий фрагмент',
                      onPressed: !_busy && _position > 0
                          ? () => _move(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Фрагмент ' + (_position + 1).toString() +
                        ' из ' + chunks.length.toString() +
                        ' · глава ' + (chunk.chapterIndex + 1).toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      key: const Key('zai-next-chunk'),
                      tooltip: 'Следующий фрагмент',
                      onPressed: !_busy && _position + 1 < chunks.length
                          ? () => _move(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Исходный текст · ' + size.toString() +
                    ' байт. Его можно прочитать целиком перед согласием.'),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      chunk.text,
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
                if (!allowed)
                  const Text('Фрагмент больше безопасного лимита. '
                      'Ничего не отправлено.'),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const Text('Анализируем один фрагмент. '
                      'Никакие файлы не изменяются.'),
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
                      '. Проверено по буквальному совпадению цитат: ' +
                      _result!.batch.candidates.length.toString() +
                      '. Отброшено: ' + _result!.rejectedCount.toString() +
                      '. Это только предварительные гипотезы.'),
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
                            Text('Категория: ' + candidate.category.name),
                            const SizedBox(height: 4),
                            SelectableText('Цитата: ' + candidate.quote),
                            const SizedBox(height: 4),
                            Text('Проверить: ' + candidate.uncertainty),
                          ],
                        ),
                        leading: const Icon(Icons.fact_check_outlined),
                      ),
                    ),
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
