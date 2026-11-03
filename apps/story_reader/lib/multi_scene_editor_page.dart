import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'multi_scene_draft_workbench.dart';
import 'draft_scene_graph_panel.dart';
import 'native_private_bookworld_compiler.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'source_character_dossiers.dart';
import 'source_relation_review.dart';
import 'private_adaptation_preflight.dart';
import 'reviewed_story_editor_page.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';
import 'world_campaigns_page.dart';
import 'world_library_gateway.dart';

/// Edits the same typed M2c graph that the native private compiler consumes.
/// An unfinished graph is never published as a game, even if saved locally.
/// Separate draft scope leaves the short editor's source intact.
class MultiSceneEditorPage extends StatefulWidget {
  const MultiSceneEditorPage({
    super.key, required this.index, required this.gateway,
    this.narrativeRepository, this.catalogRepository,
    this.editorialRepository, this.shortDraftRepository,
    this.multiDraftRepository,
    this.npcNotebookRepository, this.npcRulesRepository,
    this.identityRepository,
  });

  final BookSourceIndex index;
  final WorldLibraryGateway gateway;
  final SourceAnalysisCheckpointRepository? narrativeRepository;
  final SourceAnalysisCheckpointRepository? catalogRepository;
  final SourceAnalysisCheckpointRepository? editorialRepository;
  final SourceAnalysisCheckpointRepository? shortDraftRepository;
  final SourceAnalysisCheckpointRepository? multiDraftRepository;
  final SourceAnalysisCheckpointRepository? npcNotebookRepository;
  final SourceAnalysisCheckpointRepository? npcRulesRepository;
  final SourceAnalysisCheckpointRepository? identityRepository;

  @override
  State<MultiSceneEditorPage> createState() => _MultiSceneEditorPageState();
}

class _MultiSceneEditorPageState extends State<MultiSceneEditorPage> {
  late final SourceAnalysisCheckpointRepository _narrativeStore =
      widget.narrativeRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.narrativeEvidence);
  late final SourceAnalysisCheckpointRepository _catalogStore =
      widget.catalogRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.semanticCatalog);
  late final SourceAnalysisCheckpointRepository _editorStore =
      widget.editorialRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.semanticEditorial);
  late final SourceAnalysisCheckpointRepository _shortStore =
      widget.shortDraftRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.intermediateDraft);
  late final SourceAnalysisCheckpointRepository _multiStore =
      widget.multiDraftRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.multiSceneDraft);

  late final SourceAnalysisCheckpointRepository _npcStore =
      widget.npcNotebookRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.npcEditorial);
  late final SourceAnalysisCheckpointRepository _knowledgeStore =
      widget.npcRulesRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.npcKnowledgeRules);
  late final SourceAnalysisCheckpointRepository _identityStore =
      widget.identityRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.identityRelations);

  final _flagController = TextEditingController();
  StoryEvidenceReviewSession? _review;
  SourceSemanticCatalog? _catalog;
  SemanticEditorialReviewSession? _editorial;
  IntermediateStoryBlueprint? _short;
  IntermediateStoryBlueprint? _draft;
  List<SourceSemanticAssertion> _available = const [];
  String? _selectedSceneId;
  String? _selectedClaimId;
  String? _error;
  String? _notice;
  String? _validatedRaw;
  CausalPreflight? _validated;
  bool _loading = true;
  bool _working = false;
  bool _privateConsent = false;
  bool _includeNpcRules = false;
  bool _dirty = false;
  bool _showSpoilers = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_working) return;
    if (mounted) setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _review = null;
      _catalog = null;
      _editorial = null;
      _available = const [];
      _draft = null;
      _short = null;
      _selectedSceneId = null;
      _selectedClaimId = null;
      _validatedRaw = null;
      _validated = null;
      _dirty = false;
      _showSpoilers = false;
      _privateConsent = false;
      _includeNpcRules = false;
    });
    final fingerprint = widget.index.sourceFingerprint;
    try {
      final narrativeRaw = await _narrativeStore.read(fingerprint);
      if (narrativeRaw == null) {
        throw const FormatException('Сначала подготовьте события книги.');
      }
      final review = StoryEvidenceReviewSession.decode(
          widget.index, narrativeRaw);
      if (review.scannedChunks != widget.index.chunks.length) {
        throw const FormatException(
            'Не все фрагменты книги проверены на события.');
      }
      final catalogRaw = await _catalogStore.read(fingerprint);
      if (catalogRaw == null) {
        throw const FormatException('Не найден смысловой каталог.');
      }
      final catalog = SourceSemanticCatalog.decode(
          widget.index, review.graph, catalogRaw);
      final editorialRaw = await _editorStore.read(fingerprint);
      final editorial = editorialRaw == null
          ? SemanticEditorialReviewSession.create(widget.index, catalog)
          : SemanticEditorialReviewSession.decode(
              widget.index, review.graph, catalog, editorialRaw);
      final byEvidence = {
        for (final quote in review.graph.records) quote.id: quote,
      };
      final available = catalog.assertions.where((claim) =>
          (claim.kind == SemanticAssertionKind.event ||
           claim.kind == SemanticAssertionKind.fact) &&
          editorial.verdicts[claim.id] ==
              SemanticEditorialVerdict.canonCandidate &&
          claim.evidenceIds.isNotEmpty &&
          claim.evidenceIds.every((id) {
            final source = byEvidence[id];
            return source != null &&
                source.status == EvidenceStatus.confirmed &&
                source.spoilerGate == EvidenceSpoilerGate.chapter &&
                source.visibleAfterChapter == source.chapterIndex;
          })).toList();

      final multiRaw = await _multiStore.read(fingerprint);
      final multi = multiRaw == null ? null
          : IntermediateStoryBlueprint.decode(multiRaw);
      if (multi != null) {
        MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, multi);
      }
      // Invalid legacy short drafts are not overwritten; they are simply
      // unavailable as a seed. The independent multi-scene draft can still load.
      IntermediateStoryBlueprint? short;
      final shortRaw = await _shortStore.read(fingerprint);
      if (shortRaw != null) {
        try {
          final candidate = IntermediateStoryBlueprint.decode(shortRaw);
          MultiSceneDraftWorkbench.fromReviewedShortDraft(
              widget.index, review.graph, catalog, editorial, candidate);
          short = candidate;
        } on FormatException {
          short = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _review = review;
        _catalog = catalog;
        _editorial = editorial;
        _short = short;
        _draft = multi;
        _available = available;
        _selectedSceneId = multi?.entrySceneId;
        _selectedClaimId = available.isEmpty ? null : available.first.id;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Конструктор недоступен: $error. '
            'Существующие черновики, книги и игры не изменены.';
        _loading = false;
      });
    }
  }

  String _claimName(SourceSemanticAssertion claim) {
    final value = [claim.subject, claim.predicate, claim.object]
        .where((text) => text.trim().isNotEmpty).join(' ');
    return value.length > 100 ? '${value.substring(0, 100)}…' : value;
  }

  void _errorNotice(Object error) {
    if (mounted) setState(() => _error = error.toString());
  }

  void _edit(IntermediateStoryBlueprint Function(
      IntermediateStoryBlueprint) action, {String? select}) {
    final current = _draft;
    if (current == null || _working) return;
    try {
      final next = action(current);
      MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, next);
      setState(() {
        _draft = next;
        _selectedSceneId = select ?? _selectedSceneId;
        _dirty = true;
        _validated = null;
        _validatedRaw = null;
        _error = null;
        _notice = null;
      });
    } catch (error) {
      _errorNotice(error);
    }
  }

  void _startFromShort() {
    if (_short == null || _review == null ||
        _catalog == null || _editorial == null) return;
    try {
      final copy = MultiSceneDraftWorkbench.fromReviewedShortDraft(
          widget.index, _review!.graph, _catalog!, _editorial!, _short!);
      MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, copy);
      setState(() {
        _draft = copy;
        _selectedSceneId = copy.entrySceneId;
        _dirty = true;
        _showSpoilers = true;
        _notice = 'Создан отдельный многосценный черновик. '
            'Короткая адаптация не изменена. Сохраните его.';
        _error = null;
      });
    } catch (error) {
      _errorNotice(error);
    }
  }

  Future<void> _openShortEditor() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ReviewedStoryEditorPage(
          index: widget.index, gateway: widget.gateway),
    ));
    if (mounted) await _load();
  }

  Future<void> _saveOnly() async {
    final draft = _draft;
    if (_working || draft == null) return;
    setState(() { _working = true; _error = null; });
    try {
      MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, draft);
      await _multiStore.write(widget.index.sourceFingerprint, draft.encode());
      if (mounted) setState(() {
        _dirty = false;
        _notice = 'Многосценный черновик сохранён отдельно от короткого.';
      });
    } catch (error) {
      _errorNotice('Не удалось сохранить черновик: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _checkCausality() {
    final draft = _draft;
    if (draft == null || _review == null ||
        _catalog == null || _editorial == null) return;
    try {
      MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, draft);
      final acceptance = PrivateAdaptationPreflight.evaluate(
          widget.index, _review!.graph, _catalog!, _editorial!, draft);
      if (!acceptance.isStructurallyReady) {
        throw FormatException(
            'Сценарий ещё не готов: ${acceptance.userFacingBlockers.join("; ")}');
      }
      setState(() {
        _validated = acceptance.causal;
        _validatedRaw = draft.encode();
        _notice = 'Причинность проверена: '
            '${acceptance.causal.reachableScenes} сцен, '
            '${acceptance.causal.reachableEndings} финалов, '
            '${acceptance.causal.reachableStates} игровых состояний. '
            'Это не означает полный охват книги.';
        _error = null;
      });
    } catch (error) {
      setState(() {
        _validated = null;
        _validatedRaw = null;
        _error = '$error';
      });
    }
  }

  bool get _canCompile => !_working && _draft != null &&
      _validated != null && _validatedRaw == _draft!.encode() &&
      _privateConsent;

  Future<void> _compileAndOpen() async {
    final draft = _draft;
    if (!_canCompile || draft == null ||
        _review == null || _catalog == null || _editorial == null) return;
    setState(() { _working = true; _error = null; });
    try {
      // Optional opt-in overlay. When disabled, the established compiler
      // path remains bit-for-bit unchanged and does not read NPC checkpoints.
      NpcKnowledgeRulebook? rules;
      NpcEditorialNotebook? notebook;
      SourceCharacterDossierIndex? dossiers;
      if (_includeNpcRules) {
        final fingerprint = widget.index.sourceFingerprint;
        final graph = _review!.graph;
        final rawRules = await _knowledgeStore.read(fingerprint);
        final rawNpc = await _npcStore.read(fingerprint);
        final rawIdentity = await _identityStore.read(fingerprint);
        if (rawRules == null || rawNpc == null) {
          throw const FormatException(
              'Нет сохранённых правил знаний и карточек NPC');
        }
        final relations = rawIdentity == null
            ? SourceRelationReviewSession.create(widget.index, graph)
            : SourceRelationReviewSession.decode(
                widget.index, graph, rawIdentity);
        dossiers = SourceCharacterDossierIndex.build(
            widget.index, graph, relations, _catalog!, _editorial!);
        notebook = NpcEditorialNotebook.decode(
            widget.index, dossiers, graph, _catalog!, _editorial!, rawNpc);
        rules = NpcKnowledgeRulebook.decode(
            index: widget.index, dossiers: dossiers, graph: graph,
            catalog: _catalog!, editorial: _editorial!,
            notebook: notebook, scenario: draft, raw: rawRules);
        if (rules.rules.isEmpty) {
          throw const FormatException(
              'Сначала добавьте явное правило знания NPC');
        }
      }
      MultiSceneDraftWorkbench.checkSafeCheckpoint(widget.index, draft);
      await _multiStore.write(widget.index.sourceFingerprint, draft.encode());
      final bytes = await compileReviewedPrivateBookworldInWorker(
          widget.index, _review!.graph, _catalog!, _editorial!, draft,
          npcRules: rules, npcNotebook: notebook, npcDossiers: dossiers);
      final world = await widget.gateway.install(bytes);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _notice = 'Многосценный .bworld проверен и добавлен в библиотеку.';
      });
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldCampaignsPage(
            world: world, gateway: widget.gateway),
      ));
    } catch (error) {
      _errorNotice('Сборка/установка не выполнена: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _addSource() {
    final chosen = _selectedClaimId;
    if (chosen == null) {
      _errorNotice('Нет проверенных исходных событий для сцены.');
      return;
    }
    final current = _draft;
    if (current == null) return;
    _edit((draft) => MultiSceneDraftWorkbench.addSourceScene(
        draft, widget.index, _review!.graph, _catalog!, _editorial!, chosen));
    if (_draft != current && _draft!.scenes.isNotEmpty) {
      setState(() => _selectedSceneId = _draft!.scenes.last.id);
    }
  }

  void _addAuthored() {
    final prior = _selectedScene;
    final current = _draft;
    if (current == null) return;
    _edit((draft) => MultiSceneDraftWorkbench.addAuthoredScene(
        draft, chapterIndex: prior?.chapterIndex ?? 0));
    if (_draft != current && _draft!.scenes.isNotEmpty) {
      setState(() => _selectedSceneId = _draft!.scenes.last.id);
    }
  }

  DraftScene? get _selectedScene {
    final draft = _draft;
    if (draft == null) return null;
    for (final scene in draft.scenes) {
      if (scene.id == _selectedSceneId) return scene;
    }
    return draft.scenes.isEmpty ? null : draft.scenes.first;
  }

  void _editScene(DraftScene scene,
      DraftScene Function(DraftScene) action) {
    _edit((draft) => MultiSceneDraftWorkbench.replaceScene(
        draft, action(scene)));
  }

  int _earliestChapter(DraftScene scene) {
    final catalog = _catalog;
    final graph = _review?.graph;
    if (catalog == null || graph == null) return 0;
    final sources = {for (final s in graph.records) s.id: s};
    final claims = {for (final a in catalog.assertions) a.id: a};
    var latest = 0;
    for (final id in scene.assertionIds) {
      for (final evidenceId in claims[id]?.evidenceIds ?? <String>[]) {
        final chapter = sources[evidenceId]?.chapterIndex ?? 0;
        if (chapter > latest) latest = chapter;
      }
    }
    return latest;
  }

  void _editChoice(String sceneId, DraftChoice choice,
      DraftChoice Function(DraftChoice) action) {
    _edit((draft) => MultiSceneDraftWorkbench.replaceChoice(
        draft, sceneId, action(choice)));
  }

  void _toggleChoiceFlag(DraftScene scene, DraftChoice choice,
      String flag, String role, bool selected) {
    List<String> revised(List<String> old) => [
      for (final item in old) if (item != flag) item,
      if (selected) flag,
    ];
    List<String> without(List<String> old) => [
      for (final item in old) if (item != flag) item,
    ];
    // Conflicting flag pairs are mutually exclusive.
    final edited = MultiSceneDraftWorkbench.choiceCopy(choice,
      requires: role == 'requires'
          ? revised(choice.requires)
          : role == 'forbids' && selected
              ? without(choice.requires) : choice.requires,
      forbids: role == 'forbids'
          ? revised(choice.forbids)
          : role == 'requires' && selected
              ? without(choice.forbids) : choice.forbids,
      adds: role == 'adds'
          ? revised(choice.adds)
          : role == 'removes' && selected
              ? without(choice.adds) : choice.adds,
      removes: role == 'removes'
          ? revised(choice.removes)
          : role == 'adds' && selected
              ? without(choice.removes) : choice.removes,
    );
    _editChoice(scene.id, choice, (_) => edited);
  }

  Widget _choiceFlagLine(DraftScene scene, DraftChoice choice,
      String title, String role, List<String> selected) {
    final draft = _draft!;
    if (draft.flags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final flag in draft.flags)
              FilterChip(
                key: Key('multi-flag-$role-${choice.id}-$flag'),
                label: Text(flag),
                selected: selected.contains(flag),
                onSelected: _working ? null : (checked) =>
                    _toggleChoiceFlag(scene, choice, flag, role, checked),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _choiceEditor(DraftScene scene, DraftChoice choice) {
    final draft = _draft!;
    return Card(
      key: Key('multi-choice-card-${choice.id}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Действие ${choice.id}',
                  style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                key: Key('multi-remove-choice-${choice.id}'),
                tooltip: 'Удалить выбор',
                onPressed: _working ? null : () => _edit((draft) =>
                    MultiSceneDraftWorkbench.removeChoice(
                        draft, scene.id, choice.id)),
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            TextFormField(
              key: Key('multi-choice-label-${choice.id}'),
              initialValue: choice.label,
              enabled: !_working,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Текст действия игрока',
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => _editChoice(scene.id, choice,
                  (old) => MultiSceneDraftWorkbench.choiceCopy(old,
                      label: text)),
            ),
            DropdownButtonFormField<String>(
              key: Key('multi-choice-target-${choice.id}'),
              initialValue: choice.nextSceneId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Следующая сцена',
                  border: OutlineInputBorder()),
              items: [
                for (final node in draft.scenes)
                  DropdownMenuItem(
                    value: node.id,
                    child: Text('${node.id} · глава ${node.chapterIndex + 1}'),
                  ),
              ],
              onChanged: _working ? null : (id) {
                if (id != null) {
                  _editChoice(scene.id, choice,
                      (old) => MultiSceneDraftWorkbench.choiceCopy(
                          old, nextSceneId: id));
                }
              },
            ),
            if (draft.flags.isNotEmpty)
              ExpansionTile(
                title: const Text('Условия и последствия'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  _choiceFlagLine(scene, choice, 'Требуется', 'requires',
                      choice.requires),
                  _choiceFlagLine(scene, choice, 'Запрещено', 'forbids',
                      choice.forbids),
                  _choiceFlagLine(scene, choice, 'Добавить флаг', 'adds',
                      choice.adds),
                  _choiceFlagLine(scene, choice, 'Снять флаг', 'removes',
                      choice.removes),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteScene(DraftScene scene) async {
    final approved = await showDialog<bool>(
      context: context, builder: (context) => AlertDialog(
        title: const Text('Удалить сцену?'),
        content: const Text('Сцена будет убрана только из этого черновика. '
            'Входящие переходы сначала необходимо перенаправить. '
            'Книга и уже созданные игры не меняются.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить сцену'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    _edit((draft) => MultiSceneDraftWorkbench.removeScene(
        draft, scene.id), select: _draft!.entrySceneId);
  }

  Widget _sceneEditor(DraftScene scene) {
    final draft = _draft!;
    final earliest = _earliestChapter(scene);
    return Column(
      key: ValueKey('multi-selected-${scene.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Сцена ${scene.id}',
              style: Theme.of(context).textTheme.titleMedium)),
          if (scene.id != draft.entrySceneId)
            IconButton(
              key: const Key('multi-delete-scene'),
              onPressed: _working ? null : () => _deleteScene(scene),
              tooltip: 'Удалить сцену',
              icon: const Icon(Icons.delete_outline),
            ),
        ]),
        Text(scene.origin == DraftSceneOrigin.sourcePassage
            ? 'По книге: подтверждённые цитаты; нельзя изменить источник.'
            : 'Авторская альтернатива: написана вами, не канон книги.'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: Key('multi-scene-chapter-${scene.id}'),
          initialValue: scene.chapterIndex,
          decoration: const InputDecoration(
              labelText: 'Глава, после которой доступна сцена',
              border: OutlineInputBorder()),
          items: [
            for (var i = earliest; i < widget.index.chapterCount; i++)
              DropdownMenuItem<int>(
                value: i, child: Text('Глава ${i + 1}'),
              ),
          ],
          onChanged: _working ? null : (value) {
            if (value != null) {
              _editScene(scene, (old) =>
                  MultiSceneDraftWorkbench.sceneCopy(
                      old, chapterIndex: value));
            }
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: Key('multi-scene-text-${scene.id}'),
          initialValue: scene.text,
          enabled: !_working,
          minLines: 3, maxLines: 8,
          maxLength: 6000,
          decoration: const InputDecoration(
              labelText: 'Текст игровой сцены',
              border: OutlineInputBorder()),
          onChanged: (text) => _editScene(scene,
              (old) => MultiSceneDraftWorkbench.sceneCopy(
                  old, text: text)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Выборы: ${scene.choices.length} · '
              '${scene.choices.isEmpty ? "Финал" : "Продолжение"}')),
          OutlinedButton.icon(
            key: const Key('multi-add-choice'),
            onPressed: _working || draft.scenes.length < 2 ? null : () {
              final destination = draft.scenes.firstWhere(
                  (other) => other.id != scene.id,
                  orElse: () => draft.scenes.first);
              _edit((current) => MultiSceneDraftWorkbench.addChoice(
                  current, scene.id, destination.id));
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить выбор'),
          ),
        ]),
        if (scene.choices.isEmpty)
          const Text('Без переходов это финальная сцена. '
              'Для продолжения добавьте выбор и укажите его цель.'),
        for (final choice in scene.choices) _choiceEditor(scene, choice),
      ],
    );
  }

  Widget _flagEditor(IntermediateStoryBlueprint draft) => ExpansionTile(
    key: const Key('multi-flags-section'),
    title: Text('Игровые состояния (флаги): ${draft.flags.length}'),
    subtitle: const Text('Используются для условий и последствий выборов.'),
    childrenPadding: const EdgeInsets.only(bottom: 12),
    children: [
      Row(children: [
        Expanded(child: TextField(
          key: const Key('multi-new-flag'),
          controller: _flagController,
          enabled: !_working,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: 'Идентификатор флага: found_key',
          ),
        )),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('multi-add-flag'),
          onPressed: _working ? null : () {
            final previous = _draft;
            _edit((draft) => MultiSceneDraftWorkbench.addFlag(
                draft, _flagController.text.trim()));
            if (_draft != previous) _flagController.clear();
          },
          child: const Text('Добавить'),
        ),
      ]),
      for (final flag in draft.flags)
        Row(children: [
          Expanded(child: CheckboxListTile(
            key: Key('multi-initial-flag-$flag'),
            dense: true,
            value: draft.initialFlags.contains(flag),
            title: Text(flag),
            subtitle: const Text('Активен в начале игры'),
            onChanged: _working ? null : (checked) => _edit(
                (draft) => MultiSceneDraftWorkbench.setInitiallyActive(
                    draft, flag, checked ?? false)),
          )),
          IconButton(
            key: Key('multi-remove-flag-$flag'),
            tooltip: 'Удалить флаг',
            onPressed: _working ? null : () => _edit(
                (draft) => MultiSceneDraftWorkbench.removeFlag(
                    draft, flag)),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final selected = _selectedScene;
    return Scaffold(
      appBar: AppBar(title: const Text('Конструктор многосценной RPG')),
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
                    const Text('Создавайте собственные сцены, переходы '
                        'и последствия решений. Это частная офлайн-адаптация, '
                        'не автоматическая RPG по всему роману. '
                        'Книга не отправляется в сеть, ИИ отключён.'),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                    ],
                    if (_notice != null) Text(_notice!),
                    const SizedBox(height: 12),
                    if (_review == null || _catalog == null ||
                        _editorial == null)
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Повторить загрузку'),
                      )
                    else if (draft == null) ...[
                      const Text('Для начала подготовьте проверенный '
                          'короткий сценарий из двух событий книги. '
                          'Затем скопируйте его в независимый '
                          'многосценный черновик.'),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('multi-open-short-editor'),
                        onPressed: _openShortEditor,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Открыть короткий редактор'),
                      ),
                      if (_short != null) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('multi-copy-short'),
                          onPressed: _startFromShort,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Создать многосценный черновик'),
                        ),
                      ],
                    ] else ...[
                      Text('Сцен: ${draft.scenes.length} · '
                          'Флагов: ${draft.flags.length} · '
                          '${_dirty ? "Есть несохранённые изменения" : "Сохранённый черновик"}'),
                      const SizedBox(height: 8),
                      if (!_showSpoilers)
                        OutlinedButton.icon(
                          key: const Key('multi-show-spoilers'),
                          onPressed: () => setState(() =>
                              _showSpoilers = true),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Открыть сцены (спойлеры)'),
                        )
                      else ...[
                        const Divider(height: 24),
                        DraftSceneGraphPanel(
                          key: ValueKey('scene-graph-${draft.sourceFingerprint}'),
                          index: widget.index,
                          draft: draft,
                          enabled: !_working,
                          onSelectScene: (id) => setState(
                              () => _selectedSceneId = id),
                        ),
                        const SizedBox(height: 12),
                        Text('Создание сцен',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        if (_available.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            key: const Key('multi-source-claim'),
                            initialValue: _selectedClaimId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Подтверждённое событие книги',
                              border: OutlineInputBorder()),
                            items: [
                              for (final claim in _available)
                                DropdownMenuItem(
                                  value: claim.id,
                                  child: Text(_claimName(claim),
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: _working ? null : (id) =>
                                setState(() => _selectedClaimId = id),
                          ),
                          const SizedBox(height: 8),
                        ] else
                          const Text('Нет подтверждённых событий для '
                              'новых сцен из книги. Можно добавлять '
                              'только явно авторские альтернативы.'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                            key: const Key('multi-add-source'),
                            onPressed: _working || _available.isEmpty
                                ? null : _addSource,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Добавить событие из книги'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('multi-add-authored'),
                            onPressed: _working ? null : _addAuthored,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Добавить авторскую сцену'),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          key: ValueKey('multi-select-${draft.scenes.length}-${selected?.id}'),
                          initialValue: selected?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Редактируемая сцена',
                            border: OutlineInputBorder()),
                          items: [
                            for (final scene in draft.scenes)
                              DropdownMenuItem(
                                value: scene.id,
                                child: Text('${scene.id} · '
                                    'глава ${scene.chapterIndex + 1} · '
                                    '${scene.origin == DraftSceneOrigin.sourcePassage ? "по книге" : "авторская"}'),
                              ),
                          ],
                          onChanged: _working ? null : (value) =>
                              setState(() => _selectedSceneId = value),
                        ),
                        const SizedBox(height: 16),
                        if (selected != null) _sceneEditor(selected),
                        const Divider(height: 28),
                        _flagEditor(draft),
                        const Divider(height: 28),
                        Text('Проверка и запуск',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Text('Черновик можно сохранить недописанным. '
                            'Сборка доступна только после проверки '
                            'источников, двух достижимых финалов, '
                            'всех переходов и причинных зависимостей.'),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                            key: const Key('multi-save-draft'),
                            onPressed: _working ? null : _saveOnly,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Сохранить черновик'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('multi-check-causality'),
                            onPressed: _working ? null : _checkCausality,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Проверить сюжет и причинность'),
                          ),
                        ]),
                        if (_validated != null) ...[
                          const SizedBox(height: 8),
                          Text('Проверено: ${_validated!.reachableScenes} '
                              'сцен · ${_validated!.reachableEndings} '
                              'финалов · ${_validated!.reachableStates} '
                              'состояний.'),
                        ],
                        CheckboxListTile(
                          key: const Key('multi-use-npc-rules'),
                          value: _includeNpcRules,
                          onChanged: _working ? null : (checked) =>
                              setState(() =>
                                  _includeNpcRules = checked ?? false),
                          title: const Text(
                              'Включить вручную проверенные знания NPC'),
                          subtitle: const Text(
                              'По умолчанию выключено. При включении '
                              'требуется отдельная проверка всех NPC, '
                              'цитат, заметок и переходов. В новую RPG '
                              'попадут лишь идентификаторы знаний, '
                              'без текста секретов.'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          key: const Key('multi-private-consent'),
                          value: _privateConsent,
                          onChanged: _working ? null : (checked) =>
                              setState(() => _privateConsent = checked ?? false),
                          title: const Text('Только личная адаптация'),
                          subtitle: const Text('Не разрешает публикацию '
                              'или распространение чужого текста.'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        FilledButton.icon(
                          key: const Key('multi-compile-private'),
                          onPressed: _canCompile ? _compileAndOpen : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Собрать и открыть личную RPG'),
                        ),
                        if (_working)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ],
                  ],
                ),
              )),
            ),
    );
  }
}
