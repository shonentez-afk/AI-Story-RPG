import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'blueprint.dart';
import 'codec.dart';
import 'world_state.dart';
import 'alternate_plot.dart';

/// Source-reviewed NPC contact, with a NEW durable memory/goal. Identity,
/// witness presence, life and cause checkpoints are checked by story_core.
/// No inferred NPC appearance, knowledge or player-provided display name.
final class FreeformNpcInteraction {
  const FreeformNpcInteraction._({
    required this.actorId,
    required this.memoryId,
    required this.kind,
    required this.trustDelta,
    this.goalId,
    this.learnFactId,
    this.giveItemId,
    this.takeItemId,
  });
  final String actorId, memoryId, kind;
  final int trustDelta;
  final String? goalId;
  /// New: the player explicitly communicates one ALREADY KNOWN fact.
  final String? learnFactId;
  /// Existing player item transferred to this NPC.
  final String? giveItemId;
  /// Existing NPC-owned item transferred back to the player.
  final String? takeItemId;

  static final _actor = RegExp(r'^npc_[a-f0-9]{32}$');
  static final _gm = RegExp(r'^gm_[a-z0-9_]{1,59}$');
  static const kinds = {
    'warned', 'helped', 'betrayed', 'promise_received',
    'promise_broken', 'rumor_heard', 'witnessed',
  };
  factory FreeformNpcInteraction.fromJson(Object? source) {
    if (source is! Map<String, dynamic> ||
        !source.keys.toSet().containsAll({
          'actor_id', 'memory_id', 'kind', 'trust_delta', 'goal_id',
        }) ||
        source.keys.toSet().difference({
          'actor_id', 'memory_id', 'kind', 'trust_delta', 'goal_id',
          'learn_fact_id', 'give_item_id', 'take_item_id',
        }).isNotEmpty ||
        source['actor_id'] is! String ||
        !_actor.hasMatch(source['actor_id'] as String) ||
        source['memory_id'] is! String ||
        !_gm.hasMatch(source['memory_id'] as String) ||
        source['kind'] is! String ||
        !kinds.contains(source['kind']) ||
        source['trust_delta'] is! int ||
        (source['trust_delta'] as int).abs() > 10 ||
        (source['goal_id'] != null &&
            (source['goal_id'] is! String ||
             !_gm.hasMatch(source['goal_id'] as String))) ||
        ['learn_fact_id', 'give_item_id', 'take_item_id'].any((key) =>
          source.containsKey(key) &&
          (source[key] is! String ||
           (source[key] as String).isEmpty)) ||
        (source.containsKey('give_item_id') &&
         source.containsKey('take_item_id'))) {
      throw const FormatException('Unverified NPC freeform intervention');
    }
    return FreeformNpcInteraction._(
      actorId: source['actor_id'] as String,
      memoryId: source['memory_id'] as String,
      kind: source['kind'] as String,
      trustDelta: source['trust_delta'] as int,
      goalId: source['goal_id'] as String?,
      learnFactId: source['learn_fact_id'] as String?,
      giveItemId: source['give_item_id'] as String?,
      takeItemId: source['take_item_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'actor_id': actorId, 'memory_id': memoryId,
    'kind': kind, 'trust_delta': trustDelta, 'goal_id': goalId,
    if (learnFactId != null) 'learn_fact_id': learnFactId,
    if (giveItemId != null) 'give_item_id': giveItemId,
    if (takeItemId != null) 'take_item_id': takeItemId,
  };
}

/// A NEW, scene-local game action. It is not a mapping to a compiled choice.
/// The model's response is an untrusted proposal. Only the bounded typed
/// fiction-state DSL below may be committed, after a fresh CAS and consent.
/// In particular it cannot create/mutate canonical flags, other actors'
/// knowledge, NPC custody, source scenes, or the book's chronology.
final class FreeformActionDraft {
  FreeformActionDraft._(this.playerText, this.narration,
      this.effects, this.npcInteraction, this.plotIntent, this.plotBeat, this._json);

  static const format = 'ai_story_freeform_action_v1';
  static const fictionScope = 'private_noncanonical_interlude';
  static const reservedChoice = 'freeform_action';
  static final RegExp _control = RegExp(
      r'[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]');
  static final RegExp _gmName = RegExp(r'^gm_[a-z0-9_]{1,59}$');

  final String playerText;
  /// Unsigned model prose is ALWAYS shown as fictional, never book narration.
  final String narration;
  final List<TypedRule> effects;
  /// Optional witnessed, replayable NPC memory and directed relationship.
  final FreeformNpcInteraction? npcInteraction;
  /// continue (default), explicitly diverge or finish an existing branch.
  final String plotIntent;
  final AlternateStoryBeat? plotBeat;
  final Map<String, dynamic> _json;
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(
          jsonDecode(canonicalJson(_json)) as Map);
  String get digest => sha256.convert(
      utf8.encode(canonicalJson(_json))).toString();

  static FreeformActionDraft fromJson(Object? raw) {
    const required = {
      'format', 'scope', 'player_text', 'narration', 'effects'
    };
    const optional = {'npc_interaction', 'plot_intent', 'plot_beat'};
    if (raw is! Map<String, dynamic> ||
        !raw.keys.toSet().containsAll(required) ||
        raw.keys.toSet().difference({...required, ...optional}).isNotEmpty ||
        raw['format'] != format || raw['scope'] != fictionScope ||
        raw['player_text'] is! String || raw['narration'] is! String ||
        raw['effects'] is! List) {
      throw const FormatException('Invalid AI interlude schema');
    }
    final npcInteraction = raw.containsKey('npc_interaction')
        ? FreeformNpcInteraction.fromJson(raw['npc_interaction']) : null;
    final intent = raw['plot_intent'] ?? 'continue';
    if (intent is! String || !{'continue', 'diverge', 'end'}.contains(intent)) {
      throw const FormatException('Unknown alternative plot intent');
    }
    final player = raw['player_text'] as String;
    final narration = raw['narration'] as String;
    if (player.trim() != player || player.isEmpty ||
        player.runes.length > 320 || _control.hasMatch(player) ||
        narration.trim() != narration || narration.isEmpty ||
        narration.runes.length > 1200 || _control.hasMatch(narration)) {
      throw const FormatException('Unsafe AI freeform text');
    }
    final rows = raw['effects'] as List;
    if (rows.length > 4) {
      throw const FormatException('AI interlude has too many effects');
    }
    final effects = <TypedRule>[];
    final seen = <String>{};
    for (final row in rows) {
      final rule = TypedRule.fromJson(row, effect: true);
      if (!{
        'set_flag', 'stat_delta', 'advance_time',
        'grant_item', 'consume_item', 'learn_fact'
      }.contains(rule.op) ||
          (rule.id != null && !_gmName.hasMatch(rule.id!)) ||
          (rule.op == 'learn_fact' && rule.actor != 'player') ||
          (rule.op == 'stat_delta' &&
              (rule.amount == null || rule.amount!.abs() > 10)) ||
          (rule.op == 'advance_time' &&
              (rule.amount == null || rule.amount! < 1 ||
               rule.amount! > 24)) ||
          !seen.add(rule.op + '|' + (rule.id ?? 'clock'))) {
        throw const FormatException('AI attempted to alter book canon or NPC');
      }
      effects.add(rule);
    }
    return FreeformActionDraft._(
      player, narration, List.unmodifiable(effects),
      npcInteraction, intent,
      raw.containsKey('plot_beat')
          ? AlternateStoryBeat.fromJson(raw['plot_beat']) : null,
      Map.unmodifiable(Map<String, dynamic>.from(
          jsonDecode(canonicalJson(raw)) as Map)),
    );
  }

  /// Executable authorization is based only on signed compiled catalog and
  /// current replayed state. Human or model prose cannot grant new objects.
  void validate(StoryBlueprint bp, WorldState current) {
    if (!bp.supportsFreeform || bp.rightsStatus != 'private_adaptation' ||
        bp.scenes[current.sceneId]?.terminal != false) {
      throw const FormatException('This game does not allow dynamic actions');
    }
    if (npcInteraction != null) {
      final interaction = npcInteraction!;
      if (!bp.actors.contains(interaction.actorId)) {
        throw const FormatException('NPC not in source-reviewed cast');
      }
      final fact = interaction.learnFactId;
      if (fact != null &&
          (!(bp.facts.contains(fact) || _gmName.hasMatch(fact)) ||
           !(current.knowledge['player']?.contains(fact) ?? false))) {
        throw const FormatException('NPC cannot learn an unowned fact');
      }
      for (final item in [interaction.giveItemId, interaction.takeItemId]) {
        if (item != null &&
            !(bp.items.contains(item) || _gmName.hasMatch(item))) {
          throw const FormatException('NPC transfer references unapproved item');
        }
      }
    }
    for (final e in effects) {
      switch (e.op) {
        case 'set_flag':
          // New GM-only flags are persistent player-created fiction, not
          // source-defined book state. No canonical flag can be overwritten.
          if (!e.id!.startsWith('gm_')) {
            throw const FormatException('Cannot change canonical flags');
          }
        case 'stat_delta':
          final next = (current.stats[e.id] ?? 0) + e.amount!;
          if (next < 0 || next > 1000000) {
            throw const FormatException('AI stat exceeds approved limits');
          }
        case 'advance_time':
          if (current.tick + 1 + e.amount! > 100000000) {
            throw const FormatException('AI time overflow');
          }
        case 'grant_item':
          if (current.inventory.contains(e.id)) {
            throw const FormatException('AI cannot duplicate an owned item');
          }
        case 'consume_item':
          if (!current.inventory.contains(e.id)) {
            throw const FormatException('AI cannot spend an absent item');
          }
        case 'learn_fact':
          if (e.actor != 'player') {
            throw const FormatException('AI cannot reveal book/NPC secrets');
          }
        default:
          throw const FormatException('Unknown dynamic action operation');
      }
    }
  }
}
