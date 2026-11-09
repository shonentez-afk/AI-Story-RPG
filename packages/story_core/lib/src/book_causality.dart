import 'blueprint.dart';
import 'codec.dart';
import 'world_state.dart';
import 'npc_social_ledger.dart';

/// A human-reviewed causal predicate, never inferred from narrative text.
/// Facts, owners, memories and goals are checked on the COMMITTED playthrough.
final class BookCausalPredicate {
  const BookCausalPredicate(this.op, this.actorId, this.id, this.value);
  final String op;
  final String actorId;
  final String? id;
  final Object? value;

  factory BookCausalPredicate.fromJson(Object? raw, StoryBlueprint bp) {
    final row = jsonObject(raw, 'book_causal_predicate');
    assertFields(row, 'book_causal_predicate',
        {'op', 'actor_id', 'id', 'value'},
        {'op', 'actor_id', 'id', 'value'});
    final op = row['op'];
    final actor = row['actor_id'];
    final id = row['id'];
    final val = row['value'];
    const facts = {'fact_known', 'fact_unknown'};
    const items = {'item_owner'};
    const npc = {'memory_present', 'memory_absent', 'goal_is',
        'trust_min', 'trust_max', 'life_is'};
    const flags = {'flag_is'};
    if (op is! String ||
        !{...facts, ...items, ...npc, ...flags}.contains(op) ||
        actor is! String || !bp.actors.contains(actor) ||
        (npc.contains(op) && actor == 'player') ||
        (flags.contains(op) && actor != 'player')) {
      throw const FormatException('Unknown causal predicate or actor');
    }
    final needsId = facts.contains(op) || items.contains(op) ||
        {'memory_present', 'memory_absent', 'goal_is', 'flag_is'}.contains(op);
    if ((needsId && (id is! String || id.isEmpty)) ||
        (!needsId && id != null)) {
      throw const FormatException('Causal predicate has incorrect id');
    }
    final gm = RegExp(r'^gm_[a-z0-9_]{1,59}$');
    if (facts.contains(op) &&
        !(bp.facts.contains(id) || (id is String && gm.hasMatch(id)))) {
      throw const FormatException('Unregistered source or GM fact');
    }
    if (items.contains(op) &&
        !(bp.items.contains(id) || (id is String && gm.hasMatch(id))) ||
        (items.contains(op) &&
         (val is! String || !bp.actors.contains(val)))) {
      throw const FormatException('Unregistered item or owner');
    }
    if ({'memory_present', 'memory_absent', 'goal_is'}.contains(op) &&
        (id is! String || !gm.hasMatch(id) || val != null)) {
      throw const FormatException('Unreviewed NPC memory or goal');
    }
    if (facts.contains(op) && val != null) {
      throw const FormatException('Fact condition cannot carry a value');
    }
    if ((op == 'trust_min' || op == 'trust_max') &&
        (val is! int || val < -100 || val > 100)) {
      throw const FormatException('Invalid trust threshold');
    }
    if (op == 'life_is' && !{'present', 'absent', 'dead'}.contains(val)) {
      throw const FormatException('Invalid NPC life prerequisite');
    }
    if (op == 'trust_min' || op == 'trust_max' || op == 'life_is') {
      // Trust/life have no resource ID; retain the actor-bound signed value.
    } else if (!needsId && val != null) {
      throw const FormatException('Unexpected causal predicate value');
    }
    if (op == 'flag_is' &&
        (id is! String ||
         !(bp.initial.flags.containsKey(id) || gm.hasMatch(id)) ||
         val is! bool)) {
      throw const FormatException('Unregistered causal flag');
    }
    return BookCausalPredicate(op, actor, id as String?, val);
  }

  Map<String, Object?> toJson() =>
      {'op': op, 'actor_id': actorId, 'id': id, 'value': value};

  bool isSatisfied(WorldState state, NpcSocialSnapshot social) {
    switch (op) {
      case 'fact_known':
        return state.knowledge[actorId]?.contains(id) ?? false;
      case 'fact_unknown':
        return !(state.knowledge[actorId]?.contains(id) ?? false);
      case 'item_owner':
        if (actorId != value) return false;
        if (actorId == 'player') return state.inventory.contains(id);
        return social.itemOwner(id!) == actorId;
      case 'memory_present':
        return social.hasMemory(actorId, id!);
      case 'memory_absent':
        return !social.hasMemory(actorId, id!);
      case 'goal_is':
        return social.currentGoal(actorId) == id;
      case 'trust_min':
        return social.directedScore(actorId, 'player') >= (value as int);
      case 'trust_max':
        return social.directedScore(actorId, 'player') <= (value as int);
      case 'life_is':
        return social.lifeState(actorId).name == value;
      case 'flag_is':
        return state.flags[id] == value;
    }
    throw StateError('Validated causal operation unknown');
  }
}

/// A source-backed event with explicit earlier causes and observed results.
/// Authored effects apply ON LEAVING the exact quoted source scene; no AI text
/// may invent those effects while playing.
final class BookCausalEvent {
  const BookCausalEvent(this.sceneId, this.dependsOn, this.preconditions,
      this.effects);
  final String sceneId;
  final List<String> dependsOn;
  final List<BookCausalPredicate> preconditions;
  final List<TypedRule> effects;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId, 'depends_on': dependsOn,
    'preconditions': preconditions.map((v) => v.toJson()).toList(),
    'effects': effects.map((v) => v.toJson()).toList(),
  };
}

/// Optional rulebook-owned graph. All edges point backwards in source order;
/// a cycle or a forward dependency is rejected at import, never at runtime.
final class BookCausalGraph {
  BookCausalGraph(this.nodes);
  final List<BookCausalEvent> nodes;

  BookCausalEvent? at(String sceneId) {
    for (final node in nodes) {
      if (node.sceneId == sceneId) return node;
    }
    return null;
  }

  static BookCausalGraph fromReview(Object? raw, StoryBlueprint bp) {
    if (raw is! List || raw.isEmpty || raw.length > 5000) {
      throw const FormatException('Book causal graph is empty or over budget');
    }
    final sceneOrder = bp.scenes.keys.toList();
    final order = {
      for (var i = 0; i < sceneOrder.length; i++) sceneOrder[i]: i,
    };
    final seen = <String>{};
    final events = <BookCausalEvent>[];
    for (final entry in raw) {
      final row = jsonObject(entry, 'book causal event');
      assertFields(row, 'book causal event',
          {'scene_id', 'depends_on', 'preconditions', 'effects'},
          {'scene_id', 'depends_on', 'preconditions', 'effects'});
      final sceneId = row['scene_id'];
      if (sceneId is! String || !bp.scenes.containsKey(sceneId) ||
          !seen.add(sceneId)) {
        throw const FormatException('Unknown or repeated source event');
      }
      final prior = row['depends_on'];
      final rawConditions = row['preconditions'];
      final rawEffects = row['effects'];
      if (prior is! List || prior.length > 64 ||
          rawConditions is! List || rawConditions.length > 32 ||
          rawEffects is! List || rawEffects.length > 24) {
        throw const FormatException('Source event budget exceeded');
      }
      final dependencies = <String>[];
      for (final dep in prior) {
        if (dep is! String || !order.containsKey(dep) ||
            order[dep]! >= order[sceneId]! ||
            dependencies.contains(dep)) {
          throw const FormatException('Cyclic, future or duplicate cause');
        }
        dependencies.add(dep);
      }
      final conditions = rawConditions.map(
          (row) => BookCausalPredicate.fromJson(row, bp)).toList();
      final checks = conditions.map((v) =>
          v.op + '|' + v.actorId + '|' + (v.id ?? '')).toSet();
      if (checks.length != conditions.length) {
        throw const FormatException('Contradictory duplicate cause');
      }
      final effects = <TypedRule>[];
      for (final effectRaw in rawEffects) {
        final effect = TypedRule.fromJson(effectRaw, effect: true);
        if (!{'learn_fact', 'grant_item', 'consume_item',
              'set_flag', 'stat_delta', 'advance_time'}.contains(effect.op) ||
            (effect.op == 'learn_fact' &&
              (!bp.actors.contains(effect.actor) ||
               !bp.facts.contains(effect.id))) ||
            ((effect.op == 'grant_item' || effect.op == 'consume_item') &&
               !bp.items.contains(effect.id)) ||
            (effect.op == 'set_flag' &&
                !bp.initial.flags.containsKey(effect.id)) ||
            (effect.op == 'stat_delta' &&
                !bp.initial.stats.containsKey(effect.id))) {
          throw const FormatException('Unreviewed source event effect');
        }
        effects.add(effect);
      }
      events.add(BookCausalEvent(sceneId,
          List.unmodifiable(dependencies),
          List.unmodifiable(conditions), List.unmodifiable(effects)));
    }
    if (seen.length != bp.scenes.length) {
      throw const FormatException('Incomplete source-wide causal event coverage');
    }
    final first = events.firstWhere((e) => e.sceneId == bp.entrySceneId);
    if (first.dependsOn.isNotEmpty || first.preconditions.isNotEmpty) {
      throw const FormatException('Entry source cannot require future events');
    }
    for (final event in events) {
      if (event.dependsOn.any((id) => !seen.contains(id))) {
        throw const FormatException('Cause references an unreviewed event');
      }
    }
    return BookCausalGraph(List.unmodifiable(events));
  }

  /// Explicit semantics for the NEXT signed source scene. Visited causes are
  /// reconstructed from event history; no author claim can stand in for play.
  bool permits(String nextSceneId, WorldState nextState,
      NpcSocialSnapshot social, Set<String> visited) {
    final event = at(nextSceneId);
    if (event == null) return true;
    if (!visited.containsAll(event.dependsOn)) return false;
    return event.preconditions.every((v) => v.isSatisfied(nextState, social));
  }

  Map<String, Object?> toJson() =>
      {'events': nodes.map((v) => v.toJson()).toList()};
}
