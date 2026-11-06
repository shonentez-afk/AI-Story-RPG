import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'gameplay_candidate_reachability.dart';
import 'reviewed_gameplay_compiler.dart';
import 'zai_source_locked_gameplay_candidates.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'whole_plan_gameplay_candidate_batch.dart';
import 'zai_semantic_preview.dart';

/// A reviewed subset of the completed whole-book, multi-window candidates.
/// Returning it to the parent DOES NOT install an effect or make a new game.
class SelectedWholePlanGameplayCandidates {
  const SelectedWholePlanGameplayCandidates({
    required this.manifest,
    required this.drafts,
    required this.selectedUserReviewNotes,
  });

  final WholePlanGameplayBatchManifest manifest;
  final List<GameplayCandidateDraft> drafts;
  final Map<String, String> selectedUserReviewNotes;
}

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
  GameplayReachabilityReport? _audit;
  List<GameplayCandidateDraft> _drafts = const [];
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _notes = {};
  bool _confirmPrivateFiction = false;
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
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    final manifest = _manifest;
    if (manifest == null) return;
    try {
      final progress = await _service.inspect(manifest);
      final all = await _service.readUnreviewedProposals(manifest);
      final report = progress.allProposalsCollected
          ? const GameplayCandidateReachabilityAuditor().auditAcrossBatches(
              plan: manifest.plan, manifest: manifest, drafts: all,
            )
          : null;
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _audit = report;
        if (progress.allProposalsCollected) {
          _drafts = List.unmodifiable(all);
        }
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
      final report = progress.allProposalsCollected
          ? const GameplayCandidateReachabilityAuditor().auditAcrossBatches(
              plan: manifest.plan, manifest: manifest, drafts: all,
            )
          : null;
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _audit = report;
        if (progress.allProposalsCollected) {
          _drafts = List.unmodifiable(all);
        }
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

  void _selectForNextGame() {
    final manifest = _manifest;
    final status = _progress;
    if (_working || manifest == null || status == null ||
        !status.allProposalsCollected || !_confirmPrivateFiction ||
        _selected.isEmpty || _selected.length > 6 ||
        _drafts.length != manifest.totalBatches) return;

    final notes = <String, String>{};
    for (final id in _selected) {
      final value = _notes[id]?.text.trim() ?? '';
      if (value.length < 18 || value.length > 350) {
        setState(() => _error = 'Каждый выбранный эффект требует '
            'отдельного пояснения (от 18 до 350 символов).');
        return;
      }
      notes[id] = value;
    }
    final selectedDrafts = [
      for (final draft in _drafts)
        GameplayCandidateDraft(
          sourceFingerprint: draft.sourceFingerprint,
          approvalDigest: draft.approvalDigest,
          candidates: [
            for (final candidate in draft.candidates)
              if (_selected.contains(
                  ReviewedGameplayCompiler.signature(candidate)))
                candidate,
          ],
        ),
    ];
    try {
      final audit = const GameplayCandidateReachabilityAuditor()
          .auditAcrossBatches(
        plan: manifest.plan, manifest: manifest, drafts: selectedDrafts,
      );
      if (!audit.hasNoRouteConflicts) {
        final failure = audit.issues.first;
        setState(() => _error = 'Выбранные игровые эффекты '
            'противоречат маршруту: ' + failure.code +
            ' / ' + failure.pathChoiceIds.join(' → '));
        return;
      }
      // No game is modified: the parent must compile and ask the user
      // to confirm the resulting exact-digest review in a SECOND dialog.
      Navigator.of(context).pop(SelectedWholePlanGameplayCandidates(
        manifest: manifest,
        drafts: List.unmodifiable(_drafts),
        selectedUserReviewNotes: Map.unmodifiable(notes),
      ));
    } catch (error) {
      setState(() => _error = 'Нельзя передать эти предложения '
          'в подготовку: ' + error.toString());
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
              if (_audit != null) ...[
                ListTile(
                  key: Key(_audit!.hasNoRouteConflicts
                      ? 'whole-gameplay-batch-audit-ok'
                      : 'whole-gameplay-batch-audit-problems'),
                  leading: Icon(_audit!.hasNoRouteConflicts
                      ? Icons.fact_check_outlined
                      : Icons.report_problem_outlined),
                  title: Text(_audit!.hasNoRouteConflicts
                      ? 'Противоречий игровых маршрутов не найдено'
                      : 'Конфликты игровых маршрутов: '
                          '${_audit!.issues.length}'),
                  subtitle: Text('Проверено состояний: '
                      '${_audit!.visitedStates}. '
                      'Это НЕ подтверждает литературный канон.'),
                ),
                for (final issue in _audit!.issues)
                  Card(
                    child: ListTile(
                      title: Text(issue.code + ' / ' +
                          issue.resourceId),
                      subtitle: Text('Сцена: ' + issue.sceneId +
                          ', выбор: ' + issue.choiceId +
                          ', путь: ' + issue.pathChoiceIds.join(' → ')),
                    ),
                  ),
              ],
              if (status.allProposalsCollected &&
                  _drafts.length == manifest.totalBatches) ...[
                const SizedBox(height: 16),
                const Text('Одобрить отдельные игровые эффекты',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Text('Это отдельное редакторское решение. '
                    'Можно выбрать максимум ШЕСТЬ эффектов '
                    'из ВСЕХ пакетов. Никаких новых запросов Z.ai '
                    'при выборе не отправляется. '
                    'Отказ от всех предложений допустим.'),
                for (final (n, candidate) in [
                  for (final draft in _drafts) ...draft.candidates,
                ].indexed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            key: Key('whole-gameplay-select-' +
                                n.toString()),
                            title: Text(candidate.label),
                            subtitle: Text(candidate.op + ' · ' +
                                candidate.sceneId + '/' +
                                candidate.choiceId),
                            value: _selected.contains(
                                ReviewedGameplayCompiler.signature(candidate)),
                            onChanged: _working || (_selected.length == 6 &&
                                    !_selected.contains(ReviewedGameplayCompiler
                                        .signature(candidate)))
                                ? null : (checked) => setState(() {
                                  final id = ReviewedGameplayCompiler
                                      .signature(candidate);
                                  if (checked == true) {
                                    _selected.add(id);
                                    _notes.putIfAbsent(id,
                                        () => TextEditingController());
                                  } else {
                                    _selected.remove(id);
                                  }
                                  _confirmPrivateFiction = false;
                                }),
                          ),
                          Text(candidate.uncertainty),
                          if (_selected.contains(
                              ReviewedGameplayCompiler.signature(candidate)))
                            TextField(
                              key: Key('whole-gameplay-note-' +
                                  n.toString()),
                              controller: _notes[
                                  ReviewedGameplayCompiler.signature(
                                      candidate)],
                              maxLength: 350,
                              maxLines: 3,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Почему допустимо для частной игры',
                                helperText: '18–350 символов. '
                                    'Не подтверждает канон книги.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_selected.isNotEmpty) ...[
                  Text('Выбрано: ' + _selected.length.toString() +
                      ' из 6 возможных эффектов.'),
                  CheckboxListTile(
                    key: const Key('whole-gameplay-private-fiction'),
                    value: _confirmPrivateFiction,
                    onChanged: _working ? null :
                        (value) => setState(() =>
                            _confirmPrivateFiction = value == true),
                    title: const Text('Я отдельно разрешаю только '
                        'частную ИГРОВУЮ выдумку, не литературный канон'),
                  ),
                  FilledButton.icon(
                    key: const Key('whole-gameplay-return-selection'),
                    onPressed: !_working && _confirmPrivateFiction &&
                        _selected.length <= 6 &&
                        _selected.every((id) {
                          final note = _notes[id]?.text.trim() ?? '';
                          return note.length >= 18 && note.length <= 350;
                        }) ? _selectForNextGame : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Вернуть выбранное в подготовку RPG'),
                  ),
                ],
              ],
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
          if (_error != null) ...[
            Text(_error!, key: const Key('whole-gameplay-batch-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
            if (status != null && !_working)
              TextButton(
                key: const Key('whole-gameplay-batch-recheck'),
                onPressed: () => setState(() {
                  _error = null;
                  _reviewed = false;
                  _consented = false;
                }),
                child: const Text('Перепроверить и подтвердить заново'),
              ),
          ],
          const SizedBox(height: 10),
          const Text('Этот экран ничего не записывает в BookWorld или '
              'кампанию. После сбора предложений потребуется '
              'независимая проверка и редакторское подтверждение.'),
        ],
      )),
    );
  }
}
