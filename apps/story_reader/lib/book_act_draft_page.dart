import 'dart:async';

import 'package:flutter/material.dart';

import 'act_dilemma_checkpoint_store.dart';
import 'book_source_index.dart';
import 'bookwide_act_dilemma_gateway.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
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
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final ActDilemmaProposalGateway? gateway;
  final ActDilemmaCheckpointStore? checkpoint;

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

  Future<void> _requestForAct(BookActSegment act) async {
    if (_working || _loading || _error != null) return;
    ActDilemmaConsentManifest manifest;
    try {
      manifest = ActDilemmaConsentManifest.fromAct(
        book: widget.book, bookMap: widget.bookMap, actId: act.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    final includeTitle = await _askActConsent(manifest);
    if (includeTitle == null || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
      _composed = null;
      _notice = 'Запрашиваем одно предложение для выбранной части.';
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
      if (!mounted) return;
      // Persist only AFTER independent source/causal checks succeeded.
      // Failure leaves the previous checkpoint unchanged; no duplicate POST.
      String? saveFailure;
      try {
        await _checkpoint.save(
            book: widget.book, bookMap: widget.bookMap,
            candidate: result);
      } catch (error) {
        saveFailure = 'Не удалось сохранить ответ локально: ' +
            error.toString() + '. Он доступен до закрытия экрана.';
      }
      if (!mounted) return;
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
            ? 'Получено одно сценарное предложение. '
              'Смысл оригинала ещё не подтверждён.'
            : 'ИИ не предложил содержательной развилки для этой части. '
              'Ничего не было выдумано автоматически.';
        if (saveFailure != null) {
          _notice = _notice! + ' ' + saveFailure;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Предложение для части не получено: ' + error.toString() +
            '. Другие части не отправлялись.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
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
        _error = 'Не удалось связать черновые акты: ' + error.toString();
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
              for (final act in eligible.take(32)) ...[
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
              if (eligible.length > 32)
                Text('Показаны первые 32 части из ' +
                    eligible.length.toString() +
                    '. Для длинной книги потребуется '
                    'поэтапная подготовка без пропуска событий.'),
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
              ],
              const SizedBox(height: 8),
              if (_working) const LinearProgressIndicator(),
              if (_notice != null)
                Text(_notice!, key: const Key('act-draft-notice')),
              if (_error != null)
                Text(_error!, key: const Key('act-draft-error'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              const Text('Подготовленные предложения хранятся локально. '
                  'Создание BookWorld и автоматический запуск '
                  'полной RPG пока недоступны на этом этапе.'),
            ],
          ],
        ),
      ),
    );
  }
}
