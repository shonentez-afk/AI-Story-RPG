import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/material.dart';
import 'package:story_core/story_core.dart';

/// System Back cancels the build; Skip deliberately installs the unchanged
/// base world. The screen never mutates a signed archive or campaign.
class NpcResponsesReviewDecision {
  const NpcResponsesReviewDecision._(this.proposal, this.skipped);
  const NpcResponsesReviewDecision.skip() : this._(null, true);
  const NpcResponsesReviewDecision.accept(ReviewedNpcResponsePlan proposal)
      : this._(proposal, false);

  final ReviewedNpcResponsePlan? proposal;
  final bool skipped;
}

class NpcResponseSceneOption {
  const NpcResponseSceneOption({
    required this.scene, required this.actors,
    required this.sourceQuotes, required this.sceneLabel,
  });

  final BlueprintScene scene;
  /// Source-reviewed permanent actor IDs -> named speaker.
  final Map<String, String> actors;
  /// Source quote digests -> confirmed local citation captions.
  final Map<String, String> sourceQuotes;
  final String sceneLabel;
}

/// Editor of spoken PLAYER answers for already verified NPC source scenes.
/// Only existing typed StoryBlueprint choices can be submitted as outcomes.
class NpcDialogueResponsesReviewPage extends StatefulWidget {
  const NpcDialogueResponsesReviewPage({
    super.key, required this.world, required this.sceneOrigins,
    this.sourceQuoteLabels = const {},
  });

  final VerifiedRichPrivateBookworld world;
  final Map<String, dynamic> sceneOrigins;
  final Map<String, String> sourceQuoteLabels;

  /// A fail-closed availability gate for the authoring UI. The same signed
  /// facts are checked again during proposal acceptance AND ZIP import.
  static List<NpcResponseSceneOption> eligibleScenes({
    required VerifiedRichPrivateBookworld world,
    required Map<String, dynamic> sceneOrigins,
    Map<String, String> sourceQuoteLabels = const {},
  }) {
    final signed = world.presentation['scene_dialogues'];
    final guards = world.presentation['scene_dialogue_knowledge'];
    if (signed is! Map<String, dynamic> ||
        guards is! Map<String, dynamic>) return const [];
    final result = <NpcResponseSceneOption>[];
    for (final scene in world.blueprint.scenes.values) {
      if (scene.terminal || scene.choices.length < 2 ||
          scene.choices.length > 16 ||
          !signed.containsKey(scene.id) ||
          guards[scene.id] is! List) continue;
      final origin = sceneOrigins[scene.id];
      if (origin is! Map || origin['origin'] != 'SOURCE_PASSAGE' ||
          origin['chapter_index'] is! int ||
          origin['source_refs'] is! List) continue;
      final chapter = origin['chapter_index'] as int;
      final quotes = <String, String>{};
      for (final raw in origin['source_refs'] as List) {
        if (raw is! Map || raw['quote_sha256'] is! String ||
            raw['chapter_index'] is! int ||
            raw['visible_after_chapter'] is! int ||
            (raw['chapter_index'] as int) > chapter ||
            (raw['visible_after_chapter'] as int) > chapter) continue;
        final digest = raw['quote_sha256'] as String;
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) continue;
        quotes[digest] = sourceQuoteLabels[digest] ??
            'Глава ' + (chapter + 1).toString() +
                ' · источник ' + digest.substring(0, 8);
      }
      if (quotes.isEmpty) continue;
      final actors = <String, String>{};
      for (final raw in guards[scene.id] as List) {
        if (raw is! Map || raw['actor_id'] is! String ||
            raw['speaker'] is! String ||
            !CharacterId.isValidNpc(raw['actor_id'] as String)) continue;
        actors[raw['actor_id'] as String] = raw['speaker'] as String;
      }
      if (actors.isEmpty) continue;
      for (final actor in actors.keys.toList()) {
        final candidate = <String, dynamic>{
          scene.id: [
            for (final choice in scene.choices)
              {
                'choice_id': choice.id,
                'interlocutor_id': actor,
                'player_line': 'Я готов обсудить это решение.',
                'source_quote_sha256': quotes.keys.first,
                'private_fiction_confirmed': true,
              },
          ],
        };
        try {
          RichNpcDialogueResponses.validate(
            candidate, world.blueprint, signed, guards,
            sceneOrigins, socialRules: world.npcSocialRulebook,
          );
        } on FormatException {
          actors.remove(actor);
        }
      }
      if (actors.isEmpty) continue;
      final names = world.presentation['scene_names'];
      final label = names is Map && names[scene.id] is String
          ? names[scene.id] as String : 'Сцена ' + scene.id;
      result.add(NpcResponseSceneOption(
        scene: scene, actors: Map.unmodifiable(actors),
        sourceQuotes: Map.unmodifiable(quotes), sceneLabel: label,
      ));
    }
    return List.unmodifiable(result);
  }

  @override
  State<NpcDialogueResponsesReviewPage> createState() =>
      _NpcDialogueResponsesReviewPageState();
}

class _NpcDialogueResponsesReviewPageState
    extends State<NpcDialogueResponsesReviewPage> {
  late final List<NpcResponseSceneOption> _scenes;
  final Set<String> _selected = {};
  final Map<String, String> _actors = {};
  final Map<String, String> _quotes = {};
  final Map<String, String> _replies = {};
  bool _confirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scenes = NpcDialogueResponsesReviewPage.eligibleScenes(
      world: widget.world, sceneOrigins: widget.sceneOrigins,
      sourceQuoteLabels: widget.sourceQuoteLabels,
    );
  }

  void _change(void Function() action) => setState(() {
    action();
    _confirmed = false;
    _error = null;
  });

  String _key(String sceneId, String choiceId) => sceneId + '|' + choiceId;

  String _outcome(BlueprintScene scene, BlueprintChoice choice) {
    final changes = <String>[];
    final names = widget.world.presentation['scene_names'];
    final destination = names is Map && names[choice.nextSceneId] is String
        ? names[choice.nextSceneId] as String : choice.nextSceneId;
    changes.add('Переход: ' + destination);
    for (final effect in choice.effects) {
      changes.add(switch (effect.op) {
        'learn_fact' => effect.actor == 'player'
            ? 'Герой узнаёт факт' : 'NPC узнаёт факт',
        'grant_item' => 'Герой получает предмет',
        'consume_item' => 'Герой расходует предмет',
        'set_flag' => 'Меняется сюжетное условие',
        'stat_delta' => 'Меняется характеристика героя',
        _ => 'Игровое последствие',
      });
    }
    final social = widget.world.npcSocialRulebook;
    if (social != null) {
      for (final memory in social.rules.where((rule) =>
          rule.sceneId == scene.id && rule.choiceId == choice.id)) {
        changes.add('NPC запоминает событие');
        if (memory.relationshipDelta != 0) {
          changes.add('Отношение: ' +
              (memory.relationshipDelta > 0 ? '+' : '') +
              memory.relationshipDelta.toString());
        }
      }
    }
    return changes.join(' · ');
  }

  bool get _complete => _selected.isNotEmpty &&
      _scenes.where((s) => _selected.contains(s.scene.id)).every((s) =>
        _actors.containsKey(s.scene.id) &&
        _quotes.containsKey(s.scene.id) &&
        s.scene.choices.every((choice) {
          final value = _replies[_key(s.scene.id, choice.id)];
          return value != null && value.trim().length >= 4 &&
              value.trim().length <= 220;
        }));

  void _accept() {
    if (!_confirmed || !_complete) return;
    try {
      final selected = _scenes.where(
          (s) => _selected.contains(s.scene.id)).toList();
      final proposal = RichNpcDialogueResponses.propose(
        blueprint: widget.world.blueprint,
        sceneOrigins: widget.sceneOrigins,
        signedDialogues:
            widget.world.presentation['scene_dialogues'] as Map<String, dynamic>,
        reviewedSpeakerTurns: widget.world.presentation[
            'scene_dialogue_knowledge'] as Map<String, dynamic>,
        playerLinesByScene: {
          for (final s in selected)
            s.scene.id: {
              for (final choice in s.scene.choices)
                choice.id: _replies[_key(s.scene.id, choice.id)]!.trim(),
            },
        },
        interlocutorByScene: {
          for (final s in selected) s.scene.id: _actors[s.scene.id]!,
        },
        sourceQuoteByScene: {
          for (final s in selected) s.scene.id: _quotes[s.scene.id]!,
        },
        wholeDialogueReviewed: _confirmed,
        privateFictionAcknowledged: _confirmed,
        socialRules: widget.world.npcSocialRulebook,
      );
      Navigator.of(context).pop(NpcResponsesReviewDecision.accept(proposal));
    } on FormatException catch (error) {
      setState(() {
        _confirmed = false;
        _error = 'Не удалось подтвердить ответы: ' + error.message +
            '. Проверьте цитаты, собеседников и последствия.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ответы героя в разговорах')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text('Проверка ответов перед сборкой',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Этот этап необязателен. Выберите сцены с '
                'проверенными NPC и допишите ответы героя. '
                'Каждый ответ привязан к уже созданному игровому выбору '
                'и его последствиям. Здесь нельзя придумать новые '
                'знания, предметы или сюжетные решения.'),
            const SizedBox(height: 8),
            const Text('Пишите слова героя без имени и кавычек. '
                'Исходная цитата подтверждает контекст сцены, '
                'но не доказывает, что эти слова есть в книге.'),
            const SizedBox(height: 10),
            Text('Доступно сцен: ' + _scenes.length.toString() +
                ' · выбрано: ' + _selected.length.toString(),
                key: const Key('npc-replies-progress')),
            const SizedBox(height: 10),
            for (final option in _scenes)
              Card(
                key: Key('npc-reply-scene-' + option.scene.id),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        key: Key('npc-reply-select-' + option.scene.id),
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.sceneLabel),
                        subtitle: Text(option.scene.choices.length.toString() +
                            ' ответа · разные подтверждённые исходы'),
                        value: _selected.contains(option.scene.id),
                        onChanged: (value) => _change(() {
                          if (value == true) {
                            _selected.add(option.scene.id);
                          } else {
                            _selected.remove(option.scene.id);
                          }
                        }),
                      ),
                      if (_selected.contains(option.scene.id)) ...[
                        const Divider(height: 16),
                        DropdownButtonFormField<String>(
                          key: Key('npc-reply-actor-' + option.scene.id),
                          isExpanded: true,
                          initialValue: _actors[option.scene.id],
                          decoration: const InputDecoration(
                            labelText: 'Кому отвечает герой',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final actor in option.actors.entries)
                              DropdownMenuItem(
                                value: actor.key,
                                child: Text(actor.value,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (actor) => _change(() {
                            if (actor != null) {
                              _actors[option.scene.id] = actor;
                            }
                          }),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: Key('npc-reply-quote-' + option.scene.id),
                          isExpanded: true,
                          initialValue: _quotes[option.scene.id],
                          decoration: const InputDecoration(
                            labelText: 'Подтверждённая цитата сцены',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final quote in option.sourceQuotes.entries)
                              DropdownMenuItem(
                                value: quote.key,
                                child: Text(quote.value,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (quote) => _change(() {
                            if (quote != null) {
                              _quotes[option.scene.id] = quote;
                            }
                          }),
                        ),
                        const SizedBox(height: 12),
                        for (final choice in option.scene.choices) ...[
                          Text('Решение: ' + choice.label,
                              style: theme.textTheme.titleSmall),
                          Text(_outcome(option.scene, choice),
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          TextFormField(
                            key: Key('npc-reply-line-' + choice.id),
                            initialValue: _replies[
                                _key(option.scene.id, choice.id)],
                            minLines: 1, maxLines: 3, maxLength: 220,
                            decoration: const InputDecoration(
                              labelText: 'Реплика героя',
                              hintText: 'Я отвечаю собеседнику…',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (line) => _change(() =>
                                _replies[_key(option.scene.id, choice.id)] =
                                    line),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            if (_scenes.isEmpty)
              const Text('Не найдено сцен с несколькими реальными '
                  'последствиями, source-locked диалогом и подтверждённым '
                  'личным присутствием NPC. Добавьте такие сцены в сценарий.'),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const Key('npc-reply-approve'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _complete
                  ? (value) => setState(() {
                      _confirmed = value == true;
                      _error = null;
                    })
                  : null,
              title: const Text('Подтверждаю все выбранные ответы '
                  'и последствия для частной RPG'),
              subtitle: const Text('Это художественная адаптация, '
                  'а не буквальный текст оригинала.'),
            ),
            if (_error != null)
              Text(_error!,
                  key: const Key('npc-reply-error'),
                  style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('npc-reply-accept'),
              onPressed: _complete && _confirmed ? _accept : null,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Проверить и включить ответы в RPG'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('npc-reply-skip'),
              onPressed: () => Navigator.of(context)
                  .pop(const NpcResponsesReviewDecision.skip()),
              child: const Text('Собрать RPG без новых ответов'),
            ),
            const SizedBox(height: 8),
            const Text('Назад — отменить текущую сборку. '
                'Пропустить — оставить проверенную базовую игру.'),
          ],
        ),
      ))),
    );
  }
}
