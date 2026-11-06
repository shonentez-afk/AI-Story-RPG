import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'whole_plan_gameplay_candidate_batch.dart';
import 'zai_semantic_preview.dart';

/// Optional foreground UI. No GLM call until exact on-screen consent.
/// Suggestions collected here NEVER edit a BookWorld or install a campaign.
class WholePlanGameplayBatchPage extends StatefulWidget {
  const WholePlanGameplayBatchPage({
    super.key,
    required this.index,
    required this.book,
    required this.plan,
    this.service,
  });
  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final WholePlanGameplayBatchService? service;

  @override
  State<WholePlanGameplayBatchPage> createState() =>
      _WholePlanGameplayBatchPageState();
}

class _WholePlanGameplayBatchPageState
    extends State<WholePlanGameplayBatchPage> {
  // Constant across page reopens, so stored request consent is not
  // accidentally invalidated by a changed per-run cost limit.
  static const maxRequestsPerTap = 2;
  final _cancellation = ZaiPreviewCancellation();
  late final WholePlanGameplayBatchService _service;
  WholePlanGameplayBatchManifest? _manifest;
  WholePlanGameplayBatchProgress? _progress;
  String? _error;
  bool _working = false;
  bool _loaded = false;
  bool _reviewed = false;
  bool _consented = false;
  int _suggestions = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WholePlanGameplayBatchService();
    try {
      _manifest = WholePlanGameplayBatchManifest.fromPlan(
        index: widget.index, book: widget.book, plan: widget.plan,
        maxNewRequestsPerRun: maxRequestsPerTap,
      );
      _restore();
    } catch (error) {
      _error = 'Не удалось проверить план книги: $error';
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final manifest = _manifest;
    if (manifest == null) return;
    try {
      final progress = await _service.inspect(manifest);
      final all = await _service.readUnreviewedProposals(manifest);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _suggestions = all.fold<int>(
            0, (n, draft) => n + draft.candidates.length);
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = 'Checkpoint не прошёл проверку: $error. '
            'Новые платные запросы не отправлены.';
      });
    }
  }

  Future<void> _generate() async {
    final manifest = _manifest;
    if (manifest == null || _working || !_loaded ||
        _error != null || !_reviewed || !_consented ||
        (_progress?.remaining ?? 0) == 0) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final progress = await _service.generate(
        manifest: manifest,
        approvedManifestDigest: manifest.approvalDigest,
        explicitBatchConsent: true,
        cancellation: _cancellation,
        onProgress: (next) {
          if (mounted) setState(() => _progress = next);
        },
      );
      final all = await _service.readUnreviewedProposals(manifest);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _suggestions = all.fold<int>(
            0, (n, draft) => n + draft.candidates.length);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Проверка остановлена: $error. '
          'Уже сохранённые предложения остаются на устройстве.');
    } finally {
      if (mounted) {
        // A second bounded batch always requires a FRESH user action.
        setState(() {
          _working = false;
          _reviewed = false;
          _consented = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final status = _progress;
    final canSend = manifest != null && status != null && _loaded &&
        !_working && _error == null && status.remaining > 0 &&
        _reviewed && _consented;
    return Scaffold(
      appBar: AppBar(title: const Text('Предметы: весь игровой план')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(widget.index.title,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Это НЕ литературная проверка всех событий '
              'книги. Предложения ИИ по решениям StoryPlan '
              'не становятся игровыми предметами автоматически.'),
          if (manifest != null) ...[
            const SizedBox(height: 10),
            Text('Пакетов: ${manifest.totalBatches}, '
                'проверяемых событий: '
                '${manifest.totalReferencedSourceEvents}. '
                'Событий без привязанных игровых решений: '
                '${manifest.unanchoredBookEvents}.'),
            Text('Каждый запрос — максимум 6 цитат, 16 решений, 8 КБ. '
                'Один запуск — не больше $maxRequestsPerTap новых запросов '
                '(до ${manifest.maxHttpAttempts} HTTP-попыток '
                'при временных ошибках). Запросы могут расходовать '
                'лимит API.'),
            Text('Контрольный SHA согласия: ${manifest.approvalDigest}'),
            const SizedBox(height: 12),
            const Text('Проверьте ТОЧНО те отрывки, решения и JSON, '
                'которые могут быть отправлены в Z.ai:'),
            for (final (n, request) in manifest.contexts.indexed)
              Card(child: ExpansionTile(
                key: Key('whole-gameplay-batch-source-$n'),
                title: Text('Пакет ${n + 1} из ${manifest.totalBatches}'),
                subtitle: Text('${request.excerpts.length} цитат, '
                    '${request.choices.length} решений'),
                childrenPadding: const EdgeInsets.all(12),
                children: [
                  for (final e in request.excerpts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Глава ${e.source.chapterIndex + 1}'),
                          SelectableText('«${e.source.quote}»'),
                        ],
                      ),
                    ),
                  for (final d in request.choices)
                    ListTile(
                      dense: true, title: Text(d.intent),
                      subtitle: Text('Сцена: ${d.sceneId} · '
                          'выбор: ${d.choiceId}'),
                    ),
                  ExpansionTile(
                    title: const Text('Точный JSON отправки'),
                    children: [SelectableText(request.payloadJson)],
                  ),
                ],
              )),
            if (!_loaded) const LinearProgressIndicator(),
            if (status != null) ...[
              Text('Сохранено пакетов: ${status.completed} '
                  'из ${status.total}, осталось: ${status.remaining}.'),
              Text('Неподтверждённых предложений: $_suggestions. '
                  'Пустой ответ — допустимый результат.'),
              if (status.allProposalsCollected)
                const ListTile(
                  key: Key('whole-gameplay-batch-finished'),
                  leading: Icon(Icons.task_alt),
                  title: Text('Все пакеты собраны'),
                  subtitle: Text('Это только черновики, '
                      'не исполняемые правила RPG.'),
                ),
            ],
            if (status != null && status.remaining > 0) ...[
              CheckboxListTile(
                key: const Key('whole-gameplay-batch-reviewed'),
                value: _reviewed, contentPadding: EdgeInsets.zero,
                onChanged: _working ? null : (v) => setState(() =>
                    _reviewed = v == true),
                title: const Text('Я сверил(а) исходные цитаты, '
                    'решения и состав пакетов'),
              ),
              CheckboxListTile(
                key: const Key('whole-gameplay-batch-consent'),
                value: _consented, contentPadding: EdgeInsets.zero,
                onChanged: _working ? null : (v) => setState(() =>
                    _consented = v == true),
                title: const Text('Разрешаю сейчас отправить не более '
                    'двух новых пакетов в Z.ai, возможно с оплатой API'),
              ),
              FilledButton.icon(
                key: const Key('whole-gameplay-batch-run'),
                onPressed: canSend ? _generate : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Обработать следующие пакеты'),
              ),
            ],
          ],
          if (_working) ...[
            const LinearProgressIndicator(),
            const Text('Следующий запуск потребует отдельного '
                'подтверждения. Закрытие страницы остановит '
                'дальнейшие запросы.'),
          ],
          if (_error != null)
            Text(_error!, key: const Key('whole-gameplay-batch-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 10),
          const Text('Этот экран ничего не записывает в BookWorld или '
              'кампанию. После сбора предложений потребуется '
              'независимая проверка и редакторское подтверждение.'),
        ],
      )),
    );
  }
}
