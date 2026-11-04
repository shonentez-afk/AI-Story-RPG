import 'package:flutter/material.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_provider.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency.dart';

/// M2f3c manual editor. This screen is OFFLINE: no network/provider, no
/// mutation of M2f3a/b, no RPG/BookWorld writes and no canonical promotions.
class ZaiEditorialConsistencyPage extends StatefulWidget {
  const ZaiEditorialConsistencyPage({
    super.key,
    required this.graph,
    this.repository,
  });

  final ZaiCrossWindowEvidenceGraph graph;
  final SourceAnalysisCheckpointRepository? repository;

  @override
  State<ZaiEditorialConsistencyPage> createState() =>
      _ZaiEditorialConsistencyPageState();
}

class _ZaiEditorialConsistencyPageState
    extends State<ZaiEditorialConsistencyPage> {
  late final SourceAnalysisCheckpointRepository _repository =
      widget.repository ?? const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.zaiEditorialConsistency,
      );
  late final List<ZaiPossibleDiscrepancy> _hints =
      ZaiConsistencyHints.reviewCues(widget.graph);

  ZaiEditorialConsistencyNotebook? _notebook;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  ZaiConsistencyKind _kind = ZaiConsistencyKind.possibleDiscrepancy;
  String? _firstId;
  String? _secondId;
  int _visibleHints = 10;
  int _visibleSaved = 20;
  String _filter = '';
  final TextEditingController _filterController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final raw = await _repository.read(widget.graph.index.sourceFingerprint);
      final restored = raw == null
          ? ZaiEditorialConsistencyNotebook.empty(widget.graph)
          : ZaiEditorialConsistencyNotebook.decode(widget.graph, raw);
      if (mounted) setState(() { _notebook = restored; _error = null; });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Ранее сохранённые редакторские вопросы '
            'повреждены либо ссылаются на отозванные цитаты. '
            'Файл не перезаписан, предложения доступны только для просмотра.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _store(ZaiEditorialConsistencyNotebook updated) async {
    if (_saving || _loading || _notebook == null) return;
    setState(() => _saving = true);
    try {
      await _repository.write(
          widget.graph.index.sourceFingerprint, updated.encode());
      if (mounted) setState(() { _notebook = updated; _error = null; });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Запись не выполнена. Прежний блокнот '
            'сохранён, можно повторить действие.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetOnlyConsistency() async {
    if (_saving || _loading) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить вопросы согласованности?'),
        content: const Text('Удалится только отдельный блокнот M2f3c. '
            'Книги, цитаты, решения редактора, связи M2f3b и '
            'игровые сохранения останутся без изменений.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-consistency-reset-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить блокнот M2f3c'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() => _saving = true);
    try {
      await _repository.delete(widget.graph.index.sourceFingerprint);
      if (mounted) setState(() {
        _notebook = ZaiEditorialConsistencyNotebook.empty(widget.graph);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() =>
          _error = 'Не удалось сбросить вопросы. Исходный файл не изменён.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _kindName(ZaiConsistencyKind kind) => switch (kind) {
    ZaiConsistencyKind.possibleAlias => 'Возможные разные имена одного героя',
    ZaiConsistencyKind.possibleDiscrepancy => 'Возможное противоречие',
    ZaiConsistencyKind.possibleRelationship => 'Возможные отношения героев',
    ZaiConsistencyKind.possibleBefore => 'Возможный порядок событий',
  };

  static String _description(ZaiConsistencyKind kind) => switch (kind) {
    ZaiConsistencyKind.possibleAlias =>
        'Два разных имени героя или места — не доказательство тождества. '
        'Даже если кто-то назван по прозвищу, требуется проверить контекст.',
    ZaiConsistencyKind.possibleDiscrepancy =>
        'Противоположные фразы могут относиться к разным временам, '
        'говорящим или условиям. Это вопрос, а не ошибка книги.',
    ZaiConsistencyKind.possibleRelationship =>
        'Упоминания двух героев не доказывают дружбу, родство или вражду. '
        'Запишите, какую связь нужно проверить в исходном тексте.',
    ZaiConsistencyKind.possibleBefore =>
        'Задайте предполагаемый порядок событий внутри истории, '
        'даже если книга рассказывает о них в обратном порядке. '
        'Циклы таких предположений запрещены.',
  };

  List<ZaiAnchoredFinding> _eligible() => [
    for (final source in widget.graph.reviewed)
      if (switch (_kind) {
        ZaiConsistencyKind.possibleAlias =>
          source.category == SemanticCategory.character ||
          source.category == SemanticCategory.location,
        ZaiConsistencyKind.possibleDiscrepancy =>
          source.category == SemanticCategory.fact ||
          source.category == SemanticCategory.state,
        ZaiConsistencyKind.possibleRelationship =>
          source.category == SemanticCategory.character,
        ZaiConsistencyKind.possibleBefore =>
          source.category == SemanticCategory.event,
      }) source,
  ];

  List<ZaiAnchoredFinding> _shownOptions(List<ZaiAnchoredFinding> all) {
    final search = _filter.trim().toLowerCase();
    final subset = all.where((item) =>
        search.isEmpty ||
        item.label.toLowerCase().contains(search) ||
        item.quote.toLowerCase().contains(search)).take(60).toList();
    for (final id in [_firstId, _secondId]) {
      if (id == null || subset.any((item) => item.id == id)) continue;
      for (final item in all) {
        if (item.id == id) {
          subset.add(item);
          break;
        }
      }
    }
    return subset;
  }

  void _prefill(ZaiPossibleDiscrepancy hint) {
    setState(() {
      _kind = ZaiConsistencyKind.possibleDiscrepancy;
      _firstId = hint.first.id;
      _secondId = hint.second.id;
      _filter = '';
      _filterController.clear();
      _reasonController.text = 'Проверить время, говорящего и контекст '
          'двух похожих утверждений с отрицанием.';
    });
  }

  Future<void> _propose() async {
    final notebook = _notebook;
    final firstId = _firstId;
    final secondId = _secondId;
    if (notebook == null || _saving || _loading ||
        firstId == null || secondId == null) return;
    final first = widget.graph.reviewed.where((e) => e.id == firstId).firstOrNull;
    final second = widget.graph.reviewed.where((e) => e.id == secondId).firstOrNull;
    if (first == null || second == null) return;
    final reason = _reasonController.text.trim();
    ZaiEditorialConsistencyNotebook proposed;
    try {
      proposed = notebook.propose(_kind, firstId, secondId, reason);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (identical(proposed, notebook)) {
      setState(() => _error = 'Этот вопрос уже есть в блокноте.');
      return;
    }
    var acknowledged = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, localSet) => AlertDialog(
          scrollable: true,
          title: Text(_kindName(_kind)),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Это только локальный вопрос редактора. '
                    'Данные НЕ попадают в канон или игру.'),
                const SizedBox(height: 10),
                Text('Первый источник · глава ${first.chapterIndex + 1}, '
                    'окно ${first.windowPosition + 1}'),
                SelectableText('«${first.quote}»'),
                const SizedBox(height: 12),
                Text('Второй источник · глава ${second.chapterIndex + 1}, '
                    'окно ${second.windowPosition + 1}'),
                SelectableText('«${second.quote}»'),
                const SizedBox(height: 10),
                Text('Что проверить: $reason'),
                CheckboxListTile(
                  key: const Key('zai-consistency-confirm-check'),
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  title: const Text('Понимаю, что цитаты не доказывают '
                      'тождество, противоречие, отношения или хронологию.'),
                  onChanged: (value) => localSet(
                      () => acknowledged = value == true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('zai-consistency-confirm-save'),
              onPressed: acknowledged ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Сохранить вопрос'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || approved != true) return;
    // Re-evaluate against current state after the dialog; never publish
    // a stale optimistic proposal if another asynchronous save happened.
    try {
      await _store(_notebook!.propose(_kind, firstId, secondId, reason));
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _jumpToSource(ZaiAnchoredFinding finding) =>
      Navigator.of(context).pop(finding.windowPosition);

  Widget _source(ZaiAnchoredFinding finding) => ListTile(
    dense: true,
    title: Text(finding.label),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Глава ${finding.chapterIndex + 1}, '
            'окно ${finding.windowPosition + 1} · '
            '${finding.candidate.chunkId}'),
        SelectableText('«${finding.quote}»'),
      ],
    ),
    trailing: IconButton(
      tooltip: 'Открыть точное исходное окно',
      onPressed: () => _jumpToSource(finding),
      icon: const Icon(Icons.open_in_new),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final visible = _shownOptions(_eligible());
    final enabled = !_loading && !_saving && _notebook != null;
    final palette = Theme.of(context).colorScheme;
    final byId = {for (final finding in graph.reviewed) finding.id: finding};
    final notes = _notebook;

    return Scaffold(
      appBar: AppBar(title: const Text('Проверка согласованности сюжета')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: [
                Text('Алиасы, противоречия и хронология',
                    key: const Key('zai-consistency-title'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Все выводы опираются на оставленные вручную '
                    'дословные цитаты. Истинность высказываний, личность '
                    'героев и время событий здесь НЕ подтверждаются. '
                    'Нет сетевых запросов и автоматического изменения RPG.'),
                const SizedBox(height: 8),
                Text('Источников: ${graph.reviewed.length} · '
                    'возможных противоречий по формулировке: ${_hints.length} · '
                    'вопросов редактора: ${notes?.questions.length ?? 0}',
                    key: const Key('zai-consistency-summary')),
                if (_loading || _saving) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!, key: const Key('zai-consistency-error'),
                      style: TextStyle(color: palette.error)),
                  if (notes == null)
                    OutlinedButton.icon(
                      key: const Key('zai-consistency-reset'),
                      onPressed: _saving ? null : _resetOnlyConsistency,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Сбросить только вопросы M2f3c'),
                    ),
                ],
                const SizedBox(height: 18),
                Text('Сигналы для проверки противоречий',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Подсказки находятся только при одинаковых '
                    'словах с отдельной частицей «не» / «not». '
                    'Это может быть смена состояния, пересказ слухов '
                    'или разные говорящие — не доказанное противоречие.'),
                if (_hints.isEmpty)
                  const Text('Надёжных текстовых совпадений с отрицанием '
                      'пока нет; ручное сравнение доступно ниже.'),
                for (final pair in _hints.take(_visibleHints))
                  Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _source(pair.first),
                        _source(pair.second),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Text(pair.reason),
                        ),
                        TextButton.icon(
                          key: Key('zai-consistency-hint-${pair.first.id}-'
                              '${pair.second.id}'),
                          onPressed: enabled ? () => _prefill(pair) : null,
                          icon: const Icon(Icons.rule),
                          label: const Text('Сравнить эти цитаты вручную'),
                        ),
                      ],
                    ),
                  ),
                if (_hints.length > _visibleHints)
                  TextButton(
                    onPressed: () => setState(() => _visibleHints += 10),
                    child: const Text('Ещё сигналы'),
                  ),
                const SizedBox(height: 20),
                Text('Новый редакторский вопрос',
                    style: Theme.of(context).textTheme.titleMedium),
                DropdownButtonFormField<ZaiConsistencyKind>(
                  key: ValueKey('zai-consistency-kind-${_kind.name}'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Что проверить'),
                  items: [
                    for (final kind in ZaiConsistencyKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(_kindName(kind), overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled ? (kind) {
                    if (kind == null) return;
                    setState(() {
                      _kind = kind;
                      _firstId = null;
                      _secondId = null;
                      _filter = '';
                      _filterController.clear();
                    });
                  } : null,
                ),
                const SizedBox(height: 8),
                Text(_description(_kind)),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('zai-consistency-filter'),
                  controller: _filterController,
                  onChanged: (s) => setState(() => _filter = s),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Найти цитату по имени или словам',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                Text('Показаны первые ${visible.length} '
                    'из ${_eligible().length} источников. '
                    'Для длинной книги используйте поиск.'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-consistency-first-${_kind.name}-${_firstId ?? 'none'}'),
                  initialValue: _firstId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Первая цитата'),
                  items: [
                    for (final item in visible)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text('Гл. ${item.chapterIndex + 1}: '
                            '${item.label}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled
                      ? (id) => setState(() => _firstId = id) : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-consistency-second-${_kind.name}-${_secondId ?? 'none'}'),
                  initialValue: _secondId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Вторая цитата'),
                  items: [
                    for (final item in visible)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text('Гл. ${item.chapterIndex + 1}: '
                            '${item.label}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled
                      ? (id) => setState(() => _secondId = id) : null,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('zai-consistency-reason'),
                  controller: _reasonController,
                  maxLength: 240,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Что именно нужно проверить по двум цитатам?',
                  ),
                ),
                FilledButton.icon(
                  key: const Key('zai-consistency-propose'),
                  onPressed: enabled && _firstId != null &&
                          _secondId != null && _firstId != _secondId
                      ? _propose : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Сопоставить источники'),
                ),
                const SizedBox(height: 18),
                Text('Блокнот вопросов · только локально',
                    style: Theme.of(context).textTheme.titleMedium),
                if (notes == null)
                  const Text('Загрузка или проверка сохранённого блокнота.')
                else if (notes.questions.isEmpty)
                  const Text('Вопросов пока нет. Ни одна связь не подтверждена.'),
                for (final question in notes?.questions.take(_visibleSaved) ??
                    const <ZaiConsistencyQuestion>[])
                  Card(
                    child: ExpansionTile(
                      title: Text(_kindName(question.kind)),
                      subtitle: Text(question.reason),
                      children: [
                        if (byId[question.firstId] != null)
                          _source(byId[question.firstId]!),
                        if (byId[question.secondId] != null)
                          _source(byId[question.secondId]!),
                        const Text('Статус: открытый вопрос, НЕ доказано'),
                        TextButton.icon(
                          onPressed: enabled
                              ? () => _store(notes!.remove(question.id)) : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Удалить этот вопрос'),
                        ),
                      ],
                    ),
                  ),
                if ((notes?.questions.length ?? 0) > _visibleSaved)
                  TextButton(
                    onPressed: () => setState(() => _visibleSaved += 20),
                    child: const Text('Ещё вопросы'),
                  ),
                const SizedBox(height: 16),
                const Text('Это не генератор игрового канона. '
                    'Алиасы, отношения, расхождения и порядок событий '
                    'не публикуются в BookWorld или игровые сохранения.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
