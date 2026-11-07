import 'package:flutter/material.dart';
import 'package:bookworld_format/bookworld_format.dart';

import 'native_private_bookworld_compiler.dart';
import 'zai_npc_dialogue_draft.dart';
import 'npc_dialogue_draft_page.dart';
import 'npc_dialogue_responses_review_page.dart';
import 'private_classic_scenario_translator.dart';
import 'world_campaigns_page.dart';
import 'world_library_gateway.dart';

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

/// Optional item review in the EXISTING NPC build dialog (no second editor).
/// Typed gameplay IDs are derived internally from source+name+character_id.
class _BookItemReviewDraft {
  _BookItemReviewDraft(this.index);
  final int index;
  String name = '';
  String description = '';
  String? actorId;
  String? acquireChoice;
  String? acquireQuote;
  String? giveChoice;
  String? giveQuote;
  String? returnChoice;
  String? returnQuote;
  bool witnessed = false;
}


/// Source-reviewed lifecycle action, never inferred from free prose.
class _NpcLifeReviewDraft {
  _NpcLifeReviewDraft(this.index);
  final int index;
  String? actorId;
  String? choiceId;
  String? quote;
  String? nextState;
}

/// Manual, private rule authoring. No implicit AI consent or note publication.
class NpcKnowledgeRulesPage extends StatefulWidget {
  const NpcKnowledgeRulesPage({
    super.key, required this.index, required this.dossiers,
    required this.graph, required this.catalog, required this.editorial,
    required this.notebook, required this.scenario, this.repository,
    this.gateway,
  });
  final BookSourceIndex index;
  final SourceCharacterDossierIndex dossiers;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final NpcEditorialNotebook notebook;
  final IntermediateStoryBlueprint scenario;
  final SourceAnalysisCheckpointRepository? repository;
  /// Test/host can inject an existing library; production uses the same
  /// DeviceWorldLibraryGateway as all other BookWorld paths.
  final WorldLibraryGateway? gateway;

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
  NpcDialogueDraftContext? _npcDialoguePreview;
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
      _npcDialoguePreview = null;
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
        _npcDialoguePreview = null;
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

  /// ONE source-reviewed handoff from the existing NPC rules screen to the
  /// existing compiler/library. No new authoring page, game core or cloud API.
  Future<void> _buildNpcRichWorld() async {
    final book = _book;
    if (_saving || book == null ||
        !book.rules.any((rule) =>
            rule.recipient == KnowledgeRecipient.ownerNpc)) return;
    setState(() { _saving = true; _error = null; _notice = null; });
    try {
      _check(book);
      final translation = PrivateClassicScenarioTranslator.translate(
        widget.index, widget.graph, widget.catalog, widget.editorial,
        widget.scenario,
        npcRules: book, npcNotebook: widget.notebook,
        npcDossiers: widget.dossiers,
      );
      final blueprint = translation.blueprintJson;
      final originValues = translation.provenanceJson['scene_origins'] as List;
      final origins = {
        for (final raw in originValues)
          (raw as Map<String, dynamic>)['scene_id'] as String: raw,
      };
      final sourceEvidence = {
        for (final evidence in widget.graph.records) evidence.id: evidence,
      };
      final sceneByChoice = <String, String>{};
      final dialogues = <({String sceneId, int index, String speaker})>[];
      for (final raw in blueprint['scenes'] as List) {
        final scene = raw as Map<String, dynamic>;
        final id = scene['id'] as String;
        for (final rawChoice in scene['choices'] as List) {
          final choice = rawChoice as Map<String, dynamic>;
          sceneByChoice[choice['id'] as String] = id;
        }
        final turns = RichSceneDialogue.parse(scene['text'] as String);
        if (turns == null) continue;
        for (var i = 0; i < turns.length; i++) {
          final speaker = turns[i].speaker;
          if (speaker != null) {
            dialogues.add((sceneId: id, index: i, speaker: speaker));
          }
        }
      }
      final grants = book.rules.where((rule) =>
          rule.recipient == KnowledgeRecipient.ownerNpc).toList();
      final options = <String, List<({String digest, String caption})>>{};
      for (final rule in grants) {
        final sceneId = sceneByChoice[rule.choiceId];
        final origin = origins[sceneId];
        final sourceRefs = origin?['source_refs'];
        if (sceneId == null || origin?['origin'] != 'SOURCE_PASSAGE' ||
            sourceRefs is! List || sourceRefs.isEmpty) {
          throw FormatException('Для правила ' + rule.id +
              ' нужна сцена с подтверждённой цитатой книги. '
              'Вернитесь к источникам и сценарию.');
        }
        final available = <String, ({String digest, String caption})>{};
        for (final raw in sourceRefs) {
          if (raw is! Map) continue;
          final evidenceId = raw['id'];
          final quote = evidenceId is String ? sourceEvidence[evidenceId] : null;
          if (quote == null || quote.status != EvidenceStatus.confirmed ||
              quote.visibleAfterChapter > (origin!['chapter_index'] as int) ||
              raw['quote_sha256'] != quote.evidenceSha256) continue;
          available[quote.evidenceSha256] = (
            digest: quote.evidenceSha256,
            caption: 'Глава ' + (quote.chapterIndex + 1).toString() +
                ' · ' + quote.label,
          );
        }
        if (available.isEmpty) {
          throw FormatException('Для правила ' + rule.id +
              ' нет доступных подтверждённых цитат.');
        }
        options[rule.id] = available.values.toList();
      }
      // Only decisions from source-verified scenes can be restricted by an
      // NPC social prerequisite. A quote for the target choice is confirmed
      // separately; the witness quote of an earlier action is not reused.
      final gateCandidates =
          <String, ({String sceneId, String label,
              List<({String digest, String caption})> quotes})>{};
      for (final rawScene in blueprint['scenes'] as List) {
        final scene = rawScene as Map<String, dynamic>;
        final sceneId = scene['id'] as String;
        final origin = origins[sceneId];
        if (origin?['origin'] != 'SOURCE_PASSAGE' ||
            origin?['source_refs'] is! List) continue;
        final available = <String, ({String digest, String caption})>{};
        for (final raw in origin!['source_refs'] as List) {
          if (raw is! Map) continue;
          final evidence = sourceEvidence[raw['id']];
          if (evidence == null ||
              evidence.status != EvidenceStatus.confirmed ||
              raw['quote_sha256'] != evidence.evidenceSha256 ||
              evidence.visibleAfterChapter >
                  (origin['chapter_index'] as int)) continue;
          available[evidence.evidenceSha256] = (
            digest: evidence.evidenceSha256,
            caption: 'Глава ' + (evidence.chapterIndex + 1).toString() +
                ' · ' + evidence.label,
          );
        }
        if (available.isEmpty) continue;
        for (final rawChoice in scene['choices'] as List) {
          final choice = rawChoice as Map<String, dynamic>;
          gateCandidates[choice['id'] as String] = (
            sceneId: sceneId,
            label: choice['label'] as String,
            quotes: available.values.toList(),
          );
        }
      }
      final profiles = {
        for (final profile in widget.notebook.profiles)
          if (profile.characterId != null)
            profile.characterId!: profile.displayName,
      };
      final actors = blueprint['actors'] as List;
      if (profiles.isEmpty || actors.length != profiles.length + 1 ||
          !profiles.keys.toSet().containsAll(actors.where(
              (id) => id != 'player').cast<String>())) {
        throw const FormatException(
            'Нужны постоянные карточки character_id всех NPC');
      }
      final factNames = <String, String>{};
      for (final rule in book.rules) {
        final profile = widget.notebook.profiles.singleWhere(
            (profile) => profile.dossierId == rule.dossierId);
        final note = profile.notes.singleWhere(
            (note) => note.id == rule.noteId);
        factNames[NpcKnowledgeRulebook.factId(
            widget.index.sourceFingerprint, rule.groupDigest, note)] =
            profile.displayName + ' · ' + rule.noteId;
      }
      final factIds = (blueprint['facts'] as List).cast<String>();
      if (!factNames.keys.toSet().containsAll(factIds)) {
        throw const FormatException('Есть факты без проверенной заметки');
      }
      final quotes = <String, String>{};
      // The author must explicitly say whether a named NPC witnessed a
      // committed action or merely heard a report. No model guesses this.
      final socialKind = <String, String>{};
      final socialMode = <String, String>{};
      final socialDelta = <String, int>{};
      final choiceGateTarget = <String, String>{};
      final choiceGateQuote = <String, String>{};
      final actorsForTurn = <String, String>{};
      final prerequisites = <String, String>{};
      final socialMemoryForTurn = <String, String>{};
      final socialTrustForTurn = <String, int>{};
      final itemDrafts = <_BookItemReviewDraft>[];
      var nextItemIndex = 1;
      final lifeDrafts = <_NpcLifeReviewDraft>[];
      var nextLifeIndex = 1;
      var consent = false;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(builder: (ctx, update) {
          final targets = choiceGateTarget.values
              .where((target) => target != 'none_required').toList();
          bool citedChoice(String? choiceId, String? quote) =>
              choiceId != null && quote != null &&
              gateCandidates[choiceId]?.quotes.any(
                  (candidate) => candidate.digest == quote) == true;
          final namedItems = itemDrafts.map((d) => d.name.trim()).toList();
          final itemsReady = itemDrafts.length <= 8 &&
              namedItems.length == namedItems.toSet().length &&
              itemDrafts.every((d) =>
                d.witnessed &&
                d.name.trim().length >= 2 && d.name.trim().length <= 90 &&
                d.description.trim().isNotEmpty &&
                d.description.trim().length <= 240 &&
                d.actorId != null && profiles.containsKey(d.actorId) &&
                citedChoice(d.acquireChoice, d.acquireQuote) &&
                citedChoice(d.giveChoice, d.giveQuote) &&
                d.acquireChoice != d.giveChoice &&
                d.returnChoice != null &&
                (d.returnChoice == 'none_required' ||
                 (d.returnChoice != d.giveChoice &&
                  d.returnChoice != d.acquireChoice &&
                  citedChoice(d.returnChoice, d.returnQuote))));
          final lifeKeys = lifeDrafts.map((e) =>
              '${e.choiceId}|${e.actorId}').toList();
          final lifeReady = lifeDrafts.length <= 16 &&
              lifeKeys.toSet().length == lifeKeys.length &&
              lifeDrafts.every((e) =>
                  e.actorId != null && profiles.containsKey(e.actorId) &&
                  const ['present', 'absent', 'dead'].contains(e.nextState) &&
                  citedChoice(e.choiceId, e.quote));
          final ready = consent && itemsReady && lifeReady &&
              quotes.length == grants.length &&
              targets.length == targets.toSet().length &&
              choiceGateTarget.entries.every((entry) =>
                entry.value == 'none_required' ||
                (socialKind[entry.key] != null &&
                 socialKind[entry.key] != 'none' &&
                 choiceGateQuote.containsKey(entry.key) &&
                 gateCandidates[entry.value]?.quotes.any((quote) =>
                     quote.digest == choiceGateQuote[entry.key]) == true)) &&
              socialKind.length == grants.length &&
              grants.every((rule) =>
                socialKind[rule.id] == 'none' ||
                (socialMode.containsKey(rule.id) &&
                 socialDelta.containsKey(rule.id) &&
                 !(socialMode[rule.id] == 'reported' &&
                   (socialKind[rule.id] != 'rumorHeard' ||
                    socialDelta[rule.id] != 0)))) &&
              actorsForTurn.length == dialogues.length &&
              prerequisites.length == dialogues.length &&
              socialMemoryForTurn.length == dialogues.length &&
              socialTrustForTurn.length == dialogues.length &&
              socialMemoryForTurn.entries.every((entry) =>
                entry.value == 'none_required' || grants.any((rule) =>
                  rule.id == entry.value &&
                  socialKind[rule.id] != 'none' &&
                  widget.notebook.profiles.any((profile) =>
                    profile.dossierId == rule.dossierId &&
                    profile.characterId == actorsForTurn[entry.key]))) &&
              socialTrustForTurn.entries.every((entry) =>
                entry.value == 0 || grants.any((rule) =>
                  socialKind[rule.id] != 'none' &&
                  (socialDelta[rule.id] ?? 0) > 0 &&
                  widget.notebook.profiles.any((profile) =>
                    profile.dossierId == rule.dossierId &&
                    profile.characterId == actorsForTurn[entry.key])));
          return AlertDialog(
            title: const Text('Проверить и собрать RPG с NPC'),
            content: SizedBox(width: 620, child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Это личная игровая адаптация, а не '
                      'доказанный литературный канон. Сначала выберите '
                      'источник каждого знания, затем проверьте говорящих. '
                      'Без этого сборка не начнётся.'),
                  const SizedBox(height: 14),
                  for (final rule in grants) ...[
                    Text('После действия ' + rule.choiceId +
                        ' · знание ' + rule.noteId),
                    DropdownButtonFormField<String>(
                      key: Key('npc-build-quote-' + rule.id),
                      isExpanded: true,
                      initialValue: quotes[rule.id],
                      decoration: const InputDecoration(
                        labelText: 'Подтверждённая цитата',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final ref in options[rule.id]!)
                          DropdownMenuItem(
                            value: ref.digest,
                            child: Text(ref.caption,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (digest) {
                        if (digest != null) {
                          update(() => quotes[rule.id] = digest);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: Key('npc-build-social-kind-' + rule.id),
                      isExpanded: true,
                      initialValue: socialKind[rule.id],
                      decoration: const InputDecoration(
                        labelText: 'Что NPC действительно запомнит?',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Не подтверждаю социальное событие')),
                        DropdownMenuItem(
                          value: 'witnessed', child: Text('Был очевидцем')),
                        DropdownMenuItem(
                          value: 'promiseReceived', child: Text('Услышал обещание')),
                        DropdownMenuItem(
                          value: 'promiseBroken', child: Text('Увидел нарушение обещания')),
                        DropdownMenuItem(
                          value: 'helped', child: Text('Получил помощь')),
                        DropdownMenuItem(
                          value: 'betrayed', child: Text('Стал свидетелем предательства')),
                        DropdownMenuItem(
                          value: 'rumorHeard', child: Text('Услышал слух')),
                      ],
                      onChanged: (kind) {
                        if (kind != null) update(() {
                          socialKind[rule.id] = kind;
                          socialMode.remove(rule.id);
                          socialDelta.remove(rule.id);
                          socialMemoryForTurn.clear();
                          socialTrustForTurn.clear();
                          choiceGateTarget.remove(rule.id);
                          choiceGateQuote.remove(rule.id);
                        });
                      },
                    ),
                    if (socialKind[rule.id] != null &&
                        socialKind[rule.id] != 'none') ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: Key('npc-build-social-witness-' + rule.id),
                        initialValue: socialMode[rule.id],
                        decoration: const InputDecoration(
                          labelText: 'Откуда NPC знает об этом?',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'present',
                              child: Text('Лично присутствовал в сцене')),
                          DropdownMenuItem(value: 'reported',
                              child: Text('Узнал со слов других (только слух)')),
                        ],
                        onChanged: (mode) {
                          if (mode != null) update(() {
                            socialMode[rule.id] = mode;
                            if (mode == 'reported') socialDelta[rule.id] = 0;
                            socialMemoryForTurn.clear();
                            socialTrustForTurn.clear();
                          });
                        },
                      ),
                      if (socialMode[rule.id] != null) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          key: Key('npc-build-social-relation-' + rule.id),
                          initialValue: socialDelta[rule.id],
                          decoration: const InputDecoration(
                            labelText: 'Как изменится отношение NPC к герою?',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: 0,
                                child: Text('Не изменится')),
                            if (socialMode[rule.id] == 'present') ...const [
                              DropdownMenuItem(value: 10,
                                  child: Text('Доверие +10')),
                              DropdownMenuItem(value: -10,
                                  child: Text('Доверие −10')),
                            ],
                          ],
                          onChanged: (value) {
                            if (value != null) update(() {
                              socialDelta[rule.id] = value;
                              socialMemoryForTurn.clear();
                              socialTrustForTurn.clear();
                            });
                          },
                        ),
                      ],
                    ],
                    if (socialKind[rule.id] != null &&
                        socialKind[rule.id] != 'none' &&
                        socialMode[rule.id] != null) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: Key('npc-build-choice-gate-' + rule.id),
                        isExpanded: true,
                        initialValue: choiceGateTarget[rule.id],
                        decoration: const InputDecoration(
                          labelText: 'Какое решение зависит от памяти NPC?',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'none_required',
                            child: Text('Не ограничивать игровые решения')),
                          for (final entry in gateCandidates.entries)
                            if (entry.key != rule.choiceId)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value.label,
                                    overflow: TextOverflow.ellipsis),
                              ),
                        ],
                        onChanged: (target) {
                          if (target != null) update(() {
                            choiceGateTarget[rule.id] = target;
                            choiceGateQuote.remove(rule.id);
                          });
                        },
                      ),
                      if (choiceGateTarget[rule.id] != null &&
                          choiceGateTarget[rule.id] != 'none_required') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: Key('npc-build-choice-quote-' + rule.id),
                          isExpanded: true,
                          initialValue: choiceGateQuote[rule.id],
                          decoration: const InputDecoration(
                            labelText: 'Цитата для ограничения решения',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final candidate in
                                gateCandidates[choiceGateTarget[rule.id]]!
                                    .quotes)
                              DropdownMenuItem(
                                value: candidate.digest,
                                child: Text(candidate.caption,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (digest) {
                            if (digest != null) update(() =>
                                choiceGateQuote[rule.id] = digest);
                          },
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                  ],
                  if (dialogues.isNotEmpty)
                    const Text('Говорящие и необходимое знание. '
                        'У каждой именованной реплики подтверждаются '
                        'личность и условие показа.'),
                  for (final turn in dialogues) ...[
                    const Divider(),
                    Text('Сцена ' + turn.sceneId + ' · реплика ' +
                        (turn.index + 1).toString() + ' · ' + turn.speaker),
                    DropdownButtonFormField<String>(
                      key: Key('npc-build-speaker-' + turn.sceneId +
                          '-' + turn.index.toString()),
                      isExpanded: true,
                      initialValue: actorsForTurn[
                          turn.sceneId + '|' + turn.index.toString()],
                      decoration: const InputDecoration(
                        labelText: 'Кто именно говорит',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'player',
                            child: Text('Игрок')),
                        for (final actorId in (profiles.keys.toList()..sort()))
                          DropdownMenuItem(value: actorId,
                              child: Text(profiles[actorId]!,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (actorId) {
                        if (actorId != null) {
                          update(() {
                            final key = turn.sceneId + '|' +
                                turn.index.toString();
                            actorsForTurn[key] = actorId;
                            socialMemoryForTurn.remove(key);
                            socialTrustForTurn.remove(key);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: Key('npc-build-fact-' + turn.sceneId +
                          '-' + turn.index.toString()),
                      isExpanded: true,
                      initialValue: prerequisites[
                          turn.sceneId + '|' + turn.index.toString()],
                      decoration: const InputDecoration(
                        labelText: 'Какое знание нужно для реплики',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'none_required',
                          child: Text('Не требует знания (я проверил)'),
                        ),
                        for (final id in factIds)
                          DropdownMenuItem(value: id,
                            child: Text(factNames[id] ?? id,
                                overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (fact) {
                        if (fact != null) {
                          update(() => prerequisites[
                              turn.sceneId + '|' +
                                  turn.index.toString()] = fact);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: Key('npc-build-memory-gate-' + turn.sceneId +
                          '-' + turn.index.toString()),
                      isExpanded: true,
                      initialValue: socialMemoryForTurn[
                          turn.sceneId + '|' + turn.index.toString()],
                      decoration: const InputDecoration(
                        labelText: 'Какой прошлый поступок NPC должен помнить?',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'none_required',
                            child: Text('Не требует воспоминания')),
                        for (final rule in grants)
                          if (socialKind[rule.id] != null &&
                              socialKind[rule.id] != 'none' &&
                              widget.notebook.profiles.any((profile) =>
                                profile.dossierId == rule.dossierId &&
                                profile.characterId == actorsForTurn[
                                  turn.sceneId + '|' + turn.index.toString()]))
                            DropdownMenuItem(value: rule.id,
                              child: Text('Поступок ' + rule.choiceId,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (memory) {
                        if (memory != null) update(() =>
                            socialMemoryForTurn[turn.sceneId + '|' +
                                turn.index.toString()] = memory);
                      },
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      key: Key('npc-build-trust-gate-' + turn.sceneId +
                          '-' + turn.index.toString()),
                      initialValue: socialTrustForTurn[
                          turn.sceneId + '|' + turn.index.toString()],
                      decoration: const InputDecoration(
                        labelText: 'Минимальное доверие NPC к герою для реплики',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 0,
                            child: Text('Не требуется')),
                        if (grants.any((rule) =>
                            (socialDelta[rule.id] ?? 0) > 0 &&
                            socialKind[rule.id] != 'none' &&
                            widget.notebook.profiles.any((profile) =>
                              profile.dossierId == rule.dossierId &&
                              profile.characterId == actorsForTurn[
                                turn.sceneId + '|' + turn.index.toString()])))
                          const DropdownMenuItem(value: 10,
                              child: Text('Доверие не меньше +10')),
                      ],
                      onChanged: (score) {
                        if (score != null) update(() =>
                            socialTrustForTurn[turn.sceneId + '|' +
                                turn.index.toString()] = score);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Divider(height: 24),
                  const Text('События жизни NPC (необязательно)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text('Событие меняет состояние NPC после выбора. '
                      'Гибель необратима. Для каждого события нужна цитата.'),
                  for (final life in lifeDrafts) ...[
                    Row(children: [
                      Expanded(child: Text('Событие ' +
                          life.index.toString())),
                      IconButton(
                        key: Key('npc-life-remove-' + life.index.toString()),
                        tooltip: 'Удалить событие',
                        icon: const Icon(Icons.close),
                        onPressed: () => update(() => lifeDrafts.remove(life)),
                      ),
                    ]),
                    DropdownButtonFormField<String>(
                      key: Key('npc-life-actor-' + life.index.toString()),
                      initialValue: life.actorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Персонаж', border: OutlineInputBorder()),
                      items: [
                        for (final entry in profiles.entries)
                          DropdownMenuItem(value: entry.key,
                              child: Text(entry.value,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => update(() => life.actorId = value),
                    ),
                    DropdownButtonFormField<String>(
                      key: Key('npc-life-state-' + life.index.toString()),
                      initialValue: life.nextState,
                      decoration: const InputDecoration(
                          labelText: 'Состояние после решения',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'absent',
                            child: Text('Ушёл / отсутствует')),
                        DropdownMenuItem(value: 'present',
                            child: Text('Вернулся')),
                        DropdownMenuItem(value: 'dead',
                            child: Text('Погиб (необратимо)')),
                      ],
                      onChanged: (value) => update(() => life.nextState = value),
                    ),
                    DropdownButtonFormField<String>(
                      key: Key('npc-life-choice-' + life.index.toString()),
                      initialValue: life.choiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'После игрового выбора',
                          border: OutlineInputBorder()),
                      items: [
                        for (final entry in gateCandidates.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value.label,
                                overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => update(() {
                        life.choiceId = value;
                        life.quote = null;
                      }),
                    ),
                    if (life.choiceId != null &&
                        gateCandidates.containsKey(life.choiceId))
                      DropdownButtonFormField<String>(
                        key: Key('npc-life-quote-' +
                            life.index.toString() + '-' + life.choiceId!),
                        initialValue: life.quote,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Цитата этого события',
                            border: OutlineInputBorder()),
                        items: [
                          for (final quote in
                              gateCandidates[life.choiceId]!.quotes)
                            DropdownMenuItem(
                              value: quote.digest,
                              child: Text(quote.caption,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) => update(() => life.quote = value),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (lifeDrafts.length < 16)
                    TextButton.icon(
                      key: const Key('npc-life-add'),
                      onPressed: () => update(() => lifeDrafts.add(
                          _NpcLifeReviewDraft(nextLifeIndex++))),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить событие жизни NPC'),
                    ),
                  const Divider(height: 24),
                  const Text('Предметы истории (необязательно)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text('Добавляйте только реальные предметы книги. '
                      'Укажите, каким выбором герой получает вещь, '
                      'каким передаёт NPC и, при наличии, каким получает '
                      'обратно. Для каждого действия нужна отдельная '
                      'подтверждённая цитата. ИИ предметы не выдумывает.'),
                  const SizedBox(height: 8),
                  for (final item in itemDrafts) ...[
                    const Divider(),
                    Row(children: [
                      Expanded(child: Text('Предмет ' +
                          item.index.toString())),
                      IconButton(
                        key: Key('npc-item-remove-' +
                            item.index.toString()),
                        tooltip: 'Убрать предмет из сборки',
                        icon: const Icon(Icons.close),
                        onPressed: () => update(() =>
                            itemDrafts.remove(item)),
                      ),
                    ]),
                    TextFormField(
                      key: Key('npc-item-name-' + item.index.toString()),
                      initialValue: item.name,
                      maxLength: 90,
                      decoration: const InputDecoration(
                        labelText: 'Название предмета из книги',
                        border: OutlineInputBorder()),
                      onChanged: (value) => update(() => item.name = value),
                    ),
                    TextFormField(
                      key: Key('npc-item-description-' +
                          item.index.toString()),
                      initialValue: item.description,
                      maxLength: 240,
                      decoration: const InputDecoration(
                        labelText: 'Краткое описание предмета',
                        border: OutlineInputBorder()),
                      onChanged: (value) =>
                          update(() => item.description = value),
                    ),
                    DropdownButtonFormField<String>(
                      key: Key('npc-item-actor-' + item.index.toString()),
                      initialValue: item.actorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Кому герой может передать предмет',
                        border: OutlineInputBorder()),
                      items: [
                        for (final entry in profiles.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value,
                                overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() {
                          item.actorId = value;
                          item.witnessed = false;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: Key('npc-item-acquire-' + item.index.toString()),
                      initialValue: item.acquireChoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Решение: герой получает предмет',
                        border: OutlineInputBorder()),
                      items: [
                        for (final entry in gateCandidates.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value.label,
                                overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() {
                          item.acquireChoice = value;
                          item.acquireQuote = null;
                          if (item.giveChoice == value) {
                            item.giveChoice = null;
                            item.giveQuote = null;
                          }
                          if (item.returnChoice == value) {
                            item.returnChoice = null;
                            item.returnQuote = null;
                          }
                          item.witnessed = false;
                        });
                      },
                    ),
                    if (item.acquireChoice != null) ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: Key('npc-item-acquire-quote-' +
                            item.index.toString()),
                        initialValue: item.acquireQuote,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Цитата: откуда предмет у героя',
                          border: OutlineInputBorder()),
                        items: [
                          for (final quote in
                              gateCandidates[item.acquireChoice]!.quotes)
                            DropdownMenuItem(
                              value: quote.digest,
                              child: Text(quote.caption,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() {
                            item.acquireQuote = value;
                            item.witnessed = false;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: Key('npc-item-give-' + item.index.toString()),
                      initialValue: item.giveChoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Решение: герой передаёт вещь NPC',
                        border: OutlineInputBorder()),
                      items: [
                        for (final entry in gateCandidates.entries)
                          if (entry.key != item.acquireChoice)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value.label,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() {
                          item.giveChoice = value;
                          item.giveQuote = null;
                          if (item.returnChoice == value) {
                            item.returnChoice = null;
                            item.returnQuote = null;
                          }
                          item.witnessed = false;
                        });
                      },
                    ),
                    if (item.giveChoice != null) ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: Key('npc-item-give-quote-' +
                            item.index.toString()),
                        initialValue: item.giveQuote,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Цитата: NPC получает вещь',
                          border: OutlineInputBorder()),
                        items: [
                          for (final quote in
                              gateCandidates[item.giveChoice]!.quotes)
                            DropdownMenuItem(
                              value: quote.digest,
                              child: Text(quote.caption,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() {
                            item.giveQuote = value;
                            item.witnessed = false;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: Key('npc-item-return-' + item.index.toString()),
                      initialValue: item.returnChoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Решение: NPC возвращает вещь',
                        border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                          value: 'none_required',
                          child: Text('Без возврата')),
                        for (final entry in gateCandidates.entries)
                          if (entry.key != item.acquireChoice &&
                              entry.key != item.giveChoice)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value.label,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() {
                          item.returnChoice = value;
                          item.returnQuote = null;
                          item.witnessed = false;
                        });
                      },
                    ),
                    if (item.returnChoice != null &&
                        item.returnChoice != 'none_required') ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: Key('npc-item-return-quote-' +
                            item.index.toString()),
                        initialValue: item.returnQuote,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Цитата: NPC возвращает вещь',
                          border: OutlineInputBorder()),
                        items: [
                          for (final quote in
                              gateCandidates[item.returnChoice]!.quotes)
                            DropdownMenuItem(
                              value: quote.digest,
                              child: Text(quote.caption,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() {
                            item.returnQuote = value;
                            item.witnessed = false;
                          });
                        },
                      ),
                    ],
                    CheckboxListTile(
                      key: Key('npc-item-witness-' +
                          item.index.toString()),
                      value: item.witnessed,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Проверено: выбранный NPC лично '
                          'присутствует при передаче и возврате вещи'),
                      subtitle: const Text('Нужна проверка по тексту; '
                          'совпадение имён не доказывает присутствие.'),
                      onChanged: (value) => update(() =>
                          item.witnessed = value == true),
                    ),
                  ],
                  OutlinedButton.icon(
                    key: const Key('npc-item-add'),
                    icon: const Icon(Icons.add),
                    onPressed: itemDrafts.length >= 8 ? null : () =>
                        update(() => itemDrafts.add(
                            _BookItemReviewDraft(nextItemIndex++))),
                    label: const Text('Добавить предмет из книги'),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const Key('npc-build-consent'),
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (value) =>
                        update(() => consent = value == true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Я проверил источники, '
                        'присутствие, события и реплики NPC для личной RPG'),
                    subtitle: const Text(
                        'ИИ не вызывается. Заметки NPC не публикуются. '
                        'Новая игра не изменяет существующие прохождения.'),
                  ),
                ],
              ),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена')),
              FilledButton(
                key: const Key('npc-build-confirm'),
                onPressed: ready ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Проверить и собрать'),
              ),
            ],
          );
        }),
      );
      if (accepted != true || !mounted) return;
      final spoken = <String, List<Map<String, dynamic>>>{};
      final verifiedSpeakers = <String, String>{};
      for (final turn in dialogues) {
        final key = turn.sceneId + '|' + turn.index.toString();
        final actorId = actorsForTurn[key]!;
        final prior = verifiedSpeakers[turn.speaker];
        if (prior != null && prior != actorId) {
          throw const FormatException(
              'Одинаковое имя назначено разным персонажам.');
        }
        verifiedSpeakers[turn.speaker] = actorId;
        final required = prerequisites[key]!;
        final requiredMemory = socialMemoryForTurn[key]!;
        final requiredTrust = socialTrustForTurn[key]!;
        spoken.putIfAbsent(turn.sceneId, () => []).add({
          'turn_index': turn.index, 'speaker': turn.speaker,
          'actor_id': actorId,
          'required_fact_ids':
              required == 'none_required' ? <String>[] : <String>[required],
          if (requiredMemory != 'none_required')
            'required_social_memory_id': requiredMemory,
          if (requiredTrust > 0) 'minimum_trust_to_player': requiredTrust,
        });
      }
      final socialWitnesses = <Map<String, dynamic>>[];
      final socialRules = <Map<String, dynamic>>[];
      final witnessModes = <String, String>{};
      for (final rule in grants) {
        final kind = socialKind[rule.id]!;
        if (kind == 'none') continue;
        final profile = widget.notebook.profiles.singleWhere(
            (profile) => profile.dossierId == rule.dossierId);
        final npc = profile.characterId;
        final scene = sceneByChoice[rule.choiceId];
        final mode = socialMode[rule.id]!;
        final quote = quotes[rule.id]!;
        final change = socialDelta[rule.id]!;
        if (npc == null || scene == null) {
          throw const FormatException('NPC без сцены или постоянного ID');
        }
        final witnessKey = scene + '|' + npc;
        if (witnessModes.containsKey(witnessKey) &&
            witnessModes[witnessKey] != mode) {
          throw const FormatException(
              'Один NPC не может одновременно отсутствовать и быть '
              'очевидцем той же сцены. Исправьте утверждения.');
        }
        if (!witnessModes.containsKey(witnessKey)) {
          witnessModes[witnessKey] = mode;
          socialWitnesses.add({
            'scene_id': scene,
            'actor_id': npc,
            'mode': mode,
            'source_quote_sha256': quote,
          });
        }
        socialRules.add({
          'memory_id': rule.id,
          'scene_id': scene,
          'choice_id': rule.choiceId,
          'observer_id': npc,
          'kind': kind,
          'related_actor_id': change == 0 ? null : 'player',
          'relationship_delta': change,
          'max_triggers': 1,
          'source_quote_sha256': quote,
        });
      }
      final reviewedChoiceGates = <Map<String, dynamic>>[];
      for (final rule in grants) {
        final target = choiceGateTarget[rule.id];
        if (target == null || target == 'none_required') continue;
        final profile = widget.notebook.profiles.singleWhere(
            (profile) => profile.dossierId == rule.dossierId);
        final candidate = gateCandidates[target];
        final quote = choiceGateQuote[rule.id];
        if (profile.characterId == null || candidate == null ||
            quote == null || socialKind[rule.id] == 'none') {
          throw const FormatException('Не подтверждён выбор NPC');
        }
        reviewedChoiceGates.add({
          'scene_id': candidate.sceneId,
          'choice_id': target,
          'actor_id': profile.characterId!,
          'required_memory_id': rule.id,
          'minimum_trust_to_player':
              (socialDelta[rule.id] ?? 0) > 0 ? socialDelta[rule.id] : null,
          'source_quote_sha256': quote,
        });
      }
      final socialReview =
          socialRules.isEmpty && lifeDrafts.isEmpty ? null : <String, dynamic>{
        'format': lifeDrafts.isNotEmpty
            ? RichNpcSocialContract.lifeEventFormat
            : reviewedChoiceGates.isEmpty
                ? RichNpcSocialContract.format
                : RichNpcSocialContract.choiceGateFormat,
        'review_scope': 'user_declared_private_game_fiction',
        'source_fingerprint': widget.index.sourceFingerprint,
        'user_confirmed': true,
        'literary_canon_verified': false,
        'witnesses': socialWitnesses,
        'rules': socialRules,
        if (reviewedChoiceGates.isNotEmpty || lifeDrafts.isNotEmpty)
          'choice_gates': reviewedChoiceGates,
        if (lifeDrafts.isNotEmpty) ...{
          'item_transfers': <Map<String, dynamic>>[],
          'item_grants': <Map<String, dynamic>>[],
          'life_transitions': [
            for (final event in lifeDrafts)
              {
                'scene_id': gateCandidates[event.choiceId]!.sceneId,
                'choice_id': event.choiceId,
                'actor_id': event.actorId,
                'next_state': event.nextState,
                'source_quote_sha256': event.quote,
              },
          ],
        },
      };
      final reviewedItems = <Map<String, dynamic>>[
        for (final item in itemDrafts)
          {
            'item_name': item.name.trim(),
            'item_description': item.description.trim(),
            'actor_id': item.actorId,
            'acquire_choice_id': item.acquireChoice,
            'acquire_quote_sha256': item.acquireQuote,
            'give_choice_id': item.giveChoice,
            'give_quote_sha256': item.giveQuote,
            'return_choice_id':
                item.returnChoice == 'none_required'
                    ? null : item.returnChoice,
            'return_quote_sha256':
                item.returnChoice == 'none_required'
                    ? null : item.returnQuote,
            'personally_witnessed': item.witnessed,
          },
      ];
      var bytes = await compileReviewedNpcRichPrivateBookworldInWorker(
        widget.index, widget.graph, widget.catalog, widget.editorial,
        widget.scenario,
        npcRules: book, npcNotebook: widget.notebook,
        npcDossiers: widget.dossiers,
        sourceQuoteByRuleId: quotes,
        userConfirmed: true,
        reviewedNpcSocial: socialReview,
        reviewedBookItems: reviewedItems,
        reviewedDialogueTurns: spoken,
        reviewedSpeakerBindings: verifiedSpeakers,
      );
      // Build and STRICTLY verify the base rich-v3 world first. The reply
      // editor cannot see or change unreviewed speakers or arbitrary choices.
      // This is a separate stage of the SAME wizard, not a new compiler.
      var verifiedWorld = const RichPrivateBookworldImporter().inspect(bytes);
      final availableReplies =
          NpcDialogueResponsesReviewPage.eligibleScenes(
        world: verifiedWorld,
        sceneOrigins: origins,
        sourceQuoteLabels: {
          for (final evidence in sourceEvidence.values)
            if (evidence.status == EvidenceStatus.confirmed)
              evidence.evidenceSha256:
                  'Глава ' + (evidence.chapterIndex + 1).toString() +
                  ' · ' + evidence.label,
        },
      );
      if (availableReplies.isNotEmpty) {
        if (!mounted) return;
        final decision = await Navigator.of(context).push<
            NpcResponsesReviewDecision>(MaterialPageRoute(
          builder: (_) => NpcDialogueResponsesReviewPage(
            world: verifiedWorld,
            sceneOrigins: origins,
            sourceQuoteLabels: {
              for (final evidence in sourceEvidence.values)
                if (evidence.status == EvidenceStatus.confirmed)
                  evidence.evidenceSha256:
                      'Глава ' + (evidence.chapterIndex + 1).toString() +
                      ' · ' + evidence.label,
            },
          ),
        ));
        // System Back cancels this WHOLE build. The explicit Skip button
        // is the only way to install an unchanged base world here.
        if (!mounted || decision == null) return;
        if (!decision.skipped) {
          final proposal = decision.proposal;
          if (proposal == null) {
            throw const FormatException(
                'Подтверждённые ответы NPC потеряны');
          }
          bytes = await compileReviewedNpcRichPrivateBookworldInWorker(
            widget.index, widget.graph, widget.catalog, widget.editorial,
            widget.scenario,
            npcRules: book, npcNotebook: widget.notebook,
            npcDossiers: widget.dossiers,
            sourceQuoteByRuleId: quotes,
            userConfirmed: true,
            reviewedNpcSocial: socialReview,
            reviewedBookItems: reviewedItems,
            reviewedDialogueTurns: spoken,
            reviewedSpeakerBindings: verifiedSpeakers,
            reviewedResponseProposal: proposal,
            approvedResponseDigest: proposal.approvalDigest,
          );
          verifiedWorld = const RichPrivateBookworldImporter().inspect(bytes);
          if (verifiedWorld.presentation['scene_dialogue_responses'] == null) {
            throw const FormatException(
                'Собранная игра потеряла принятые ответы NPC');
          }
        }
      }
      // Cloud authoring remains separate from OFFLINE play; no network
      // request is sent when merely building or answering an NPC.
      // Only a source-reviewed conversation can offer a later prose draft.
      NpcDialogueDraftContext? dialoguePrompt;
      final reviewed = verifiedWorld.presentation['scene_dialogue_knowledge'];
      if (reviewed is Map<String, dynamic>) {
        for (final entry in reviewed.entries) {
          final turns = entry.value;
          if (turns is! List ||
              !turns.any((line) => line is Map &&
                  line['actor_id'] != 'player')) continue;
          try {
            dialoguePrompt = NpcDialogueDraftContext.fromVerifiedWorld(
              world: verifiedWorld,
              sceneId: entry.key,
              sceneOrigins: origins,
            );
            break;
          } on FormatException {
            // An unreviewed or unsupported scene must never become a
            // cloud writing prompt. The already checked game is unchanged.
          }
        }
      }
      // Writer + importer have already checked the archive; install via
      // the existing SQLite gateway and open ONE existing campaigns page.
      final gateway = widget.gateway ?? const DeviceWorldLibraryGateway();
      final installed = await gateway.install(bytes);
      if (!mounted) return;
      setState(() {
        _npcDialoguePreview = dialoguePrompt;
        _notice = 'Частная RPG с проверенными правилами NPC создана. '
            'Новый художественный текст можно подготовить отдельно, '
            'только при явном согласии на облачный запрос.';
      });
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldCampaignsPage(
          world: installed, gateway: gateway,
        ),
      ));
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Сборка NPC заблокирована: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                    const Text('Правила и источники проверяются здесь. '
                        'После проверки появится отдельный понятный шаг: '
                        'ответы героя в разговорах, собеседники и реальные '
                        'последствия выбора. Его можно пропустить. '
                        'Требуются исходные цитаты и постоянные ID NPC.'),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('npc-build-world'),
                      onPressed: _saving || !book.rules.any((rule) =>
                          rule.recipient == KnowledgeRecipient.ownerNpc)
                          ? null : _buildNpcRichWorld,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Проверить и собрать RPG с NPC'),
                    ),
                    if (_npcDialoguePreview != null)
                      OutlinedButton.icon(
                        key: const Key('npc-build-cloud-dialogue-draft'),
                        onPressed: _saving ? null : () =>
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => NpcDialogueDraftPage(
                                  preview: _npcDialoguePreview!,
                                ),
                              ),
                            ),
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: const Text(
                            'Предложить реплики NPC через Z.ai (черновик)'),
                      ),
                    if (_saving) const LinearProgressIndicator(),
                  ],
                ],
              ),
            )),
          ),
    );
  }
}
