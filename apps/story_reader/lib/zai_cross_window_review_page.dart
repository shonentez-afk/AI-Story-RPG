import 'package:flutter/material.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency_page.dart';
import 'zai_source_scene_workbench_page.dart';
import 'zai_semantic_review_queue.dart';

/// A read-only overview of source-backed, manually retained findings,
/// with an isolated notebook of explicitly proposed, NEVER canonical links.
/// No network, no hidden story inference, no BookWorld or campaign writes.
class ZaiCrossWindowReviewPage extends StatefulWidget {
  const ZaiCrossWindowReviewPage({
    super.key,
    required this.queue,
    this.linksRepository,
    this.consistencyRepository,
    this.scenesRepository,
  });

  final ZaiWindowReviewQueue queue;
  final SourceAnalysisCheckpointRepository? linksRepository;
  final SourceAnalysisCheckpointRepository? consistencyRepository;
  final SourceAnalysisCheckpointRepository? scenesRepository;

  @override
  State<ZaiCrossWindowReviewPage> createState() =>
      _ZaiCrossWindowReviewPageState();
}

class _ZaiCrossWindowReviewPageState
    extends State<ZaiCrossWindowReviewPage> {
  late final ZaiCrossWindowEvidenceGraph _graph =
      ZaiCrossWindowEvidenceGraph.fromQueue(widget.queue);
  late final SourceAnalysisCheckpointRepository _repository =
      widget.linksRepository ?? const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.zaiCrossWindowLinks,
      );

  ZaiCrossWindowLinkNotebook? _notebook;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _namesVisible = 20;
  int _eventsVisible = 30;
  int _statementsVisible = 30;
  String? _causeFirst;
  String? _causeSecond;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _repository.read(widget.queue.index.sourceFingerprint);
      final notebook = raw == null
          ? ZaiCrossWindowLinkNotebook.empty(_graph)
          : ZaiCrossWindowLinkNotebook.decode(_graph, raw);
      if (mounted) setState(() { _notebook = notebook; _error = null; });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Сохранённые связи устарели либо повреждены. '
            'Они не применены и не перезаписаны. Обзор цитат доступен; '
            'для создания новых связей можно отдельно сбросить только блокнот.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(ZaiCrossWindowLinkNotebook notebook) async {
    if (_saving || _loading || _notebook == null) return;
    setState(() => _saving = true);
    try {
      await _repository.write(widget.queue.index.sourceFingerprint,
          notebook.encode());
      if (mounted) setState(() { _notebook = notebook; _error = null; });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Не удалось записать новые связи. Старые решения не заменены.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetLinks() async {
    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить только блокнот связей?'),
        content: const Text('Смысловые окна и редакторские отметки сохранятся. '
            'Будут удалены только ранее предложенные связи между цитатами. '
            'Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сбросить связи')),
        ],
      ),
    );
    if (!mounted || agree != true) return;
    setState(() => _saving = true);
    try {
      await _repository.delete(widget.queue.index.sourceFingerprint);
      if (mounted) setState(() {
        _notebook = ZaiCrossWindowLinkNotebook.empty(_graph);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() =>
          _error = 'Сброс блокнота не выполнен. Исходные данные не изменены.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _linkIdentity(ZaiPossibleSameName group) async {
    final notebook = _notebook;
    if (notebook == null || _saving) return;
    final first = group.findings.first;
    final next = group.findings.firstWhere(
        (item) => item.windowPosition != first.windowPosition);
    final yes = await _confirmProposal(
      title: 'Отметить возможное совпадение?',
      first: first,
      second: next,
      explanation: 'Совпадение написания НЕ означает, что это один герой '
          'или одно место. Сохраним только предварительную связь с двумя '
          'точными цитатами для последующей проверки.',
    );
    if (!mounted || !yes) return;
    try {
      await _save(notebook.propose(
          ZaiProposedLinkKind.possibleIdentity, first.id, next.id));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _linkCause() async {
    final notebook = _notebook;
    final firstId = _causeFirst;
    final secondId = _causeSecond;
    if (notebook == null || _saving ||
        firstId == null || secondId == null) return;
    final byId = {for (final e in _graph.reviewed) e.id: e};
    final first = byId[firstId];
    final second = byId[secondId];
    if (first == null || second == null) return;
    final yes = await _confirmProposal(
      title: 'Предложить причинную связь?',
      first: first,
      second: second,
      explanation: 'Порядок изложения в книге НЕ доказывает причинность '
          'или хронологию событий. Это будет только гипотеза редактора '
          '«возможная причина» с обеими исходными цитатами.',
    );
    if (!mounted || !yes) return;
    try {
      await _save(notebook.propose(
          ZaiProposedLinkKind.possibleCause, firstId, secondId));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<bool> _confirmProposal({
    required String title,
    required ZaiAnchoredFinding first,
    required ZaiAnchoredFinding second,
    required String explanation,
  }) async {
    var checked = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(explanation),
                const SizedBox(height: 12),
                Text('Глава ${first.chapterIndex + 1}, окно '
                    '${first.windowPosition + 1}:'),
                SelectableText('«${first.quote}»'),
                const SizedBox(height: 12),
                Text('Глава ${second.chapterIndex + 1}, окно '
                    '${second.windowPosition + 1}:'),
                SelectableText('«${second.quote}»'),
                CheckboxListTile(
                  key: const Key('zai-link-confirm-checkbox'),
                  value: checked,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) =>
                      setLocal(() => checked = value == true),
                  title: const Text('Понимаю, что связь остаётся '
                      'неподтверждённой гипотезой, не каноном.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('zai-link-confirm-submit'),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Сохранить гипотезу'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _openConsistency() async {
    if (!mounted || _saving) return;
    final position = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ZaiEditorialConsistencyPage(
          graph: _graph,
          repository: widget.consistencyRepository,
        ),
      ),
    );
    if (!mounted || position == null) return;
    Navigator.of(context).pop(position);
  }

  Future<void> _openScenes() async {
    if (!mounted || _saving) return;
    final position = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ZaiSourceSceneWorkbenchPage(
          queue: widget.queue,
          scenesRepository: widget.scenesRepository,
          consistencyRepository: widget.consistencyRepository,
        ),
      ),
    );
    if (!mounted || position == null) return;
    Navigator.of(context).pop(position);
  }

  void _toWindow(int position) {
    // Parent page navigates to the exact originally reviewed window.
    Navigator.of(context).pop(position);
  }

  Widget _sourceRow(ZaiAnchoredFinding entry) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    title: Text(entry.label),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Глава ${entry.chapterIndex + 1}, '
            'окно ${entry.windowPosition + 1} · '
            '${entry.candidate.chunkId}'),
        SelectableText('Цитата: «${entry.quote}»'),
      ],
    ),
    trailing: IconButton(
      key: Key('zai-graph-jump-${entry.id}'),
      tooltip: 'Показать исходное окно',
      onPressed: () => _toWindow(entry.windowPosition),
      icon: const Icon(Icons.open_in_new),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final names = _graph.possibleNames;
    final events = _graph.textOrderedEvents.toList();
    final statements = _graph.statedFactsAndStates.toList();
    final notebook = _notebook;
    final enabled = notebook != null && !_saving && !_loading && _error == null;
    final palette = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Сводка цитат книги')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text('Сквозной анализ книги',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Здесь показаны только гипотезы, которые вы '
                    'отметили «Оставить на проверку». Отклонённые и ещё '
                    'нерассмотренные предложения не объединяются. '
                    'Это НЕ готовый сюжет, не канон и не игровая хронология.'),
                const SizedBox(height: 10),
                Text('Окон проверено ${widget.queue.completedCount} '
                    'из ${widget.queue.windows.length} · '
                    'цитат на дальнейшую проверку ${_graph.reviewed.length} · '
                    'возможных повторов имён ${names.length} · '
                    'событий ${events.length} · '
                    'состояний и фактов ${statements.length}',
                    key: const Key('zai-graph-summary')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('zai-open-editorial-consistency'),
                  onPressed: _saving ? null : _openConsistency,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Проверить алиасы, противоречия и хронологию'),
                ),
                OutlinedButton.icon(
                  key: const Key('zai-open-scene-workbench'),
                  onPressed: _saving ? null : _openScenes,
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: const Text('Черновые сцены и отчёт готовности RPG'),
                ),
                if (_loading || _saving)
                  const LinearProgressIndicator(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      key: const Key('zai-graph-checkpoint-error'),
                      style: TextStyle(color: palette.error)),
                  if (notebook == null)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _resetLinks,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Сбросить только старые связи'),
                    ),
                ],
                const SizedBox(height: 18),
                Text('Возможные совпадения имён',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Показываем одинаково написанные имена/места '
                    'в разных окнах. Сознательно НЕ объединяем разных '
                    'людей, псевдонимы и одноимённые локации автоматически.'),
                if (names.isEmpty)
                  const Text('Пока нет повторов среди оставленных цитат.'),
                for (final group in names.take(_namesVisible))
                  Card(
                    child: ExpansionTile(
                      title: Text(group.displayName),
                      subtitle: Text(
                          '${group.findings.length} упоминаний · '
                          'личность НЕ установлена'),
                      children: [
                        for (final entry in group.findings.take(12))
                          _sourceRow(entry),
                        if (group.findings.length > 12)
                          Text('Ещё ${group.findings.length - 12} упоминаний. '
                              'Все цитаты сохранены в локальной очереди.'),
                        TextButton.icon(
                          key: Key('zai-graph-possible-identity-'
                              '${group.findings.first.id}'),
                          onPressed: enabled ? () => _linkIdentity(group) : null,
                          icon: const Icon(Icons.link_outlined),
                          label: const Text('Отметить возможное совпадение'),
                        ),
                      ],
                    ),
                  ),
                if (names.length > _namesVisible)
                  TextButton(
                    onPressed: () => setState(() => _namesVisible += 20),
                    child: const Text('Ещё совпадения'),
                  ),
                const SizedBox(height: 16),
                Text('События в порядке текста',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Порядок цитат не обязательно равен '
                    'хронологии действий в мире книги. Повторяющиеся '
                    'события НЕ схлопываются в одно.'),
                if (events.isEmpty)
                  const Text('Пока нет событий, оставленных на проверку.'),
                for (final entry in events.take(_eventsVisible))
                  Card(child: _sourceRow(entry)),
                if (events.length > _eventsVisible)
                  TextButton(
                    onPressed: () => setState(() => _eventsVisible += 30),
                    child: const Text('Ещё события'),
                  ),
                const SizedBox(height: 16),
                Text('Состояния, намерения и факты',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Это не установленные истины игрового мира. '
                    'В книге могут встречаться обман, слухи и ошибки рассказчика.'),
                for (final entry in statements.take(_statementsVisible))
                  Card(child: _sourceRow(entry)),
                if (statements.isEmpty)
                  const Text('Пока нет утверждений на дальнейшую проверку.'),
                if (statements.length > _statementsVisible)
                  TextButton(
                    onPressed: () => setState(() => _statementsVisible += 30),
                    child: const Text('Ещё утверждения'),
                  ),
                const SizedBox(height: 18),
                Text('Предполагаемые причинные связи',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Можно предложить связь между двумя событиями '
                    'из разных окон. Оба предложения должны иметь проверенные '
                    'цитаты и быть вручную оставлены для дальнейшего анализа.'),
                if (events.length >= 2) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('zai-graph-cause-first'),
                    isExpanded: true,
                    initialValue: _causeFirst,
                    decoration: const InputDecoration(
                        labelText: 'Возможная причина — первое событие'),
                    items: [
                      for (final entry in events)
                        DropdownMenuItem(
                          value: entry.id,
                          child: Text('Гл. ${entry.chapterIndex + 1}: '
                              '${entry.label}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: enabled
                        ? (value) => setState(() => _causeFirst = value) : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('zai-graph-cause-second'),
                    isExpanded: true,
                    initialValue: _causeSecond,
                    decoration: const InputDecoration(
                        labelText: 'Предполагаемое следствие'),
                    items: [
                      for (final entry in events)
                        DropdownMenuItem(
                          value: entry.id,
                          child: Text('Гл. ${entry.chapterIndex + 1}: '
                              '${entry.label}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: enabled
                        ? (value) => setState(() => _causeSecond = value) : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('zai-graph-propose-cause'),
                    onPressed: enabled && _causeFirst != null &&
                        _causeSecond != null && _causeFirst != _causeSecond
                        ? _linkCause : null,
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Предложить связь для проверки'),
                  ),
                ] else
                  const Text('Нужны как минимум два подтверждённых '
                      'редактором для проверки события.'),
                if (notebook != null) ...[
                  const SizedBox(height: 12),
                  Text('Редакторских гипотез о связях: '
                      '${notebook.links.length}',
                      key: const Key('zai-graph-links-count')),
                  for (final link in notebook.links)
                    Card(
                      child: ListTile(
                        title: Text(link.kind ==
                                ZaiProposedLinkKind.possibleIdentity
                            ? 'Возможно один персонаж / место'
                            : 'Возможная причина → следствие'),
                        subtitle: Text('Два исходных свидетельства; '
                            'связь НЕ подтверждена'),
                        trailing: IconButton(
                          tooltip: 'Удалить только эту гипотезу',
                          onPressed: enabled
                              ? () => _save(notebook.remove(link.id)) : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                const Text('Нет автоматических слияний, публикации BookWorld, '
                    'сохранений RPG или сетевых запросов. Результат '
                    'предназначен только для дальнейшей редакторской проверки.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
