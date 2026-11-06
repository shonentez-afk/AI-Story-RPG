import 'package:ai_story_reader/npc_character_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('128-bit character ID is newly issued, opaque, stable on edits', () {
    final card = NpcCharacterCard.fresh();
    final second = NpcCharacterCard.fresh();
    expect(card.characterId, matches(RegExp(r'^npc_[0-9a-f]{32}$')));
    expect(second.characterId, isNot(card.characterId));
    final edited = card.copyWith(
      aliases: ['Волк', 'Хранитель ворот'],
      appearance: 'Высокий, седой',
      role: 'Страж',
      biography: 'Когда-то жил у реки.',
      personality: 'Осторожный',
      speechStyle: 'Короткие предложения',
      motivation: 'Защитить ворота',
      goals: 'Найти ключ',
      portraitAssetId: 'wolf_face_local_1',
    );
    expect(edited.characterId, card.characterId);
    expect(edited.literaryCanonVerified, false);
    expect(edited.npcKnowledgeVerified, false);
    expect(edited.maySendToCloud, false);
    expect(edited.isGameplayState, false);
    final saved = edited.toJson();
    expect(saved, containsPair('character_id', card.characterId));
    final restored = NpcCharacterCard.fromJson(saved);
    expect(restored.toJson(), saved);
    expect(restored.characterId, card.characterId);
    expect(restored.aliases, ['Волк', 'Хранитель ворот']);
    expect(restored.portraitAssetId, 'wolf_face_local_1');
  });

  test('invalid or tampered IDs, portrait paths and duplicate aliases fail', () {
    final card = NpcCharacterCard.fresh();
    final saved = card.toJson();
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'character_id': 'npc_NaN',
    }), throwsFormatException);
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'character_id': 'npc_from_name_Артём',
    }), throwsFormatException);
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'portrait_asset_id': '../private/key.png',
    }), throwsFormatException);
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'aliases': ['Тень', 'тень'],
    }), throwsFormatException);
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'extra': 'change',
    }), throwsFormatException);
    expect(() => NpcCharacterCard.fromJson({
      ...saved, 'goals': List.filled(700, 'x').join(),
    }), throwsFormatException);
    expect(card.toJson(), saved);
  });
}
