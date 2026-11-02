import 'package:flutter/material.dart';

import 'book_isolate_workers.dart';
import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_provider.dart';
import 'source_semantic_review.dart';

/// A collapsible panel on the EXISTING "Подготовка книги" page.
/// No automatic cloud requests, NPC canon, or second import/library screen.
class SourceSemanticReviewPanel extends StatefulWidget {
  const SourceSemanticReviewPanel({
    super.key,
    required this.index,
    this.checkpointRepository,
    this.batchProcessor,
    this.checkpointEncoder,
    this.checkpointDecoder,
  });

  final BookSourceIndex index;
  final SourceAnalysisCheckpointRepository? checkpointRepository;

  /// Production uses a top-level compute worker. Test seams never cross
  /// a BuildContext/State into the isolate.
  final Future<SemanticReviewSession> Function(
      BookSourceIndex, SemanticReviewSession)? batchProcessor;
  final Future<String> Function(SemanticReviewSession)? checkpointEncoder;
  final Future<SemanticReviewSession> Function(
      BookSourceIndex, String)? checkpointDecoder;

  @override
  State<SourceSemanticReviewPanel> createState() =>
      _SourceSemanticReviewPanelState();
}

class _SourceSemanticReviewPanelState extends State<SourceSemanticReviewPanel> {
  late final SourceAnalysisCheckpointRepository _repository =
      widget.checkpointRepository ??
          const FileSourceAnalysisCheckpointRepository(
            scope: SourceCheckpointScope.semanticProposals,
          );

  static const _provider = OfflineRuleProvider();
  SemanticReviewSession? _session;
  bool _expanded = false;
  bool _showQuotes = false;
  bool _busy = false;
  bool _pause = false;
  String? _error;
  int _generation = 0;
  int _page = 0;
  static const _pageSize = 12;

  @override
  void didUpdateWidget(covariant SourceSemanticReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index.sourceFingerprint != widget.index.sourceFingerprint) {
      _generation++;
      _session = null;
      _expanded = false;
      _showQuotes = false;
      _page = 0;
      _pause = true;
      _error = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _pause = true;
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    if (_expanded && _session != null) {
      setState(() {
        _expanded = false;
        _showQuotes = false;
        _pause = true;
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _expanded = true;
      _busy = true;
      _error = null;
      _showQuotes = false;
      _page = 0;
    });
    try {
      final raw = await _repository.read(widget.index.sourceFingerprint);
      final restored = raw == null
          ? SemanticReviewSession.create(widget.index, _provider)
          : widget.checkpointDecoder == null
              ? await decodeSemanticReviewInWorker(widget.index, raw)
              : await widget.checkpointDecoder!(widget.index, raw);
      if (!mounted || generation != _generation) return;
      setState(() => _session = restored);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Не удалось восстановить семантический анализ: $error. '
            'Книга, прежние проверки и игровые сохранения не изменены.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _persist(SemanticReviewSession candidate) async {
    final encoded = widget.checkpointEncoder == null
        ? await encodeSemanticReviewInWorker(candidate)
        : await widget.checkpointEncoder!(candidate);
    await _repository.write(widget.index.sourceFingerprint, encoded);
    if (mounted) setState(() => _session = candidate);
  }

  /// Complete batches are saved BEFORE advancing UI. Pause, navigation and
  /// provider failure stop after the current batch, without phantom progress.
  Future<void> _process({required bool all}) async {
    if (_busy || _session == null || _session!.pendingCount == 0) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _pause = false;
      _error = null;
    });
    try {
      var current = _session!;
      do {
        final next = widget.batchProcessor == null
            ? await processSemanticReviewInWorker(widget.index, current)
            : await widget.batchProcessor!(widget.index, current);
        if (!mounted || generation != _generation) return;
        if (identical(next, current)) break;
        await _persist(next);
        current = next;
      } while (all && mounted && generation == _generation &&
          !_pause && _expanded && current.pendingCount > 0);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Анализ остановлен: $error. Последняя успешно сохранённая '
            'порция остаётся доступной.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _decide(String id, SemanticReviewDecision? decision) async {
    if (_busy || _session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _persist(_session!.decide(id, decision));
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Решение не сохранено: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final agree = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Сбросить семантические предложения?'),
        content: const Text(
          'Удалится только результат M2b4a для этой редакции книги. '
          'Исходный текст, предыдущие три проверки, закладки и игровые '
          'сохранения останутся без изменений.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить предложения'),
          ),
        ],
      ),
    );
    if (!mounted || agree != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _pause = true;
    });
    try {
      await _repository.delete(widget.index.sourceFingerprint);
      if (mounted) {
        setState(() {
          _session = SemanticReviewSession.create(widget.index, _provider);
          _showQuotes = false;
          _page = 0;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Сброс не выполнен: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Семантические предложения · M2b4a',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Работает только локальный поиск по явным шаблонам. '
            'Полноценная ИИ-модель ещё не подключена. '
            'Книга не отправляется в сеть и не становится игровой RPG.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('semantic-open'),
          onPressed: _busy ? null : _open,
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(_expanded && session != null
              ? 'Свернуть семантический анализ'
              : 'Открыть локальный анализ'),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          if (_busy && session == null)
            const CircularProgressIndicator(),
          if (_error != null)
            Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error)),
          if (session != null) ...[
            Text('Обработано: ${session.processedCount} из ${session.tasks.length} '
                'фрагментов · Предложений: ${session.candidates.length}'),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: session.tasks.isEmpty
                ? 0 : session.processedCount / session.tasks.length),
            const SizedBox(height: 5),
            Text('На проверку: ${session.undecidedCount} · '
                'Отмечено для проверки: ${session.keptCount}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                key: const Key('semantic-batch'),
                onPressed: _busy || session.pendingCount == 0
                    ? null : () => _process(all: false),
                icon: const Icon(Icons.manage_search),
                label: const Text('Обработать порцию'),
              ),
              if (!_busy)
                OutlinedButton.icon(
                  onPressed: session.pendingCount == 0
                      ? null : () => _process(all: true),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Обработать все'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _pause = true),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Остановить после порции'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Сбросить предложения'),
              ),
            ]),
            if (session.candidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('semantic-reveal'),
                onPressed: _busy ? null : () => setState(
                    () => _showQuotes = !_showQuotes),
                icon: Icon(_showQuotes
                    ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                label: Text(_showQuotes
                    ? 'Скрыть цитаты' : 'Показать цитаты (возможны спойлеры)'),
              ),
              if (!_showQuotes)
                const Text('Цитаты скрыты до явного открытия. '
                    'Все предложения имеют статус INFERRED.'),
              if (_showQuotes)
                ...session.candidates.skip(_page * _pageSize)
                    .take(_pageSize).map((item) {
                  final decision = session.decisions[item.id];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text('${item.category.name} · '
                              'глава ${item.visibleAfterChapter + 1} · '
                              'фрагмент ${item.chunkId}'),
                          SelectableText('Цитата: «${item.quote}»'),
                          Text(item.uncertainty),
                          if (decision != null)
                            Text(decision == SemanticReviewDecision.keptForReview
                                ? 'Отмечено: требует дальнейшей проверки'
                                : 'Отклонено редактором'),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            OutlinedButton(
                              onPressed: _busy ? null : () => _decide(
                                  item.id, SemanticReviewDecision.rejected),
                              child: const Text('Отклонить'),
                            ),
                            FilledButton(
                              onPressed: _busy ? null : () => _decide(
                                  item.id, SemanticReviewDecision.keptForReview),
                              child: const Text('Оставить для проверки'),
                            ),
                            if (decision != null)
                              TextButton(
                                onPressed: _busy ? null : () => _decide(
                                    item.id, null),
                                child: const Text('Отменить решение'),
                              ),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
              if (_showQuotes && session.candidates.length > _pageSize)
                Wrap(spacing: 8, runSpacing: 6, children: [
                  OutlinedButton(
                    key: const Key('semantic-prev'),
                    onPressed: _page == 0 ? null :
                        () => setState(() => _page--),
                    child: const Text('Предыдущие предложения'),
                  ),
                  Text('Страница ${_page + 1} из '
                      '${(session.candidates.length + _pageSize - 1) ~/ _pageSize}'),
                  OutlinedButton(
                    key: const Key('semantic-next'),
                    onPressed: (_page + 1) * _pageSize >= session.candidates.length
                        ? null : () => setState(() => _page++),
                    child: const Text('Следующие предложения'),
                  ),
                ]),
            ],
          ] else if (!_busy) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить загрузку анализа'),
            ),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Сбросить предложения'),
            ),
          ],
          const SizedBox(height: 8),
          const Text('Отмеченное предложение не подтверждает канон. '
              'Для игровой адаптации нужны отдельная проверка событий, '
              'прав и сценарного blueprint.'),
        ],
      ],
    );
  }
}
