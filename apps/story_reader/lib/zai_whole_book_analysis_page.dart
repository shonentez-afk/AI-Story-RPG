import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_connection_settings_page.dart';
import 'book_source_index.dart';
import 'book_act_draft_page.dart';
import 'bookwide_act_planner.dart';
import 'narrative_book_model.dart';
import 'story_plan_quality_gate.dart';
import 'story_plan_draft_checkpoint.dart';
import 'quick_rpg_page.dart';
import 'story_plan_trial_page.dart';
import 'world_library_gateway.dart';
import 'zai_auto_whole_book_analysis.dart';
import 'zai_whole_book_event_outline.dart';
import 'zai_semantic_preview.dart';
import 'zai_story_dilemma_proposal.dart';

/// User-facing, opt-in book-wide preparation. This screen DOES NOT publish a
/// game or silently send excerpts when opened. It uses the exact source
/// index already opened in the local library and the private M2g2 checkpoint.
class ZaiWholeBookAnalysisPage extends StatefulWidget {
  const ZaiWholeBookAnalysisPage({
    super.key,
    required this.index,
    this.analysis,
    this.dilemmaService,
    this.dilemmaCheckpoint,
    this.gateway,
  });

  final BookSourceIndex index;
  final ZaiAutoWholeBookAnalysis? analysis;
  final ZaiStoryDilemmaProposalService? dilemmaService;
  final StoryPlanDraftCheckpointStore? dilemmaCheckpoint;
  final WorldLibraryGateway? gateway;

  @override
  State<ZaiWholeBookAnalysisPage> createState() =>
      _ZaiWholeBookAnalysisPageState();
}

class _ZaiWholeBookAnalysisPageState extends State<ZaiWholeBookAnalysisPage> {
  late final ZaiAutoWholeBookAnalysis _analysis =
      widget.analysis ?? ZaiAutoWholeBookAnalysis();
  late final ZaiStoryDilemmaProposalService _dilemmaService =
      widget.dilemmaService ?? ZaiStoryDilemmaProposalService();
  late final StoryPlanDraftCheckpointStore _dilemmaCheckpoint =
      widget.dilemmaCheckpoint ?? StoryPlanDraftCheckpointStore();
  late final ZaiWholeBookConsentManifest _manifest =
      ZaiWholeBookConsentManifest.fromIndex(widget.index);

  ZaiWholeBookReviewResult? _review;
  ZaiWholeBookProgress? _progress;
  ZaiPreviewCancellation? _cancellation;
  ZaiStoryDilemmaPreview? _dilemmaPreview;
  StoryPlanQualityReport? _qualityReport;
  BookwideActPlan? _bookActs;
  BookwideStoryCoverage? _bookCoverage;
  String? _bookActError;
  bool _dilemmaBusy = false;
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
      BookwideActPlan? localActs;
      String? localActError;
      if (review.complete) {
        try {
          final book = NarrativeBookModel.fromExisting(
              index: widget.index,
              outline: ZaiWholeBookEventOutline.build(review));
          localActs = BookwideActPlanner.build(
              index: widget.index, book: book);
        } catch (error) {
          localActError = 'Не удалось построить карту частей книги: ' +
              error.toString();
        }
      }
      ZaiStoryDilemmaPreview? restored;
      BookwideStoryCoverage? restoredCoverage;
      StoryPlanQualityReport? restoredQuality;
      String? recoveryNotice;
      if (review.complete && review.progress.eventProposals >= 2) {
        try {
          final outline = ZaiWholeBookEventOutline.build(review);
          final book = NarrativeBookModel.fromExisting(
              index: widget.index, outline: outline);
          // Private local read only. Never POST on opening a book.
          restored = await _dilemmaCheckpoint.read(book);
          if (restored != null && restored.foundCandidate) {
            restoredQuality = StoryPlanQualityGate.assess(
                book: book, preview: restored);
            if (localActs != null) {
              restoredCoverage = BookwideActPlanner.compareWithStoryPlan(
                  bookMap: localActs,
                  book: book,
                  story: restoredQuality.plan);
            }
          }
          if (restored != null) {
            recoveryNotice = restored.foundCandidate
                ? 'Черновой план восстановлен локально. '
                  'Повторная отправка книги в Z.ai не требуется.'
                : 'Ранее ИИ не предложил подходящей развилки. '
                  'Повторный запрос возможен только с новым согласием.';
          }
        } catch (error) {
          recoveryNotice = 'Не удалось восстановить локальный черновик: ' +
              error.toString() +
              '. Автоматической повторной отправки в Z.ai не было.';
        }
      }
      if (!mounted) return;
      setState(() {
        _review = review;
        _progress = review.progress;
        _dilemmaPreview = restored;
        _qualityReport = restoredQuality;
        _bookActs = localActs;
        _bookCoverage = restoredCoverage;
        _bookActError = localActError;
        _notice = recoveryNotice;
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
      _dilemmaBusy = false;
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
      BookwideActPlan? updatedActs;
      String? updatedActError;
      if (next.complete) {
        try {
          final book = NarrativeBookModel.fromExisting(
              index: widget.index,
              outline: ZaiWholeBookEventOutline.build(next));
          updatedActs = BookwideActPlanner.build(
              index: widget.index, book: book);
        } catch (error) {
          updatedActError = 'Не удалось подготовить карту книги: ' +
              error.toString();
        }
      }
      if (!mounted) return;
      setState(() {
        _review = next;
        _progress = next.progress;
        _bookActs = updatedActs;
        _bookCoverage = null;
        _bookActError = updatedActError;
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

  /// The model must see exactly the same short excerpts as the user.
  /// This consent is independent of the earlier whole-book scan.
  Future<bool?> _requestDilemmaConsent(NarrativeBookModel book) async {
    final snippets = ZaiStoryDilemmaProposalService.samples(book);
    var accepted = false;
    var includeTitle = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Предложить сюжетную развилку через Z.ai?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Будут отправлены только ' +
                  snippets.length.toString() +
                  ' коротких цитат событий, показанных ниже. '
                  'Полная книга и сохранения НЕ отправляются.'),
              const SizedBox(height: 8),
              const Text('Модель попробует предложить игровой выбор, '
                  'но может ответить, что данных недостаточно. '
                  'Это отдельный запрос (до 3 попыток при 429/обрыве), '
                  'который может тарифицироваться. '
                  'Полученный результат остаётся черновиком, '
                  'не утверждается как канон и не запускает игру.'),
              const SizedBox(height: 8),
              for (final event in snippets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText('Глава ' +
                      (event.source.chapterIndex + 1).toString() +
                      ': «' + event.source.quote + '»'),
                ),
              CheckboxListTile(
                key: const Key('whole-book-dilemma-title'),
                title: const Text('Также передать название книги'),
                value: includeTitle,
                onChanged: (value) =>
                    change(() => includeTitle = value == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                key: const Key('whole-book-dilemma-consent'),
                title: const Text('Разрешаю отправку именно этих '
                    'цитат в Z.ai для предложения сценария'),
                value: accepted,
                onChanged: (value) =>
                    change(() => accepted = value == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('whole-book-dilemma-approve'),
              onPressed: accepted
                  ? () => Navigator.pop(context, includeTitle) : null,
              child: const Text('Предложить черновик'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _proposeDilemma() async {
    final review = _review;
    if (_loading || _working || review == null || !review.complete) return;
    ZaiPreviewCancellation? cancel;
    try {
      final outline = ZaiWholeBookEventOutline.build(review);
      final book = NarrativeBookModel.fromExisting(
          index: widget.index, outline: outline);
      final titleConsent = await _requestDilemmaConsent(book);
      if (titleConsent == null || !mounted) return;
      cancel = ZaiPreviewCancellation();
      setState(() {
        _working = true;
        _dilemmaBusy = true;
        _cancellation = cancel;
        _error = null;
        _notice = null;
        _dilemmaPreview = null;
        _qualityReport = null;
      });
      final result = await _dilemmaService.propose(
        book: book,
        consentForTheseSampledQuotes: true,
        consentForBookTitle: titleConsent,
        cancellation: cancel,
        onProgress: (attempt, total, status) {
          if (!mounted) return;
          setState(() => _notice = status + ': ' +
              attempt.toString() + '/' + total.toString());
        },
      );
      if (!mounted) return;
      // Structural readiness is always checked locally. Never present an
      // unvalidated model result as a game or accept it as source truth.
      final quality = result.foundCandidate
          ? StoryPlanQualityGate.assess(book: book, preview: result)
          : null;
      final coverage = quality != null && _bookActs != null
          ? BookwideActPlanner.compareWithStoryPlan(
              bookMap: _bookActs!, book: book, story: quality.plan)
          : null;
      if (!mounted) return;
      String? saveError;
      try {
        // Save atomically before confirming that the paid result can be
        // restored after an app restart. Never retry the GLM POST here.
        await _dilemmaCheckpoint.save(book, result);
      } catch (error) {
        saveError = 'Не удалось сохранить черновик локально: ' +
            error.toString() +
            '. Он доступен только до закрытия этого экрана.';
      }
      if (!mounted) return;
      setState(() {
        _dilemmaPreview = result;
        _qualityReport = quality;
        _bookCoverage = coverage;
        _notice = (quality != null
            ? 'Черновой сценарий проверен по игровым правилам. '
              'Смысл, полнота книги и литературные сцены ещё не приняты.'
            : 'Подходящая причинная развилка не предложена. '
              'Ничего не подставлено вместо ответа ИИ.') +
            (saveError == null
                ? ' Результат сохранён локально, без повторной оплаты.'
                : ' ' + saveError);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = cancel?.isCancelled == true
          ? 'Подготовка развилки отменена. Игра не изменена.'
          : 'Не удалось предложить черновой сценарий: ' + error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _dilemmaBusy = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final review = _review;
    final outline = review == null
        ? null : ZaiWholeBookEventOutline.build(review);
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
                Text(_dilemmaBusy
                    ? 'Черновое предложение не сохраняется в игре. '
                      'Уже отправленный запрос невозможно отозвать.'
                    : 'Результаты сохраняются после каждой '
                      'успешной части. Приложение должно оставаться открытым.'),
              ],
              if (review!.complete) ...[
                const Icon(Icons.check_circle_outline, size: 32),
                const Text('Анализ всех выбранных частей завершён.'),
                const Text('Следующий этап — проверка связей, '
                    'причинных развилок и компиляция полного сценария. '
                    'Пока можно сыграть короткую RPG по найденным событиям.'),
                if (outline != null && outline.events.length >= 2) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('whole-book-quick-play'),
                    onPressed: _working ? null : () async {
                      final report = _qualityReport;
                      final preview = _dilemmaPreview;
                      if (report != null && report.passedFormalPreflight &&
                          preview != null && preview.foundCandidate) {
                        final book = NarrativeBookModel.fromExisting(
                            index: widget.index, outline: outline);
                        if (!mounted) return;
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => StoryPlanTrialPage(
                              index: widget.index, book: book,
                              preview: preview, quality: report,
                              gateway: widget.gateway ??
                                  const DeviceWorldLibraryGateway(),
                            ),
                          ),
                        );
                      } else {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => QuickRpgPage(
                              index: widget.index,
                              gateway: widget.gateway ??
                                  const DeviceWorldLibraryGateway(),
                              eventOutline: outline,
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_qualityReport?.passedFormalPreflight == true
                        ? 'Создать и играть в пробную RPG с развилкой'
                        : 'Создать пробную RPG по событиям'),
                  ),
                  const Text('Потребуется отдельная проверка цитат. '
                      'Это не полная игра по всему сюжету.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('whole-book-propose-dilemma'),
                    onPressed: _working ? null : _proposeDilemma,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Предложить развилку с ИИ (черновик)'),
                  ),
                  const Text('Z.ai проанализирует только показанные '
                      'перед отправкой цитаты. Отказ от условия '
                      'будет иметь отдельный маршрут. '
                      'Пока это НЕ готовая игра и не канонический сюжет.'),
                  if (_dilemmaPreview != null &&
                      _dilemmaPreview!.foundCandidate) ...[
                    const SizedBox(height: 10),
                    Text('Черновой план: ' +
                        _dilemmaPreview!.plan!.situations.length.toString() +
                        ' ситуаций. Литературный смысл и полнота книги '
                        'ещё должны пройти проверку.'),
                    if (_qualityReport != null) ...[
                      const SizedBox(height: 8),
                      Text(_qualityReport!.passedFormalPreflight
                          ? 'Проверка игровых условий: пройдена.'
                          : 'Проверка игровых условий: есть проблемы.',
                          key: const Key('whole-book-dilemma-preflight')),
                      Text('Исправлено формальных нарушений: ' +
                          _qualityReport!.repair.appliedChanges.length
                              .toString() + '. '
                          'Нерешённых противоречий: ' +
                          _qualityReport!.repair.after.counterexamples.length
                              .toString() + '.'),
                      const Text('Готовность к установке и игре: НЕТ. '
                          'Формальные правила не подтверждают '
                          'причинность литературного оригинала.'),
                      ExpansionTile(
                        key: const Key('whole-book-dilemma-readiness'),
                        title: const Text('Что ещё требуется для игры?'),
                        children: [
                          for (final message in _qualityReport!.blockers)
                            ListTile(title: Text(message)),
                          for (final message in
                              _qualityReport!.reviewRequirements)
                            ListTile(title: Text(message)),
                        ],
                      ),
                    ],
                    ExpansionTile(
                      key: const Key('whole-book-dilemma-preview'),
                      title: const Text('Посмотреть предлагаемые события'),
                      children: [
                        for (final situation in
                            _dilemmaPreview!.plan!.situations)
                          ListTile(
                            title: Text(situation.goal),
                            subtitle: Text(situation.terminal
                                ? 'Предлагаемая концовка'
                                : 'Доступных решений в черновике: ' +
                                    situation.decisions.length.toString()),
                          ),
                      ],
                    ),
                  ],

                ],
              ],
            ],
            if (outline != null && progress != null) ...[
              const SizedBox(height: 14),
              Text('Сводка событий',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('Предложено событий: ${outline.events.length}; '
                  'глав с предложениями: '
                  '${outline.chaptersWithEventProposals} '
                  'из ${outline.totalChapters}.'),
              if (_bookActs != null) ...[
                const SizedBox(height: 8),
                Text('Карта книги: ' +
                    _bookActs!.acts.length.toString() +
                    ' частей; все ' + _bookActs!.sourceEvents.toString() +
                    ' найденных событий распределены без потерь.',
                    key: const Key('whole-book-act-summary')),
                Text(_bookActs!.chaptersWithoutEvents.isEmpty
                    ? 'Во всех главах есть предложения событий. '
                      'Их смысл пока не проверен.'
                    : 'Глав без предложений событий: ' +
                      _bookActs!.chaptersWithoutEvents.length.toString() +
                      '. Это пробел анализа, а не отсутствие сюжета.'),
                if (_bookCoverage != null)
                  Text('Текущий черновой сюжет использует ' +
                      _bookCoverage!.referencedEvents.toString() +
                      ' из ' + _bookCoverage!.allEvents.toString() +
                      ' предложенных событий книги. '
                      'Это не полная литературная RPG.',
                      key: const Key('whole-book-act-coverage')),
                ExpansionTile(
                  key: const Key('whole-book-act-map'),
                  title: const Text('Части книги и непокрытые эпизоды'),
                  subtitle: const Text('Порядок частей — по тексту книги, '
                      'не доказанная хронология игрового мира.'),
                  children: [
                    for (final act in _bookActs!.acts.take(12))
                      ListTile(
                        title: Text('Глава ' +
                            (act.chapterIndex + 1).toString() +
                            ' · часть ' + (act.partIndex + 1).toString()),
                        subtitle: Text(act.isCoverageGap
                            ? 'Нет предложенных событий: '
                              'требуется проверка главы.'
                            : 'Найдено событий: ' +
                              act.events.length.toString() +
                              '. Смысл и причинность не проверены.'),
                      ),
                    if (_bookActs!.acts.length > 12)
                      ListTile(title: Text('Показаны первые 12 из ' +
                          _bookActs!.acts.length.toString() +
                          ' частей. Остальные сохранены в локальном '
                          'анализе, ни одно событие не отброшено.')),
                    const ListTile(title: Text('Для полной игры ещё '
                        'нужны связи между актами, знания персонажей, '
                        'проверенные решения и художественные сцены.')),
                  ],
                ),
                if (_bookActs!.acts.where(
                    (a) => a.events.length >= 2).length >= 2)
                  OutlinedButton.icon(
                    key: const Key('whole-book-act-draft-start'),
                    onPressed: _working ? null : () async {
                      final book = NarrativeBookModel.fromExisting(
                        index: widget.index, outline: outline);
                      if (!mounted) return;
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => BookActDraftPage(
                            index: widget.index,
                            book: book,
                            bookMap: _bookActs!,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Подготовить решения по частям книги'),
                  ),
                if (_bookActs!.acts.where(
                    (a) => a.events.length >= 2).length >= 2)
                  const Text('В расширенном режиме каждая часть '
                      'отправляется в Z.ai отдельно и только с согласия. '
                      'Пока создаётся многоактовый черновик, '
                      'не полноценная литературная игра.'),
              ],
              if (_bookActError != null)
                Text(_bookActError!,
                    key: const Key('whole-book-act-error')),
              ExpansionTile(
                key: const Key('whole-book-event-report'),
                title: const Text('Источники, пробелы и предупреждения'),
                subtitle: const Text('Возможны спойлеры. '
                    'Предложения ИИ ещё не сюжетные факты.'),
                children: [
                  for (final warning in outline.warnings)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 3, 14, 7),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('• $warning'),
                      ),
                    ),
                  for (final proposal in outline.events.take(12))
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Глава ${proposal.chapterIndex + 1} · '
                                '${proposal.label}',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 5),
                            SelectableText('«${proposal.quote}»'),
                          ],
                        ),
                      ),
                    ),
                  if (outline.events.length > 12)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('Показаны первые 12 из '
                          '${outline.events.length} предложений. '
                          'Полный перечень остаётся в локальном '
                          'контрольном файле.'),
                    ),
                ],
              ),
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
