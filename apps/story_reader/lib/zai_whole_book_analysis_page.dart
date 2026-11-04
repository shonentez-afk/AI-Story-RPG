import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_connection_settings_page.dart';
import 'book_source_index.dart';
import 'source_semantic_provider.dart';
import 'zai_auto_whole_book_analysis.dart';
import 'zai_semantic_preview.dart';

/// User-facing, opt-in book-wide preparation. This screen DOES NOT publish a
/// game or silently send excerpts when opened. It uses the exact source
/// index already opened in the local library and the private M2g2 checkpoint.
class ZaiWholeBookAnalysisPage extends StatefulWidget {
  const ZaiWholeBookAnalysisPage({
    super.key,
    required this.index,
    this.analysis,
  });

  final BookSourceIndex index;
  final ZaiAutoWholeBookAnalysis? analysis;

  @override
  State<ZaiWholeBookAnalysisPage> createState() =>
      _ZaiWholeBookAnalysisPageState();
}

class _ZaiWholeBookAnalysisPageState extends State<ZaiWholeBookAnalysisPage> {
  late final ZaiAutoWholeBookAnalysis _analysis =
      widget.analysis ?? ZaiAutoWholeBookAnalysis();
  late final ZaiWholeBookConsentManifest _manifest =
      ZaiWholeBookConsentManifest.fromIndex(widget.index);

  ZaiWholeBookReviewResult? _review;
  ZaiWholeBookProgress? _progress;
  ZaiPreviewCancellation? _cancellation;
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _notice;
  static const int _batchSize = 12;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    // Do not start another request after the user leaves this route.
    // A POST already in flight cannot be recalled from the provider.
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final review = await _analysis.read(widget.index);
      if (!mounted) return;
      setState(() {
        _review = review;
        _progress = review.progress;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось восстановить подготовку книги: $error';
      });
    }
  }

  Future<bool?> _requestConsent(int batchCount) async {
    var accepted = false;
    var includeTitle = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: !_working,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Разрешить анализ книги через Z.ai?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Книга: «${_manifest.bookTitle}»'),
              Text('Глав: ${_manifest.chapters}. '
                  'Всего текстовых частей: ${_manifest.plannedRequests}.'),
              const SizedBox(height: 8),
              Text('Сейчас будет передано до $batchCount частей '
                  'текста книги. Каждая часть — до 5000 символов; '
                  'при временных ошибках возможны повторные запросы '
                  '(до ${batchCount * ZaiSemanticPreviewService.maxAttempts} '
                  'попыток суммарно).'),
              const SizedBox(height: 8),
              const Text('Внешний сервис Z.ai получит содержимое '
                  'выбранных фрагментов книги. Продолжение обработки '
                  'потребует нового подтверждения. Проверьте тариф и '
                  'лимиты своего аккаунта: запросы могут тарифицироваться.'),
              const SizedBox(height: 8),
              const Text('Исходный файл, прежние прохождения и ключ API '
                  'останутся на устройстве. Остановить отправку '
                  'следующих частей можно в любой момент. '
                  'Уже отправленный текст невозможно отозвать у провайдера.'),
              CheckboxListTile(
                key: const Key('whole-book-include-title'),
                title: const Text('Дополнительно передавать название книги'),
                subtitle: const Text('Не обязательно для анализа цитат.'),
                value: includeTitle,
                onChanged: (value) =>
                    change(() => includeTitle = value == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                key: const Key('whole-book-confirm-send'),
                title: const Text('Я разрешаю передачу указанных частей '
                    'текста книги в Z.ai для личного анализа'),
                value: accepted,
                onChanged: (value) =>
                    change(() => accepted = value == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const Text('Это подготовка, а не готовая игра. '
                  'Ответы ИИ будут сохранены как неподтверждённые '
                  'предложения событий и персонажей.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('whole-book-approve'),
              onPressed: accepted
                  ? () => Navigator.pop(context, includeTitle)
                  : null,
              child: const Text('Начать анализ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendNext() async {
    final review = _review;
    if (_loading || _working || review == null || review.complete) return;
    final count = math.min(_batchSize, review.progress.remaining);
    final includeTitle = await _requestConsent(count);
    if (includeTitle == null || !mounted) return;
    final cancel = ZaiPreviewCancellation();
    setState(() {
      _working = true;
      _cancellation = cancel;
      _error = null;
      _notice = null;
    });
    try {
      final next = await _analysis.analyze(
        index: widget.index,
        approvedManifestDigest: _manifest.approvalDigest,
        explicitWholeBookConsent: true,
        consentForBookTitle: includeTitle,
        maxWindowsPerRun: count,
        cancellation: cancel,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _review = next;
        _progress = next.progress;
        _notice = next.complete
            ? 'Все текстовые части отправлены и ответы проверены. '
              'Это ещё не готовый сценарий RPG.'
            : 'Часть книги проверена и сохранена. Можно продолжить.';
      });
    } catch (error) {
      if (!mounted) return;
      // A failed window leaves the last successfully persisted checkpoint.
      // Read back exact progress instead of reporting unpersisted in-memory state.
      try {
        final saved = await _analysis.read(widget.index);
        if (!mounted) return;
        setState(() {
          _review = saved;
          _progress = saved.progress;
          _error = cancel.isCancelled
              ? 'Анализ остановлен. Уже полученные ответы сохранены.'
              : 'Анализ прервался: $error. '
                'Уже проверенные части сохранены, их не нужно отправлять снова.';
        });
      } catch (restoreError) {
        if (!mounted) return;
        setState(() => _error = 'Ошибка сохранённого анализа: $restoreError');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final review = _review;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Анализ всей книги'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(_manifest.bookTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('ИИ выделяет события, персонажей и факты '
                'в последовательных частях текста. На этом этапе '
                'он не сочиняет готовую RPG и не меняет '
                'книгу или уже начатые игры.'),
            const SizedBox(height: 12),
            Text('Глав: ${_manifest.chapters} · '
                'окон анализа: ${_manifest.plannedRequests}'),
            Text('Объём текста для отправки за весь анализ: '
                'около ${(_manifest.sourceUtf8Bytes / 1024).ceil()} КиБ.'),
            const SizedBox(height: 12),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const Text('Проверяем сохранённые результаты…'),
            ] else if (progress != null) ...[
              Text('Обработано: ${progress.completed} из ${progress.total}',
                  key: const Key('whole-book-progress-label')),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress.total == 0
                    ? 0 : progress.completed / progress.total,
              ),
              const SizedBox(height: 6),
              Text('Предложений: ${progress.candidates}, '
                  'событий: ${progress.eventProposals}. '
                  'Пока ни одно из них не утверждено как канон.'),
              const SizedBox(height: 18),
              if (!_working && !review!.complete)
                FilledButton.icon(
                  key: const Key('whole-book-start'),
                  onPressed: _sendNext,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(progress.completed == 0
                      ? 'Начать проверку через Z.ai'
                      : 'Продолжить анализ книги'),
                ),
              if (_working) ...[
                OutlinedButton.icon(
                  key: const Key('whole-book-stop'),
                  onPressed: () {
                    _cancellation?.cancel();
                    setState(() => _notice =
                        'Останавливаем следующие запросы. '
                        'Уже отправленный запрос может завершиться.');
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Остановить'),
                ),
                const SizedBox(height: 8),
                const Text('Результаты сохраняются после каждой '
                    'успешной части. Приложение должно оставаться открытым.'),
              ],
              if (review!.complete) ...[
                const Icon(Icons.check_circle_outline, size: 32),
                const Text('Анализ всех выбранных частей завершён.'),
                const Text('Следующий этап — проверка связей, '
                    'причинных развилок и компиляция сценария. '
                    'Не путайте завершение анализа с готовой игрой.'),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('whole-book-settings'),
              onPressed: _working ? null : () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => const AiConnectionSettingsPage(),
                ));
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Настроить ключ Z.ai'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('whole-book-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
              if (_review == null)
                OutlinedButton(
                  onPressed: _load,
                  child: const Text('Повторить загрузку'),
                ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Text(_notice!, key: const Key('whole-book-notice')),
            ],
          ],
        ),
      ),
    );
  }
}
