import 'package:flutter/material.dart';
import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan_quality_gate.dart';
import 'story_plan_trial_compiler.dart';
import 'reviewed_gameplay_compiler.dart';
import 'source_locked_gameplay_review_page.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';
import 'zai_story_dilemma_proposal.dart';

/// An explicit, PRIVATE short-trial route after the GLM draft has passed
/// structural checks. Never confuses this short trial with CANON or full
/// automatic book adaptation; never silently installs/starts a campaign.
class StoryPlanTrialPage extends StatefulWidget {
  const StoryPlanTrialPage({
    super.key,
    required this.index,
    required this.book,
    required this.preview,
    required this.quality,
    required this.gateway,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final ZaiStoryDilemmaPreview preview;
  final StoryPlanQualityReport quality;
  final WorldLibraryGateway gateway;

  @override
  State<StoryPlanTrialPage> createState() => _StoryPlanTrialPageState();
}

class _StoryPlanTrialPageState extends State<StoryPlanTrialPage> {
  bool _reviewedQuotes = false;
  bool _privateFiction = false;
  bool _working = false;
  String? _error;
  SelectedGameplayCandidates? _gameplaySelection;

  List<NarrativeEvent> get _sourceEvents {
    final proposal = widget.preview.proposal;
    if (proposal == null) return const [];
    final ids = {proposal.setupEventId, proposal.outcomeEventId};
    return [
      for (final event in widget.book.events)
        if (ids.contains(event.id)) event,
    ];
  }

  Future<void> _chooseGameplay() async {
    if (_working || !_reviewedQuotes || !_privateFiction ||
        !widget.quality.passedFormalPreflight) return;
    final selection = await Navigator.of(context)
        .push<SelectedGameplayCandidates>(MaterialPageRoute(
      builder: (_) => SourceLockedGameplayReviewPage(
        index: widget.index,
        book: widget.book,
        plan: widget.quality.plan,
        exactEventIds: [for (final e in _sourceEvents) e.id],
      ),
    ));
    if (!mounted || selection == null) return;
    setState(() {
      _gameplaySelection = selection;
      _error = null;
    });
  }

  Future<void> _start() async {
    final events = _sourceEvents;
    if (_working || !_reviewedQuotes || !_privateFiction ||
        !widget.quality.passedFormalPreflight ||
        events.length != 2) return;
    setState(() { _working = true; _error = null; });
    try {
      final compiled = await StoryPlanTrialCompiler.compile(
        index: widget.index,
        book: widget.book,
        preview: widget.preview,
        sourceEventIdsReviewedByUser: {
          for (final event in events) event.id,
        },
        privateUseConfirmed: _privateFiction,
        fictionalTrialAcknowledged: _privateFiction,
      );
      if (!mounted || compiled.sourceFingerprint !=
          widget.index.sourceFingerprint) return;
      var archive = compiled.archive;
      if (_gameplaySelection != null) {
        final selection = _gameplaySelection!;
        final review = ReviewedGameplayCompiler.preview(
          currentRichBookworld: compiled.archive,
          index: widget.index, book: widget.book,
          plan: widget.quality.plan,
          context: selection.context,
          proposals: selection.draft,
          selectedUserReviewNotes: selection.selectedUserReviewNotes,
        );
        if (!mounted) return;
        final effects = review.shownReview['effects'] as List;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Подтвердить игровые предметы'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Это вымышленная частная игровая '
                      'адаптация. Цитаты подтверждают слова, но '
                      'не доказывают владение или канон.'),
                  const SizedBox(height: 8),
                  for (final e in effects)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        (e as Map)['label'].toString() + ' — ' +
                        e['op'].toString() + ' / ' +
                        e['choice_id'].toString(),
                      ),
                    ),
                  const Text('Только после подтверждения будет '
                      'собран НОВЫЙ игровой мир. Старые игры '
                      'и сохранения останутся без изменений.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отменить'),
              ),
              FilledButton(
                key: const Key('story-trial-final-gameplay-approval'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Подтверждаю частную игровую выдумку'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        archive = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
          preview: review,
          currentRichBookworld: compiled.archive,
          index: widget.index,
          explicitlyConfirmedPrivateGameFiction: true,
          approvedReviewDigest: review.approvalDigest,
        );
      }
      final finalCheck = const RichPrivateBookworldImporter().inspect(archive);
      if (finalCheck.sourceFingerprint != widget.index.sourceFingerprint) {
        throw const FormatException('Чужая редакция готовой игровой истории');
      }
      final installed = await widget.gateway.install(archive);
      if (installed.archiveHash != finalCheck.archiveSha256 ||
          installed.bookworldId != finalCheck.bookworldId) {
        throw const FormatException(
            'Установленный пакет отличается от проверенной частной игры.');
      }
      if (!mounted) return;
      // A NEW campaign is created. Existing campaigns/saves are untouched.
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(
          gateway: widget.gateway, campaignId: campaignId),
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось запустить пробную RPG: ' +
            error.toString() +
            '. Существующие игры и исходная книга не удалены.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _sourceEvents;
    final allowed = events.length == 2 &&
        widget.quality.passedFormalPreflight && !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('Пробная RPG по развилке')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(widget.index.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text('Это короткая ЛИЧНАЯ игровая адаптация на основе '
                'двух подлинных отрывков и предложений ИИ. '
                'Поступки и две концовки могут отличаться от книги. '
                'Это НЕ полноценная RPG по всему произведению.'),
            const SizedBox(height: 10),
            Text('Ситуаций: ' +
                widget.quality.plan.situations.length.toString() +
                '. Проверка игровых условий: ' +
                (widget.quality.passedFormalPreflight
                    ? 'пройдена' : 'не пройдена') + '.'),
            const SizedBox(height: 8),
            const Text('Проверьте дословные цитаты, которые станут '
                'источниками для пробной игры:'),
            for (final event in events)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Глава ' +
                          (event.source.chapterIndex + 1).toString(),
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      SelectableText('«' + event.source.quote + '»'),
                    ],
                  ),
                ),
              ),
            CheckboxListTile(
              key: const Key('story-trial-review'),
              value: _reviewedQuotes,
              onChanged: allowed
                  ? (value) => setState(
                      () => _reviewedQuotes = value == true) : null,
              title: const Text('Я проверил(а) эти два отрывка в книге'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              key: const Key('story-trial-private-fiction'),
              value: _privateFiction,
              onChanged: allowed
                  ? (value) => setState(
                      () => _privateFiction = value == true) : null,
              title: const Text('Понимаю, что остальные события '
                  'вымышлены, и использую игру только для себя'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('story-trial-optional-gameplay'),
              onPressed: allowed && _reviewedQuotes && _privateFiction
                  ? _chooseGameplay : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Предметы и знания из книги '
                  '(дополнительный запрос ИИ)'),
            ),
            if (_gameplaySelection != null) ...[
              ListTile(
                title: Text('Выбрано игровых эффектов: ' +
                    _gameplaySelection!.selectedUserReviewNotes.length
                        .toString()),
                subtitle: const Text('Не канон. Можно убрать '
                    'перед запуском пробной игры.'),
                trailing: IconButton(
                  key: const Key('story-trial-clear-gameplay'),
                  tooltip: 'Убрать игровые эффекты',
                  onPressed: _working ? null :
                      () => setState(() => _gameplaySelection = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
            FilledButton.icon(
              key: const Key('story-trial-start'),
              onPressed: allowed && _reviewedQuotes && _privateFiction
                  ? _start : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Создать и начать пробную игру'),
            ),
            if (_working) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const Text('Проверяем цитаты, компилируем частный '
                  'BookWorld и создаём новую кампанию.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('story-trial-error'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 8),
            const Text('После подготовки игра работает офлайн. '
                'Она не переписывает существующие сохранения. '
                'Результат не публикуется.'),
          ],
        ),
      ),
    );
  }
}
