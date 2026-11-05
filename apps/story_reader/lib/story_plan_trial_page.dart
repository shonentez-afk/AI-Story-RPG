import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan_quality_gate.dart';
import 'story_plan_trial_compiler.dart';
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

  List<NarrativeEvent> get _sourceEvents {
    final proposal = widget.preview.proposal;
    if (proposal == null) return const [];
    final ids = {proposal.setupEventId, proposal.outcomeEventId};
    return [
      for (final event in widget.book.events)
        if (ids.contains(event.id)) event,
    ];
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
      final installed = await widget.gateway.install(compiled.archive);
      if (installed.archiveHash != compiled.archiveSha256 ||
          installed.bookworldId != compiled.bookworldId) {
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
