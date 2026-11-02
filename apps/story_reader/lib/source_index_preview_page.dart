import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'book_import.dart';
import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';

/// The single preparation page already opened from Library. M2b2 adds local
/// evidence review here, not a second library/import or an unverified RPG.
class SourceIndexPreviewPage extends StatefulWidget {
  const SourceIndexPreviewPage({
    super.key,
    required this.book,
    this.indexer,
    this.checkpointRepository,
    this.batchProcessor,
    this.checkpointEncoder,
    this.checkpointDecoder,
  });

  final ImportedBook book;

  /// Test seam. Production indexing and analysis use worker isolates.
  final Future<BookSourceIndex> Function(ImportedBook)? indexer;
  final SourceAnalysisCheckpointRepository? checkpointRepository;

  /// Deterministic test seams. Production uses Isolate.run.
  final Future<SourceAnalysisSession> Function(
      BookSourceIndex, SourceAnalysisSession)? batchProcessor;
  final Future<String> Function(SourceAnalysisSession)? checkpointEncoder;
  final Future<SourceAnalysisSession> Function(
      BookSourceIndex, String)? checkpointDecoder;

  @override
  State<SourceIndexPreviewPage> createState() =>
      _SourceIndexPreviewPageState();
}

class _SourceIndexPreviewPageState extends State<SourceIndexPreviewPage> {
  late Future<BookSourceIndex> _result;
  late final SourceAnalysisCheckpointRepository _repository =
      widget.checkpointRepository ??
      const FileSourceAnalysisCheckpointRepository();

  BookSourceIndex? _index;
  SourceAnalysisSession? _analysis;
  String? _analysisError;
  bool _loadingAnalysis = false;
  bool _busy = false;
  bool _showCandidates = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _buildIndex();
  }

  void _buildIndex() {
    final generation = ++_generation;
    _index = null;
    _analysis = null;
    _analysisError = null;
    _loadingAnalysis = false;
    _showCandidates = false;
    final book = widget.book;
    final worker = widget.indexer;
    _result = worker == null
        ? Isolate.run(() => BookSourceIndexer.index(book))
        : worker(book);
    _result.then((index) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _index = index;
        _loadingAnalysis = true;
      });
      unawaited(_loadAnalysis(index, generation));
    }, onError: (Object error, StackTrace stack) {
      // FutureBuilder displays indexing failures. Do not persist anything.
    });
  }

  Future<void> _loadAnalysis(BookSourceIndex index, int generation) async {
    try {
      final checkpoint = await _repository.read(index.sourceFingerprint);
      final decoder = widget.checkpointDecoder;
      final restored = checkpoint == null
          ? SourceAnalysisSession.create(index)
          : decoder == null
              ? await Isolate.run(
                  () => SourceAnalysisSession.decode(index, checkpoint),
                )
              : await decoder(index, checkpoint);
      if (!mounted || generation != _generation) return;
      setState(() {
        _analysis = restored;
        _analysisError = null;
        _loadingAnalysis = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _analysisError = 'Не удалось восстановить анализ: $error. '
            'Исходная книга и игровые сохранения не изменены.';
        _loadingAnalysis = false;
      });
    }
  }

  void _retry() => setState(_buildIndex);

  void _retryAnalysis() {
    final index = _index;
    if (index == null || _busy || _loadingAnalysis) return;
    setState(() {
      _loadingAnalysis = true;
      _analysisError = null;
    });
    unawaited(_loadAnalysis(index, _generation));
  }

  /// Publish the new state only AFTER the checkpoint is safely saved. A
  /// failed write leaves the last confirmed progress visible and intact.
  Future<void> _persist(SourceAnalysisSession candidate) async {
    final index = _index!;
    final encoder = widget.checkpointEncoder;
    final encoded = encoder == null
        ? await Isolate.run(() => candidate.encode())
        : await encoder(candidate);
    await _repository.write(index.sourceFingerprint, encoded);
    if (mounted) setState(() => _analysis = candidate);
  }

  Future<void> _processBatch() async {
    final index = _index;
    final current = _analysis;
    if (_busy || index == null || current == null ||
        current.pendingCount == 0) return;
    setState(() {
      _busy = true;
      _analysisError = null;
    });
    try {
      // Never scan a long novel synchronously on the Flutter UI isolate.
      final processor = widget.batchProcessor;
      final updated = processor == null
          ? await Isolate.run(
              () => current.processBatch(index, limit: 24),
            )
          : await processor(index, current);
      await _persist(updated);
    } catch (error) {
      if (mounted) setState(() =>
          _analysisError = 'Не удалось сохранить очередную порцию: $error. '
              'Предыдущий checkpoint сохранён.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryFailed() async {
    final current = _analysis;
    if (_busy || current == null || current.failedCount == 0) return;
    setState(() {
      _busy = true;
      _analysisError = null;
    });
    try {
      await _persist(current.retryFailed());
    } catch (error) {
      if (mounted) setState(() =>
          _analysisError = 'Не удалось восстановить очередь: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(SourceMention mention,
      MentionDecision decision) async {
    final current = _analysis;
    if (_busy || current == null) return;
    setState(() {
      _busy = true;
      _analysisError = null;
    });
    try {
      await _persist(current.decide(mention.id, decision));
    } catch (error) {
      if (mounted) setState(() =>
          _analysisError = 'Не удалось сохранить решение: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetAnalysis() async {
    final index = _index;
    if (index == null || _busy) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Сбросить анализ книги?'),
        content: const Text(
          'Будут удалены только результаты анализа и решения по '
          'упоминаниям этой редакции. Книга, закладки и игровые '
          'прохождения останутся без изменений.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить анализ'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.delete(index.sourceFingerprint);
      if (mounted) setState(() {
        _analysis = SourceAnalysisSession.create(index);
        _analysisError = null;
        _showCandidates = false;
      });
    } catch (error) {
      if (mounted) setState(() =>
          _analysisError = 'Сброс не выполнен: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _contextSnippet(SourceMention mention, BookSourceIndex index) {
    final chunk = index.chunks.firstWhere(
      (candidate) => candidate.id == mention.chunkId,
    );
    final start = (mention.startUtf16 - chunk.startUtf16 - 35)
        .clamp(0, chunk.text.length).toInt();
    final end = (mention.endUtf16 - chunk.startUtf16 + 35)
        .clamp(0, chunk.text.length).toInt();
    return chunk.text.substring(start, end).replaceAll('\n', ' ');
  }

  Widget _analysisControls(BookSourceIndex index) {
    final analysis = _analysis;
    final error = _analysisError;
    final pending = analysis?.pendingCount ?? index.chunks.length;
    final processed = analysis?.processedCount ?? 0;
    final total = index.chunks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Анализ источников · M2b',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Локальный поиск явных упоминаний персонажей и мест. '
          'Все находки требуют ручной проверки. Это не готовый '
          'сюжет, не установленные факты и не игровая история.',
        ),
        const SizedBox(height: 10),
        Text('Обработано фрагментов: $processed из $total'),
        LinearProgressIndicator(value: total == 0 ? 0 : processed / total),
        const SizedBox(height: 6),
        Text('Ожидают: $pending · Ошибок: '
            '${analysis?.failedCount ?? 0} · '
            'Упоминаний на проверку: ${analysis?.reviewCount ?? 0}'),
        if (_loadingAnalysis)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Загружаем сохранённый прогресс анализа…'),
          ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error, style: TextStyle(
            color: Theme.of(context).colorScheme.error,
          )),
          if (analysis == null)
            TextButton.icon(
              onPressed: _retryAnalysis,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить чтение анализа'),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || _loadingAnalysis ||
                  analysis == null || pending == 0 ? null : _processBatch,
              icon: const Icon(Icons.manage_search),
              label: Text(_busy ? 'Сохраняем…' : 'Обработать порцию'),
            ),
            if (analysis != null && analysis.failedCount > 0)
              OutlinedButton.icon(
                onPressed: _busy ? null : _retryFailed,
                icon: const Icon(Icons.replay),
                label: const Text('Повторить ошибки'),
              ),
            OutlinedButton.icon(
              onPressed: _busy || _loadingAnalysis ? null : _resetAnalysis,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Сбросить анализ'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (analysis != null && analysis.reviewCount > 0) ...[
          TextButton.icon(
            onPressed: _busy ? null : () => setState(
              () => _showCandidates = !_showCandidates,
            ),
            icon: Icon(_showCandidates
                ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            label: Text(_showCandidates
                ? 'Скрыть упоминания'
                : 'Показать упоминания (возможны спойлеры)'),
          ),
          if (!_showCandidates)
            const Text('Содержание найденных упоминаний скрыто '
                'до вашего выбора.'),
        ] else if (analysis != null && pending == 0) ...[
          const Text('Явных упоминаний на проверку не осталось. '
              'Это не означает, что все события и персонажи книги '
              'извлечены или проверены.'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подготовка книги')),
    body: FutureBuilder<BookSourceIndex>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Разбиваем исходный текст на проверяемые фрагменты…'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text('Не удалось проиндексировать книгу: '
                        '${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final index = snapshot.requireData;
        final analysis = _analysis;
        final pendingReview = analysis?.mentions
            .where((mention) => mention.decision == MentionDecision.review)
            .take(40).toList() ?? <SourceMention>[];
        // Pre-compute chapter progress once, not O(chunks²) per tile.
        final chapterProgress = List<int>.filled(index.chapters.length, 0);
        if (analysis != null) {
          for (var j = 0; j < analysis.tasks.length; j++) {
            final status = analysis.tasks[j].status;
            if (status == ChunkAnalysisStatus.done ||
                status == ChunkAnalysisStatus.review) {
              chapterProgress[index.chunks[j].chapterIndex]++;
            }
          }
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.book.title,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const Text('Этап M2 — индекс и локальный анализ'),
                        const SizedBox(height: 14),
                        Text('Главы с текстом: '
                            '${index.indexedChapterCount} из ${index.chapterCount}'),
                        Text('Индексировано символов: '
                            '${index.indexedTextUtf16} из ${index.totalTextUtf16}'),
                        Text('Текстовое покрытие индекса: '
                            '${(index.textIndexCoverage * 100).toStringAsFixed(1)}%'),
                        Text('Иллюстраций на отдельную проверку: '
                            '${index.unindexedMediaBlocks}'),
                        const SizedBox(height: 12),
                        const Text(
                          'Это только подготовка исходных фрагментов. '
                          'Персонажи, сюжет и игровые сцены ещё не созданы. '
                          'Готового игрового мира нет; текст никуда не отправлялся.',
                        ),
                        const SizedBox(height: 12),
                        Text('Фрагментов на последующий анализ: '
                            '${index.chunks.length}'),
                        const Divider(height: 28),
                        _analysisControls(index),
                        const Divider(height: 28),
                        Text('Разделы произведения',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: index.chapters.length,
                  itemBuilder: (context, i) {
                    final chapter = index.chapters[i];
                    final done = chapterProgress[i];
                    return ListTile(
                      title: Text('Глава ${chapter.chapterIndex + 1}'),
                      subtitle: Text(
                        'Фрагментов: ${chapter.sourceChunks} · '
                        'Статус анализа: $done из ${chapter.sourceChunks}' +
                            (chapter.hasUnindexedMedia
                                ? ' · Иллюстрации требуют проверки'
                                : ''),
                      ),
                      leading: Icon(
                        chapter.fullyIndexed
                            ? Icons.check_circle_outline
                            : Icons.report_gmailerrorred_outlined,
                      ),
                    );
                  },
                ),
                if (_showCandidates && pendingReview.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Кандидаты на проверку · первые '
                        '${pendingReview.length} из ${analysis!.reviewCount}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                if (_showCandidates)
                  SliverList.builder(
                    itemCount: pendingReview.length,
                    itemBuilder: (context, i) {
                      final mention = pendingReview[i];
                      final kindLabel = mention.kind == 'CHARACTER_NAME'
                          ? 'Имя персонажа' : 'Название места';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(mention.label,
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text('$kindLabel · '
                                  'глава ${mention.chapterIndex + 1}, '
                                  'блок ${mention.blockIndex + 1}'),
                              const SizedBox(height: 6),
                              Text(_contextSnippet(mention, index)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                OutlinedButton(
                                  onPressed: _busy ? null : () => _decide(
                                      mention, MentionDecision.rejected),
                                  child: const Text('Отклонить'),
                                ),
                                FilledButton(
                                  onPressed: _busy ? null : () => _decide(
                                      mention, MentionDecision.accepted),
                                  child: const Text('Подтвердить упоминание'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    ),
  );
}
