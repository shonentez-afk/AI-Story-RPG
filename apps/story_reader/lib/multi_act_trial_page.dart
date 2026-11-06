import 'package:flutter/material.dart';
import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'cross_act_consequence_gate.dart';
import 'multi_act_trial_compiler.dart';
import 'source_locked_prose_preview_page.dart';
import 'source_locked_prose_batch_page.dart';
import 'reviewed_prose_scene_overlay.dart';
import 'reviewed_gameplay_compiler.dart';
import 'source_locked_gameplay_review_page.dart';
import 'whole_plan_gameplay_batch_page.dart';
import 'narrative_book_model.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';

/// A voluntarily started PRIVATE multi-act FICTIONAL trial, not a literary
/// CANON generator. All exact source excerpts are visible BEFORE compilation.
/// Installing/starting requires an explicit tap and never overwrites saves.
class MultiActTrialPage extends StatefulWidget {
  const MultiActTrialPage({
    super.key,
    required this.index,
    required this.book,
    required this.bookMap,
    required this.draft,
    required this.gateway,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final WorldLibraryGateway gateway;

  @override
  State<MultiActTrialPage> createState() => _MultiActTrialPageState();
}

class _MultiActTrialPageState extends State<MultiActTrialPage> {
  bool _reviewed = false;
  bool _privateFiction = false;
  bool _enforceEarlierOutcome = false;
  bool _working = false;
  String? _error;
  final Map<String, ReviewedProseSceneApproval> _reviewedProse = {};
  SelectedGameplayCandidates? _gameplaySelection;
  SelectedWholePlanGameplayCandidates? _wholeGameplaySelection;

  List<NarrativeEvent> get _reviewEvents {
    final ids = <String>{
      for (final part in widget.draft.parts) ...[
        part.setupEventId, part.outcomeEventId,
      ],
    };
    return List.unmodifiable([
      for (final event in widget.book.events)
        if (ids.contains(event.id)) event,
    ]);
  }

  Future<void> _chooseGameplay() async {
    if (_working || !_reviewed || !_privateFiction ||
        _enforceEarlierOutcome || !widget.draft.formalRulesPassed) return;
    // M2h8d1 is deliberately bounded to SIX short, exact source excerpts.
    // Larger multi-act source sets require a separate consented batch.
    final sample = _reviewEvents.take(6).toList(growable: false);
    if (sample.isEmpty) return;
    final selection = await Navigator.of(context)
        .push<SelectedGameplayCandidates>(MaterialPageRoute(
      builder: (_) => SourceLockedGameplayReviewPage(
        index: widget.index,
        book: widget.book,
        plan: widget.draft.plan,
        exactEventIds: [for (final e in sample) e.id],
      ),
    ));
    if (!mounted || selection == null) return;
    setState(() {
      _gameplaySelection = selection;
      _wholeGameplaySelection = null;
      _error = null;
    });
  }

  Future<void> _chooseWholeGameplay() async {
    if (_working || !_reviewed || !_privateFiction ||
        _enforceEarlierOutcome || !widget.draft.formalRulesPassed) return;
    final selection = await Navigator.of(context)
        .push<SelectedWholePlanGameplayCandidates>(MaterialPageRoute(
      builder: (_) => WholePlanGameplayBatchPage(
        index: widget.index, book: widget.book,
        plan: widget.draft.plan,
      ),
    ));
    if (!mounted || selection == null) return;
    setState(() {
      _wholeGameplaySelection = selection;
      _gameplaySelection = null; // Do not mix two different consent scopes.
      _error = null;
    });
  }

  Future<void> _start() async {
    if (!_reviewed || !_privateFiction || _working) return;
    if (_enforceEarlierOutcome &&
        (_reviewedProse.isNotEmpty || _gameplaySelection != null ||
         _wholeGameplaySelection != null)) {
      setState(() => _error = 'Подтверждённые художественные сцены '
          'относятся к прежней версии игрового плана. '
          'Снимите дополнительное правило или удалите '
          'выбранные художественные сцены из подготовки.');
      return;
    }
    setState(() { _working = true; _error = null; });
    try {
      CrossActContinuityDraft? continuity;
      if (_enforceEarlierOutcome) {
        final earlier = widget.draft.parts.first;
        final later = widget.draft.parts[1];
        continuity = CrossActConsequenceGate.apply(
          index: widget.index,
          book: widget.book,
          bookMap: widget.bookMap,
          draft: widget.draft,
          rules: [
            CrossActConsequenceRule(
              id: 'player_reviewed_fictional_rule',
              earlierActId: earlier.actId,
              laterActId: later.actId,
              earlierSourceEventId: earlier.outcomeEventId,
              laterSourceEventId: later.setupEventId,
              laterDecisionId: 'act_2_accept_offer',
              priorOutcome: CrossActPriorOutcome.original,
              mode: CrossActRuleMode.requiresPriorOutcome,
              reviewedAsGameFiction: true,
              privateReviewReason: 'Пользователь отдельно подтвердил '
                  'выдуманное правило: второй акт допускает принятие '
                  'условия только после исхода первого акта.',
            ),
          ],
        );
      }
      final compiled = await MultiActTrialCompiler.compile(
        index: widget.index,
        book: widget.book,
        bookMap: widget.bookMap,
        draft: widget.draft,
        continuity: continuity,
        sourceEventIdsReviewedByUser: {
          for (final event in _reviewEvents) event.id,
        },
        privateUseConfirmed: _privateFiction,
        fictionalTrialAcknowledged: _privateFiction,
        reviewedProse: _reviewedProse.values.toList(growable: false),
      );
      if (!mounted || compiled.sourceFingerprint !=
          widget.index.sourceFingerprint) return;
      var archive = compiled.archive;
      if (_wholeGameplaySelection != null || _gameplaySelection != null) {
        final ReviewedGameplayApprovalPreview preview;
        if (_wholeGameplaySelection != null) {
          final selection = _wholeGameplaySelection!;
          preview = ReviewedGameplayCompiler.previewAcrossBatches(
            currentRichBookworld: compiled.archive,
            index: widget.index,
            book: widget.book,
            plan: widget.draft.plan,
            manifest: selection.manifest,
            proposals: selection.drafts,
            selectedUserReviewNotes: selection.selectedUserReviewNotes,
          );
        } else {
          final selection = _gameplaySelection!;
          preview = ReviewedGameplayCompiler.preview(
          currentRichBookworld: compiled.archive,
          index: widget.index,
          book: widget.book,
          plan: widget.draft.plan,
          context: selection.context,
          proposals: selection.draft,
          selectedUserReviewNotes: selection.selectedUserReviewNotes,
          );
        }
        if (!mounted) return;
        final approved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Подтвердить игровые предметы'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Только частная игровая адаптация, '
                      'не литературный канон. '
                      'Существующие игры не изменяются.'),
                  const SizedBox(height: 8),
                  for (final effect in (preview.shownReview['effects'] as List))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text((effect as Map)['label'].toString() +
                          ': ' + effect['op'].toString() +
                          ' / ' + effect['choice_id'].toString()),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отменить'),
              ),
              FilledButton(
                key: const Key('multiact-trial-final-gameplay-approval'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Подтверждаю частную игровую выдумку'),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return;
        archive = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
          preview: preview,
          currentRichBookworld: compiled.archive,
          index: widget.index,
          explicitlyConfirmedPrivateGameFiction: true,
          approvedReviewDigest: preview.approvalDigest,
        );
      }
      final finalCheck = const RichPrivateBookworldImporter().inspect(archive);
      if (finalCheck.sourceFingerprint != widget.index.sourceFingerprint) {
        throw const FormatException('Чужая исходная редакция игрового мира');
      }
      final installed = await widget.gateway.install(archive);
      if (installed.archiveHash != finalCheck.archiveSha256 ||
          installed.bookworldId != finalCheck.bookworldId) {
        throw const FormatException(
            'Установленный мир отличается от проверенного пакета.');
      }
      if (!mounted) return;
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(
          gateway: widget.gateway, campaignId: campaignId),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось создать многоактовую пробную RPG: ' +
            error.toString() + '. Исходная книга и старые игры сохранены.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _reviewEvents;
    final count = widget.draft.parts.length;
    final valid = count >= 2 && events.length == count * 2 &&
        widget.draft.formalRulesPassed &&
        !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('Пробная игра по частям книги')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            Text(widget.index.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text('Исходных цитат: ' + events.length.toString() +
                '; предложенных актов: ' + count.toString() +
                '; игровых ситуаций: ' +
                widget.draft.plan.situations.length.toString() + '.'),
            const SizedBox(height: 8),
            const Text('Это приватная ПРОБНАЯ игровая адаптация, '
                'НЕ полный сюжет книги и НЕ подтверждённый канон. '
                'Между частями используются придуманные переходы; '
                'диалоги и знания персонажей ещё не сверены с оригиналом. '
                'После компиляции игра работает офлайн.'),
            const SizedBox(height: 8),
            const Text('Проверьте все исходные отрывки:'),
            for (final event in events)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Глава ' +
                          (event.source.chapterIndex + 1).toString()),
                      SelectableText('«' + event.source.quote + '»'),
                    ],
                  ),
                ),
              ),
            CheckboxListTile(
              key: const Key('multiact-trial-source-reviewed'),
              contentPadding: EdgeInsets.zero,
              value: _reviewed,
              onChanged: valid
                  ? (v) => setState(() => _reviewed = v == true)
                  : null,
              title: const Text('Я проверил(а) все показанные цитаты '
                  'в этой редакции книги'),
            ),
            CheckboxListTile(
              key: const Key('multiact-trial-private-fiction'),
              contentPadding: EdgeInsets.zero,
              value: _privateFiction,
              onChanged: valid
                  ? (v) => setState(() => _privateFiction = v == true)
                  : null,
              title: const Text('Разрешаю создать частную ПРОБНУЮ игру '
                  'с вымышленными причинными связями, '
                  'не выдавая её за полный сюжет оригинала'),
            ),
            CheckboxListTile(
              key: const Key('multiact-trial-consequence'),
              contentPadding: EdgeInsets.zero,
              value: _enforceEarlierOutcome,
              onChanged: valid && _reviewedProse.isEmpty &&
                  _gameplaySelection == null &&
                  _wholeGameplaySelection == null
                  ? (v) => setState(() =>
                      _enforceEarlierOutcome = v == true)
                  : null,
              title: const Text('Дополнительное вымышленное правило: '
                  'во втором акте принять условие можно только '
                  'после соответствующего исхода первого акта'),
              subtitle: const Text('Реально меняет доступные действия. '
                  'Это игровая адаптация, не установленный факт книги.'),
            ),
            ExpansionTile(
              key: const Key('multiact-trial-prose-preview-expansion'),
              title: const Text('Художественный черновик (дополнительно)'),
              subtitle: const Text('Одна сцена, отдельное согласие Z.ai. '
                  'Только явно одобренный текст включается в новую игру.'),
              children: [
                ListTile(
                  key: const Key('multiact-trial-open-prose-batch'),
                  leading: const Icon(Icons.auto_awesome_motion_outlined),
                  title: const Text('Подготовить несколько сцен'),
                  subtitle: Text(_enforceEarlierOutcome
                      ? 'Отключите дополнительное правило второго акта: '
                        'оно меняет сценарий'
                      : 'Одно согласие на список показанных сцен, '
                        'ограничение запросов и возобновление'),
                  onTap: _working || _enforceEarlierOutcome ? null : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => SourceLockedProseBatchPage(
                          index: widget.index,
                          book: widget.book,
                          plan: widget.draft.plan,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const Key('multiact-trial-open-prose-preview'),
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Предпросмотр художественной сцены'),
                  subtitle: Text(_enforceEarlierOutcome
                      ? 'Сначала отключите дополнительное правило '
                        'второго акта: оно меняет проверяемый план'
                      : 'Можно восстановить ранее сохранённый '
                        'черновик без нового запроса'),
                  onTap: _working || _enforceEarlierOutcome ? null : () async {
                    final accepted = await Navigator.of(context)
                        .push<ReviewedProseSceneApproval>(
                      MaterialPageRoute(
                        builder: (_) => SourceLockedProsePreviewPage(
                          index: widget.index,
                          book: widget.book,
                          plan: widget.draft.plan,
                        ),
                      ),
                    );
                    if (!mounted || accepted == null) return;
                    setState(() =>
                        _reviewedProse[accepted.situationId] = accepted);
                  },
                ),
              ],
            ),
            if (_reviewedProse.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Художественные сцены для следующей игры: ' +
                          _reviewedProse.length.toString()),
                      const Text('Каждая сцена подтверждена отдельно. '
                          'Исходные цитаты и игровая логика не изменяются. '
                          'Эта версия игрового плана должна оставаться '
                          'неизменной до сборки.'),
                      TextButton(
                        key: const Key('multiact-trial-clear-prose'),
                        onPressed: _working ? null : () => setState(() =>
                            _reviewedProse.clear()),
                        child: const Text('Убрать художественные сцены '
                            'из следующей игры'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('multiact-trial-optional-gameplay'),
              onPressed: valid && _reviewed && _privateFiction &&
                  !_enforceEarlierOutcome ? _chooseGameplay : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Добавить предметы и знания '
                  '(необязательный запрос ИИ)'),
            ),
            const Text('Для одного запроса используются максимум '
                'шесть проверенных отрывков. '
                'Это НЕ анализ всего произведения.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('multiact-trial-whole-gameplay-batch'),
              onPressed: valid && _reviewed && _privateFiction &&
                  !_enforceEarlierOutcome ? () async {
                await _chooseWholeGameplay();
              } : null,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Предложения по всему сюжету '
                  '(пакетная обработка)'),
            ),
            const Text('Пакеты используют все привязанные к игровым '
                'решениям цитаты, сохраняя прогресс на устройстве. '
                'Модельные предложения не добавляются в игру без '
                'отдельного выбора и второго подтверждения.'), 
            if (_wholeGameplaySelection != null)
              ListTile(
                title: Text('Выбрано из всех пакетов: ' +
                    _wholeGameplaySelection!.selectedUserReviewNotes.length
                        .toString() + ' эффектов'),
                subtitle: const Text('Только частная игровая адаптация. '
                    'Можно отменить перед новой игрой.'),
                trailing: IconButton(
                  key: const Key('multiact-trial-clear-whole-gameplay'),
                  tooltip: 'Не применять выбранные эффекты из всех пакетов',
                  onPressed: _working ? null : () => setState(
                      () => _wholeGameplaySelection = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_gameplaySelection != null)
              ListTile(
                title: Text('Выбрано игровых эффектов: ' +
                    _gameplaySelection!.selectedUserReviewNotes.length
                        .toString()),
                subtitle: const Text('Не канон; влияние на игру '
                    'проверяется перед созданием нового мира.'),
                trailing: IconButton(
                  key: const Key('multiact-trial-clear-gameplay'),
                  tooltip: 'Убрать выбранные игровые эффекты',
                  onPressed: _working ? null : () => setState(
                      () => _gameplaySelection = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            FilledButton.icon(
              key: const Key('multiact-trial-start'),
              onPressed: valid && _reviewed && _privateFiction
                  ? _start : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Создать и начать пробную RPG'),
            ),
            if (_working) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const Text('Проверяем цитаты и условия, компилируем '
                  'частный BookWorld и создаём НОВУЮ кампанию.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  key: const Key('multiact-trial-error'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 8),
            const Text('Ни книга, ни сохранения ранее созданных '
                'кампаний не перезаписываются. '
                'Загрузка в облако для запуска не требуется.'),
          ],
        ),
      ),
    );
  }
}
