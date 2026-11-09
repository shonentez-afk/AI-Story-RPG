import 'package:rpg_api/rpg_api.dart';

/// Read-only, privacy-safe presentation of already replay-verified game data.
/// NEVER predicts a choice, creates an NPC, changes an obligation or parses
/// future book chapters. Shared by the world screen and free-action preview.
abstract final class WorldUiPresenter {
  static String record(String id, {Map<String, String> names = const {}}) {
    final named = names[id];
    if (named != null && named.trim().isNotEmpty) return named;
    final handle = id.startsWith('gm_') ? id.substring(3) : id;
    return handle.replaceAll('_', ' ');
  }

  static String npcMemoryKind(String kind) => switch (kind) {
    'witnessed' => 'Наблюдал',
    'warned' => 'Получил предупреждение',
    'promiseReceived' => 'Принял обещание',
    'promiseFulfilled' => 'Исполненное обещание',
    'promiseBroken' => 'Нарушенное обещание',
    'autonomousDecision' => 'Самостоятельное решение',
    'helped' => 'Получил помощь',
    'betrayed' => 'Пережил предательство',
    'rumorHeard' => 'Услышал сведения',
    _ => 'Подтверждённые события',
  };

  static String route(String kind) => switch (kind) {
    'investigate' => 'Исследование',
    'negotiate' => 'Переговоры',
    'protect' => 'Защита',
    'confront' => 'Противостояние',
    'recover' => 'Возвращение',
    'resolve' => 'Разрешение конфликта',
    'travel' => 'Путешествие',
    _ => 'Развитие истории',
  };

  static String npcName(WorldGameView view, String actor) {
    for (final npc in view.npcRelations) {
      if (npc.actorId == actor) return npc.displayName;
    }
    return actor == 'player' ? (view.heroName ?? 'Герой')
        : 'Персонаж (имя не раскрыто)';
  }

  /// An alternate plot can already be divergent without a new beat.
  /// Display neither hidden world data nor invented future objectives.
  static List<String> alternatePlot(WorldGameView view) {
    if (view.activePlotMode != 'ALTER_FATE') return const [];
    final state = view.alternatePlotContinuity;
    if (state['last_beat_id'] == null) {
      return const [
        'Книжный ход событий изменён. Продолжение больше не является текстом оригинала.',
        'Новая сюжетная цель появится после подтверждённого игрового действия.',
      ];
    }
    final result = <String>[
      'Ветка развивается по сохранённым событиям, не по следующему абзацу книги.',
    ];
    if (state['last_objective_id'] is String) {
      result.add('Текущая цель: ' +
          record(state['last_objective_id'] as String));
    }
    final lead = state['last_lead_actor_id'];
    if (lead is String) {
      result.add('Участник, ведущий текущую линию: ' +
          npcName(view, lead));
    }
    final obligations = state['open_obligation_ids'];
    if (obligations is List && obligations.isNotEmpty) {
      result.add('Открытые обязательства:');
      for (final value in obligations.whereType<String>()) {
        result.add('• ' + record(value));
      }
    } else {
      result.add('Незавершённых сюжетных обязательств не числится.');
    }
    final directions = state['next_directions'];
    if (directions is List && directions.isNotEmpty) {
      result.add('Следующий проверяемый шаг:');
      for (final value in directions) {
        if (value is! Map) continue;
        if (value['kind'] == 'resolve_obligation' &&
            value['obligation_id'] is String) {
          result.add('• Исполнить: ' + record(value['obligation_id'] as String));
        } else if (value['kind'] == 'develop_objective' &&
            value['objective_id'] is String) {
          result.add('• Продолжить цель: ' +
              record(value['objective_id'] as String));
        }
      }
    }
    return List.unmodifiable(result);
  }

  static List<String> heroRecentChanges(WorldGameView view) {
    final recent = <String>[];
    for (final event in view.journal.reversed) {
      for (final delta in event.changes.reversed) {
        if (recent.length == 4) return List.unmodifiable(recent);
        recent.add('Ход ${event.sequence}: ' + delta);
      }
    }
    return List.unmodifiable(recent);
  }

  static List<String> availableItemActions(WorldGameView view) {
    if (view.inventory.isEmpty) return const [];
    final names = [
      for (final id in view.inventory)
        view.itemNames[id] ?? record(id),
    ];
    return List.unmodifiable(view.choices.where((choice) =>
        choice.enabled && names.any((item) =>
            item.length >= 3 && choice.label.contains(item)))
        .map((choice) => choice.label));
  }

  /// All consequences are PROPOSALS until successful native commit.
  /// No speculative text is ever included in the authenticated journal.
  static List<String> dynamicImpact(FreeformActionDraft draft,
      WorldGameView before) {
    final lines = <String>[];
    for (final effect in draft.effects) {
      final name = effect.id == null ? null : record(effect.id!,
          names: {
            ...before.itemNames, ...before.factNames, ...before.statNames,
          });
      lines.add(switch (effect.op) {
        'grant_item' => 'Получить предмет: ${name ?? "неизвестно"}',
        'consume_item' => 'Использовать предмет: ${name ?? "неизвестно"}',
        'learn_fact' => 'Узнать: ${name ?? "неизвестно"}',
        'set_flag' => 'Изменить игровое условие: ${name ?? "неизвестно"}',
        'stat_delta' => 'Изменить параметр ${name ?? "игры"}: '
            '${effect.amount != null && effect.amount! > 0 ? "+" : ""}${effect.amount}',
        'advance_time' => 'Игровое время: +${effect.amount} ',
        _ => 'Игровое последствие проверяется движком',
      });
    }
    final interaction = draft.npcInteraction;
    if (interaction != null) {
      lines.add('Участник: ' + npcName(before, interaction.actorId));
      lines.add('Контакт с NPC: ' + switch (interaction.kind) {
        'warned' => 'предупреждение',
        'helped' => 'помощь',
        'betrayed' => 'предательство',
        'promise_received' => 'дано обещание',
        'promise_fulfilled' => 'исполнено обещание',
        'promise_broken' => 'нарушено обещание',
        'rumor_heard' => 'переданы слухи',
        _ => 'новое подтверждённое воспоминание',
      });
      lines.add('Изменение доверия: '
          '${interaction.trustDelta >= 0 ? "+" : ""}${interaction.trustDelta}');
      if (interaction.goalId != null) {
        lines.add('Новая цель NPC: ' + record(interaction.goalId!));
      }
      if (interaction.learnFactId != null) {
        lines.add('NPC узнает: ' +
            record(interaction.learnFactId!, names: before.factNames));
      }
      if (interaction.giveItemId != null) {
        lines.add('Передать NPC: ' +
            record(interaction.giveItemId!, names: before.itemNames));
      }
      if (interaction.takeItemId != null) {
        lines.add('Получить от NPC: ' +
            record(interaction.takeItemId!, names: before.itemNames));
      }
      if (interaction.promiseId != null) {
        lines.add('Обещание: ' + record(interaction.promiseId!));
      }
    }
    final beat = draft.plotBeat;
    if (beat != null) {
      lines.add('Альтернативная ветка: ' + record(beat.threadId));
      lines.add('Направление: ' + route(beat.route));
      lines.add('Ведущий участник: ' + npcName(before, beat.leadActorId));
      lines.add('Цель: ' + record(beat.objectiveId));
      for (final id in beat.openedObligationIds) {
        lines.add('Открыть обязательство: ' + record(id));
      }
      for (final id in beat.resolvedObligationIds) {
        lines.add('Закрыть обязательство: ' + record(id));
      }
      for (final evidence in beat.resolutionProofs) {
        lines.add('Проверка исполнения: ' +
            record(evidence.obligationId) + ' — ' +
            record(evidence.resourceId) + ' (' + evidence.effectOp + ')');
      }
    }
    if (draft.plotIntent == 'diverge') {
      lines.add('Предложен разрыв с CANON: решение принимает движок.');
    } else if (draft.plotIntent == 'end') {
      lines.add('Предлагается завершить ветку; открытые обязательства проверяются.');
    }
    if (lines.isEmpty) {
      lines.add('Только новая вымышленная сцена; прочие последствия не заявлены.');
    }
    lines.add('До подтверждения состояние игры и журнал не изменены.');
    return List.unmodifiable(lines);
  }
}
