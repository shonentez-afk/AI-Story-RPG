import 'dart:async';

import 'package:flutter/material.dart';

import 'act_dilemma_checkpoint_store.dart';
import 'book_source_index.dart';
import 'bookwide_act_dilemma_gateway.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'multi_act_trial_page.dart';
import 'world_library_gateway.dart';
import 'zai_semantic_preview.dart';

/// Optional advanced path, not a new home-screen or required editor.
/// A user reviews the EXACT excerpts of ONE act before each paid POST.
/// A locally saved proposal can be reopened without contacting Z.ai.
class BookActDraftPage extends StatefulWidget {
  const BookActDraftPage({
    super.key,
    required this.index,
    required this.book,
    required this.bookMap,
    this.gateway,
    this.checkpoint,
    this.worldGateway,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final ActDilemmaProposalGateway? gateway;
  final ActDilemmaCheckpointStore? checkpoint;
  final WorldLibraryGateway? worldGateway;

  @override
  State<BookActDraftPage> createState() => _BookActDraftPageState();
}

class _BookActDraftPageState extends State<BookActDraftPage> {
  late final ActDilemmaProposalGateway _gateway =
      widget.gateway ?? ActDilemmaProposalGateway();
  late final ActDilemmaCheckpointStore _checkpoint =
      widget.checkpoint ?? ActDilemmaCheckpointStore();

  final ZaiPreviewCancellation _cancellation = ZaiPreviewCancellation();
  List<ActDilemmaCandidate> _candidates = const [];
  MultiActStoryPlanDraft? _composed;
  bool _loading = true, _working = false;
  bool _sequencePreparing = false, _stopAfterCurrent = false;
  bool _awaitingActConsent = false;
  int _actPage = 0;
  static const int _pageSize = 12;
  String? _notice, _error;

  List<BookActSegment> get _eligible => [
    for (final act in widget.bookMap.acts)
      if (act.events.length >= 2) act,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _checkpoint.readAll(
          book: widget.book, bookMap: widget.bookMap);
      if (!mounted) return;
      setState(() {
        _candidates = data;
        _loading = false;
        _error = null;
        _notice = data.isEmpty
            ? 'Сохранённых предложений для этих частей пока нет. '
              'Открытие экрана не отправляет книгу в Z.ai.'
            : 'Восстановлены сохранённые предложения: ' +
              data.length.toString() +
              '. Повторная отправка цитат не требуется.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось восстановить локальные предложения: ' +
            error.toString() +
            '. Автоматической отправки в Z.ai не было.';
      });
    }
  }

  /// null = cancelled, bool = whether to ALSO share the title explicitly.
  Future<bool?> _askActConsent(ActDilemmaConsentManifest manifest) async {
    var agreed = false;
    var title = false;
    return showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Разрешить анализ этой части через Z.ai?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Будут отправлены только ' +
                  manifest.snippets.length.toString() +
                  ' показанных ниже цитат. Это один отдельный запрос '
                  '(возможны до трёх одинаковых попыток при сбоях). '
                  'Остальная книга, сохранения и ключ не отправляются.'),
              const SizedBox(height: 8),
              for (final event in manifest.snippets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText('Глава ' +
                      (event.source.chapterIndex + 1).toString() +
                      ': «' + event.source.quote + '»'),
                ),
              CheckboxListTile(
                key: const Key('act-draft-title-consent'),
                contentPadding: EdgeInsets.zero,
                value: title,
                onChanged: (value) =>
                    update(() => title = value == true),
                title: const Text('Дополнительно отправить название книги'),
              ),
              CheckboxListTile(
                key: const Key('act-draft-quote-consent'),
                contentPadding: EdgeInsets.zero,
                value: agreed,
                onChanged: (value) =>
                    update(() => agreed = value == true),
                title: const Text('Разрешаю отправить именно эти цитаты '
                    'для чернового предложения игрового решения'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('act-draft-approve'),
              onPressed: agreed
                  ? () => Navigator.pop(dialog, title)
                  : null,
              child: const Text('Запросить предложение'),
            ),
          ],
        ),
      ),
    );
  }

  /// A single act is always authorized individually, with the exact quotes
  /// visible before any POST. Returning false stops sequential preparation:
  /// cancel, network error and failed checkpoint writes cannot authorize the
  /// next act.
  Future<bool> _requestAndSave(BookActSegment act) async {
    ActDilemmaConsentManifest manifest;
    try {
      manifest = ActDilemmaConsentManifest.fromAct(
          book: widget.book, bookMap: widget.bookMap, actId: act.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    }
    // Do not keep an indeterminate progress animation running behind
    // the consent dialog: it makes widget settling unreliable and suggests
    // a network request already started when none has.
    setState(() => _awaitingActConsent = true);
    bool? includeTitle;
    try {
      includeTitle = await _askActConsent(manifest);
    } finally {
      if (mounted) setState(() => _awaitingActConsent = false);
    }
    if (includeTitle == null || !mounted) {
      if (mounted) setState(() => _notice =
          'Следующая часть не отправлена. Можно возобновить позже.');
      return false;
    }

    setState(() {
      _error = null;
      _composed = null;
      _notice = 'Запрашиваем предложение только для подтверждённой части.';
    });
    try {
      final result = await _gateway.request(
        book: widget.book,
        bookMap: widget.bookMap,
        actId: act.id,
        approvedDigest: manifest.approvalDigest,
        explicitConsentForShownActQuotes: true,
        consentForBookTitle: includeTitle,
        cancellation: _cancellation,
        onProgress: (attempt, total, status) {
          if (!mounted) return;
          setState(() => _notice = status + ' · попытка ' +
              attempt.toString() + '/' + total.toString());
        },
      );
      if (!mounted) return false;

      // Never advance a sequential run unless its independently checked
      // candidate has been durably saved. A failed write is NOT a success.
      try {
        await _checkpoint.save(
            book: widget.book, bookMap: widget.bookMap,
            candidate: result);
      } catch (error) {
        if (mounted) setState(() => _notice =
            'Ответ получен, но не сохранён: ' + error.toString() +
            '. Последующие части не отправлялись; попробуйте снова.');
        return false;
      }
      if (!mounted) return false;
      final previous = [
        for (final c in _candidates)
          if (c.actId != result.actId) c,
        result,
      ];
      final order = {
        for (var i = 0; i < widget.bookMap.acts.length; i++)
          widget.bookMap.acts[i].id: i,
      };
      previous.sort((a, b) =>
          order[a.actId]!.compareTo(order[b.actId]!));
      setState(() {
        _candidates = List.unmodifiable(previous);
        _notice = result.foundCandidate
            ? 'Предложение сохранено. Литературный смысл ещё не проверен.'
            : 'Модель не нашла подходящую развилку для этой части. '
              'Пустой результат сохранён без выдумывания событий.';
      });
      return true;
    } catch (error) {
      if (mounted) setState(() => _notice =
          'Предложение не получено: ' + error.toString() +
          '. Другие части не отправлялись.');
      return false;
    }
  }

  Future<void> _requestForAct(BookActSegment act) async {
    if (_working || _loading || _error != null) return;
    setState(() => _working = true);
    try {
      await _requestAndSave(act);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// The foreground-only assisted path skips durable results, asks a fresh
  /// consent for EACH remaining act, and stops on cancel/failure. There is no
  /// whole-book blanket approval, silent POST or background work.
  Future<void> _prepareRemaining() async {
    if (_working || _loading || _error != null) return;
    final pending = [
      for (final act in _eligible)
        if (!_candidates.any((c) => c.actId == act.id)) act,
    ];
    final capacity = ActDilemmaCheckpointStore.maxStoredActs -
        _candidates.length;
    if (pending.isEmpty || capacity <= 0) return;
    setState(() {
      _working = true;
      _sequencePreparing = true;
      _stopAfterCurrent = false;
    });
    try {
      for (final act in pending.take(capacity)) {
        if (!mounted || _stopAfterCurrent) break;
        setState(() => _notice =
            'Следующая часть: глава ' +
            (act.chapterIndex + 1).toString() +
            '. Прочтите цитаты и отдельно подтвердите запрос.');
        final saved = await _requestAndSave(act);
        if (!saved || !mounted || _stopAfterCurrent) break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _sequencePreparing = false;
          _stopAfterCurrent = false;
        });
        // Compose only locally and only when enough formally valid drafts
        // exist. This cannot promote the result to canonical/full RPG.
        final ready = _candidates.where((c) => c.foundCandidate).length;
        if (ready >= 2 && ready <=
            ActDilemmaCheckpointStore.maxStoredActs) {
          _assemble();
        }
      }
    }
  }

  void _assemble() {
    try {
      final chosen = [
        for (final c in _candidates)
          if (c.foundCandidate) c,
      ];
      final draft = _gateway.composeLocal(
        index: widget.index, bookMap: widget.bookMap,
        book: widget.book, candidates: chosen);
      setState(() {
        _composed = draft;
        _error = null;
        _notice = 'Собран только многоактовый ЧЕРНОВИК. '
            'Связи между частями ещё не подтверждены книгой.';
      });
    } catch (error) {
      setState(() {
        _composed = null;
        _notice = 'Не удалось связать черновые акты: ' +
            error.toString() + '. Можно изменить выбранные части.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligible;
    final candidateCount =
        _candidates.where((c) => c.foundCandidate).length;
    final full = _candidates.length >=
        ActDilemmaCheckpointStore.maxStoredActs;
    final firstVisible = _actPage * _pageSize;
    final shown = eligible.skip(firstVisible).take(_pageSize).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('План по частям книги')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(widget.index.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Это расширенная подготовка ЧЕРНОВИКА. '
                'Для каждой части вы отдельно разрешаете отправку '
                'конкретных показанных цитат. Никаких скрытых '
                'запросов по всей книге. Проект не утверждает '
                'хронологию и причинность оригинала.'),
            const SizedBox(height: 10),
            Text('Частей с минимум двумя предложениями событий: ' +
                eligible.length.toString() + '. '
                'Можно подготовить до ' +
                ActDilemmaCheckpointStore.maxStoredActs.toString() +
                ' частей одного пробного многоактового черновика.'),
            if (widget.bookMap.hasSourceGaps)
              Text('Глав с пробелами анализа: ' +
                  widget.bookMap.chaptersWithoutEvents.length.toString() +
                  '. Их нельзя молча заполнять выдумкой.'),
            const SizedBox(height: 10),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const Text('Восстанавливаем локальные предложения…'),
            ] else ...[
              for (final act in shown) ...[
                Builder(builder: (context) {
                  final saved = [
                    for (final c in _candidates)
                      if (c.actId == act.id) c,
                  ];
                  final existing = saved.isEmpty ? null : saved.single;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Глава ' +
                              (act.chapterIndex + 1).toString() +
                              ' · часть ' + (act.partIndex + 1).toString(),
                              style: Theme.of(context).textTheme.titleSmall),
                          Text('Предложений событий: ' +
                              act.events.length.toString() +
                              '. Идентичность цитат будет проверена.'),
                          if (existing != null)
                            Text(existing.foundCandidate
                                ? 'Черновая развилка сохранена или получена '
                                  'в этом сеансе. Не является каноном.'
                                : 'Модель не нашла подходящей развилки.'),
                          OutlinedButton(
                            key: Key('act-draft-request-' + act.id),
                            onPressed: (_working || _loading ||
                                    _error != null ||
                                    (full && existing == null))
                                ? null : () => _requestForAct(act),
                            child: Text(existing == null
                                ? 'Проверить эту часть через ИИ'
                                : 'Повторить анализ с новым согласием'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              if (eligible.length > _pageSize) ...[
                Text('Показаны части ' +
                    (firstVisible + 1).toString() + '–' +
                    (firstVisible + shown.length).toString() +
                    ' из ' + eligible.length.toString() +
                    '. Остальные доступны на следующих страницах.'),
                Row(
                  children: [
                    TextButton(
                      key: const Key('act-draft-prev'),
                      onPressed: _actPage == 0 || _working
                          ? null
                          : () => setState(() => _actPage--),
                      child: const Text('Предыдущие'),
                    ),
                    TextButton(
                      key: const Key('act-draft-next'),
                      onPressed: firstVisible + shown.length >=
                              eligible.length || _working
                          ? null
                          : () => setState(() => _actPage++),
                      child: const Text('Следующие'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text('Сохранено частей: ' + _candidates.length.toString() +
                  ' из ' + eligible.length.toString() +
                  ' подходящих. Получено развилок: ' +
                  candidateCount.toString() +
                  '. Повторные обращения по сохранённым частям не нужны.',
                  key: const Key('act-draft-batch-progress')),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('act-draft-prepare-remaining'),
                onPressed: (!_working && !_loading && _error == null &&
                        !full && eligible.any((act) =>
                            !_candidates.any((c) => c.actId == act.id)))
                    ? _prepareRemaining : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Продолжить подготовку по частям'),
              ),
              const Text('Приложение пропускает уже сохранённые результаты. '
                  'Перед КАЖДЫМ новым запросом показывает точные цитаты '
                  'этой части и отдельно спрашивает согласие. '
                  'Отмена останавливает последующие запросы; '
                  'не более 6 частей в одном черновике.'),
              if (_sequencePreparing)
                OutlinedButton.icon(
                  key: const Key('act-draft-stop-after-current'),
                  onPressed: _stopAfterCurrent ? null
                      : () => setState(() {
                          _stopAfterCurrent = true;
                          _notice = 'Следующие части не будут отправлены. '
                              'Уже подтверждённый запрос может завершиться.';
                        }),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Остановить после текущей части'),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('act-draft-assemble'),
                onPressed: (!_working && !_loading &&
                        _error == null && candidateCount >= 2 &&
                        candidateCount <=
                            ActDilemmaCheckpointStore.maxStoredActs)
                    ? _assemble : null,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Собрать многоактовый черновик'),
              ),
              if (_composed != null) ...[
                const SizedBox(height: 10),
                Text('Соединено актов: ' +
                    _composed!.parts.length.toString() +
                    '. Игровых ситуаций: ' +
                    _composed!.plan.situations.length.toString() + '.',
                    key: const Key('act-draft-composed-summary')),
                Text('Исходных событий в черновике: ' +
                    _composed!.coverage.referencedEvents.toString() +
                    ' из ' + _composed!.coverage.allEvents.toString() + '.'),
                const Text('Готовность к полноценной игре: НЕТ. '
                    'Переходы между актами — вымышленная '
                    'игровая гипотеза, не доказанный текст книги.'),
                ExpansionTile(
                  title: const Text('Что мешает полной игре'),
                  children: [
                    for (final blocker in _composed!.blockers)
                      ListTile(title: Text(blocker)),
                  ],
                ),
                if (widget.worldGateway != null)
                  OutlinedButton.icon(
                    key: const Key('act-draft-private-play'),
                    onPressed: _working ? null : () async {
                      final draft = _composed;
                      if (draft == null || !mounted) return;
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => MultiActTrialPage(
                            index: widget.index,
                            book: widget.book,
                            bookMap: widget.bookMap,
                            draft: draft,
                            gateway: widget.worldGateway!,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Попробовать частную '
                        'многоактовую RPG'),
                  ),
              ],
              const SizedBox(height: 8),
              if (_working && !_awaitingActConsent)
                const LinearProgressIndicator(),
              if (_notice != null)
                Text(_notice!, key: const Key('act-draft-notice')),
              if (_error != null)
                Text(_error!, key: const Key('act-draft-error'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              const Text('Подготовленные предложения хранятся локально. '
                  'С подтверждёнными цитатами доступна частная '
                  'ПРОБНАЯ игра по нескольким актам. Полноценная '
                  'литературная RPG по всей книге ещё не готова.'),
            ],
          ],
        ),
      ),
    );
  }
}
