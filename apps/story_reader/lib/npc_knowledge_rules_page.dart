import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

typedef NoteOption = ({
  NpcDraftProfile profile, SourceCharacterDossier dossier, NpcDraftNote note,
});
typedef ChoiceOption = ({DraftScene scene, DraftChoice choice});

/// Manual, private rule authoring. No implicit AI consent or note publication.
class NpcKnowledgeRulesPage extends StatefulWidget {
  const NpcKnowledgeRulesPage({
    super.key, required this.index, required this.dossiers,
    required this.graph, required this.catalog, required this.editorial,
    required this.notebook, required this.scenario, this.repository,
  });
  final BookSourceIndex index;
  final SourceCharacterDossierIndex dossiers;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final NpcEditorialNotebook notebook;
  final IntermediateStoryBlueprint scenario;
  final SourceAnalysisCheckpointRepository? repository;

  @override
  State<NpcKnowledgeRulesPage> createState() => _NpcKnowledgeRulesPageState();
}

class _NpcKnowledgeRulesPageState extends State<NpcKnowledgeRulesPage> {
  late final SourceAnalysisCheckpointRepository _store =
      widget.repository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.npcKnowledgeRules);
  late final List<NoteOption> _notes = [
    for (final profile in widget.notebook.profiles)
      for (final dossier in widget.dossiers.dossiers)
        if (dossier.id == profile.dossierId)
          for (final note in profile.notes)
            if (note.field == NpcDraftField.knowledge ||
                note.field == NpcDraftField.secret)
              (profile: profile, dossier: dossier, note: note),
  ];
  late final List<ChoiceOption> _choices = [
    for (final scene in widget.scenario.scenes)
      for (final choice in scene.choices)
        (scene: scene, choice: choice),
  ];

  NpcKnowledgeRulebook? _book;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _check(NpcKnowledgeRulebook book) => book.validate(
    index: widget.index, dossiers: widget.dossiers, graph: widget.graph,
    catalog: widget.catalog, editorial: widget.editorial,
    notebook: widget.notebook, scenario: widget.scenario,
  );

  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = true; _error = null; _notice = null; _book = null;
    });
    try {
      final raw = await _store.read(widget.index.sourceFingerprint);
      final book = raw == null
          ? NpcKnowledgeRulebook.empty(widget.index)
          : NpcKnowledgeRulebook.decode(
              index: widget.index, dossiers: widget.dossiers,
              graph: widget.graph, catalog: widget.catalog,
              editorial: widget.editorial, notebook: widget.notebook,
              scenario: widget.scenario, raw: raw);
      _check(book);
      if (mounted) setState(() { _book = book; _loading = false; });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Редактор правил заблокирован: $error. '
            'Старый файл не изменён.';
        _loading = false;
      });
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title), content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Подтвердить')),
          ],
        ),
      ) == true;

  Future<void> _save(NpcKnowledgeRulebook candidate) async {
    if (_saving || _book == null) return;
    setState(() { _saving = true; _error = null; _notice = null; });
    try {
      _check(candidate);
      await _store.write(widget.index.sourceFingerprint, candidate.encode());
      if (mounted) setState(() {
        _book = candidate;
        _notice = 'Правила записаны отдельно от книги и сценария.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Не сохранено: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    final yes = await _confirm('Очистить только правила NPC?',
        'Удалить только связи знаний с выборами этой книги? '
        'NPC, цитаты, сценарии, миры и игры останутся.');
    if (!yes || !mounted) return;
    setState(() => _saving = true);
    try {
      await _store.delete(widget.index.sourceFingerprint);
    } catch (error) {
      if (mounted) setState(() => _error = 'Сброс не выполнен: $error');
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) await _load();
  }

  Future<void> _remove(NpcKnowledgeRule rule) async {
    if (_saving || _book == null) return;
    if (!await _confirm('Удалить правило?', 'Удалить только '
        'правило ${rule.id}, сохранив заметку и выбор?')) return;
    if (mounted) await _save(_book!.withoutRule(rule.id));
  }

  Future<void> _edit([NpcKnowledgeRule? existing]) async {
    if (_saving || _book == null || _notes.isEmpty || _choices.isEmpty) return;
    var noteId = existing?.noteId ?? _notes.first.note.id;
    var choiceId = existing?.choiceId ?? _choices.first.choice.id;
    var recipient = existing?.recipient ?? KnowledgeRecipient.ownerNpc;
    var approved = existing?.playerApproval ?? false;

    final proposal = await showDialog<({
      String note, String choice, KnowledgeRecipient recipient, bool approved,
    })>(
      context: context, builder: (ctx) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(existing == null ? 'Добавить правило' : 'Изменить правило'),
          content: SizedBox(width: 510, child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Выберите точную заметку и действие. '
                    'Текст тайны не копируется в игровую схему.'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('knowledge-note-select'),
                  initialValue: noteId, isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Знание или секрет', border: OutlineInputBorder()),
                  items: [
                    for (final item in _notes)
                      DropdownMenuItem(value: item.note.id,
                        child: Text('${item.profile.displayName} · '
                            '${item.note.field.name} · ${item.note.id}',
                            overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => noteId = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('knowledge-choice-select'),
                  initialValue: choiceId, isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Игровой переход', border: OutlineInputBorder()),
                  items: [
                    for (final option in _choices)
                      DropdownMenuItem(value: option.choice.id,
                        child: Text('Глава ${option.scene.chapterIndex + 1} · '
                            '${option.choice.label}',
                            overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => choiceId = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<KnowledgeRecipient>(
                  key: const Key('knowledge-recipient'),
                  initialValue: recipient, isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Кому добавить знание',
                    border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: KnowledgeRecipient.ownerNpc,
                        child: Text('Самому NPC')),
                    DropdownMenuItem(value: KnowledgeRecipient.player,
                        child: Text('Игроку (с отдельным согласием)')),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() {
                      recipient = v;
                      if (v == KnowledgeRecipient.ownerNpc) approved = false;
                    });
                  },
                ),
                if (recipient == KnowledgeRecipient.player)
                  CheckboxListTile(
                    key: const Key('knowledge-player-approval'),
                    value: approved,
                    onChanged: (v) => update(() => approved = v == true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Я разрешаю добавить факт в знания игрока'),
                    subtitle: const Text('Без текста секрета, без ИИ и '
                        'только после указанного действия.'),
                  ),
              ],
            ),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('knowledge-confirm'),
              onPressed: recipient == KnowledgeRecipient.player && !approved
                  ? null : () => Navigator.pop(dialog, (
                    note: noteId, choice: choiceId,
                    recipient: recipient, approved: approved,
                  )),
              child: const Text('Проверить и сохранить'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || proposal == null || _book == null) return;
    final note = _notes.singleWhere((x) => x.note.id == proposal.note);
    final route = _choices.singleWhere((x) => x.choice.id == proposal.choice);
    if (proposal.recipient == KnowledgeRecipient.player) {
      if (!await _confirm('Разрешить знание игроку?',
          'После выбора «${route.choice.label}» игрок получит только '
          'непрозрачный идентификатор заметки ${note.note.id}. '
          'Текст секрета не станет видимым автоматически. '
          'Для этого потребуется новая сборка личной RPG.')) return;
      if (!mounted) return;
    }
    await _save(_book!.withRule(NpcKnowledgeRulebook.compose(
      id: existing?.id ?? _book!.nextRuleId(),
      index: widget.index, dossier: note.dossier, note: note.note,
      scene: route.scene, choice: route.choice,
      recipient: proposal.recipient,
      playerApproval: proposal.recipient == KnowledgeRecipient.player &&
          proposal.approved,
    )));
  }

  List<ChoiceOption> _gateTargets(NpcKnowledgeRule grant) {
    final source = _choices.singleWhere(
        (option) => option.choice.id == grant.choiceId);
    return [
      for (final option in _choices)
        if (option.choice.id != grant.choiceId &&
            option.scene.chapterIndex >= source.scene.chapterIndex)
          option,
    ];
  }

  Future<void> _removeGate(NpcKnowledgeGate gate) async {
    if (_saving || _book == null) return;
    final approved = await _confirm('Снять условие выбора?',
        'Условие ${gate.id} будет удалено только из авторских правил. '
        'Уже созданные игровые миры и сохранения останутся без изменений.');
    if (approved && mounted && _book != null) {
      await _save(_book!.withoutGate(gate.id));
    }
  }

  Future<void> _editGate([NpcKnowledgeGate? existing]) async {
    final book = _book;
    if (_saving || book == null || book.rules.isEmpty) return;
    var grantId = existing?.grantRuleId ?? book.rules.first.id;
    var targetId = existing?.choiceId;

    final proposal = await showDialog<({String grantId, String choiceId})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialog, update) {
          final grant = book.rules.singleWhere((rule) => rule.id == grantId);
          final targets = _gateTargets(grant);
          if (!targets.any((x) => x.choice.id == targetId)) {
            targetId = targets.isEmpty ? null : targets.first.choice.id;
          }
          return AlertDialog(
            title: Text(existing == null
                ? 'Условие знания для выбора'
                : 'Изменить условие знания'),
            content: SizedBox(
              width: 510,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Действие станет доступно только после того, '
                        'как указанный NPC или игрок действительно узнает '
                        'факт на другом переходе. Условие не раскрывает '
                        'текст секрета.'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('knowledge-gate-grant'),
                      initialValue: grantId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Какое полученное знание требуется',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final rule in book.rules)
                          DropdownMenuItem<String>(
                            value: rule.id,
                            child: Text(
                              '${rule.id}: ${rule.noteId} · '
                              '${rule.recipient == KnowledgeRecipient.player ? "игрок" : "NPC"}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() {
                          grantId = value;
                          targetId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: ValueKey('knowledge-gate-target-$grantId'),
                      child: DropdownButtonFormField<String>(
                      key: const Key('knowledge-gate-choice'),
                      initialValue: targetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Какой игровой выбор заблокировать',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final option in targets)
                          DropdownMenuItem<String>(
                            value: option.choice.id,
                            child: Text('Глава ${option.scene.chapterIndex + 1} · '
                                '${option.choice.label}',
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: targets.isEmpty ? null : (value) {
                        if (value != null) update(() => targetId = value);
                      },
                      ),
                    ),
                    if (targets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('Нет подходящих более поздних переходов. '
                            'Добавьте выбор в конструкторе сцен.'),
                      ),
                    const SizedBox(height: 8),
                    const Text('Недостижимые условия заблокируют сборку '
                        'BookWorld при независимой проверке причинности.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const Key('knowledge-gate-confirm'),
                onPressed: targetId == null ? null : () =>
                    Navigator.pop(dialog,
                        (grantId: grantId, choiceId: targetId!)),
                child: const Text('Проверить и сохранить'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || proposal == null || _book == null) return;
    final source = _book!.rules.singleWhere(
        (rule) => rule.id == proposal.grantId);
    final destination = _choices.singleWhere(
        (option) => option.choice.id == proposal.choiceId);
    if (!await _confirm('Добавить условие к игровому выбору?',
        'После получения ${source.noteId} выбор '
        '«${destination.choice.label}» станет доступным именно тому '
        'получателю, который указан в правиле ${source.id}. '
        'Старые игровые миры не изменятся.')) return;
    if (!mounted || _book == null) return;
    await _save(_book!.withGate(NpcKnowledgeRulebook.composeGate(
      id: existing?.id ?? _book!.nextGateId(),
      grant: source,
      scene: destination.scene,
      choice: destination.choice,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      appBar: AppBar(title: const Text('Правила знаний NPC')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.index.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Все правила задаются вручную. '
                      'Действия применяет существующий story_core. '
                      'ИИ отключён. Старые миры и сохранения не изменяются.'),
                  if (_error != null)
                    Text(_error!, style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                  if (_notice != null) Text(_notice!),
                  const SizedBox(height: 10),
                  if (book == null) ...[
                    OutlinedButton(
                      key: const Key('knowledge-retry'),
                      onPressed: _saving ? null : _load,
                      child: const Text('Повторить проверку')),
                    TextButton(
                      key: const Key('knowledge-reset'),
                      onPressed: _saving ? null : _reset,
                      child: const Text('Очистить только правила…')),
                  ] else ...[
                    Text('Правил: ${book.rules.length} · '
                        'условий: ${book.gates.length} · '
                        'заметок: ${_notes.length} · '
                        'переходов: ${_choices.length}'),
                    OutlinedButton.icon(
                      key: const Key('knowledge-add'),
                      onPressed: _saving || _notes.isEmpty || _choices.isEmpty
                          ? null : () => _edit(),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Добавить правило')),
                    if (_notes.isEmpty)
                      const Text('Добавьте в карточку NPC хотя бы одно '
                          'подтверждённое знание или секрет.'),
                    if (_choices.isEmpty)
                      const Text('Создайте переходы в конструкторе сцен.'),
                    for (final rule in book.rules)
                      Card(
                        key: Key('knowledge-rule-${rule.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${rule.id} · ${rule.noteId}'),
                              Text('После выбора ${rule.choiceId} · '
                                  '${rule.recipient == KnowledgeRecipient.player ? "узнаёт игрок" : "узнаёт NPC"}'),
                              const Text('Текст секрета не копируется в мир.'),
                              Wrap(spacing: 6, children: [
                                TextButton(
                                  key: Key('knowledge-edit-${rule.id}'),
                                  onPressed: _saving ? null : () => _edit(rule),
                                  child: const Text('Изменить')),
                                TextButton(
                                  key: Key('knowledge-delete-${rule.id}'),
                                  onPressed: _saving ? null : () => _remove(rule),
                                  child: const Text('Удалить')),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 18),
                    Text('Условия доступности действий',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('Сначала сохраните выдачу знания NPC, '
                        'затем укажите выбор, требующий это знание. '
                        'Для удаления выдачи сначала удалите связанные условия.'),
                    OutlinedButton.icon(
                      key: const Key('knowledge-gate-add'),
                      onPressed: _saving || !book.rules.any(
                          (rule) => _gateTargets(rule).isNotEmpty)
                          ? null : () => _editGate(),
                      icon: const Icon(Icons.rule),
                      label: const Text('Добавить условие знания'),
                    ),
                    for (final gate in book.gates)
                      Card(
                        key: Key('knowledge-gate-${gate.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${gate.id} · знание по ${gate.grantRuleId}'),
                              Text('Требуется перед выбором ${gate.choiceId}'),
                              Wrap(spacing: 6, children: [
                                TextButton(
                                  key: Key('knowledge-gate-edit-${gate.id}'),
                                  onPressed: _saving ? null : () => _editGate(gate),
                                  child: const Text('Изменить')),
                                TextButton(
                                  key: Key('knowledge-gate-delete-${gate.id}'),
                                  onPressed: _saving ? null : () => _removeGate(gate),
                                  child: const Text('Удалить')),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 18),
                    const Text('Для применения вернитесь в конструктор '
                        'многосценной RPG и вручную включите эти правила '
                        'при создании новой личной сборки.'),
                    if (_saving) const LinearProgressIndicator(),
                  ],
                ],
              ),
            )),
          ),
    );
  }
}
