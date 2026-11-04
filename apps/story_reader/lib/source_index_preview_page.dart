import 'dart:async';

import 'package:flutter/material.dart';

import 'book_import.dart';
import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'book_isolate_workers.dart';
import 'offline_preparation_coordinator.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_narrative_review_panel.dart';
import 'source_semantic_catalog.dart';
import 'zai_semantic_preview_page.dart';
import 'zai_whole_book_analysis_page.dart';
import 'reviewed_story_editor_page.dart';
import 'quick_rpg_page.dart';
import 'multi_scene_editor_page.dart';
import 'source_editorial_review_page.dart';
import 'private_game_readiness_panel.dart';
import 'world_library_gateway.dart';

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
    this.localPreparationCoordinator,
    this.worldGateway,
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

  /// Optional seam for widget tests; production uses private scoped stores.
  final OfflinePreparationCoordinator? localPreparationCoordinator;
  final WorldLibraryGateway? worldGateway;

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
  bool _offlineWorking = false;
  bool _offlinePause = false;
  OfflinePreparationProgress? _offlineProgress;
  String? _offlineMessage;
  int _narrativeRefresh = 0;
  int _editorReturnRevision = 0;
  bool _openingEditor = false;
  bool _showCandidates = false;
  bool _showChapters = false;
  bool _advancedModeOpen = false;
  int _visibleCandidates = 10;
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
    _offlinePause = true;
    _offlineProgress = null;
    _offlineMessage = null;
    _showCandidates = false;
    _showChapters = false;
    _visibleCandidates = 10;
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

  /// Editors persist independent scoped checkpoints. Recreate quote review
  /// from disk and recheck the installed game only after returning.
  /// Ignore same-frame repeat taps instead of stacking editor routes.
  Future<void> _openEditor(Widget editor) async {
    if (_openingEditor || _offlineWorking || _busy) return;
    _openingEditor = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => editor),
      );
    } finally {
      _openingEditor = false;
      if (mounted) {
        setState(() {
          _narrativeRefresh++;
          _editorReturnRevision++;
        });
      }
    }
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
              'Ранее проверенные результаты сохранены.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Run existing local stages with one button, never a model/network call.
  /// Cancellation occurs at a saved batch boundary and resumes by fingerprint.
  Future<void> _runLocalPreparation() async {
    final index = _index;
    if (_busy || _offlineWorking || _loadingAnalysis ||
        index == null || _analysis == null) return;
    final generation = _generation;
    final coordinator = widget.localPreparationCoordinator ??
        OfflinePreparationCoordinator(
          mentionsRepository: _repository,
          narrativeRepository: const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.narrativeEvidence),
          catalogRepository: const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.semanticCatalog),
        );
    setState(() {
      _offlineWorking = true;
      _offlinePause = false;
      _busy = true;
      _analysisError = null;
      _offlineMessage = 'Локальная подготовка выполняется…';
    });
    try {
      final result = await coordinator.run(index,
          shouldPause: () => _offlinePause ||
              !mounted || generation != _generation,
          onProgress: (progress) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _offlineProgress = progress;
              if (progress.mentions != null) {
                _analysis = progress.mentions;
              }
            });
          });
      if (!mounted || generation != _generation) return;
      final assertions = result.catalog?.assertions ?? const <SourceSemanticAssertion>[];
      final eventCount = assertions
          .where((item) => item.kind == SemanticAssertionKind.event).length;
      setState(() {
        _analysis = result.mentions;
        _narrativeRefresh++;
        _offlineMessage = result.paused
            ? 'Остановлено после сохранённой порции. '
                'Нажмите «Продолжить локальную подготовку».'
            : eventCount == 0
                ? 'Локальный анализ завершён, но события по текущим '
                    'шаблонам не найдены. Это не ошибка книги: в сказках '
                    'герои часто не имеют собственных имён, а действия '
                    'описаны непрямо. Необходимо проверить исходный текст '
                    'и вручную подготовить сюжет; без этого готовую RPG '
                    'обещать нельзя. ИИ пока отключён.'
                : 'Локальный анализ завершён: '
                    '${assertions.length} предварительных утверждений, '
                    'из них событий — $eventCount. '
                    'Каждую цитату, персонажа и причинную связь необходимо '
                    'проверить. Это ещё не готовая RPG.';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _offlineMessage = 'Локальная подготовка прервана: $error. '
              'Ранее сохранённые результаты остались на устройстве.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _offlineWorking = false;
          _busy = false;
        });
      }
    }
  }

  Widget _offlinePreparationControls(BookSourceIndex index) {
    final progress = _offlineProgress;
    final label = _offlineWorking
        ? (_offlinePause
            ? 'Останавливаем после сохранения…'
            : 'Остановить после порции')
        : _offlineMessage?.startsWith('Остановлено') == true
            ? 'Продолжить локальную подготовку'
            : 'Выполнить локальную подготовку';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Локальная подготовка книги',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Одна кнопка: ищем имена, затем цитаты событий и '
                'локальные смысловые предложения. Результаты сохраняются '
                'после каждой порции, их можно проверить и уточнить ниже. '
                'Полноценная ИИ-модель не используется.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('prepare-offline-all'),
              onPressed: _offlineWorking
                  ? (_offlinePause
                      ? null : () => setState(() => _offlinePause = true))
                  : _busy || _loadingAnalysis || _analysis == null
                      ? null : _runLocalPreparation,
              icon: Icon(_offlineWorking
                  ? Icons.pause_circle_outline : Icons.play_arrow),
              label: Text(label),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              Text(switch (progress.stage) {
                OfflinePreparationStage.names => 'Ищем имена и места',
                OfflinePreparationStage.narrative => 'Ищем цитаты событий',
                OfflinePreparationStage.semantics => 'Составляем смысловой каталог',
                OfflinePreparationStage.completed => 'Локальный поиск закончен',
                OfflinePreparationStage.paused => 'Остановлено',
              }),
              LinearProgressIndicator(value: progress.fraction),
              Text('${progress.completed} из ${progress.total} порций/фрагментов'),
            ],
            if (_offlineMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_offlineMessage!),
              ),
            const SizedBox(height: 6),
            const Text('Результат этой кнопки — проверяемые предположения, '
                'не готовая игра. Текст не отправляется в облако, '
                'старые игровые сохранения не меняются.'),
          ],
        ),
      ),
    );
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
        _offlineProgress = null;
        _offlinePause = false;
        _offlineMessage = 'Поиск имён сброшен. Локальная подготовка '
            'нуждается в повторном запуске. Проверка цитат и сценарные '
            'черновики других этапов не удалены.';
        _narrativeRefresh++;
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
        ? 'ещё не запускался'
        : analysis.pendingCount == 0 && analysis.failedCount == 0
            ? 'завершён; проверьте результаты'
            : 'обработано ${analysis.processedCount} '
                'из ${index.chunks.length} фрагментов';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Как создать RPG из этой книги',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Начните с локального анализа, затем проверьте '
                'найденные события и создайте короткую игровую историю. '
                'Подробные редакторы находятся в «Расширенной настройке».'),
            const SizedBox(height: 8),
            Text('Книга: ${index.chapterCount} разделов. '
                'Локальный поиск: $searchStatus.'),
            const SizedBox(height: 8),
            const Text('Автоматической RPG по всей книге пока нет. '
                'Личная короткая или многосценная RPG собирается '
                'после проверки источника и сценария.'),
            const SizedBox(height: 6),
            ExpansionTile(
              key: const Key('prepare-how-it-works'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Как пройти подготовку: 4 шага'),
              children: [
                _preparationStep('1', 'Найти события в книге',
                    'Нажмите «Выполнить локальную подготовку». '
                    'Можно остановить процесс и продолжить позже.'),
                _preparationStep('2', 'Проверить важные находки',
                    'Убедитесь, что цитаты действительно описывают '
                    'события. При необходимости откройте '
                    '«Расширенную настройку».'),
                _preparationStep('3', 'Написать игровой вариант',
                    'Начните с короткой RPG: выберите исходные события, '
                    'решение игрока и альтернативный финал. '
                    'Для большого сценария есть расширенный редактор.'),
                _preparationStep('4', 'Проверить и начать игру',
                    'Компилятор проверит связи и установит личный игровой '
                    'мир после вашего подтверждения. Создание '
                    'игры не удаляет исходную книгу или прохождения.'),
              ],
            ),
            const Text('Локальная подготовка не отправляет книгу в интернет. '
                'В расширенном режиме можно отдельно разрешить '
                'ИИ проверить выбранные фрагменты.'),
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
        Text('Дополнительно: ручной поиск имён и мест',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Основная кнопка «Выполнить локальную подготовку» выше '
          'уже включает этот поиск, цитаты и смысловые предложения. '
          'Кнопка ниже нужна только для ручного запуска по 24 фрагмента. '
          'Простые шаблоны не распознают всех персонажей и событий.',
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 4),
        const Text('За одно нажатие проверяется не более 24 фрагментов. '
            'При большой книге используйте кнопку повторно.'),
        const SizedBox(height: 8),
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
        // "Show more" never removes earlier cards or jumps the viewport
        // backwards, unlike paging a shrinking sliver list on mobile.
        final pendingReview = allPending
            .take(_visibleCandidates)
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
                        const SizedBox(height: 12),
                        _offlinePreparationControls(index),
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
                if (_showCandidates && allPending.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Показано ${pendingReview.length} из '
                              '${allPending.length} упоминаний'),
                          if (pendingReview.length < allPending.length)
                            OutlinedButton.icon(
                              key: const Key('prepare-review-more'),
                              onPressed: () => setState(
                                  () => _visibleCandidates += _candidatesPerPage),
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Показать ещё находки'),
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
                        Text('Шаг 2. Создайте первую RPG',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('Начните с короткой истории: выберите '
                            'события книги, решение игрока и альтернативный '
                            'исход. Это проще, чем сразу строить большой сюжет.'),

                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-quick-rpg'),
                            leading: const Icon(Icons.auto_stories_outlined),
                            title: const Text('Быстрая RPG из книги'),
                            subtitle: const Text(
                              'Выберите «Сохранить сюжет» или «Менять сюжет», '
                              'подтвердите показанные цитаты и начинайте '
                              'играть. Короткий маршрут из подлинных '
                              'отрывков, без ручного конструктора.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              QuickRpgPage(
                                index: index,
                                gateway: widget.worldGateway ??
                                    const DeviceWorldLibraryGateway(),
                              ),
                            )),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Если нужен собственный текст и '
                            'альтернативный финал, используйте '
                            'ручной редактор ниже.'),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-story-editor'),
                            leading: const Icon(Icons.edit_note),
                            title: const Text('Создать короткую RPG'),
                            subtitle: const Text(
                              'Выберите два проверенных события, напишите '
                              'альтернативный финал и создайте короткую '
                              'офлайн-RPG. Не создаёт игру по всей книге '
                              'автоматически.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              ReviewedStoryEditorPage(
                                index: index,
                                gateway: widget.worldGateway ??
                                    const DeviceWorldLibraryGateway(),
                              ),
                            )),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Шаг 3. Проверьте и запустите',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Text('Проверка покажет, какие события, '
                            'выборы или концовки ещё не готовы. '
                            'Установленный игровой мир появится в библиотеке.'),

                        PrivateGameReadinessPanel(
                          key: ValueKey('private-readiness-'
                              '${index.sourceFingerprint}-$_editorReturnRevision'),
                          checkOnOpen: _editorReturnRevision > 0,
                          index: index,
                          gateway: widget.worldGateway ??
                              const DeviceWorldLibraryGateway(),
                        ),
                        const SizedBox(height: 10),

                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Полная RPG по всей книге'),
                            subtitle: const Text('Сейчас можно создать проверенную короткую игру. '
                                'Короткую личную RPG можно собрать в редакторе выше. '
                                'Автоматическая RPG по всей книге пока '
                                'не реализована.'),
                          ),
                        ),
                        const Divider(height: 30),
                        ExpansionTile(
                          key: const Key('prepare-advanced-mode'),
                          initiallyExpanded: false,
                          onExpansionChanged: (open) =>
                              setState(() => _advancedModeOpen = open),
                          tilePadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tune_outlined),
                          title: const Text('Расширенная настройка RPG'),
                          subtitle: const Text('Необязательно: исправить '
                              'события, привлечь ИИ, создать больше сцен '
                              'или проверить импорт. Начните с нужного раздела.'),
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                              child: Text('Редакторские инструменты нужны '
                                  'только для сложных случаев. Их результаты '
                                  'сохраняются отдельно от книги и '
                                  'прохождений. Откройте раздел и прочитайте '
                                  'его назначение перед работой.'),
                            ),
                            ExpansionTile(
                              key: const Key('prepare-advanced-evidence'),
                              title: const Text(
                                  '1. Уточнить цитаты, персонажей и события'),
                              subtitle: const Text('Если анализ пропустил '
                                  'событие, перепутал имена или хронологию. '
                                  'Результат — проверенные факты, ещё не игра.'),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Найдите фразу в книге, '
                                      'подтвердите или отклоните цитату. '
                                      'Затем уточните, кто действовал '
                                      'и в каком порядке. Это основа '
                                      'для игровых сцен.'),
                                ),

                        IgnorePointer(
                          ignoring: _offlineWorking || _busy,
                          child: SourceNarrativeReviewPanel(
                          key: ValueKey('${index.sourceFingerprint}-${_narrativeRefresh}'),
                          index: index,
                          sourceMentions: _analysis,
                          ),
                        ),

                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-expanded-source-editor'),
                            leading: const Icon(Icons.account_tree_outlined),
                            title: const Text(
                                'Редактор персонажей, событий и хронологии'),
                            subtitle: const Text(
                                'Проверьте все найденные смысловые утверждения, '
                                'разделите похожие имена и уточните порядок глав. '
                                'Редактор не меняет канон автоматически.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              SourceEditorialReviewPage(index: index),
                            )),
                          ),
                        ),
                              ],
                            ),
                            ExpansionTile(
                              key: const Key('prepare-advanced-ai'),
                              title: const Text(
                                  '2. Помощь ИИ при разборе фрагментов'),
                              subtitle: const Text('Необязательно: '
                                  'получить предложения по выбранному '
                                  'отрывку и проверить их вручную.'),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Нужен настроенный Z.ai. '
                                      'Вы увидите точный текст отправки '
                                      'и отдельно разрешите каждый запрос. '
                                      'Ответы ИИ — предположения, '
                                      'а не подтверждённые события. '
                                      'После проверки переходите к сценам.'),
                                ),

                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-whole-book-ai'),
                            leading: const Icon(Icons.menu_book_outlined),
                            title: const Text('ИИ: анализ всей книги'),
                            subtitle: const Text(
                              'Обработать все главы через Z.ai, '
                              'с возобновлением после обрыва. Передача '
                              'текста только после явного согласия. '
                              'Результат — предложения событий, '
                              'не готовая игра.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              ZaiWholeBookAnalysisPage(
                                index: index,
                                gateway: widget.worldGateway,
                              ),
                            )),
                          ),
                        ),
                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-zai-preview'),
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: const Text(
                                'ИИ: проверить отдельный фрагмент книги'),
                            subtitle: const Text('GLM-4.7-Flash предложит '
                                'персонажей, места, события и факты. '
                                'Вы заранее увидите точный текст отправки '
                                'и отдельно подтвердите каждый запрос. '
                                'Результат — только предпросмотр без '
                                'автоматического сохранения или изменения RPG.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              ZaiSemanticPreviewPage(index: index),
                            )),
                          ),
                        ),
                              ],
                            ),
                            ExpansionTile(
                              key: const Key('prepare-advanced-story'),
                              title: const Text(
                                  '3. Написать расширенный сюжет'),
                              subtitle: const Text('Добавить сцены, '
                                  'развилки, условия и последствия. '
                                  'Начните с короткой RPG выше.'),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Сцена — эпизод игры. '
                                      'Выбор ведёт к другой сцене; '
                                      'условие проверяет, можно ли его '
                                      'сделать, а последствие меняет '
                                      'игровое состояние. После редактирования '
                                      'снова проверьте готовность игры.'),
                                ),

                        Card(
                          child: ListTile(
                            key: const Key('prepare-open-multi-scene-editor'),
                            leading: const Icon(Icons.account_tree_outlined),
                            title: const Text('Конструктор многосценной RPG'),
                            subtitle: const Text(
                              'Продолжите проверенную короткую адаптацию: '
                              'добавляйте события, сцены, выборы, условия '
                              'и последствия. Сценарий проверяется перед '
                              'сборкой и не создаётся автоматически.'),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !_offlineWorking && !_busy,
                            onTap: () => unawaited(_openEditor(
                              MultiSceneEditorPage(
                                index: index,
                                gateway: widget.worldGateway ??
                                    const DeviceWorldLibraryGateway(),
                              ),
                            )),
                          ),
                        ),
                              ],
                            ),
                            ExpansionTile(
                              key: const Key('prepare-advanced-glossary'),
                              title: const Text(
                                  'Справка: что означают термины'),
                              childrenPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              children: const [
                                ListTile(
                                  title: Text('Цитата и факт'),
                                  subtitle: Text('Цитата — точные слова '
                                      'книги. Факт — проверенное '
                                      'утверждение о событии. Одно '
                                      'не заменяет другое.'),
                                ),
                                ListTile(
                                  title: Text('Сцена и выбор'),
                                  subtitle: Text('Сцена — текущий эпизод. '
                                      'Выбор — действие игрока, '
                                      'доступное в этом эпизоде.'),
                                ),
                                ListTile(
                                  title: Text('Условие и последствие'),
                                  subtitle: Text('Условие определяет '
                                      'доступность выбора. Последствие '
                                      'меняет ход истории или состояние мира.'),
                                ),
                                ListTile(
                                  title: Text('Канон и альтернатива'),
                                  subtitle: Text('Канон опирается '
                                      'на проверенное событие книги. '
                                      'Альтернативу придумывает редактор; '
                                      'она не выдаётся за исходный текст.'),
                                ),
                                ListTile(
                                  title: Text('Игровой мир и прохождение'),
                                  subtitle: Text('Мир — готовый сценарий. '
                                      'Прохождение — решения игрока '
                                      'и сохранённый прогресс в этом мире.'),
                                ),
                              ],
                            ),

                        ExpansionTile(
                          key: const Key('prepare-source-details'),
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Диагностика импорта книги'),
                          subtitle: const Text('Проверяйте, если главы или изображения '
                              'распознались не полностью'),
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
                      ],
                    ),
                  ),
                ),

                if (_showChapters && _advancedModeOpen)
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
