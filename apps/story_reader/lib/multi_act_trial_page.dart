import 'package:flutter/material.dart';
import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'bookwide_source_encounters.dart';
import 'story_plan.dart';
import 'reviewed_hero_role.dart';
import 'reviewed_hero_source_action.dart';
import 'bookwide_npc_arc.dart';
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
    this.heroRoleCatalog,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final WorldLibraryGateway gateway;
  /// Defaults to existing local NPC editorial checkpoints, no network.
  /// Injectable for deterministic widget and source-identity tests.
  final ReviewedHeroRoleCatalog? heroRoleCatalog;

  @override
  State<MultiActTrialPage> createState() => _MultiActTrialPageState();
}

class _MultiActTrialPageState extends State<MultiActTrialPage> {
  bool _reviewed = false;
  bool _privateFiction = false;
  bool _enforceEarlierOutcome = false;
  bool _working = false;
  String _heroName = 'Игрок';
  final TextEditingController _heroController =
      TextEditingController(text: 'Игрок');
  late final ReviewedHeroRoleCatalog _roleCatalog =
      widget.heroRoleCatalog ?? const ReviewedHeroRoleCatalog();
  List<ReviewedHeroRole> _eligibleHeroes = const [];
  ReviewedHeroRole? _selectedHeroRole;
  bool _reviewedHeroSourceAction = false;
  ReviewedHeroRole? _selectedNpcRole;
  bool _reviewedNpcArc = false;
  String _npcPlayerLine = 'Я хочу поговорить о том, что произошло.';
  String _npcReplyLine = 'Я помню нашу встречу и отвечу в игровой истории.';
  bool _loadingHeroRoles = false;
  String? _heroNotice;
  String? _error;
  final Map<String, ReviewedProseSceneApproval> _reviewedProse = {};
  final Set<String> _interactiveEvents = {};
  SelectedGameplayCandidates? _gameplaySelection;
  SelectedWholePlanGameplayCandidates? _wholeGameplaySelection;
  WholeStoryLiteraryRecheckApproval? _recheckedRepair;
  WholeStoryLiteraryUnchangedApproval? _unchangedReview;

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _loadHeroRoles() async {
    if (_loadingHeroRoles || _working) return;
    setState(() { _loadingHeroRoles = true; _heroNotice = null; });
    try {
      final roles = await _roleCatalog.load(widget.index);
      if (!mounted) return;
      setState(() {
        _eligibleHeroes = roles;
        if (_selectedHeroRole != null && !roles.any((r) =>
            r.characterId == _selectedHeroRole!.characterId &&
            r.groupDigest == _selectedHeroRole!.groupDigest &&
            r.displayName == _selectedHeroRole!.displayName)) {
          _selectedHeroRole = null;
          _selectedNpcRole = null;
          _reviewedNpcArc = false;
          _reviewedHeroSourceAction = false;
          _heroName = 'Игрок';
          _heroController.text = _heroName;
          _reviewed = false;
          _gameplaySelection = null;
          _wholeGameplaySelection = null;
          _reviewedProse.clear();
          _recheckedRepair = null;
          _unchangedReview = null;
        }
        _heroNotice = roles.isEmpty
            ? 'Подтверждённых персонажей нет. Создайте и проверьте '
              'постоянные карточки NPC в редакторе этой книги.'
            : 'Подтверждено персонажей: ' + roles.length.toString() +
              '. Книга и уже сохранённые игры не меняются.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _eligibleHeroes = const [];
        _selectedNpcRole = null;
        _reviewedNpcArc = false;
        _selectedHeroRole = null;
        _reviewedHeroSourceAction = false;
        _heroName = 'Игрок';
        _heroController.text = _heroName;
        _reviewed = false;
        _gameplaySelection = null;
        _wholeGameplaySelection = null;
        _reviewedProse.clear();
        _recheckedRepair = null;
        _unchangedReview = null;
        _heroNotice = 'Не удалось подтвердить персонажей: ' +
            error.toString() +
            '. Имя не будет автоматически угадано по тексту.';
      });
    } finally {
      if (mounted) setState(() => _loadingHeroRoles = false);
    }
  }

  void _chooseHero(String? id) {
    if (_working) return;
    final chosen = [
      for (final role in _eligibleHeroes)
        if (role.characterId == id) role,
    ];
    if (id != null && id.isNotEmpty && chosen.length != 1) {
      setState(() => _heroNotice =
          'Нужен существующий постоянный character_id.');
      return;
    }
    final role = chosen.isEmpty ? null : chosen.single;
    setState(() {
      _selectedHeroRole = role;
      if (role != null && role.characterId == _selectedNpcRole?.characterId) {
        _selectedNpcRole = null;
        _reviewedNpcArc = false;
      }
      _reviewedHeroSourceAction = false;
      _heroName = role?.displayName ?? 'Игрок';
      _heroController.text = _heroName;
      // Player identity IS part of signed scenario state, so previous
      // role-specific proposals, approvals and prose become stale.
      _reviewed = false;
      _gameplaySelection = null;
      _wholeGameplaySelection = null;
      _reviewedProse.clear();
      _recheckedRepair = null;
      _unchangedReview = null;
      _error = null;
    });
  }

  void _chooseNpc(String? id) {
    if (_working) return;
    final found = _eligibleHeroes.where((r) => r.characterId == id).toList();
    if (id != null && id.isNotEmpty && found.length != 1) return;
    final next = found.isEmpty ? null : found.single;
    setState(() {
      _selectedNpcRole =
          next?.characterId == _selectedHeroRole?.characterId ? null : next;
      _reviewedNpcArc = false;
      _reviewed = false;
      _gameplaySelection = null;
      _wholeGameplaySelection = null;
      _reviewedProse.clear();
      _recheckedRepair = null;
      _unchangedReview = null;
      _error = null;
    });
  }

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
  StoryPlan _effectivePlan({CrossActContinuityDraft? continuity}) {
    final source = BookwideSourceEncounters.attach(
      index: widget.index, book: widget.book, bookMap: widget.bookMap,
      draft: widget.draft,
      plan: _recheckedRepair?.draft ??
          continuity?.plan ?? widget.draft.plan,
      reviewedEventIds: _interactiveEvents,
      userConfirmedPrivateAdaptation: true,
    );
    final rolePlan = _selectedHeroRole?.bindTo(source, widget.book) ?? source;
    final npcArc = _reviewedNpcArc
        ? BookwideNpcArc.review(
            index: widget.index, book: widget.book, plan: rolePlan,
            role: _selectedNpcRole!, privateFictionConfirmed: true,
            playerLine: _npcPlayerLine, npcLine: _npcReplyLine)
        : null;
    if (_reviewedNpcArc && npcArc == null) {
      throw const FormatException('NPC больше не связан с исходной цитатой.');
    }
    final npcPlan = npcArc?.attach(rolePlan, widget.book) ?? rolePlan;
    return _reviewedHeroSourceAction
        ? ReviewedHeroSourceAction.attach(
            index: widget.index, book: widget.book,
            plan: npcPlan, role: _selectedHeroRole!,
            explicitlyConfirmedPrivateGameFiction: true)
        : npcPlan;
  }

  /// A single source/plan revision invalidates prior quotes, model digests
  /// and gameplay item/fact consent. A newly selected batch is NOT approved.
  void _setEncounters(Set<String> next, {int omitted = 0}) {
    if (next.length == _interactiveEvents.length &&
        _interactiveEvents.containsAll(next)) return;
    setState(() {
      _interactiveEvents..clear()..addAll(next);
      _reviewedHeroSourceAction = false;
      _reviewedNpcArc = false;
      _reviewed = false;
      _gameplaySelection = null;
      _wholeGameplaySelection = null;
      _reviewedProse.clear();
      _recheckedRepair = null;
      _unchangedReview = null;
      _error = omitted > 0
          ? 'Часть источника остаётся за лимитом: ещё ' +
              omitted.toString() + ' событий не добавлено в игру.'
          : null;
    });
  }

  void _changeEncounter(int act, String eventId, bool choose) {
    final eligible = BookwideSourceEncounters.eligibleForAct(
        index: widget.index, bookMap: widget.bookMap,
        draft: widget.draft, partIndex: act);
    if (!eligible.any((e) => e.id == eventId)) {
      setState(() => _error = 'Событие отсутствует в этой части книги.');
      return;
    }
    final next = <String>{..._interactiveEvents};
    if (choose) {
      final groupCount = eligible.where((e) => next.contains(e.id)).length;
      if (!next.contains(eventId) &&
          (groupCount >= BookwideSourceEncounters.maxReviewedEventsPerAct ||
           next.length >= BookwideSourceEncounters.remainingSceneCapacity(
               widget.draft.plan))) {
        setState(() => _error =
            'Достигнута вместимость акта или игрового мира. '
            'Остальные остаются в отчёте о покрытии.');
        return;
      }
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    _setEncounters(next);
  }

  void _selectAllAvailableEncounters() {
    final selected = <String>{};
    var available = 0;
    for (var act = 0; act < widget.draft.parts.length; act++) {
      final events = BookwideSourceEncounters.eligibleForAct(
          index: widget.index, bookMap: widget.bookMap,
          draft: widget.draft, partIndex: act);
      available += events.length;
      for (final event in events.take(
          BookwideSourceEncounters.maxReviewedEventsPerAct)) {
        if (selected.length >= BookwideSourceEncounters.remainingSceneCapacity(
                widget.draft.plan)) {
          break;
        }
        selected.add(event.id);
      }
    }
    _setEncounters(selected, omitted: available - selected.length);
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
    // M2h8d1 is deliberately bounded to SIX exact excerpts. If a
    // human-approved role-observe choice is in a later act, include THAT
    // verified citation rather than silently hiding the offline reading
    // option behind the first six unrelated excerpts.
    final sample = _reviewEvents.take(6).toList();
    if (_reviewedHeroSourceAction && _selectedHeroRole != null) {
      final anchor = ReviewedHeroSourceAction.find(
        index: widget.index, book: widget.book,
        plan: candidatePlan, role: _selectedHeroRole!);
      if (anchor != null && !sample.any((e) => e.id == anchor.eventId)) {
        final matching = _reviewEvents.where(
            (e) => e.id == anchor.eventId).toList();
        if (matching.length != 1) {
          setState(() => _error =
              'Не найден проверенный фрагмент ролевого действия.');
          return;
        }
        if (sample.length == 6) sample.removeLast();
        sample.add(matching.single);
        sample.sort((a, b) =>
            a.narrativePosition.compareTo(b.narrativePosition));
      }
    }
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
         _reviewedHeroSourceAction || _reviewedNpcArc ||
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
      // A second local read prevents silently compiling an ID from an
      // NPC notebook deleted or regrouped since the selection was shown.
      if (_selectedHeroRole != null || _reviewedNpcArc) {
        final fresh = await _roleCatalog.load(widget.index);
        for (final selected in [
          if (_selectedHeroRole != null) _selectedHeroRole!,
          if (_reviewedNpcArc) _selectedNpcRole!,
        ]) {
          if (!fresh.any((role) =>
              role.characterId == selected.characterId &&
              role.groupDigest == selected.groupDigest &&
              role.displayName == selected.displayName)) {
            throw const FormatException(
                'Проверенная карточка персонажа изменилась после выбора.');
          }
        }
      }
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
        selectedHeroRole: _selectedHeroRole,
        reviewedHeroSourceAction: _reviewedHeroSourceAction,
        npcEncounterRole: _reviewedNpcArc ? _selectedNpcRole : null,
        reviewedNpcEncounter: _reviewedNpcArc,
        npcPlayerLine: _npcPlayerLine,
        npcReplyLine: _npcReplyLine,
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
    final roleOpportunity = _selectedHeroRole == null ? null :
        ReviewedHeroSourceAction.find(
          index: widget.index, book: widget.book,
          plan: activePlan, role: _selectedHeroRole!);
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: widget.bookMap, book: widget.book, story: activePlan);
    BookwideNpcArc? npcAvailable;
    if (_selectedNpcRole != null &&
        _selectedNpcRole?.characterId != _selectedHeroRole?.characterId) {
      try {
        npcAvailable = BookwideNpcArc.review(
          index: widget.index, book: widget.book, plan: activePlan,
          role: _selectedNpcRole!, privateFictionConfirmed: true,
          playerLine: _npcPlayerLine, npcLine: _npcReplyLine,
        );
      } on FormatException {
        npcAvailable = null;
      }
    }
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
            OutlinedButton.icon(
              key: const Key('multiact-load-reviewed-heroes'),
              onPressed: _working || _loadingHeroRoles
                  ? null : _loadHeroRoles,
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Загрузить проверенные карточки героя и NPC'),
            ),
            if (_loadingHeroRoles)
              const LinearProgressIndicator(),
            if (_heroNotice != null)
              Text(_heroNotice!, key: const Key('multiact-hero-notice')),
            if (_eligibleHeroes.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('multiact-hero-identity-' +
                    (_selectedHeroRole?.characterId ?? 'free')),
                initialValue: _selectedHeroRole?.characterId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Постоянная личность игрового героя',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '', child: Text('Свободный игровой герой'),
                  ),
                  for (final role in _eligibleHeroes)
                    DropdownMenuItem(
                      value: role.characterId,
                      child: Text(role.displayName +
                          ' · ' + role.characterId.substring(0, 12)),
                    ),
                ],
                onChanged: _working
                    ? null : (id) => _chooseHero(id),
              ),
            if (_selectedHeroRole != null)
              const Text('Роль привязана к постоянному character_id '
                  'в игровом состоянии и сохранении. Знания NPC, '
                  'секреты и литературный канон автоматически '
                  'не передаются игроку.'),
            if (_selectedHeroRole != null)
              CheckboxListTile(
                key: const Key('multiact-reviewed-role-source-action'),
                value: _reviewedHeroSourceAction,
                onChanged: !_working && roleOpportunity != null
                    ? (value) => setState(() {
                        _reviewedHeroSourceAction = value == true;
                        // Changed real plan IDs/flags invalidate every
                        // prior source, literary and gameplay approval.
                        _reviewed = false;
                        _gameplaySelection = null;
                        _wholeGameplaySelection = null;
                        _reviewedProse.clear();
                        _recheckedRepair = null;
                        _unchangedReview = null;
                        _error = null;
                      })
                    : null,
                title: const Text(
                    'Добавить ролевое действие по цитате (частная игра)'),
                subtitle: Text(roleOpportunity == null
                    ? 'Выберите два последовательных дополнительных '
                      'события; первое должно содержать проверенное '
                      'дословное упоминание выбранного персонажа.'
                    : 'В первом выбранном событии можно отметить '
                      'своё подтверждённое упоминание. Во втором '
                      'появится вариант вспомнить сделанную проверку. '
                      'Эти решения изменяют игровой журнал/состояние, '
                      'но не подтверждают знания, канон или '
                      'присутствие NPC в оригинальном событии.'),
              ),
            TextFormField(
              key: const Key('multiact-hero-label'),
              controller: _heroController,
              enabled: _selectedHeroRole == null && !_working,
              maxLength: 90,
              decoration: InputDecoration(
                labelText: 'Имя героя в игровой версии',
                helperText: _selectedHeroRole == null
                    ? 'Свободный персонаж: только подпись игрока'
                    : 'Имя закреплено за проверенной личностью NPC',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _heroName = value),
            ),
            if (_eligibleHeroes.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('multiact-npc-identity-' +
                    (_selectedNpcRole?.characterId ?? 'none')),
                initialValue: _selectedNpcRole?.characterId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Собеседник NPC из проверенной карточки',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '', child: Text('Без NPC-диалога'),
                  ),
                  for (final role in _eligibleHeroes)
                    if (role.characterId != _selectedHeroRole?.characterId)
                      DropdownMenuItem(
                        value: role.characterId,
                        child: Text(role.displayName),
                      ),
                ],
                onChanged: _working ? null : _chooseNpc,
              ),
              if (_selectedNpcRole != null) ...[
                const Text('Диалог — частная игровая выдумка. Личность NPC '
                    'подтверждена редактором, слова не выдаются за канон.'),
                TextFormField(
                  key: const Key('multiact-npc-player-line'),
                  initialValue: _npcPlayerLine,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Реплика героя (игровая версия)',
                  ),
                  onChanged: (value) => setState(() {
                    _npcPlayerLine = value;
                    _reviewedNpcArc = false;
                    _reviewed = false;
                  }),
                ),
                TextFormField(
                  key: const Key('multiact-npc-reply-line'),
                  initialValue: _npcReplyLine,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Реплика NPC (игровая версия)',
                  ),
                  onChanged: (value) => setState(() {
                    _npcReplyLine = value;
                    _reviewedNpcArc = false;
                    _reviewed = false;
                  }),
                ),
                CheckboxListTile(
                  key: const Key('multiact-reviewed-npc-arc'),
                  value: _reviewedNpcArc,
                  onChanged: !_working && npcAvailable != null
                      ? (value) => setState(() {
                          _reviewedNpcArc = value == true;
                          _reviewed = false;
                          _gameplaySelection = null;
                          _wholeGameplaySelection = null;
                          _reviewedProse.clear();
                          _unchangedReview = null;
                          _recheckedRepair = null;
                          _error = null;
                        })
                      : null,
                  title: const Text(
                      'Разрешить NPC-встречу, память и условный ответ'),
                  subtitle: Text(npcAvailable == null
                      ? 'Нужны два последовательных выбранных события; '
                        'в первом требуется дословно подтверждённое '
                        'упоминание NPC.'
                      : 'Событие ' + npcAvailable.firstEventId +
                        ' → разговор → память NPC → ответ в следующем '
                        'событии. Всё сохранится в автономной игре.'),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Text('Перед запуском проверим ' +
                (count * 2 + _interactiveEvents.length).toString() +
                ' исходных игровых решений (включая опорные) и ' +
                (2 * (count - 1)).toString() +
                ' переходов между актами по реальным путям движка. '
                'Это не подтверждение литературного канона.',
                key: const Key('multiact-campaign-executable-contract')),
            const SizedBox(height: 8),
            ExpansionTile(
              // Keep this editorial drawer expanded when the long ListView
              // lazily disposes it while the user reviews quotes below.
              key: const PageStorageKey<String>(
                  'multiact-source-encounters'),
              title: const Text('Дополнительные игровые события из книги'),
              subtitle: Text('Выбрано ' +
                  _interactiveEvents.length.toString() +
                  '; до ' +
                  BookwideSourceEncounters.maxReviewedEventsPerAct.toString() +
                  ' событий на акт. Общего лимита 48 нет; '
                  'действуют проверки границ актов и вместимости мира. '
                  'Это настоящие интерактивные выборы, но смысл и '
                  'хронология литературного оригинала не доказаны.'),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      key: const Key('multiact-select-all-encounters'),
                      onPressed: _working ? null : _selectAllAvailableEncounters,
                      icon: const Icon(Icons.library_add_check_outlined),
                      label: const Text('Выбрать доступные события'),
                    ),
                    if (_interactiveEvents.isNotEmpty)
                      TextButton(
                        key: const Key('multiact-clear-all-encounters'),
                        onPressed: _working
                            ? null : () => _setEncounters(<String>{}),
                        child: const Text('Снять выбор'),
                      ),
                  ],
                ),
                const Text('Выбор не заменяет проверку каждой цитаты: '
                    'её потребуется подтвердить заново.'),
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
