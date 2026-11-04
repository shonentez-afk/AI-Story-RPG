import 'package:flutter/material.dart';
import 'preparation_editor_help.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'zai_causal_choices_page.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';

/// Offline, private M2f3d storyboard. No BookWorld writes, provider calls,
/// background inference, gameplay saves or accidental future-chapter reveal.
class ZaiSourceSceneWorkbenchPage extends StatefulWidget {
  const ZaiSourceSceneWorkbenchPage({
    super.key,
    required this.queue,
    this.scenesRepository,
    this.consistencyRepository,
    this.choicesRepository,
  });

  final ZaiWindowReviewQueue queue;
  final SourceAnalysisCheckpointRepository? scenesRepository;
  final SourceAnalysisCheckpointRepository? consistencyRepository;
  final SourceAnalysisCheckpointRepository? choicesRepository;

  @override
  State<ZaiSourceSceneWorkbenchPage> createState() =>
      _ZaiSourceSceneWorkbenchPageState();
}

class _ZaiSourceSceneWorkbenchPageState
    extends State<ZaiSourceSceneWorkbenchPage> {
  late final ZaiCrossWindowEvidenceGraph _graph =
      ZaiCrossWindowEvidenceGraph.fromQueue(widget.queue);
  late final SourceAnalysisCheckpointRepository _scenesRepository =
      widget.scenesRepository ?? const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.zaiSceneDraft,
      );
  late final SourceAnalysisCheckpointRepository _consistencyRepository =
      widget.consistencyRepository ??
          const FileSourceAnalysisCheckpointRepository(
            scope: SourceCheckpointScope.zaiEditorialConsistency,
          );

  ZaiSourceSceneBoard? _board;
  ZaiEditorialConsistencyNotebook? _consistency;
  bool _loading = true;
  bool _saving = false;
  bool _revealedFuture = false;
  String? _error;
  int _chapter = 0;
  int _visibleEvents = 16;
  int _visibleScenes = 16;
  final Set<String> _selected = <String>{};
  String? _selectedClaim;
  ZaiClaimContext _claimContext = ZaiClaimContext.unknown;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _sceneNote = TextEditingController();
  final TextEditingController _claimNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _sceneNote.dispose();
    _claimNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final source = widget.queue.index.sourceFingerprint;
      final rawConsistency = await _consistencyRepository.read(source);
      final consistency = rawConsistency == null
          ? ZaiEditorialConsistencyNotebook.empty(_graph)
          : ZaiEditorialConsistencyNotebook.decode(_graph, rawConsistency);
      // Keep the valid M2f3c notebook available when ONLY the M2f3d
      // scene file is corrupt. A confirmed reset must never touch M2f3c.
      if (mounted) setState(() => _consistency = consistency);
      final rawBoard = await _scenesRepository.read(source);
      final board = rawBoard == null
          ? ZaiSourceSceneBoard.empty(_graph)
          : ZaiSourceSceneBoard.decode(_graph, rawBoard);
      if (mounted) setState(() {
        _board = board;
        _consistency = consistency;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        _board = null;
        _error = 'Сохранённые сцены или редакторские вопросы повреждены, '
            'относятся к другой редакции книги либо ссылаются на '
            'отозванные цитаты. Данные не изменены. '
            'Проверьте источник или отдельно сбросьте черновик сцен.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _store(ZaiSourceSceneBoard next) async {
    if (_saving || _loading || _board == null) return false;
    setState(() => _saving = true);
    try {
      await _scenesRepository.write(
          widget.queue.index.sourceFingerprint, next.encode());
      if (mounted) setState(() { _board = next; _error = null; });
      return true;
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось сохранить черновик сцен. Предыдущая версия не заменена.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetBoard() async {
    if (_loading || _saving || _consistency == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить только черновик сцен?'),
        content: const Text('Это удалит только отдельные сцены и заметки '
            'о контексте событий. Книги и цитаты, '
            'проверенные факты и сохранения игр останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-scene-reset-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить черновик сцен'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() => _saving = true);
    try {
      await _scenesRepository.delete(widget.queue.index.sourceFingerprint);
      if (mounted) setState(() {
        _board = ZaiSourceSceneBoard.empty(_graph);
        _selected.clear();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось удалить черновик, исходные данные не изменены.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showFutureChapter() async {
    if (_revealedFuture || widget.queue.index.chapterCount < 2) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Открыть цитаты следующих глав?'),
        content: const Text('Список будущих событий может раскрыть '
            'спойлеры. Разрешение действует только до закрытия '
            'этого экрана; оно не передаётся ИИ и не сохраняется.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Не показывать')),
          FilledButton(
            key: const Key('zai-scene-spoilers-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Показать будущие главы')),
        ],
      ),
    );
    if (mounted && allowed == true) {
      setState(() => _revealedFuture = true);
    }
  }

  List<ZaiAnchoredFinding> get _chapterEvents =>
      _graph.textOrderedEvents.where((e) => e.chapterIndex == _chapter).toList();
  List<ZaiAnchoredFinding> get _chapterClaims =>
      _graph.statedFactsAndStates.where(
          (e) => e.chapterIndex == _chapter).toList();
  Map<String, ZaiAnchoredFinding> get _byId =>
      {for (final e in _graph.reviewed) e.id: e};

  Future<void> _addScene() async {
    final board = _board;
    if (board == null || _saving || _selected.isEmpty) return;
    final events = _chapterEvents.where(
        (e) => _selected.contains(e.id)).toList();
    ZaiSourceSceneBoard proposed;
    try {
      proposed = board.addScene(
          events.map((e) => e.id).toList(),
          _title.text, _sceneNote.text);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    var checked = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, localSet) => AlertDialog(
          scrollable: true,
          title: const Text('Сохранить сцену с исходными цитатами?'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сцена: ${proposed.scenes.last.title}'),
                Text('Глава ${_chapter + 1}. '
                    'Это НЕ готовая игровая сцена и НЕ канон.'),
                const SizedBox(height: 8),
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText('«${e.quote}»'),
                  ),
                CheckboxListTile(
                  key: const Key('zai-scene-confirm-check'),
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  onChanged: (value) =>
                      localSet(() => checked = value == true),
                  title: const Text('Понимаю, что цитаты и порядок '
                      'ещё не доказывают правдивость событий и причинность.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('zai-scene-confirm-save'),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Сохранить черновик сцены'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || approved != true) return;
    try {
      if (await _store(_board!.addScene(
          events.map((e) => e.id).toList(), _title.text, _sceneNote.text))) {
        if (mounted) setState(() {
          _selected.clear();
          _title.clear();
          _sceneNote.clear();
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _saveClaimContext() async {
    final board = _board;
    final claimId = _selectedClaim;
    if (board == null || claimId == null || _saving) return;
    try {
      final updated = board.noteContext(
          claimId, _claimContext, _claimNote.text);
      if (await _store(updated) && mounted) {
        setState(() {
          _selectedClaim = null;
          _claimNote.clear();
          _claimContext = ZaiClaimContext.unknown;
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openCausalChoices() async {
    final board = _board;
    final consistency = _consistency;
    if (!mounted || _saving || _loading ||
        board == null || consistency == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ZaiCausalChoicesPage(
          queue: widget.queue,
          board: board,
          consistency: consistency,
          repository: widget.choicesRepository,
        ),
      ),
    );
  }

  void _openWindow(int position) =>
      Navigator.of(context).pop(position);

  Widget _quoteRow(ZaiAnchoredFinding e) => ListTile(
    dense: true,
    title: Text(e.label),
    subtitle: SelectableText('Глава ${e.chapterIndex + 1}, '
        'окно ${e.windowPosition + 1}: «${e.quote}»'),
    trailing: IconButton(
      tooltip: 'Показать исходное окно',
      onPressed: () => _openWindow(e.windowPosition),
      icon: const Icon(Icons.open_in_new),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final ready = board != null && _consistency != null &&
        !_saving && !_loading;
    final choices = _revealedFuture
        ? <int>[for (var i = 0;
              i < widget.queue.index.chapterCount; i++) i] : <int>[0];
    final events = _chapterEvents;
    final claims = _chapterClaims;
    final used = <String>{
      for (final scene in board?.scenes ?? <ZaiSourceScene>[]) ...scene.eventIds,
    };
    final report = board == null ? null : ZaiScenePreflight.assess(
        widget.queue, board, consistency: _consistency);
    final palette = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Черновые сцены книги')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('Сцены по событиям книги',
                    key: const Key('zai-scene-title'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text('Только локальный черновик. Не создаёт '
                    'готовую RPG, персонажей или альтернативные развилки. '
                    'События сохраняют точные ссылки на книгу.'),
                const PreparationEditorHelp(
                  purpose: 'Собирает события книги в последовательные игровые сцены.',
                  steps: [
                    'Выберите подтверждённые исходные события.',
                    'Создайте для каждого эпизода понятное название и порядок.',
                    'Проверьте ссылки на книгу и готовность черновика.',
                  ],
                  result: 'сохранённые сцены с точными источниками, ещё без игровых выборов.',
                  next: 'откройте «Игровые решения и последствия».',
                ),
                if (_loading || _saving) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!, key: const Key('zai-scene-error'),
                      style: TextStyle(color: palette.error)),
                  if (board == null && _consistency != null)
                    OutlinedButton.icon(
                      key: const Key('zai-scene-reset'),
                      onPressed: _saving ? null : _resetBoard,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Сбросить только черновик сцен'),
                    ),
                ],
                const SizedBox(height: 10),
                Text('Готово сцен: ${board?.scenes.length ?? 0} · '
                    'фактов с пометкой источника: '
                    '${board?.contexts.length ?? 0} · '
                    'вся книга: ${widget.queue.index.chapterCount} глав',
                    key: const Key('zai-scene-counts')),
                const SizedBox(height: 12),
                const Text('Будущие главы и их цитаты скрыты, '
                    'пока вы отдельно не разрешите показ спойлеров.'),
                if (!_revealedFuture &&
                    widget.queue.index.chapterCount > 1)
                  OutlinedButton.icon(
                    key: const Key('zai-scene-reveal-future'),
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: _showFutureChapter,
                    label: const Text('Разрешить показ будущих глав'),
                  ),
                DropdownButtonFormField<int>(
                  key: ValueKey('zai-scene-chapter-$_chapter-'
                      '${_revealedFuture ? 'all' : 'safe'}'),
                  isExpanded: true,
                  initialValue: _chapter,
                  decoration: const InputDecoration(labelText: 'Глава для сцены'),
                  items: [
                    for (final i in choices)
                      DropdownMenuItem(
                        value: i, child: Text('Глава ${i + 1}'),
                      ),
                  ],
                  onChanged: ready ? (next) {
                    if (next == null) return;
                    setState(() {
                      _chapter = next;
                      _selected.clear();
                      _selectedClaim = null;
                      _visibleEvents = 16;
                    });
                  } : null,
                ),
                const SizedBox(height: 16),
                Text('События из этой главы',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Выберите от 1 до ${ZaiSourceSceneBoard.maxEventsPerScene} '
                    'разных событий. Не смешиваем события из разных глав '
                    'и не допускаем повторного использования одного события.'),
                if (events.isEmpty)
                  const Text('Пока нет событий, оставленных на проверку.'),
                for (final finding in events.take(_visibleEvents))
                  Card(
                    child: CheckboxListTile(
                      key: Key('zai-scene-event-${finding.id}'),
                      value: _selected.contains(finding.id),
                      onChanged: ready && !used.contains(finding.id)
                          ? (selected) => setState(() {
                              if (selected == true) {
                                if (_selected.length <
                                    ZaiSourceSceneBoard.maxEventsPerScene) {
                                  _selected.add(finding.id);
                                }
                              } else {
                                _selected.remove(finding.id);
                              }
                            }) : null,
                      title: Text(finding.label),
                      subtitle: Text('Окно ${finding.windowPosition + 1}: '
                          '«${finding.quote}»'
                          '${used.contains(finding.id) ? ' · уже включено' : ''}'),
                    ),
                  ),
                if (events.length > _visibleEvents)
                  TextButton(
                    onPressed: () => setState(() => _visibleEvents += 16),
                    child: const Text('Ещё события этой главы'),
                  ),
                TextField(
                  key: const Key('zai-scene-name-input'),
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Название черновой сцены',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  key: const Key('zai-scene-note-input'),
                  controller: _sceneNote,
                  maxLength: 320,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Замечание для проверки (не игровая команда)',
                    border: OutlineInputBorder(),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('zai-scene-add'),
                  onPressed: ready && _selected.isNotEmpty
                      ? _addScene : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Создать сцену из выбранных цитат'),
                ),
                const SizedBox(height: 20),
                Text('Утверждения: источник, а не истина мира',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Для каждого утверждения можно сохранить '
                    'характер источника: текст рассказчика, речь героя, '
                    'спорная информация или неизвестно. '
                    'Это не делает высказывание доказанным фактом.'),
                if (claims.isEmpty)
                  const Text('В этой главе пока нет таких находок.'),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-scene-claim-$_chapter-'
                      '${_selectedClaim ?? 'none'}'),
                  isExpanded: true,
                  initialValue: _selectedClaim,
                  decoration: const InputDecoration(
                      labelText: 'Выберите утверждение'),
                  items: [
                    for (final claim in claims.take(60))
                      DropdownMenuItem(
                        value: claim.id,
                        child: Text(claim.label,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: ready ? (id) => setState(
                      () => _selectedClaim = id) : null,
                ),
                if (_selectedClaim != null &&
                    _byId[_selectedClaim] != null)
                  _quoteRow(_byId[_selectedClaim]!),
                DropdownButtonFormField<ZaiClaimContext>(
                  key: const Key('zai-scene-claim-context'),
                  isExpanded: true,
                  initialValue: _claimContext,
                  decoration: const InputDecoration(
                      labelText: 'Как подана информация?'),
                  items: const [
                    DropdownMenuItem(value: ZaiClaimContext.unknown,
                        child: Text('Не установлено')),
                    DropdownMenuItem(value: ZaiClaimContext.narratorText,
                        child: Text('Текст рассказчика')),
                    DropdownMenuItem(value: ZaiClaimContext.characterSpeech,
                        child: Text('Утверждение персонажа')),
                    DropdownMenuItem(value: ZaiClaimContext.disputed,
                        child: Text('Есть основания сомневаться')),
                  ],
                  onChanged: ready && _selectedClaim != null
                      ? (value) => setState(() {
                          _claimContext = value ?? ZaiClaimContext.unknown;
                        }) : null,
                ),
                TextField(
                  key: const Key('zai-scene-context-note'),
                  controller: _claimNote,
                  maxLength: 240,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Почему выбрали такой контекст?',
                    border: OutlineInputBorder(),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('zai-scene-save-context'),
                  onPressed: ready && _selectedClaim != null
                      ? _saveClaimContext : null,
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('Сохранить контекст утверждения'),
                ),
                const SizedBox(height: 20),
                Text('Сцены в порядке редакторского черновика',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Порядок карточек можно менять; он не '
                    'устанавливает истинную хронологию событий.'),
                if (board != null && board.scenes.isEmpty)
                  const Text('Ещё нет сцен. Исходная книга не изменена.'),
                for (final entry in (board?.scenes ??
                    <ZaiSourceScene>[]).indexed.take(_visibleScenes))
                  Card(
                    child: entry.$2.chapterIndex > 0 && !_revealedFuture
                        ? const ListTile(
                            title: Text('Сцена из скрытой главы'),
                            subtitle: Text('Нужен отдельный показ спойлеров'),
                          )
                        : ExpansionTile(
                            title: Text(entry.$2.title),
                            subtitle: Text('Глава ${entry.$2.chapterIndex + 1} · '
                                '${entry.$2.eventIds.length} событий · '
                                'черновик, не канон'),
                            children: [
                              if (entry.$2.notes.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(entry.$2.notes),
                                ),
                              for (final id in entry.$2.eventIds)
                                if (_byId[id] != null) _quoteRow(_byId[id]!),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'Поднять сцену',
                                    onPressed: ready && entry.$1 > 0
                                        ? () => _store(board.moveScene(
                                            entry.$2.id, entry.$1 - 1))
                                        : null,
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: 'Опустить сцену',
                                    onPressed: ready &&
                                        entry.$1 < board.scenes.length - 1
                                        ? () => _store(board.moveScene(
                                            entry.$2.id, entry.$1 + 1))
                                        : null,
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  IconButton(
                                    tooltip: 'Удалить только сцену',
                                    onPressed: ready ? () => _store(
                                        board.removeScene(entry.$2.id)) : null,
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                if ((board?.scenes.length ?? 0) > _visibleScenes)
                  TextButton(
                    onPressed: () => setState(() => _visibleScenes += 16),
                    child: const Text('Ещё черновые сцены'),
                  ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const Key('zai-open-causal-editor'),
                  onPressed: ready && board.scenes.isNotEmpty
                      ? _openCausalChoices : null,
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Игровые решения и причинные последствия'),
                ),
                const Text('Изменение списка или порядка сцен делает '
                    'сохранённые игровые выборы требуют повторной проверки. '
                    'Их потребуется проверить заново; прежние сцены '
                    'и книги не удаляются.'),
                const SizedBox(height: 16),
                Text('Отчёт готовности к RPG',
                    key: const Key('zai-scene-preflight-title'),
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Готовый игровой мир пока НЕ собирается. '
                    'Причины ниже — проверяемые, но ни одна галочка '
                    'не заменяет отдельный компилятор BookWorld.'),
                if (report != null) ...[
                  Text('Покрытие оставленных событий: '
                      '${report.coveredEvents} / ${report.totalEvents} · '
                      'черновых сцен ${report.sceneCount}',
                      key: const Key('zai-scene-preflight-summary')),
                  for (final finding in report.findings)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: Text(finding.description),
                    ),
                ],
                const SizedBox(height: 16),
                const Text('Исходные данные, библиотека и игровые '
                    'сохранения остаются нетронутыми. Для создания '
                    'полноценной RPG требуются проверенные выборы, '
                    'последствия и независимая приёмка сценария.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
