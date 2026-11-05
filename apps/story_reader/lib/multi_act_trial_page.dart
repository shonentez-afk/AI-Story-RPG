import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'cross_act_consequence_gate.dart';
import 'multi_act_trial_compiler.dart';
import 'source_locked_prose_preview_page.dart';
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

  Future<void> _start() async {
    if (!_reviewed || !_privateFiction || _working) return;
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
      );
      if (!mounted || compiled.sourceFingerprint !=
          widget.index.sourceFingerprint) return;
      final installed = await widget.gateway.install(compiled.archive);
      if (installed.archiveHash != compiled.archiveSha256 ||
          installed.bookworldId != compiled.bookworldId) {
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
              onChanged: valid
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
                  'Черновик не включается в пробную игру.'),
              children: [
                ListTile(
                  key: const Key('multiact-trial-open-prose-preview'),
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Предпросмотр художественной сцены'),
                  subtitle: const Text('Можно восстановить ранее '
                      'сохранённый черновик без нового запроса'),
                  onTap: _working ? null : () =>
                      Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => SourceLockedProsePreviewPage(
                          index: widget.index,
                          book: widget.book,
                          plan: widget.draft.plan,
                        ),
                      )),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
