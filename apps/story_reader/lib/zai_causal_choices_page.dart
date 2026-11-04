import 'package:flutter/material.dart';
import 'preparation_editor_help.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_provider.dart';
import 'zai_causal_choice_notebook.dart';
import 'zai_editorial_consistency.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';
import 'zai_private_compilation_page.dart';

/// M2f3e: an offline, non-publishing editor over the M2f3d scene checkpoint.
class ZaiCausalChoicesPage extends StatefulWidget {
  const ZaiCausalChoicesPage({
    super.key,
    required this.queue,
    required this.board,
    required this.consistency,
    this.repository,
    this.privateDraftRepository,
    this.privateNarrativeRepository,
    this.privateCatalogRepository,
    this.privateEditorialRepository,
    this.privateAlignmentRepository,
  });

  final ZaiWindowReviewQueue queue;
  final ZaiSourceSceneBoard board;
  final ZaiEditorialConsistencyNotebook consistency;
  final SourceAnalysisCheckpointRepository? repository;
  final SourceAnalysisCheckpointRepository? privateDraftRepository;
  final SourceAnalysisCheckpointRepository? privateNarrativeRepository;
  final SourceAnalysisCheckpointRepository? privateCatalogRepository;
  final SourceAnalysisCheckpointRepository? privateEditorialRepository;
  final SourceAnalysisCheckpointRepository? privateAlignmentRepository;

  @override
  State<ZaiCausalChoicesPage> createState() => _ZaiCausalChoicesPageState();
}

class _ZaiCausalChoicesPageState extends State<ZaiCausalChoicesPage> {
  late final SourceAnalysisCheckpointRepository _repo =
      widget.repository ?? const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.zaiCausalChoices,
      );
  ZaiCausalChoiceNotebook? _notebook;
  bool _loading = true;
  bool _saving = false;
  bool _spoilers = false;
  bool _initialFlag = false;
  String? _error;
  String? _from;
  String? _to;
  String _required = '';
  String _forbidden = '';
  String _added = '';
  String _removed = '';
  String _npcId = '';
  String _knowledgeId = '';
  final _flagInput = TextEditingController();
  final _labelInput = TextEditingController();
  final _reasonInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flagInput.dispose();
    _labelInput.dispose();
    _reasonInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await _repo.read(widget.queue.index.sourceFingerprint);
      final notebook = raw == null
          ? ZaiCausalChoiceNotebook.empty(widget.board)
          : ZaiCausalChoiceNotebook.decode(widget.board, raw);
      // Preflight checks exact present-day keepForReview citations as well.
      ZaiCausalPreflight.assess(
          widget.queue, notebook, consistency: widget.consistency);
      if (mounted) setState(() { _notebook = notebook; _error = null; });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Причинный черновик повреждён или исходные сцены '
            'изменились. Старый файл не перезаписан; разрешён '
            'только отдельный подтверждённый сброс M2f3e.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _store(ZaiCausalChoiceNotebook next) async {
    if (_saving || _loading || _notebook == null) return false;
    setState(() => _saving = true);
    try {
      await _repo.write(widget.queue.index.sourceFingerprint, next.encode());
      if (mounted) setState(() { _notebook = next; _error = null; });
      return true;
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось сохранить изменения; предыдущий файл оставлен без замены.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving || _loading) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить только решения M2f3e?'),
        content: const Text('Сбросится только отдельный список '
            'состояний и причинных выборов M2f3e. Книга, сцены M2f3d, '
            'цитаты M2f3a–c, кампании и игровые сохранения не затронутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-causal-reset-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить только M2f3e'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repo.delete(widget.queue.index.sourceFingerprint);
      if (mounted) setState(() {
        _notebook = ZaiCausalChoiceNotebook.empty(widget.board);
        _error = null;
        _from = null;
        _to = null;
        _required = '';
        _forbidden = '';
        _added = '';
        _removed = '';
        _npcId = '';
        _knowledgeId = '';
      });
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось сбросить M2f3e, другие файлы не изменены.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revealFuture() async {
    if (_spoilers) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Показать сцены будущих глав?'),
        content: const Text('Названия сцен и точные цитаты могут '
            'раскрыть концовку книги. Это разрешение действует '
            'только до выхода из редактора и не отправляет текст ИИ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Оставить скрытыми')),
          FilledButton(
            key: const Key('zai-causal-spoiler-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Разрешить спойлеры')),
        ],
      ),
    );
    if (yes == true && mounted) setState(() => _spoilers = true);
  }

  List<ZaiSourceScene> get _visibleScenes => [
    for (final scene in widget.board.scenes)
      if (_spoilers || scene.chapterIndex == 0) scene,
  ];

  Future<void> _openPrivateCompilation() async {
    final notebook = _notebook;
    if (!mounted || notebook == null || _loading || _saving) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ZaiPrivateCompilationPage(
        queue: widget.queue,
        notebook: notebook,
        consistency: widget.consistency,
        causalRepository: _repo,
        draftRepository: widget.privateDraftRepository,
        narrativeRepository: widget.privateNarrativeRepository,
        catalogRepository: widget.privateCatalogRepository,
        editorialRepository: widget.privateEditorialRepository,
        alignmentRepository: widget.privateAlignmentRepository,
      ),
    ));
  }

  Future<void> _addFlag() async {
    final notebook = _notebook;
    if (notebook == null || _saving) return;
    try {
      final next = notebook.addFlag(
          _flagInput.text.trim(), active: _initialFlag);
      if (await _store(next) && mounted) setState(() {
        _flagInput.clear();
        _initialFlag = false;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addChoice() async {
    final notebook = _notebook;
    final from = _from;
    final to = _to;
    if (notebook == null || from == null || to == null || _saving) return;
    final source = widget.board.scenes.where((e) => e.id == from).firstOrNull;
    final target = widget.board.scenes.where((e) => e.id == to).firstOrNull;
    if (source == null || target == null ||
        (!_spoilers && (source.chapterIndex > 0 ||
            target.chapterIndex > 0))) return;
    final label = _labelInput.text.trim();
    final reason = _reasonInput.text.trim();
    final npc = _npcId.isEmpty ? null : _npcId;
    final knowledge = _knowledgeId.isEmpty ? null : _knowledgeId;
    final requires = _required.isEmpty ? <String>[] : [_required];
    final forbids = _forbidden.isEmpty ? <String>[] : [_forbidden];
    final adds = _added.isEmpty ? <String>[] : [_added];
    final removes = _removed.isEmpty ? <String>[] : [_removed];
    try {
      notebook.addChoice(
        from: from, to: to, label: label, reason: reason,
        requires: requires, forbids: forbids,
        adds: adds, removes: removes,
        npcFindingId: npc, knowledgeFindingId: knowledge,
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }

    final findings = {for (final e in widget.board.graph.reviewed) e.id: e};
    final a = findings[source.eventIds.first];
    final b = findings[target.eventIds.first];
    var understood = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          scrollable: true,
          title: const Text('Добавить альтернативный выбор?'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Это явно выдуманный/написанный редактором '
                    'вариант, а не событие, которое доказала книга.'),
                const SizedBox(height: 8),
                Text('Из: ${source.title} · глава ${source.chapterIndex + 1}'),
                if (a != null) SelectableText('«${a.quote}»'),
                const SizedBox(height: 6),
                Text('В: ${target.title} · глава ${target.chapterIndex + 1}'),
                if (b != null) SelectableText('«${b.quote}»'),
                const SizedBox(height: 8),
                Text('Выбор: $label'),
                Text('Пояснение: $reason'),
                if (npc != null) const Text('Знания NPC — '
                    'только неподтверждённая редакторская гипотеза.'),
                CheckboxListTile(
                  key: const Key('zai-causal-consent-check'),
                  contentPadding: EdgeInsets.zero,
                  value: understood,
                  onChanged: (value) => change(
                      () => understood = value == true),
                  title: const Text('Понимаю, что эта ветка не '
                      'устанавливает сюжетный канон, знания NPC '
                      'или разрешение на публикацию.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('zai-causal-consent-save'),
              onPressed: understood
                  ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Сохранить частный выбор'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || approved != true) return;
    try {
      if (await _store(_notebook!.addChoice(
        from: from, to: to, label: label, reason: reason,
        requires: requires, forbids: forbids, adds: adds, removes: removes,
        npcFindingId: npc, knowledgeFindingId: knowledge,
      )) && mounted) {
        setState(() {
          _labelInput.clear();
          _reasonInput.clear();
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _flagSelector({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final flags = _notebook?.flags ?? const <String>[];
    return DropdownButtonFormField<String>(
      key: ValueKey('zai-causal-${label.hashCode}-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('Нет')),
        for (final flag in flags)
          DropdownMenuItem(value: flag, child: Text(flag)),
      ],
      onChanged: _notebook == null || _saving ? null : (next) {
        onChanged(next ?? '');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = _notebook;
    final enabled = notebook != null && !_loading && !_saving;
    final visible = _visibleScenes;
    final from = visible.where((s) => s.id == _from).firstOrNull;
    final reader = widget.board.graph.reviewed;
    final characters = [
      for (final f in reader)
        if (f.category == SemanticCategory.character &&
            from != null && f.chapterIndex <= from.chapterIndex) f,
    ];
    final knowledge = [
      for (final f in reader)
        if ((f.category == SemanticCategory.fact ||
             f.category == SemanticCategory.state ||
             f.category == SemanticCategory.event) &&
            from != null && f.chapterIndex <= from.chapterIndex) f,
    ];
    final report = notebook == null ? null : ZaiCausalPreflight.assess(
        widget.queue, notebook, consistency: widget.consistency);
    final palette = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Игровые решения и последствия')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('M2f3e · альтернативы и причинность',
                    key: const Key('zai-causal-title'),
                    style: Theme.of(context).textTheme.titleLarge),
                const Text('Это только частная схема игровых выборов, '
                    'проверяемая существующим движком M2c. Она не '
                    'устанавливает факты книги, не запускает игру '
                    'и не создаёт .bworld.'),
                const PreparationEditorHelp(
                  purpose: 'Здесь сцены становятся вариантами выбора с последствиями.',
                  steps: [
                    'Добавьте условие только там, где выбор зависит от прежнего решения.',
                    'Задайте, из какой сцены в какую ведёт выбор и что изменится.',
                    'Пометьте придуманные альтернативы, проверьте связность и два достижимых исхода.',
                  ],
                  result: 'сценарий, который можно проверить компилятором; пока не запущенная игра.',
                  next: 'нажмите «Проверить сценарий и собрать RPG».',
                ),
                if (_loading || _saving) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!, key: const Key('zai-causal-error'),
                      style: TextStyle(color: palette.error)),
                  if (notebook == null)
                    OutlinedButton.icon(
                      key: const Key('zai-causal-reset'),
                      onPressed: !_saving ? _reset : null,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Сбросить только M2f3e'),
                    ),
                ],
                const SizedBox(height: 10),
                Text('Сцены: ${widget.board.scenes.length} · '
                    'флаги: ${notebook?.flags.length ?? 0} · '
                    'ручные выборы: ${notebook?.choices.length ?? 0}',
                    key: const Key('zai-causal-counts')),
                if (!_spoilers && widget.board.scenes.any((e) =>
                    e.chapterIndex > 0))
                  OutlinedButton.icon(
                    key: const Key('zai-causal-reveal'),
                    onPressed: _revealFuture,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Показать сцены будущих глав'),
                  ),
                const Divider(height: 24),
                Text('Состояния игрового сценария',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Флаг обозначает вымышленное игровое состояние, '
                    'а не доказанный факт книги. Пример: has_key.'),
                TextField(
                  key: const Key('zai-causal-flag-input'),
                  controller: _flagInput,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Имя нового флага (латиницей)',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  key: const Key('zai-causal-initial-flag'),
                  title: const Text('Включён с начала игры'),
                  value: _initialFlag,
                  onChanged: enabled ? (v) =>
                      setState(() => _initialFlag = v == true) : null,
                ),
                OutlinedButton.icon(
                  key: const Key('zai-causal-add-flag'),
                  onPressed: enabled ? _addFlag : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить состояние'),
                ),
                if (notebook != null)
                  for (final flag in notebook.flags)
                    ListTile(
                      dense: true,
                      title: Text(flag),
                      subtitle: Text(notebook.initiallyActive.contains(flag)
                          ? 'Активен с начала' : 'Начальное состояние: нет'),
                      trailing: IconButton(
                        tooltip: 'Удалить неиспользуемое состояние',
                        onPressed: enabled ? () {
                          try {
                            _store(notebook.removeFlag(flag));
                          } on FormatException catch (e) {
                            setState(() => _error = e.message);
                          }
                        } : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                const Divider(height: 24),
                Text('Написать альтернативу',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Выберите сцену-источник и пункт назначения. '
                    'Будущие главы видны только после отдельного согласия. '
                    'Выбор и последствия пишет человек, а не ИИ.'),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-causal-from-${_from ?? 'none'}-'
                      '${_spoilers ? 'all' : 'safe'}'),
                  initialValue: _from,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Из сцены'),
                  items: [
                    for (final scene in visible)
                      DropdownMenuItem(value: scene.id,
                        child: Text('Гл. ${scene.chapterIndex + 1} · '
                            '${scene.title}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (id) => setState(() {
                    _from = id; _npcId = ''; _knowledgeId = '';
                  }) : null,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-causal-to-${_to ?? 'none'}-'
                      '${_spoilers ? 'all' : 'safe'}'),
                  initialValue: _to,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'В сцену'),
                  items: [
                    for (final scene in visible)
                      DropdownMenuItem(value: scene.id,
                        child: Text('Гл. ${scene.chapterIndex + 1} · '
                            '${scene.title}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (id) => setState(() => _to = id) : null,
                ),
                TextField(
                  key: const Key('zai-causal-label-input'),
                  controller: _labelInput,
                  maxLength: 140,
                  decoration: const InputDecoration(
                    labelText: 'Что делает игрок?',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  key: const Key('zai-causal-reason-input'),
                  controller: _reasonInput,
                  maxLength: 240, maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Почему это допустимая альтернативная ветка?',
                    border: OutlineInputBorder(),
                  ),
                ),
                _flagSelector(label: 'Требуется флаг', value: _required,
                    onChanged: (v) => setState(() => _required = v)),
                _flagSelector(label: 'Запрещён флаг', value: _forbidden,
                    onChanged: (v) => setState(() => _forbidden = v)),
                _flagSelector(label: 'Установить флаг', value: _added,
                    onChanged: (v) => setState(() => _added = v)),
                _flagSelector(label: 'Убрать флаг', value: _removed,
                    onChanged: (v) => setState(() => _removed = v)),
                const SizedBox(height: 12),
                Text('Проверка риска знания NPC',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Необязательная пара цитат: персонаж и то, '
                    'что он якобы знает. Если источник находится позже '
                    'этой сцены, привязка запрещена. Даже допустимая '
                    'привязка НЕ делает знания каноном.'),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-causal-npc-$_npcId-${_from ?? 'none'}'),
                  initialValue: _npcId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Цитата персонажа (необязательно)'),
                  items: [
                    const DropdownMenuItem(value: '',
                        child: Text('Без предположения NPC')),
                    for (final f in characters.take(80))
                      DropdownMenuItem(value: f.id,
                          child: Text('Гл. ${f.chapterIndex + 1} · '
                              '${f.label}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (v) =>
                      setState(() => _npcId = v ?? '') : null,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('zai-causal-knowledge-$_knowledgeId-'
                      '${_from ?? 'none'}'),
                  initialValue: _knowledgeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Цитата знания (необязательно)'),
                  items: [
                    const DropdownMenuItem(value: '',
                        child: Text('Без предположения о знании')),
                    for (final f in knowledge.take(80))
                      DropdownMenuItem(value: f.id,
                          child: Text('Гл. ${f.chapterIndex + 1} · '
                              '${f.label}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (v) =>
                      setState(() => _knowledgeId = v ?? '') : null,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('zai-causal-add-choice'),
                  onPressed: enabled && _from != null && _to != null
                      ? _addChoice : null,
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Сравнить цитаты и сохранить выбор'),
                ),
                const Divider(height: 24),
                Text('Сохранённые альтернативы',
                    style: Theme.of(context).textTheme.titleMedium),
                if (notebook != null && notebook.choices.isEmpty)
                  const Text('Пока нет авторских вариантов решения.'),
                for (final choice in notebook?.choices ??
                    const <ZaiCausalChoice>[])
                  Card(
                    child: !_spoilers && (
                      widget.board.scenes.firstWhere(
                          (s) => s.id == choice.fromSceneId).chapterIndex > 0 ||
                      widget.board.scenes.firstWhere(
                          (s) => s.id == choice.toSceneId).chapterIndex > 0)
                      ? const ListTile(
                          title: Text('Скрытый выбор будущей главы'),
                          subtitle: Text('Спойлеры требуют согласия'),
                        )
                      : ListTile(
                          title: Text(choice.label),
                          subtitle: Text('Предположение · ${choice.reason}\n'
                              'Условия: ${choice.requires.join(', ')} · '
                              'Последствия: ${choice.adds.join(', ')} '
                              '${choice.removes.join(', ')}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Удалить частный выбор',
                            onPressed: enabled
                                ? () => _store(notebook.removeChoice(choice.id))
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                  ),
                const Divider(height: 24),
                Text('Причинный preflight M2c',
                    key: const Key('zai-causal-preflight-title'),
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Ни один успешный структурный тест не '
                    'открывает игру или публикацию.'),
                if (report != null) ...[
                  Text('Достижимых сцен: ${report.reachableScenes} · '
                      'концовок: ${report.reachableEndings} · '
                      'состояний: ${report.reachableStates}',
                      key: const Key('zai-causal-preflight-counts')),
                  for (final entry in report.blockers.entries)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: Text(entry.value),
                    ),
                ],
                const Divider(height: 24),
                Text('Следующий шаг · M2f3f2',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Проверить источниковые сцены и авторские альтернативы, '
                    'собрать частный .bworld и только после отдельного '
                    'согласия установить его в библиотеку. '
                    'Без подтверждённых цитат M2c сборка блокируется.'),
                OutlinedButton.icon(
                  key: const Key('zai-open-private-compiler'),
                  onPressed: enabled ? _openPrivateCompilation : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Проверить сценарий и собрать RPG'),
                ),
                const Text('Книги и старые сохранения не меняются. '
                    'Знания NPC и игровой ИИ пока не подключены.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
