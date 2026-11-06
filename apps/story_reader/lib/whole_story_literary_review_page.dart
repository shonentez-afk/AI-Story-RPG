import 'dart:convert';
import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';
import 'whole_story_literary_bounded_repair.dart';
import 'whole_story_literary_batch.dart';
import 'whole_story_literary_evidence_manifest.dart';
import 'whole_story_literary_review.dart';
import 'whole_story_literary_summary.dart';
import 'zai_semantic_preview.dart';

/// Opening the optional page only reads LOCAL state. Network calls require
/// TWO independent checkboxes and a deliberate foreground submit.
class WholeStoryLiteraryReviewPage extends StatefulWidget {
  const WholeStoryLiteraryReviewPage({
    super.key, required this.index, required this.book, required this.plan,
    this.claimEvidence, this.service, this.approvedRules,
    this.postRepair,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final SourceEvidenceGraph? claimEvidence;
  final WholeStoryLiteraryBatchService? service;
  // Only separately confirmed existing, typed rules; never raw GLM hints.
  final StoryCausalContract? approvedRules;
  // Set for the re-review of a newly patched plan, never for the old plan.
  final WholeStoryLiteraryRepairResult? postRepair;

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
  bool _causalRulesReviewed = false;
  bool _newResultsReviewed = false;
  bool _privateFictionConfirmed = false;
  bool _storageBlocked = false;
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
        _storageBlocked = true;
        _error = 'Повреждён или устарел локальный результат: ' +
            error.toString() + '. Повторные запросы заблокированы.';
      });
    }
  }

  Future<void> _run() async {
    final manifest = _manifest;
    if (manifest == null || _loading || _working ||
        !_reviewed || !_consented || _storageBlocked ||
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

  Future<void> _proposeRepair() async {
    final manifest = _manifest;
    if (manifest == null || _loading || _working ||
        !_causalRulesReviewed || _progress?.complete != true ||
        _reports.length != manifest.totalWindows ||
        widget.approvedRules == null) return;
    setState(() { _working = true; _error = null; });
    try {
      final summary = WholeStoryLiterarySummary.compile(
          manifest: manifest, reports: _reports);
      final proposal = WholeStoryLiteraryBoundedRepair.propose(
        manifest: manifest, reports: _reports,
        approvedRules: widget.approvedRules!,
        expectedReportDigest: summary.reportDigest,
        explicitRuleReview: true,
      );
      if (!proposal.changed) {
        if (mounted) setState(() => _error =
          'Для этой редакции не найдено безопасных автоматических правок. '
          'Неизвестные мотивы, факты и знания нельзя исправить догадкой ИИ.');
        return;
      }
      if (!mounted) return;
      // Open the SAME existing review page for the revised plan; the key
      // includes its new SHA. Never re-use the old paid consent or reports.
      final verified = await Navigator.of(context)
          .push<WholeStoryLiteraryRecheckApproval>(MaterialPageRoute(
        builder: (_) => WholeStoryLiteraryReviewPage(
          index: widget.index, book: widget.book,
          plan: proposal.draft, claimEvidence: widget.claimEvidence,
          service: _service, postRepair: proposal,
        ),
      ));
      if (mounted && verified != null) {
        Navigator.of(context).pop<WholeStoryLiteraryRecheckApproval>(verified);
      }
    } catch (error) {
      if (mounted) setState(() => _error =
          'Безопасное исправление не принято: ' + error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _acceptRecheckedPlan() {
    final repair = widget.postRepair;
    final manifest = _manifest;
    if (repair == null || manifest == null || _working || _loading ||
        _progress?.complete != true ||
        _reports.length != manifest.totalWindows ||
        !_newResultsReviewed || !_privateFictionConfirmed) return;
    try {
      if (manifest.approvalDigest !=
          repair.newReviewManifest?.approvalDigest) {
        throw const FormatException('Версия исправленного плана изменилась.');
      }
      final approval = WholeStoryLiteraryRecheckApproval.accept(
        repair: repair, newReports: _reports,
        userReviewedNewResults: true,
        confirmedPrivateGameFiction: true,
      );
      // The original plan is checked against its SHA again at compilation.
      if (mounted) Navigator.of(context)
          .pop<WholeStoryLiteraryRecheckApproval>(approval);
    } catch (error) {
      if (mounted) setState(() => _error =
          'Нельзя завершить повторную проверку: ' + error.toString());
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
    final canSend = !_loading && !_working && !_storageBlocked &&
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
                        .convert(jsonDecode(window.exactUserMessage))),
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
            if (!_loading && !_storageBlocked &&
                progress != null && !progress.complete) ...[
              CheckboxListTile(
                key: const Key('whole-literary-reviewed'),
                title: const Text('Я сверил(а) исходные цитаты '
                    'и состав всех показанных пакетов'),
                contentPadding: EdgeInsets.zero,
                value: _reviewed,
                onChanged: _working ? null : (v) =>
                    setState(() { _reviewed = v == true; _error = null; }),
              ),
              CheckboxListTile(
                key: const Key('whole-literary-consent'),
                title: const Text('Разрешаю сейчас отправить не более '
                    'двух новых пакетов в Z.ai для независимой проверки'),
                contentPadding: EdgeInsets.zero,
                value: _consented,
                onChanged: _working ? null : (v) =>
                    setState(() { _consented = v == true; _error = null; }),
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
            if (progress?.complete == true &&
                _reports.length == manifest.totalWindows) ...[
              const Divider(height: 24),
              Builder(builder: (context) {
                final summary = WholeStoryLiterarySummary.compile(
                  manifest: manifest, reports: _reports);
                return Card(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Итог всей проверки',
                          key: const Key('whole-literary-summary-title'),
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('Пакетов: ' + summary.totalWindows.toString() +
                          '; переходов: ' + summary.totalTransitions.toString() +
                          '; замечаний: ' + summary.totalFindings.toString() +
                          '; недостаточно данных: ' +
                          summary.insufficient.toString() + '.'),
                      Text('Неохваченных событий: ' +
                          summary.uncoveredEvents.toString() +
                          '; межпакетных повторов для проверки: ' +
                          summary.crossWindowIssues.length.toString() + '.'),
                      const Text('Это неподтверждённая литературная '
                          'диагностика, а не доказательство канона. '
                          'Автоматическое исправление не разрешено.'),
                      for (final issue in summary.crossWindowIssues)
                        Text('Повтор в разных пакетах: ' +
                            issue['scene_choice_kind'].toString()),
                    ],
                  ),
                ));
              }),
              if (widget.approvedRules != null &&
                  widget.postRepair == null) ...[
                const SizedBox(height: 10),
                const Text('Можно применить только безопасные условия '
                    'существующих игровых флагов, подтверждённые отдельно. '
                    'Ни одной новой книжной истины программа не придумывает.'),
                for (final rule in widget.approvedRules!.decisionInvariants)
                  Text('Игровое правило: ' + rule.decisionId +
                      (rule.requires.isEmpty ? '' :
                        '; требует: ' + rule.requires.join(', ')) +
                      (rule.forbids.isEmpty ? '' :
                        '; запрещено при: ' + rule.forbids.join(', '))),

                CheckboxListTile(
                  key: const Key('whole-literary-repair-rule-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: _causalRulesReviewed,
                  onChanged: _working ? null : (value) => setState(
                      () => _causalRulesReviewed = value == true),
                  title: const Text('Я проверил(а) причинные правила '
                      'и разрешаю создать новый черновик'),
                ),
                OutlinedButton.icon(
                  key: const Key('whole-literary-repair-propose'),
                  onPressed: !_working && _causalRulesReviewed
                      ? _proposeRepair : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Исправить допустимые ошибки '
                      'и повторно проверить сюжет'),
                ),
              ],
              if (widget.postRepair != null) ...[
                const SizedBox(height: 10),
                const Text('Это НОВАЯ версия сюжета. Старое заключение '
                    'и разрешение на платные запросы больше не действуют. '
                    'Для продолжения нужна полная повторная проверка.'),
                CheckboxListTile(
                  key: const Key('whole-literary-recheck-reviewed'),
                  contentPadding: EdgeInsets.zero,
                  value: _newResultsReviewed,
                  onChanged: _working ? null : (value) => setState(
                      () => _newResultsReviewed = value == true),
                  title: const Text('Я проверил(а) новые заключения '
                      'по всей игре'),
                ),
                CheckboxListTile(
                  key: const Key('whole-literary-recheck-private'),
                  contentPadding: EdgeInsets.zero,
                  value: _privateFictionConfirmed,
                  onChanged: _working ? null : (value) => setState(
                      () => _privateFictionConfirmed = value == true),
                  title: const Text('Это только частная вымышленная '
                      'игровая адаптация, не доказанный канон'),
                ),
                FilledButton.icon(
                  key: const Key('whole-literary-recheck-accept'),
                  onPressed: !_working && _newResultsReviewed &&
                      _privateFictionConfirmed ? _acceptRecheckedPlan : null,
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Передать проверенный черновик '
                      'для частной RPG'),
                ),
              ],
            ],
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
