import 'package:flutter/material.dart';
import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'bookwide_source_encounters.dart';
import 'story_plan.dart';
import 'cross_act_consequence_gate.dart';
import 'multi_act_trial_compiler.dart';
import 'source_locked_prose_preview_page.dart';
import 'source_locked_prose_batch_page.dart';
import 'reviewed_prose_scene_overlay.dart';
import 'reviewed_gameplay_compiler.dart';
import 'source_locked_gameplay_review_page.dart';
import 'whole_plan_gameplay_batch_page.dart';
import 'whole_story_literary_review_page.dart';
import 'whole_story_literary_bounded_repair.dart';
import 'whole_story_literary_unchanged_approval.dart';
import 'story_plan_causal_audit.dart';
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
  /// Signed player label only; this does not mint an NPC character_id.
  String _heroName = 'Игрок';
  String? _error;
  final Map<String, ReviewedProseSceneApproval> _reviewedProse = {};
  final Set<String> _interactiveEvents = {};
  SelectedGameplayCandidates? _gameplaySelection;
  SelectedWholePlanGameplayCandidates? _wholeGameplaySelection;
  WholeStoryLiteraryRecheckApproval? _recheckedRepair;
  WholeStoryLiteraryUnchangedApproval? _unchangedReview;

  List<NarrativeEvent> get _reviewEvents {
    final ids = <String>{
      for (final part in widget.draft.parts) ...[
        part.setupEventId, part.outcomeEventId,
      ],
      ..._interactiveEvents,
    };
    return List.unmodifiable([
      for (final event in widget.book.events)
        if (ids.contains(event.id)) event,
    ]);
  }

  // All reviews and previews must bind the SAME effective plan as the game.
  CrossActContinuityDraft? _currentReviewedContinuity() {
    if (!_enforceEarlierOutcome) return null;
    return CrossActConsequenceGate.applyReviewedActChain(
      index: widget.index, book: widget.book, bookMap: widget.bookMap,
      draft: widget.draft, userConfirmedFictionalContinuity: true,
    );
  }

  // Preview binds the SAME plan used for model consent, ZIP and SQLite.
  // Compilation independently checks the actual private-use consent.
  StoryPlan _effectivePlan({CrossActContinuityDraft? continuity}) =>
      BookwideSourceEncounters.attach(
        index: widget.index, book: widget.book, bookMap: widget.bookMap,
        draft: widget.draft,
        plan: _recheckedRepair?.draft ??
            continuity?.plan ?? widget.draft.plan,
        reviewedEventIds: _interactiveEvents,
        userConfirmedPrivateAdaptation: true,
      );

  void _changeEncounter(int act, String eventId, bool choose) {
    setState(() {
      for (final event in BookwideSourceEncounters.eligibleForAct(
          index: widget.index, bookMap: widget.bookMap,
          draft: widget.draft, partIndex: act)) {
        _interactiveEvents.remove(event.id);
      }
      if (choose) _interactiveEvents.add(eventId);
      // New sources alter the scenario digest and must be re-reviewed.
      _reviewed = false;
      _gameplaySelection = null;
      _wholeGameplaySelection = null;
      _reviewedProse.clear();
      _recheckedRepair = null;
      _unchangedReview = null;
      _error = null;
    });
  }

  Future<void> _chooseGameplay() async {
    if (_working || !_reviewed || !_privateFiction ||
        _unchangedReview != null || !widget.draft.formalRulesPassed) return;
    StoryPlan? candidatePlan;
    try {
      final continuity = _currentReviewedContinuity();
      candidatePlan = _effectivePlan(continuity: continuity);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Не проверены последствия всех актов: $error');
      return;
    }
    // M2h8d1 is deliberately bounded to SIX short, exact source excerpts.
    // Larger multi-act source sets require a separate consented batch.
    final sample = _reviewEvents.take(6).toList(growable: false);
    if (sample.isEmpty) return;
    final selection = await Navigator.of(context)
        .push<SelectedGameplayCandidates>(MaterialPageRoute(
      builder: (_) => SourceLockedGameplayReviewPage(
        index: widget.index,
        book: widget.book,
        plan: candidatePlan!,
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
        _unchangedReview != null || !widget.draft.formalRulesPassed) return;
    StoryPlan? candidatePlan;
    try {
      final continuity = _currentReviewedContinuity();
      candidatePlan = _effectivePlan(continuity: continuity);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Не проверены последствия всех актов: $error');
      return;
    }
    final selection = await Navigator.of(context)
        .push<SelectedWholePlanGameplayCandidates>(MaterialPageRoute(
      builder: (_) => WholePlanGameplayBatchPage(
        index: widget.index, book: widget.book,
        plan: candidatePlan!,
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
        (_reviewedProse.isNotEmpty || _recheckedRepair != null)) {
      setState(() => _error = 'Подтверждённые художественные сцены '
          'относятся к прежней версии игрового плана. '
          'Снимите дополнительное правило или удалите '
          'выбранные художественные сцены из подготовки.');
      return;
    }
    if (_unchangedReview != null &&
        (_recheckedRepair != null || _enforceEarlierOutcome ||
         _interactiveEvents.isNotEmpty ||
         _reviewedProse.isNotEmpty || _gameplaySelection != null ||
         _wholeGameplaySelection != null)) {
      setState(() => _error =
          'Независимая проверка исходного сценария устарела: '
          'нельзя добавлять правила, предметы или сцены после неё.');
      return;
    }
    if (_recheckedRepair != null &&
        (_interactiveEvents.isNotEmpty ||
         _reviewedProse.isNotEmpty || _gameplaySelection != null ||
         _wholeGameplaySelection != null)) {
      setState(() => _error =
          'Старые художественные и предметные предложения относятся '
          'к предыдущей версии плана. Снимите их для повторной сборки.');
      return;
    }
    setState(() { _working = true; _error = null; });
    try {
      final continuity = _currentReviewedContinuity();
      final effectivePlan = _effectivePlan(continuity: continuity);
      final compiled = await MultiActTrialCompiler.compile(
        index: widget.index,
        book: widget.book,
        bookMap: widget.bookMap,
        draft: widget.draft,
        continuity: continuity,
        recheckedRepair: _recheckedRepair,
        unchangedReview: _unchangedReview,
        sourceEventIdsReviewedByUser: {
          for (final event in _reviewEvents) event.id,
        },
        privateUseConfirmed: _privateFiction,
        fictionalTrialAcknowledged: _privateFiction,
        reviewedProse: _reviewedProse.values.toList(growable: false),
        reviewedInteractiveEventIds: _interactiveEvents,
        heroName: _heroName,
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
            plan: effectivePlan,
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
            plan: effectivePlan,
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
    final activePlan =
        _effectivePlan(continuity: _currentReviewedContinuity());
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: widget.bookMap, book: widget.book, story: activePlan);
    final validHero = _heroName.isNotEmpty &&
        _heroName.trim() == _heroName && _heroName.length <= 90 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(_heroName);
    final valid = count >= 2 &&
        events.length == count * 2 + _interactiveEvents.length &&
        widget.draft.formalRulesPassed && validHero && !_working;
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
                activePlan.situations.length.toString() + '.'),
            const SizedBox(height: 8),
            const Text('Это приватная ПРОБНАЯ игровая адаптация, '
                'НЕ полный сюжет книги и НЕ подтверждённый канон. '
                'Между частями используются придуманные переходы; '
                'диалоги и знания персонажей ещё не сверены с оригиналом. '
                'После компиляции игра работает офлайн.'),
            const SizedBox(height: 8),
            Text('Покрытие книги: обнаружено ' +
                coverage.allEvents.toString() + ' событий; '
                'учтено в игровых сценах ' +
                coverage.referencedEvents.toString() + '; '
                'не представлено ' +
                coverage.eventIdsStillUnrepresented.length.toString() +
                '. Глав без игрового представления: ' +
                coverage.chaptersNotCovered.length.toString() +
                '; главы без предложений событий: ' +
                coverage.chaptersWithoutEventProposals.length.toString() +
                '.',
                key: const Key('multiact-source-coverage')),
            const SizedBox(height: 8),
            const Text('Даже полное покрытие цитатами ещё не доказывает '
                'литературную причинность, знания персонажей и '
                'готовность полной игры.'),
            const SizedBox(height: 8),
            const Text('Сейчас доступен только пробный ALTER_FATE. '
                'CANON не включаем до подтверждения событий и причинности.',
                key: Key('multiact-available-mode')),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('multiact-hero-label'),
              initialValue: _heroName,
              maxLength: 90,
              decoration: const InputDecoration(
                labelText: 'Имя героя в игровой версии',
                helperText: 'Это только подпись игрока, '
                    'а не подтверждённая роль персонажа книги',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _heroName = value),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('multiact-source-encounters'),
              title: const Text('Дополнительные игровые события из книги'),
              subtitle: Text('Выбрано ' +
                  _interactiveEvents.length.toString() +
                  '; максимум одно дополнительное событие на акт. '
                  'Это настоящие интерактивные выборы, но смысл и '
                  'хронология литературного оригинала не доказаны.'),
              children: [
                for (var act = 0; act < widget.draft.parts.length; act++) ...[
                  Text('Акт ' + (act + 1).toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (BookwideSourceEncounters.eligibleForAct(
                    index: widget.index, bookMap: widget.bookMap,
                    draft: widget.draft, partIndex: act).isEmpty)
                    const ListTile(title: Text(
                        'Других подтверждённых отрывков пока нет')),
                  for (final event in BookwideSourceEncounters.eligibleForAct(
                    index: widget.index, bookMap: widget.bookMap,
                    draft: widget.draft, partIndex: act))
                    CheckboxListTile(
                      key: Key('multiact-extra-' + event.id),
                      value: _interactiveEvents.contains(event.id),
                      isThreeLine: true,
                      title: Text('Исследовать фрагмент из главы ' +
                          (event.source.chapterIndex + 1).toString()),
                      subtitle: Text('«' + event.source.quote + '»',
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      onChanged: _working ? null : (v) =>
                          _changeEncounter(act, event.id, v == true),
                    ),
                ],
              ],
            ),
            const Text('Выбор дополнительного фрагмента сбрасывает '
                'старое подтверждение цитат, версии ИИ-предложений '
                'и художественные правки; повторная сборка не '
                'сохраняет устаревшие разрешения.'),
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
                  _wholeGameplaySelection == null &&
                  _recheckedRepair == null &&
                  _unchangedReview == null
                  ? (v) => setState(() =>
                      _enforceEarlierOutcome = v == true)
                  : null,
              title: const Text('Согласен с вымышленными последствиями '
                  'между КАЖДЫМИ соседними актами книги'),
              subtitle: Text('Во всех ' +
                  (widget.draft.parts.length - 1).toString() +
                  ' переходах принять условие следующего акта можно '
                  'только после исходного решения предыдущего. '
                  'Отказ остаётся возможным. Изменяет выборы, '
                  'сохраняется в игре, но не доказывает канон.'),
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
                  onTap: _working || _enforceEarlierOutcome ||
                      _recheckedRepair != null ||
                      _unchangedReview != null ? null : () async {
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
                  onTap: _working || _enforceEarlierOutcome ||
                      _recheckedRepair != null ||
                      _unchangedReview != null ? null : () async {
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
                  _recheckedRepair == null &&
                  _unchangedReview == null
                  ? _chooseGameplay : null,
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
                  _recheckedRepair == null &&
                  _unchangedReview == null
                  ? () async {
                await _chooseWholeGameplay();
              } : null,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Предложения по всему сюжету '
                  '(пакетная обработка)'),
            ),
            const Text('Предметы и знания проверяются против ТОЙ ЖЕ '
                'редакции сюжета, включая последствия между актами. '
                'Предложения старой версии нельзя использовать повторно '
                'без проверки. Облачные запросы и игровые эффекты '
                'требуют отдельного согласия.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('multiact-trial-whole-literary-review'),
              onPressed: valid && !_working && !_enforceEarlierOutcome
                  ? () async {
                final result = await Navigator.of(context)
                    .push<Object>(
                  MaterialPageRoute(
                    builder: (_) => WholeStoryLiteraryReviewPage(
                      index: widget.index, book: widget.book,
                      plan: widget.draft.plan,
                      approvedRules: StoryCausalContract(
                        decisionInvariants: [
                          ...widget.draft.causalContract.decisionInvariants,
                        ],
                        knowledgeGates:
                            widget.draft.causalContract.knowledgeGates,
                        exclusiveGroups:
                            widget.draft.causalContract.exclusiveGroups,
                      ),
                    ),
                  ),
                );
                if (!mounted || result == null) return;
                if (result is WholeStoryLiteraryUnchangedApproval) {
                  result.verifyForCompiler(
                      index: widget.index, book: widget.book,
                      plan: widget.draft.plan);
                  setState(() {
                    _reviewedProse.clear();
                    _gameplaySelection = null;
                    _wholeGameplaySelection = null;
                    _enforceEarlierOutcome = false;
                    _recheckedRepair = null;
                    _unchangedReview = result;
                    _error = null;
                  });
                } else if (result is WholeStoryLiteraryRecheckApproval) {
                  result.verifyForCompiler(
                      index: widget.index, book: widget.book,
                      originalPlan: widget.draft.plan);
                  setState(() {
                    _reviewedProse.clear();
                    _gameplaySelection = null;
                    _wholeGameplaySelection = null;
                    _enforceEarlierOutcome = false;
                    _unchangedReview = null;
                    _recheckedRepair = result;
                    _error = null;
                  });
                }
              } : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Проверить всю логику сюжета через ИИ'),
            ),
            if (_enforceEarlierOutcome)
              const Text('Литературный отчёт базового плана нельзя '
                  'переиспользовать после изменения правил всех актов. '
                  'Для этой редакции нужна новая отдельная проверка.'),
            const Text('Независимо проверяются все достижимые решения. '
                'Если ошибок не найдено, можно отдельно принять '
                'исходный частный черновик; если ошибки исправимы — '
                'только повторно проверенную новую редакцию. '
                'Ни один результат не доказывает книжный канон. '
                'Каждый новый ИИ-запрос требует согласия.'),
            if (_unchangedReview != null)
              ListTile(
                key: const Key('multiact-trial-unchanged-review-ready'),
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Исходный план проверен без замечаний'),
                subtitle: Text('Частная пробная RPG; '
                    'окон с неопределённостью: ' +
                    _unchangedReview!.unresolvedWindows.toString() +
                    ', неохваченных событий книги: ' +
                    _unchangedReview!.uncoveredSourceEvents.toString() +
                    '. Канон не доказан. Дополнения требуют нового аудита.'),
                trailing: IconButton(
                  key: const Key('multiact-trial-clear-unchanged-review'),
                  tooltip: 'Убрать заключение исходного сценария',
                  onPressed: _working ? null : () => setState(
                      () => _unchangedReview = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_recheckedRepair != null)
              ListTile(
                key: const Key('multiact-trial-literary-recheck-ready'),
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Исправленный план повторно проверен'),
                subtitle: const Text('Только частная RPG: это новая '
                    'редакция сценария; литературный канон не доказан. '
                    'После подтверждения будет собран новый .bworld.'),
                trailing: IconButton(
                  key: const Key('multiact-trial-clear-literary-recheck'),
                  tooltip: 'Убрать повторно проверенную редакцию',
                  onPressed: _working ? null : () => setState(
                      () => _recheckedRepair = null),
                  icon: const Icon(Icons.close),
                ),
              ),
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
