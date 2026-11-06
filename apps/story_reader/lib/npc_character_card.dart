import 'dart:math';

/// The editable PRIVATE identity of a playable NPC. Created ONCE per
/// authored character; never computed from a name, source SHA, citation,
/// mention group, dialogue content, or current game position.
///
/// It is *not* a claim that any authored detail is literary CANON or that
/// an NPC has learned a fact. Runtime knowledge belongs to story_core.
class NpcCharacterCard {
  NpcCharacterCard({
    required this.characterId,
    List<String> aliases = const [],
    this.role = '',
    this.biography = '',
    this.appearance = '',
    this.personality = '',
    this.speechStyle = '',
    this.motivation = '',
    this.goals = '',
    this.portraitAssetId = '',
  }) : aliases = List.unmodifiable(aliases);

  static final RegExp _id = RegExp(r'^npc_[a-f0-9]{32}$');
  static final RegExp _portrait = RegExp(r'^[A-Za-z0-9_-]{0,64}$');
  static final RegExp _control =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]');

  /// A cryptographically random opaque 128-bit identity, allocated only
  /// when the user FIRST creates the card. The value is serialized to the
  /// independent NPC checkpoint and reused after rename, restart, updates.
  static String issueCharacterId() {
    final random = Random.secure();
    final buffer = StringBuffer('npc_');
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  factory NpcCharacterCard.fresh() =>
      NpcCharacterCard(characterId: issueCharacterId());

  final String characterId;
  final List<String> aliases;
  final String role;
  final String biography;
  final String appearance;
  final String personality;
  final String speechStyle;
  final String motivation;
  final String goals;

  /// Local portrait lookup key only. No filesystem paths, HTTP URLs, or
  /// portrait bytes are serialized into the private editorial checkpoint.
  final String portraitAssetId;

  bool get literaryCanonVerified => false;
  bool get npcKnowledgeVerified => false;
  bool get maySendToCloud => false;
  bool get isGameplayState => false;

  NpcCharacterCard copyWith({
    List<String>? aliases,
    String? role,
    String? biography,
    String? appearance,
    String? personality,
    String? speechStyle,
    String? motivation,
    String? goals,
    String? portraitAssetId,
  }) => NpcCharacterCard(
    characterId: characterId,
    aliases: aliases ?? this.aliases,
    role: role ?? this.role,
    biography: biography ?? this.biography,
    appearance: appearance ?? this.appearance,
    personality: personality ?? this.personality,
    speechStyle: speechStyle ?? this.speechStyle,
    motivation: motivation ?? this.motivation,
    goals: goals ?? this.goals,
    portraitAssetId: portraitAssetId ?? this.portraitAssetId,
  );

  static void _text(String input, int max, String field) {
    if (input.length > max || _control.hasMatch(input)) {
      throw FormatException('Недопустимое значение карточки NPC: $field');
    }
  }

  void validate() {
    if (!_id.hasMatch(characterId)) {
      throw const FormatException('Недопустимый постоянный character_id NPC');
    }
    if (aliases.length > 20 ||
        aliases.any((s) => s.trim().isEmpty || s != s.trim() ||
            s.length > 96 || _control.hasMatch(s)) ||
        aliases.map((s) => s.toLowerCase()).toSet().length != aliases.length) {
      throw const FormatException('Некорректные псевдонимы персонажа');
    }
    _text(role, 160, 'роль');
    _text(biography, 1200, 'биография');
    _text(appearance, 600, 'внешность');
    _text(personality, 600, 'характер');
    _text(speechStyle, 400, 'манера речи');
    _text(motivation, 600, 'мотивация');
    _text(goals, 600, 'цели');
    if (!_portrait.hasMatch(portraitAssetId)) {
      throw const FormatException('Портрет NPC: нужен локальный ключ, не путь');
    }
  }

  Map<String, Object> toJson() {
    validate();
    return {
      'character_id': characterId,
      'aliases': aliases,
      'role': role,
      'biography': biography,
      'appearance': appearance,
      'personality': personality,
      'speech_style': speechStyle,
      'motivation': motivation,
      'goals': goals,
      'portrait_asset_id': portraitAssetId,
    };
  }

  static NpcCharacterCard fromJson(Map<String, dynamic> input) {
    const keys = {
      'character_id', 'aliases', 'role', 'biography', 'appearance',
      'personality', 'speech_style', 'motivation', 'goals',
      'portrait_asset_id',
    };
    if (input.length != keys.length || !input.keys.toSet().containsAll(keys)) {
      throw const FormatException('Недостаточные или неизвестные поля NPC');
    }
    try {
      final card = NpcCharacterCard(
        characterId: input['character_id'] as String,
        aliases: [for (final s in input['aliases'] as List) s as String],
        role: input['role'] as String,
        biography: input['biography'] as String,
        appearance: input['appearance'] as String,
        personality: input['personality'] as String,
        speechStyle: input['speech_style'] as String,
        motivation: input['motivation'] as String,
        goals: input['goals'] as String,
        portraitAssetId: input['portrait_asset_id'] as String,
      );
      card.validate();
      return card;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждена полная карточка NPC');
    }
  }
}
