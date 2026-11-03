import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'book_isolate_workers.dart';
import 'book_source_index.dart';
import 'npc_editorial_notebook.dart';
import 'npc_continuity_audit.dart';
import 'npc_continuity_panel.dart';
import 'intermediate_story_blueprint.dart';
import 'multi_scene_draft_workbench.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_relation_review.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

SourceCharacterDossierIndex _buildNpcDossiers((
  BookSourceIndex, SourceEvidenceGraph, SourceRelationReviewSession,
  SourceSemanticCatalog, SemanticEditorialReviewSession,
) input) => SourceCharacterDossierIndex.build(
    input.$1, input.$2, input.$3, input.$4, input.$5);

/// An explicitly authored, PRIVATE NPC staging editor. Never automatically
/// writes to GameProgress, BookWorld, the source corpus, or the AI provider.
class NpcEditorialPage extends StatefulWidget {
  const NpcEditorialPage({
    super.key,
    required this.index,
    required this.graph,
    required this.catalog,
    required this.editorial,
    this.relationsRepository,
    this.notebookRepository,
    this.multiDraftRepository,
    this.sessionBuilder,
    this.sessionDecoder,
    this.dossierBuilder,
  });

  final BookSourceIndex index;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final SourceAnalysisCheckpointRepository? relationsRepository;
  final SourceAnalysisCheckpointRepository? notebookRepository;
  final SourceAnalysisCheckpointRepository? multiDraftRepository;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph)? sessionBuilder;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph, String)? sessionDecoder;
  final Future<SourceCharacterDossierIndex> Function(
      BookSourceIndex, SourceEvidenceGraph, SourceRelationReviewSession,
      SourceSemanticCatalog, SemanticEditorialReviewSession)? dossierBuilder;

  @override
  State<NpcEditorialPage> createState() => _NpcEditorialPageState();
}

class _NpcEditorialPageState extends State<NpcEditorialPage> {
  late final SourceAnalysisCheckpointRepository _relations =
      widget.relationsRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.identityRelations);
  late final SourceAnalysisCheckpointRepository _notes =
      widget.notebookRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.npcEditorial);

  late final SourceAnalysisCheckpointRepository _scenes =
      widget.multiDraftRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.multiSceneDraft);

  SourceCharacterDossierIndex? _dossiers;
  IntermediateStoryBlueprint? _scenario;
  NpcContinuityAudit? _continuity;
  String? _scenarioWarning;
  NpcEditorialNotebook? _notebook;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  String _search = '';
  final _searchController = TextEditingController();
  String? _selectedId;
  int _page = 0;
  static const int _pageSize = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    if (mounted) setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _dossiers = null;
      _notebook = null;
      _continuity = null;
      _scenario = null;
      _scenarioWarning = null;
      _selectedId = null;
      _page = 0;
    });
    try {
      final fingerprint = widget.index.sourceFingerprint;
      final rawRelations = await _relations.read(fingerprint);
      final reviewed = rawRelations == null
          ? widget.sessionBuilder != null
              ? await widget.sessionBuilder!(widget.index, widget.graph)
              : await createRelationReviewInWorker(widget.index, widget.graph)
          : widget.sessionDecoder != null
              ? await widget.sessionDecoder!(
                  widget.index, widget.graph, rawRelations)
              : await decodeRelationReviewInWorker(
                  widget.index, widget.graph, rawRelations);
      final dossiers = widget.dossierBuilder != null
          ? await widget.dossierBuilder!(widget.index, widget.graph,
              reviewed, widget.catalog, widget.editorial)
          : await compute(_buildNpcDossiers,
              (widget.index, widget.graph, reviewed,
                  widget.catalog, widget.editorial),
              debugLabel: 'npc-editor-source-index');
      final stored = await _notes.read(fingerprint);
      final notebook = stored == null
          ? NpcEditorialNotebook.empty(widget.index)
          : NpcEditorialNotebook.decode(
              widget.index, dossiers, widget.graph,
              widget.catalog, widget.editorial, stored);
      IntermediateStoryBlueprint? scenario;
      String? scenarioWarning;
      try {
        final rawScenario = await _scenes.read(fingerprint);
        if (rawScenario != null) {
          scenario = IntermediateStoryBlueprint.decode(rawScenario);
          MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, scenario);
        }
      } catch (error) {
        // A broken *independent* scenario must not destroy valid NPC notes.
        scenario = null;
        scenarioWarning = 'Черновик сцен не проверен: $error. '
            'Исходные данные не изменены.';
      }
      final continuity = NpcContinuityAudit.inspect(
          index: widget.index, dossiers: dossiers, graph: widget.graph,
          catalog: widget.catalog, editorial: widget.editorial,
          notebook: notebook, scenario: scenario);
      if (!mounted) return;
      setState(() {
        _dossiers = dossiers;
        _notebook = notebook;
        _scenario = scenario;
        _scenarioWarning = scenarioWarning;
        _continuity = continuity;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Редактор NPC заблокирован: $error. '
            'Старый файл не изменён; проверьте источники и решения SAME/DIFFERENT.';
        _loading = false;
      });
    }
  }

  SourceCharacterDossier? get _selected {
    final list = _dossiers?.dossiers;
    if (list == null) return null;
    for (final d in list) {
      if (d.id == _selectedId) return d;
    }
    return null;
  }

  NpcDraftProfile? _profileFor(String id) {
    for (final profile in _notebook?.profiles ?? const <NpcDraftProfile>[]) {
      if (profile.dossierId == id) return profile;
    }
    return null;
  }

  Future<bool> _persist(NpcEditorialNotebook next) async {
    if (_busy || _notebook == null || _dossiers == null) return false;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      next.validate(widget.index, _dossiers!, widget.graph,
          widget.catalog, widget.editorial);
      // No optimistic success state: persist to the independent atomic file.
      final audit = NpcContinuityAudit.inspect(
          index: widget.index, dossiers: _dossiers!,
          graph: widget.graph, catalog: widget.catalog,
          editorial: widget.editorial, notebook: next,
          scenario: _scenario);
      await _notes.write(widget.index.sourceFingerprint, next.encode());
      if (!mounted) return false;
      setState(() {
        _notebook = next;
        _continuity = audit;
        _notice = 'Заметки NPC сохранены только для этой книги.';
      });
      return true;
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Изменение не сохранено: $error');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _resetNpcOnly() async {
    if (_busy) return;
    final yes = await _confirm(
      'Очистить только заметки NPC?',
      'Это удалит авторские имена, роли, знания, секреты и связи '
      'из отдельного черновика NPC этой книги. Цитаты, решение об '
      'идентичности, сама книга, сюжет, игры и сохранения не затрагиваются. '
      'Операция не отменяется.',
    );
    if (!yes || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _notes.delete(widget.index.sourceFingerprint);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Не удалось очистить заметки NPC: $error');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _editName(SourceCharacterDossier dossier) async {
    if (_busy || _notebook == null) return;
    final prior = _profileFor(dossier.id);
    final initial = prior ??
        NpcEditorialNotebook.freshProfile(dossier);
    var enteredName = initial.displayName;
    final name = await showDialog<String>(
      context: context, builder: (ctx) => AlertDialog(
        title: Text(prior == null
            ? 'Создать авторскую карточку' : 'Изменить отображаемое имя'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Название нужно только для личной адаптации. '
                'Оно не переименует персонажа в оригинальной книге.'),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('npc-name-input'),
              initialValue: initial.displayName,
              onChanged: (value) => enteredName = value,
              maxLength: 96,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Имя для черновика RPG',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('npc-confirm-name'),
            onPressed: () => Navigator.pop(ctx, enteredName.trim()),
            child: const Text('Сохранить имя'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    await _persist(_notebook!.putProfile(NpcDraftProfile(
      dossierId: initial.dossierId,
      mentionIds: initial.mentionIds,
      displayName: name,
      notes: initial.notes,
    )));
  }

  Future<void> _removeProfile(SourceCharacterDossier dossier) async {
    if (_busy || _notebook == null) return;
    final yes = await _confirm(
      'Удалить авторскую карточку?',
      'Будут удалены только ваши заметки к «${dossier.labels.join(" / ")}». '
      'Книга, источники, игровые миры и сохранения не изменятся.',
    );
    if (!yes || !mounted) return;
    await _persist(_notebook!.removeProfile(dossier.id));
  }

  String _categoryName(NpcDraftField field) => switch (field) {
    NpcDraftField.role => 'Роль',
    NpcDraftField.motivation => 'Мотивация или цель',
    NpcDraftField.knowledge => 'Знание персонажа',
    NpcDraftField.secret => 'Секрет',
    NpcDraftField.relationship => 'Отношение к другому персонажу',
  };

  String _assertionLabel(SourceSemanticAssertion claim) {
    final label = [claim.subject, claim.predicate, claim.object]
        .where((x) => x.isNotEmpty).join(' ');
    return label.length <= 72 ? label : '${label.substring(0, 72)}…';
  }

  Future<void> _editNote(
      SourceCharacterDossier dossier, {NpcDraftNote? existing}) async {
    if (_busy || _notebook == null) return;
    final profile = _profileFor(dossier.id);
    if (profile == null) return;
    final choices = NpcEditorialNotebook.eligibleClaims(
        dossier, widget.catalog, widget.editorial, widget.graph);
    final targets = _dossiers!.dossiers.where((d) =>
        d.id != dossier.id && NpcEditorialNotebook.isConfirmedDossier(d)).toList();
    var field = existing?.field ?? NpcDraftField.role;
    var sourceId = existing?.sourceAssertionId;
    var targetId = existing?.targetDossierId;
    var enteredText = existing?.text ?? '';
    final proposal = await showDialog<({NpcDraftField field,
          String text, String? sourceId, String? targetId})>(
      context: context, builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: Text(existing == null ? 'Добавить авторскую заметку'
              : 'Изменить заметку'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Любой текст ниже — запись редактора, '
                    'а не автоматически установленный факт книги.'),
                const SizedBox(height: 10),
                DropdownButtonFormField<NpcDraftField>(
                  key: const Key('npc-note-category'),
                  initialValue: field,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Раздел', border: OutlineInputBorder()),
                  items: [
                    for (final choice in NpcDraftField.values)
                      DropdownMenuItem(
                        value: choice, child: Text(_categoryName(choice)),
                      ),
                  ],
                  onChanged: (next) {
                    if (next == null) return;
                    refresh(() {
                      field = next;
                      if (next != NpcDraftField.relationship) {
                        targetId = null;
                      }
                    });
                  },
                ),
                if (field == NpcDraftField.relationship) ...[
                  const SizedBox(height: 8),
                  if (targets.isEmpty)
                    const Text('Нет другого подтверждённого персонажа. '
                        'Сначала проверьте цитаты и имена.')
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('npc-note-target'),
                      initialValue: targetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Кому относится связь',
                          border: OutlineInputBorder()),
                      items: [
                        for (final target in targets)
                          DropdownMenuItem(
                            value: target.id,
                            child: Text(
                              target.labels.join(' / '),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => refresh(() => targetId = value),
                    ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('npc-note-text'),
                  initialValue: enteredText,
                  onChanged: (value) => enteredText = value,
                  minLines: 3, maxLines: 6, maxLength: 800,
                  decoration: const InputDecoration(
                    labelText: 'Авторская формулировка',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Основание записи:'),
                SwitchListTile(
                  key: const Key('npc-source-toggle'),
                  title: const Text('Привязать проверенное утверждение '
                      '(кандидат, не игровой канон)'),
                  subtitle: const Text('Выключено: авторская версия.'),
                  value: sourceId != null,
                  onChanged: choices.isEmpty ? null : (checked) => refresh(() {
                    sourceId = checked ? choices.first.id : null;
                  }),
                ),
                if (sourceId != null && choices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const Key('npc-note-source'),
                    initialValue: sourceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Проверенное утверждение и цитаты',
                        border: OutlineInputBorder()),
                    items: [
                      for (final claim in choices)
                        DropdownMenuItem(
                          value: claim.id,
                          child: Text(_assertionLabel(claim),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (next) => refresh(() => sourceId = next),
                  ),
                if (sourceId != null)
                  const Text('Связь по совпадению имени может быть '
                      'неоднозначной даже при проверенной цитате.'),
              ],
            )),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('npc-note-confirm'),
              onPressed: () => Navigator.pop(dialog, (
                field: field, text: enteredText.trim(),
                sourceId: sourceId, targetId: targetId,
              )),
              child: const Text('Сохранить запись'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || proposal == null) return;
    final note = NpcDraftNote(
      id: existing?.id ?? _notebook!.nextNoteId(),
      field: proposal.field,
      text: proposal.text,
      sourceAssertionId: proposal.sourceId,
      targetDossierId: proposal.targetId,
      targetGroupDigest: proposal.targetId == null ? null :
          NpcEditorialNotebook.groupDigest(_dossiers!.dossiers.firstWhere(
              (group) => group.id == proposal.targetId)),
    );
    final updated = NpcDraftProfile(
      dossierId: profile.dossierId,
      mentionIds: profile.mentionIds,
      displayName: profile.displayName,
      notes: [
        for (final old in profile.notes) if (old.id != note.id) old,
        note,
      ],
    );
    await _persist(_notebook!.putProfile(updated));
  }

  Future<void> _removeNote(
      SourceCharacterDossier dossier, NpcDraftNote note) async {
    if (_busy || _notebook == null) return;
    final yes = await _confirm(
        'Удалить заметку?', 'Удаляется только эта авторская запись NPC.');
    if (!yes || !mounted) return;
    final profile = _profileFor(dossier.id);
    if (profile == null) return;
    await _persist(_notebook!.putProfile(NpcDraftProfile(
      dossierId: profile.dossierId, mentionIds: profile.mentionIds,
      displayName: profile.displayName,
      notes: [
        for (final item in profile.notes) if (item.id != note.id) item,
      ],
    )));
  }

  Widget _noteCard(SourceCharacterDossier dossier, NpcDraftNote note) {
    final source = note.sourceAssertionId == null ? null
        : widget.catalog.assertions.firstWhere(
            (x) => x.id == note.sourceAssertionId);
    final byId = {for (final e in widget.graph.records) e.id: e};
    final target = note.targetDossierId == null ? null
        : _dossiers!.dossiers.firstWhere(
            (x) => x.id == note.targetDossierId);
    return Card(
      key: Key('npc-note-${note.id}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_categoryName(note.field),
              style: Theme.of(context).textTheme.titleSmall),
          Text(note.text),
          if (target != null)
            Text('Связан с: ${target.labels.join(" / ")}'),
          Text(source == null
              ? 'Источник: явно авторская версия (не канон)'
              : 'Источник: утверждение-кандидат с проверенными цитатами'),
          if (source != null) ...[
            Text(_assertionLabel(source)),
            for (final id in source.evidenceIds)
              if (byId[id] != null)
                Text('Глава ${byId[id]!.chapterIndex + 1}: '
                    '«${byId[id]!.label}»'),
          ],
          Wrap(spacing: 8, children: [
            TextButton(
              key: Key('npc-edit-note-${note.id}'),
              onPressed: _busy ? null : () => _editNote(
                  dossier, existing: note),
              child: const Text('Редактировать'),
            ),
            TextButton(
              key: Key('npc-delete-note-${note.id}'),
              onPressed: _busy ? null : () => _removeNote(dossier, note),
              child: const Text('Удалить'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _editor(SourceCharacterDossier dossier) {
    final profile = _profileFor(dossier.id);
    final allowed = NpcEditorialNotebook.isConfirmedDossier(dossier);
    return Column(
      key: ValueKey('npc-dossier-${dossier.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(dossier.labels.join(' / '),
            style: Theme.of(context).textTheme.titleMedium),
        Text('Упоминаний: ${dossier.mentions.length}; '
            'проверено: ${dossier.confirmedQuotes}. '
            'Редактор привязан к точным цитатам, не к написанию имени.'),
        for (final quote in dossier.mentions.take(3))
          Text('Глава ${quote.chapterIndex + 1}: «${quote.label}»'),
        if (!allowed) ...[
          const SizedBox(height: 8),
          const Text('Создание NPC заблокировано: подтвердите каждую '
              'опорную цитату имени и правило спойлеров в подготовке книги.'),
        ] else if (profile == null)
          FilledButton.icon(
            key: const Key('npc-create-profile'),
            onPressed: _busy ? null : () => _editName(dossier),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Создать авторскую карточку NPC'),
          )
        else ...[
          Text('Имя адаптации: ${profile.displayName}'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('npc-edit-name'),
              onPressed: _busy ? null : () => _editName(dossier),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Изменить имя'),
            ),
            OutlinedButton.icon(
              key: const Key('npc-add-note'),
              onPressed: _busy || profile.notes.length >=
                  NpcEditorialNotebook.maxNotesPerProfile
                  ? null : () => _editNote(dossier),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Добавить роль, знание или связь'),
            ),
            TextButton.icon(
              key: const Key('npc-remove-profile'),
              onPressed: _busy ? null : () => _removeProfile(dossier),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Удалить карточку NPC'),
            ),
          ]),
          if (profile.notes.isEmpty)
            const Text('Заметок пока нет. Это ещё не игровой персонаж.'),
          for (final note in profile.notes) _noteCard(dossier, note),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = _dossiers;
    final notebook = _notebook;
    final search = _search.trim().toLowerCase();
    final filtered = (index?.dossiers ?? const <SourceCharacterDossier>[])
        .where((d) => d.labels.any((name) =>
            name.toLowerCase().contains(search))).toList();
    final pages = filtered.isEmpty ? 1
        : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pages - 1).toInt();
    final visible = filtered.skip(page * _pageSize).take(_pageSize).toList();
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Авторский редактор NPC')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.index.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Личный офлайн-черновик для будущей RPG. '
                        'Ни одна роль, мотивация, связь или тайна '
                        'не становится автоматически фактом книги. '
                        'ИИ выключен, текст не отправляется в облако.'),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                    ],
                    if (_notice != null) Text(_notice!),
                    const SizedBox(height: 10),
                    if (index == null || notebook == null) ...[
                      OutlinedButton(
                        key: const Key('npc-retry-load'),
                        onPressed: _busy ? null : _load,
                        child: const Text('Перепроверить данные'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('npc-reset-only'),
                        onPressed: _busy ? null : _resetNpcOnly,
                        child: const Text('Очистить только заметки NPC…'),
                      ),
                    ] else ...[
                      Text('Карточек NPC: ${notebook.profiles.length} · '
                          'доступных групп упоминаний: '
                          '${index.possibleCharacterGroups}. '
                          'Это не прогресс построения игрового мира.'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('npc-refresh-audit'),
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Перепроверить NPC и сценарий'),
                      ),
                      if (_continuity != null)
                        NpcContinuityPanel(
                          audit: _continuity!,
                          scenarioWarning: _scenarioWarning,
                          enabled: !_busy,
                          onSelectProfile: (id) {
                            final indexOf = index.dossiers.indexWhere(
                                (group) => group.id == id);
                            if (indexOf < 0) return;
                            _searchController.clear();
                            setState(() {
                              _search = '';
                              _selectedId = id;
                              _page = indexOf ~/ _pageSize;
                            });
                          },
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('npc-search'),
                        controller: _searchController,
                        decoration: const InputDecoration(
                            labelText: 'Поиск упоминаний и псевдонимов',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder()),
                        onChanged: (text) => setState(() {
                          _search = text;
                          _page = 0;
                        }),
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        const Text('Для выбранного имени упоминаний нет.'),
                      for (final dossier in visible)
                        Card(
                          child: ListTile(
                            key: Key('npc-select-${dossier.id}'),
                            selected: _selectedId == dossier.id,
                            title: Text(dossier.labels.join(' / ')),
                            subtitle: Text(
                              '${_profileFor(dossier.id) != null ? "Авторский черновик" : "Нет карточки NPC"} · '
                              '${dossier.confirmedQuotes} подтверждённых цитат',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _busy ? null : () => setState(
                                () => _selectedId = dossier.id),
                          ),
                        ),
                      if (pages > 1)
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton(
                              key: const Key('npc-prev'),
                              onPressed: page == 0 ? null : () =>
                                  setState(() => _page--),
                              child: const Text('Назад'),
                            ),
                            Text('Страница ${page + 1} из $pages'),
                            OutlinedButton(
                              key: const Key('npc-next'),
                              onPressed: page + 1 >= pages ? null : () =>
                                  setState(() => _page++),
                              child: const Text('Дальше'),
                            ),
                          ],
                        ),
                      if (selected != null) _editor(selected),
                      const Divider(height: 22),
                      const Text('Сведения остаются в отдельном закрытом '
                          'checkpoint. Для превращения их в реальные NPC '
                          'понадобятся отдельный конструктор игровых правил '
                          'и повторная проверка источников.'),
                      if (_busy) const LinearProgressIndicator(),
                    ],
                  ],
                ),
              )),
            ),
    );
  }
}
