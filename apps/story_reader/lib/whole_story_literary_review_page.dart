import 'dart:convert';
import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'whole_story_literary_batch.dart';
import 'whole_story_literary_evidence_manifest.dart';
import 'whole_story_literary_review.dart';
import 'zai_semantic_preview.dart';

/// Opening the optional page only reads LOCAL state. Network calls require
/// TWO independent checkboxes and a deliberate foreground submit.
class WholeStoryLiteraryReviewPage extends StatefulWidget {
  const WholeStoryLiteraryReviewPage({
    super.key, required this.index, required this.book, required this.plan,
    this.claimEvidence, this.service,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final SourceEvidenceGraph? claimEvidence;
  final WholeStoryLiteraryBatchService? service;

  @override
  State<WholeStoryLiteraryReviewPage> createState() =>
      _WholeStoryLiteraryReviewPageState();
}

class _WholeStoryLiteraryReviewPageState
    extends State<WholeStoryLiteraryReviewPage> {
  late final WholeStoryLiteraryBatchService _service;
  WholeStoryLiteraryReviewManifest? _manifest;
  WholeLiteraryReviewProgress? _progress;
  List<WholeLiteraryReviewReport> _reports = const [];
  ZaiPreviewCancellation? _cancellation;
  bool _loading = true;
  bool _working = false;
  bool _reviewed = false;
  bool _consented = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WholeStoryLiteraryBatchService();
    try {
      final evidence = WholeStoryLiteraryEvidenceManifest.build(
        index: widget.index, book: widget.book, plan: widget.plan,
        claimEvidence: widget.claimEvidence,
      );
      _manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: widget.index, book: widget.book, plan: widget.plan,
        evidence: evidence, claimEvidence: widget.claimEvidence,
      );
      _load();
    } catch (error) {
      _loading = false;
      _error = 'Исходная проверка недоступна: ' + error.toString();
    }
  }

  Future<void> _load() async {
    final manifest = _manifest;
    if (manifest == null) return;
    try {
      final stored = await _service.read(manifest);
      final progress = await _service.inspect(manifest);
      if (!mounted) return;
      setState(() {
        _reports = stored;
        _progress = progress;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Повреждён или устарел локальный результат: ' +
            error.toString() + '. Повторные запросы заблокированы.';
      });
    }
  }

  Future<void> _run() async {
    final manifest = _manifest;
    if (manifest == null || _loading || _working ||
        !_reviewed || !_consented || _error != null ||
        _progress?.complete == true) return;
    final token = ZaiPreviewCancellation();
    _cancellation = token;
    setState(() { _working = true; _error = null; });
    try {
      final progress = await _service.generate(
        manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
        explicitBatchConsent: true, cancellation: token,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      final stored = await _service.read(manifest);
      if (!mounted) return;
      setState(() { _reports = stored; _progress = progress; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Проверка остановлена: ' + error.toString() +
          '. Ранее сохранённые пакеты не будут отправлены снова.');
    } finally {
      if (mounted) setState(() {
        _working = false;
        _reviewed = false;
        _consented = false;
        _cancellation = null;
      });
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final progress = _progress;
    final canSend = !_loading && !_working && _error == null &&
        manifest != null && progress != null && !progress.complete &&
        _reviewed && _consented;
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка логики всей истории')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(widget.book.title,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Это независимые замечания ИИ по игровому черновику, '
              'НЕ доказательство литературного канона. '
              'Игра, предметы и сохранения не изменяются.'),
          if (manifest != null) ...[
            Text('Достижимых переходов: ' +
                manifest.totalTransitions.toString() +
                '; пакетов: ' + manifest.totalWindows.toString() +
                '; пропущенных событий книги: ' +
                manifest.notCoveredEvents.toString() + '.'),
            Text('На отдельное согласие: не более ' +
                manifest.maxNewRequestsPerRun.toString() +
                ' новых запросов (оплата возможна) и максимум ' +
                manifest.maxHttpAttempts.toString() +
                ' HTTP-попыток с учётом повторов 429/сети.'),
            Text('Контрольная сумма точного согласия: ' +
                manifest.approvalDigest,
                style: Theme.of(context).textTheme.bodySmall),
            const Text('Раскройте пакеты для просмотра точных цитат, '
                'маршрутов и JSON, которые могут уйти на сервер. '
                'API-ключ, сохранения и полный текст книги не отправляются.'),
            for (final window in manifest.windows)
              Card(child: ExpansionTile(
                key: Key('whole-literary-window-' +
                    window.position.toString()),
                title: Text('Пакет ' +
                    (window.position + 1).toString() +
                    ' из ' + manifest.totalWindows.toString()),
                subtitle: Text(window.transitions.length.toString() +
                    ' переходов, ' +
                    window.sourceQuotes.length.toString() +
                    ' цитат'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(const JsonEncoder.withIndent('  ')
                        .convert(window.sentContext)),
                  ),
                ],
              )),
            if (progress != null) ...[
              Text('Проверено: ' + progress.completed.toString() +
                  ' из ' + progress.total.toString() +
                  '; осталось: ' + progress.remaining.toString() + '.',
                  key: const Key('whole-literary-progress')),
              if (progress.complete)
                const ListTile(
                  key: Key('whole-literary-complete'),
                  leading: Icon(Icons.task_alt),
                  title: Text('Все пакеты обработаны'),
                  subtitle: Text('Заключения остаются гипотезами. '
                      'Исправление сюжета — отдельный этап.'),
                ),
            ],
            if (!_loading && _error == null &&
                progress != null && !progress.complete) ...[
              CheckboxListTile(
                key: const Key('whole-literary-reviewed'),
                title: const Text('Я сверил(а) исходные цитаты '
                    'и состав всех показанных пакетов'),
                contentPadding: EdgeInsets.zero,
                value: _reviewed,
                onChanged: _working ? null : (v) =>
                    setState(() => _reviewed = v == true),
              ),
              CheckboxListTile(
                key: const Key('whole-literary-consent'),
                title: const Text('Разрешаю сейчас отправить не более '
                    'двух новых пакетов в Z.ai для независимой проверки'),
                contentPadding: EdgeInsets.zero,
                value: _consented,
                onChanged: _working ? null : (v) =>
                    setState(() => _consented = v == true),
              ),
              FilledButton.icon(
                key: const Key('whole-literary-submit'),
                onPressed: canSend ? _run : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Проверить следующие пакеты'),
              ),
            ],
            if (_working)
              TextButton.icon(
                key: const Key('whole-literary-cancel'),
                onPressed: () => _cancellation?.cancel(),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Остановить отправку'),
              ),
            if (_loading || _working) const LinearProgressIndicator(),
            if (_reports.isNotEmpty) ...[
              const Divider(height: 30),
              Text('Сохранённые замечания',
                  style: Theme.of(context).textTheme.titleMedium),
              for (var i = 0; i < _reports.length; i++)
                Card(child: ExpansionTile(
                  key: Key('whole-literary-result-' + i.toString()),
                  title: Text('Пакет ' + (i + 1).toString() +
                      ': ' + _reports[i].findings.length.toString() +
                      ' замечаний'),
                  subtitle: Text('Вердикт ИИ: ' +
                      _reports[i].verdict.name + ' (не канон)'),
                  children: [
                    ListTile(title: Text(_reports[i].uncertainty)),
                    for (final finding in _reports[i].findings)
                      ListTile(
                        title: Text(finding.kind.name +
                            ' — ' + finding.severity.name),
                        subtitle: Text(finding.sceneId + '/' +
                            finding.choiceId + ', источник: ' +
                            (finding.sourceEventId ?? 'UNKNOWN') + '\n' +
                            finding.problem),
                      ),
                  ],
                )),
            ],
          ],
          if (_error != null)
            Text(_error!, key: const Key('whole-literary-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
        ],
      )),
    );
  }
}
