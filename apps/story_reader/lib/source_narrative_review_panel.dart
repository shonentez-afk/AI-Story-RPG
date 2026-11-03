import 'dart:async';

import 'package:flutter/material.dart';

import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_extractor.dart';
import 'story_evidence_review_session.dart';
import 'book_isolate_workers.dart';
import 'source_relations_review_panel.dart';

/// A collapsible addition to the EXISTING preparation page. Opening this
/// section is explicit: it does not load checkpoints or reveal spoilers until
/// the user chooses to inspect story evidence.
class SourceNarrativeReviewPanel extends StatefulWidget {
  const SourceNarrativeReviewPanel({
    super.key,
    required this.index,
    this.sourceMentions,
    this.checkpointRepository,
    this.scanProcessor,
    this.checkpointEncoder,
    this.checkpointDecoder,
  });

  final BookSourceIndex index;
  final SourceAnalysisSession? sourceMentions;
  final SourceAnalysisCheckpointRepository? checkpointRepository;

  /// Injectable deterministic seams; native production work uses isolates.
  final Future<StoryEvidenceReviewSession> Function(
      BookSourceIndex, StoryEvidenceReviewSession)? scanProcessor;
  final Future<String> Function(StoryEvidenceReviewSession)? checkpointEncoder;
  final Future<StoryEvidenceReviewSession> Function(
      BookSourceIndex, String)? checkpointDecoder;

  @override
  State<SourceNarrativeReviewPanel> createState() =>
      _SourceNarrativeReviewPanelState();
}

class _SourceNarrativeReviewPanelState
    extends State<SourceNarrativeReviewPanel> {
  late final SourceAnalysisCheckpointRepository _repository =
      widget.checkpointRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.narrativeEvidence,
      );

  StoryEvidenceReviewSession? _review;
  bool _expanded = false;
  bool _showSpoilers = false;
  int _visiblePending = 12;
  bool _busy = false;
  bool _pause = false;
  bool _needsSync = false;
  String? _error;

  @override
  void didUpdateWidget(covariant SourceNarrativeReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceMentions != widget.sourceMentions &&
        _expanded && _review != null) {
      if (_busy) {
        _needsSync = true;
      } else {
        unawaited(_syncMentions());
      }
    }
  }

  Future<void> _persist(StoryEvidenceReviewSession next) async {
    final encoder = widget.checkpointEncoder;
    final raw = encoder == null
        ? await encodeNarrativeEvidenceInWorker(next)
        : await encoder(next);
    await _repository.write(widget.index.sourceFingerprint, raw);
    if (mounted) setState(() => _review = next);
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _expanded = true;
      _busy = true;
      _error = null;
      _showSpoilers = false;
      _visiblePending = 12;
    });
    try {
      final raw = await _repository.read(widget.index.sourceFingerprint);
      final decoder = widget.checkpointDecoder;
      final restored = raw == null
          ? StoryEvidenceReviewSession.create(widget.index)
          : decoder == null
              ? await decodeNarrativeEvidenceInWorker(widget.index, raw)
              : await decoder(widget.index, raw);
      final updated = restored.syncAcceptedMentions(
          widget.index, widget.sourceMentions);
      if (!identical(restored, updated)) {
        await _persist(updated);
      } else if (mounted) {
        setState(() => _review = restored);
      }
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Невозможно прочитать проверку утверждений: $error. '
              'Книги и игровые сохранения не затронуты.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_needsSync && _review != null) {
          _needsSync = false;
          unawaited(_syncMentions());
        }
      }
    }
  }

  Future<void> _syncMentions() async {
    final current = _review;
    if (current == null || !_expanded) return;
    if (_busy) {
      _needsSync = true;
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = current.syncAcceptedMentions(
          widget.index, widget.sourceMentions);
      if (!identical(current, next)) await _persist(next);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Не удалось сохранить новые упоминания: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Analyze all remaining chunks in bounded worker batches; every batch is
  /// persisted BEFORE UI progress advances. Pausing or leaving the page
  /// stops after the current batch, not after a remote/background operation.
  Future<void> _scanAll() async {
    if (_busy || _review == null) return;
    setState(() {
      _busy = true;
      _pause = false;
      _error = null;
    });
    try {
      var current = _review!.syncAcceptedMentions(
          widget.index, widget.sourceMentions);
      if (!identical(current, _review)) await _persist(current);
      while (mounted && _expanded && !_pause &&
          current.scannedChunks < widget.index.chunks.length) {
        final worker = widget.scanProcessor;
        final next = worker == null
            ? await scanNarrativeEvidenceInWorker(widget.index, current, limit: 24)
            : await worker(widget.index, current);
        if (next.scannedChunks <= current.scannedChunks ||
            next.sourceFingerprint != current.sourceFingerprint) {
          throw const FormatException('Ошибка прогресса анализа');
        }
        await _persist(next);
        current = next;
        // Give Flutter a chance to render, handle Pause and navigation.
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Анализ прерван: $error. '
              'Последняя успешно сохранённая порция сохранена.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_needsSync) {
          _needsSync = false;
          unawaited(_syncMentions());
        }
      }
    }
  }

  Future<void> _reviewEvidence(
      SourceEvidence evidence, EvidenceStatus status) async {
    final current = _review;
    if (_busy || current == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = current.syncAcceptedMentions(
          widget.index, widget.sourceMentions);
      await _persist(next.review(widget.index, evidence.id, status));
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Решение не сохранено: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_needsSync) {
          _needsSync = false;
          unawaited(_syncMentions());
        }
      }
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Сбросить проверку утверждений?'),
        content: const Text(
          'Будут удалены только извлечённые кандидаты, отметки о '
          'фактах и событиях этой редакции и прогресс их проверки. '
          'Книга, упоминания M2b1 и игровые сохранения останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить проверку'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.delete(widget.index.sourceFingerprint);
      if (mounted) setState(() {
        _review = StoryEvidenceReviewSession.create(widget.index)
            .syncAcceptedMentions(widget.index, widget.sourceMentions);
        _showSpoilers = false;
        _error = null;
      });
      // The accepted M2b1 mentions are imported as INFERRED in memory;
      // they are persisted on the next successful review/scan.
    } catch (error) {
      if (mounted) setState(() => _error = 'Сброс не выполнен: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kind(EvidenceKind kind) => switch (kind) {
    EvidenceKind.character => 'Имя персонажа',
    EvidenceKind.location => 'Название места',
    EvidenceKind.fact => 'Возможный факт',
    EvidenceKind.event => 'Возможное событие',
  };

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (!_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Проверка фраз о событиях и фактах',
              style: text.titleMedium),
          const SizedBox(height: 6),
          const Text('Отдельная локальная проверка книги. '
              'Возможны спойлеры; все находки — предположения.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Открыть проверку утверждений'),
          ),
        ],
      );
    }
    final pendingAll = review?.graph.records.where(
        (e) => e.status == EvidenceStatus.inferred).toList()
        ?? <SourceEvidence>[];
    final pending = pendingAll.take(_visiblePending).toList();
    final complete = review != null &&
        review.scannedChunks >= widget.index.chunks.length;
    final conflicts = _showSpoilers && review != null
        ? SourceNarrativeExtractor.possibleConflicts(review.graph,
            limit: 20)
        : <PossibleStateConflict>[];
    final aliases = _showSpoilers && review != null
        ? SourceNarrativeExtractor.explicitAliasHints(
            widget.index, review.graph, limit: 15)
        : <PossibleAliasRelation>[];
    final matches = _showSpoilers && review != null
        ? review.graph.possibleCrossChapterMatches.take(5).toList()
        : <PossibleEntityMatch>[];
    final recordsById = <String, SourceEvidence>{
      if (_showSpoilers && review != null)
        for (final evidence in review.graph.records) evidence.id: evidence,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Проверка фраз о событиях и фактах',
            style: text.titleMedium),
        const SizedBox(height: 6),
        const Text('Офлайн-кандидаты с точными ссылками на текст. '
            'Подтверждение означает только проверку цитаты, '
            'а не истинность утверждения или готовность игровой сцены.'),
        const SizedBox(height: 10),
        Text('Проверено фрагментов: ${review?.scannedChunks ?? 0} '
            'из ${widget.index.chunks.length}'),
        LinearProgressIndicator(
          value: widget.index.chunks.isEmpty
              ? 0 : (review?.scannedChunks ?? 0) / widget.index.chunks.length,
        ),
        const SizedBox(height: 6),
        Text('Кандидатов: ${review?.graph.records.length ?? 0} · '
            'Ожидают проверки: ${review?.pendingReviewCount ?? 0}'),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить загрузку'),
          ),
        ],
        if (_busy && review == null) const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Читаем сохранённый анализ…'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: review == null || _busy || complete
                  ? null : _scanAll,
              icon: const Icon(Icons.play_arrow),
              label: Text(complete
                  ? 'Поиск завершён'
                  : _busy ? 'Анализируем…' : 'Продолжить поиск'),
            ),
            if (_busy && review != null)
              OutlinedButton.icon(
                onPressed: () => setState(() => _pause = true),
                icon: const Icon(Icons.pause),
                label: Text(_pause ? 'Останавливаем…' : 'Пауза'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Сбросить проверку'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _expanded = false;
                _showSpoilers = false;
                _pause = true;
              }),
              child: const Text('Свернуть раздел'),
            ),
          ],
        ),
        // A book with zero regex candidates still has chapters and an
        // editorial chronology. Do not hide that workflow as 'unavailable'.
        if (review != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null :
                () => setState(() => _showSpoilers = !_showSpoilers),
            icon: Icon(_showSpoilers
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            label: Text(_showSpoilers
                ? 'Скрыть сведения'
                : 'Показать утверждения (возможны спойлеры)'),
          ),
          if (!_showSpoilers)
            const Text('Цитаты и предполагаемые связи скрыты до '
                'вашего выбора.'),
        ],
        if (_showSpoilers && review != null) ...[
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Возможные расхождения или изменения состояния',
                style: text.titleSmall),
            const Text('Разные главы могут описывать изменение '
                'ситуации во времени — это не доказанное противоречие.'),
            for (final hint in conflicts.take(3))
              Text('«${recordsById[hint.firstId]?.label ?? ""}» / '
                  '«${recordsById[hint.secondId]?.label ?? ""}»'),
          ],
          if (aliases.isNotEmpty || matches.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Возможные связи персонажей и мест',
                style: text.titleSmall),
            const Text('Ни одна пара имён не объединена автоматически.'),
            for (final hint in aliases.take(3))
              Text('${hint.firstName} — ${hint.secondName}: '
                  'совпадение из текста, требуется проверка'),
            for (final hint in matches.take(3))
              Text('${hint.normalizedName}: '
                  'повторяется в разных главах, личность не установлена'),
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Непроверенные цитаты · показано ${pending.length} '
                'из ${pendingAll.length}',
                style: text.titleSmall),
            for (final candidate in pending)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(candidate.label, style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text('${_kind(candidate.kind)} · '
                          'глава ${candidate.chapterIndex + 1}, '
                          'блок ${candidate.blockIndex + 1}'),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        OutlinedButton(
                          onPressed: _busy ? null :
                              () => _reviewEvidence(candidate,
                                  EvidenceStatus.rejected),
                          child: const Text('Отклонить цитату'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null :
                              () => _reviewEvidence(candidate,
                                  EvidenceStatus.conflicted),
                          child: const Text('Пометить спорным'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null :
                              () => _reviewEvidence(candidate,
                                  EvidenceStatus.confirmed),
                          child: const Text('Подтвердить текст'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            if (pending.length < pendingAll.length)
              OutlinedButton.icon(
                key: const Key('narrative-show-more-pending'),
                onPressed: _busy ? null : () => setState(
                    () => _visiblePending += 12),
                icon: const Icon(Icons.expand_more),
                label: Text('Показать ещё цитаты (${pending.length} '
                    'из ${pendingAll.length})'),
              ),
          ] else
            const Text('Нет новых цитат для ручной проверки. '
                'Это не означает, что сюжетная модель готова.'),
          SourceRelationsReviewPanel(
            key: ValueKey(widget.index.sourceFingerprint),
            index: widget.index,
            graph: review.graph,
          ),
        ],
      ],
    );
  }
}
