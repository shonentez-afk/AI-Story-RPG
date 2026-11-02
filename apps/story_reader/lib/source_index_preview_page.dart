import 'dart:async';

import 'package:flutter/material.dart';

import 'book_import.dart';
import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'book_isolate_workers.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_narrative_review_panel.dart';
import 'source_semantic_review_panel.dart';

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

  /// Deterministic test seams. Production uses top-level compute workers.
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
  bool _showChapters = false;
  int _candidatePage = 0;
  static const int _candidatesPerPage = 10;
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
    _showChapters = false;
    _candidatePage = 0;
    final book = widget.book;
    final worker = widget.indexer;
    _result = worker == null
        ? indexImportedBookInWorker(book)
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
              ? await decodeSourceAnalysisInWorker(index, checkpoint)
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
        ? await encodeSourceAnalysisInWorker(candidate)
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
          ? await processSourceBatchInWorker(index, current, limit: 24)
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
        title: const Text('Сбросить найденные имена и места?'),
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
            child: const Text('Сбросить поиск имён'),
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


  /// User-oriented explanation of the actual, currently supported pipeline.
  /// Never confuse a finished source index with a playable bookworld.
  Widget _preparationOverview(BookSourceIndex index) {
    final analysis = _analysis;
    final searchStatus = analysis == null || analysis.processedCount == 0
        ? 'Ещё не запускался'
        : analysis.pendingCount == 0 && analysis.failedCount == 0
            ? 'Поиск завершён, находки требуют проверки'
            : 'Просмотрено ${analysis.processedCount} из ${index.chunks.length} фрагментов';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Что делает подготовка?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Задача этого раздела — постепенно собрать проверенные '
              'сведения из книги для будущей текстовой RPG. '
              'В этой сборке мы пока анализируем текст: '
              'готовой игры из вашей книги ещё не создаём.',
            ),
            const SizedBox(height: 14),
            _preparationStep('1', 'Разобрать текст — готово',
                'Найдены ${index.chapterCount} разделов и '
                '${index.chunks.length} текстовых фрагментов. '
                'Иллюстрации пока не анализируются.'),
            _preparationStep('2', 'Найти имена и места',
                searchStatus + '. Используются простые правила, '
                'поэтому часть героев и мест может быть пропущена.'),
            const SizedBox(height: 8),
            _preparationStep('3', 'Проверить найденное',
                'Можно проверить упоминания, возможные события, '
                'противоречия и связи. Это отдельные действия ниже, '
                'а не подтверждённый сюжет.'),
            const SizedBox(height: 8),
            _preparationStep('4', 'Создать игровую историю — пока недоступно',
                'Генерация сцен, игровых выборов и альтернативного сюжета '
                'ещё разрабатывается. Завершение анализа не создаёт RPG.'),
            const SizedBox(height: 12),
            const Text(
              'Весь текущий анализ работает без отправки текста в облако. '
              'Книга, положение чтения и игровые сохранения не изменяются.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _preparationStep(String number, String title, String detail) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text('$number.',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _analysisControls(BookSourceIndex index) {
    final analysis = _analysis;
    final error = _analysisError;
    final pending = analysis?.pendingCount ?? index.chunks.length;
    final processed = analysis?.processedCount ?? 0;
    final total = index.chunks.length;
    final acceptedCount = analysis?.mentions.where(
        (item) => item.decision == MentionDecision.accepted).length ?? 0;
    final rejectedCount = analysis?.mentions.where(
        (item) => item.decision == MentionDecision.rejected).length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Шаг 2. Поиск имён персонажей и мест',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Нажмите «Начать поиск», чтобы найти выражения вроде '
          '«его звали …» и «в городе …». '
          'Поиск не распознаёт всех героев и не понимает сюжет. '
          'Найденные слова нужно проверить вручную.',
        ),
        const SizedBox(height: 10),
        Text('Обработано фрагментов: $processed из $total'),
        LinearProgressIndicator(value: total == 0 ? 0 : processed / total),
        const SizedBox(height: 6),
        Text('Осталось фрагментов: $pending · Ошибок: '
            '${analysis?.failedCount ?? 0}'),
        Text('Найдено упоминаний: ${analysis?.mentions.length ?? 0} · '
            'Принято: ${acceptedCount} · Отклонено: ${rejectedCount} · '
            'На проверку: ${analysis?.reviewCount ?? 0}'),
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
        const Text('За одно нажатие проверяется не более 24 фрагментов. '
            'При большой книге используйте кнопку повторно.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || _loadingAnalysis ||
                  analysis == null || pending == 0 ? null : _processBatch,
              icon: const Icon(Icons.manage_search),
              key: const Key('prepare-search-mentions'),
              label: Text(_busy
                  ? 'Сохраняем результаты…'
                  : pending == 0 && analysis?.failedCount == 0
                      ? 'Поиск имён и мест завершён'
                      : processed == 0 ? 'Начать поиск имён и мест'
                          : 'Продолжить поиск имён и мест'),
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
              label: const Text('Сбросить поиск имён'),
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
                : 'Проверить найденные имена (возможны спойлеры)'),
          ),
          if (!_showCandidates)
            const Text('Находки скрыты до вашего выбора. '
                'Вы отмечаете, правильно ли распознан тип: '
                'имя персонажа или название места. Это не проверка канона.'),
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
        final allPending = analysis?.mentions
            .where((mention) => mention.decision == MentionDecision.review)
            .toList() ?? <SourceMention>[];
        final pageCount = allPending.isEmpty
            ? 1 : (allPending.length + _candidatesPerPage - 1) ~/
                _candidatesPerPage;
        final page = _candidatePage.clamp(0, pageCount - 1).toInt();
        final pendingReview = allPending
            .skip(page * _candidatesPerPage)
            .take(_candidatesPerPage)
            .toList();
        // Preserve the lazy chapter list on large books, but hide it until
        // explicitly requested. Source text is NEVER copied into this UI.
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
                        const SizedBox(height: 12),
                        _preparationOverview(index),
                        const SizedBox(height: 18),
                        _analysisControls(index),
                        if (_showCandidates && allPending.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Проверка найденных слов',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Непроверенных упоминаний: ${allPending.length}. '
                              'Выбирайте только подходящие имена и места. '
                              'Это ещё не объединяет персонажей и не '
                              'подтверждает сюжетные события.'),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_showCandidates && pendingReview.isNotEmpty)
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
                              Text('${kindLabel} · '
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
                                  child: Text(mention.kind == 'CHARACTER_NAME'
                                      ? 'Это имя персонажа'
                                      : 'Это название места'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (_showCandidates && allPending.length > _candidatesPerPage)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton(
                            key: const Key('prepare-review-prev'),
                            onPressed: page == 0 ? null :
                                () => setState(() => _candidatePage = page - 1),
                            child: const Text('Назад к находкам'),
                          ),
                          Text('Страница ${page + 1} из ${pageCount}'),
                          OutlinedButton(
                            key: const Key('prepare-review-next'),
                            onPressed: page + 1 >= pageCount ? null :
                                () => setState(() => _candidatePage = page + 1),
                            child: const Text('Другие находки'),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 28),
                        Text('Шаг 3. Проверка событий, фактов и связей',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('Откройте этот раздел, чтобы найти '
                            'отдельные фразы о событиях и сопоставить '
                            'их с текстом. Вы сами решаете, какие цитаты '
                            'сохранить для последующей проверки. '
                            'Внутри есть раздел связей персонажей и хронологии.'),
                        const SizedBox(height: 10),
                        SourceNarrativeReviewPanel(
                          key: ValueKey(index.sourceFingerprint),
                          index: index,
                          sourceMentions: _analysis,
                        ),
                        const Divider(height: 28),
                        ExpansionTile(
                          key: ValueKey('prepare-experimental-${index.sourceFingerprint}'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          leading: const Icon(Icons.science_outlined),
                          title: const Text('Дополнительно: экспериментальный поиск'),
                          subtitle: const Text('Повторно ищет отдельные имена '
                              'и места; это не полноценный ИИ. '
                              'Для обычной подготовки необязателен.'),
                          children: [
                            SourceSemanticReviewPanel(
                              key: ValueKey('semantic-${index.sourceFingerprint}'),
                              index: index,
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Создать RPG по этой книге'),
                            subtitle: const Text('Пока недоступно: нужны '
                                'проверенные игровые сцены, развилки и '
                                'сценарный компилятор. Даже полный '
                                'поиск по книге не создаёт игровую историю.'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ExpansionTile(
                          key: const Key('prepare-source-details'),
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Технические сведения о книге'),
                          subtitle: const Text('Индексация, фрагменты '
                              'и иллюстрации — для диагностики'),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Глав с текстом: '
                                      '${index.indexedChapterCount} из ${index.chapterCount}'),
                                  Text('Индексировано символов: '
                                      '${index.indexedTextUtf16} из '
                                      '${index.totalTextUtf16}'),
                                  Text('Текстовое покрытие индекса: '
                                      '${(index.textIndexCoverage * 100).toStringAsFixed(1)}%'),
                                  Text('Изображений на проверку: '
                                      '${index.unindexedMediaBlocks}'),
                                  Text('Фрагментов: ${index.chunks.length}'),
                                  const Text('Покрытие индекса не означает '
                                      'готовность сюжетной RPG.'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          key: const Key('prepare-show-chapters'),
                          onPressed: () => setState(
                              () => _showChapters = !_showChapters),
                          icon: Icon(_showChapters
                              ? Icons.expand_less : Icons.expand_more),
                          label: Text(_showChapters
                              ? 'Скрыть разделы книги'
                              : 'Показать разделы книги '
                                  '(${index.chapters.length})'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showChapters)
                  SliverList.builder(
                    itemCount: index.chapters.length,
                    itemBuilder: (context, i) {
                      final chapter = index.chapters[i];
                      final done = chapterProgress[i];
                      return ListTile(
                        title: Text('Глава ${chapter.chapterIndex + 1}'),
                        subtitle: Text(
                          'Фрагментов: ${chapter.sourceChunks} · '
                          'Статус поиска: ${done} из ${chapter.sourceChunks}' +
                              (chapter.hasUnindexedMedia
                                  ? ' · Иллюстрации не проанализированы'
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
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    ),
  );
}
