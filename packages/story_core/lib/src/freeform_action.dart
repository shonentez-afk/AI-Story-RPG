import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'blueprint.dart';
import 'codec.dart';
import 'world_state.dart';

/// A NEW, scene-local game action. It is not a mapping to a compiled choice.
/// The model's response is an untrusted proposal. Only the bounded typed
/// fiction-state DSL below may be committed, after a fresh CAS and consent.
/// In particular it cannot create/mutate canonical flags, other actors'
/// knowledge, NPC custody, source scenes, or the book's chronology.
final class FreeformActionDraft {
  FreeformActionDraft._(this.playerText, this.narration,
      this.effects, this._json);

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
  final Map<String, dynamic> _json;
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(
          jsonDecode(canonicalJson(_json)) as Map);
  String get digest => sha256.convert(
      utf8.encode(canonicalJson(_json))).toString();

  static FreeformActionDraft fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().length != 5 ||
        !raw.keys.toSet().containsAll({
          'format', 'scope', 'player_text', 'narration', 'effects'
        }) ||
        raw['format'] != format || raw['scope'] != fictionScope ||
        raw['player_text'] is! String || raw['narration'] is! String ||
        raw['effects'] is! List) {
      throw const FormatException('Invalid AI interlude schema');
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
    for (final e in effects) {
      switch (e.op) {
        case 'set_flag':
          if (!bp.initial.flags.containsKey(e.id)) {
            throw const FormatException('Unknown AI flag');
          }
        case 'stat_delta':
          if (!bp.initial.stats.containsKey(e.id)) {
            throw const FormatException('Unknown AI stat');
          }
          final next = current.stats[e.id]! + e.amount!;
          if (next < 0 || next > 1000000) {
            throw const FormatException('AI stat exceeds approved limits');
          }
        case 'advance_time':
          if (current.tick + 1 + e.amount! > 100000000) {
            throw const FormatException('AI time overflow');
          }
        case 'grant_item':
          if (!bp.items.contains(e.id) || current.inventory.contains(e.id)) {
            throw const FormatException('AI cannot invent/duplicate item');
          }
        case 'consume_item':
          if (!bp.items.contains(e.id) ||
              !current.inventory.contains(e.id)) {
            throw const FormatException('AI cannot spend an absent item');
          }
        case 'learn_fact':
          if (e.actor != 'player' || !bp.facts.contains(e.id)) {
            throw const FormatException('AI cannot reveal book/NPC secrets');
          }
        default:
          throw const FormatException('Unknown dynamic action operation');
      }
    }
  }
}
