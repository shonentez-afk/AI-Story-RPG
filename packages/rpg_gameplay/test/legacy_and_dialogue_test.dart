import 'package:bookworld_format/bookworld_format.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart';
import 'package:test/test.dart';

void main() {
  test('dialogue turns, speaker attribution and private locked lines are '
      'interpreted without importing Flutter', () {
    final script = SceneDialogueScript.fromSignedTurns(const [
      RichDialogueTurn(speaker: 'Мария', text: 'Я вас помню.'),
      RichDialogueTurn(text: 'Игрок остановился у ворот.'),
      RichDialogueTurn(speaker: 'Иван', text: 'Решение за вами.'),
    ]);
    expect(script.turns, hasLength(3));
    expect(script.turns[0].speaker, 'Мария');
    expect(script.turns[1].isNarration, isTrue);
    expect(script.turns[2].speaker, 'Иван');
    expect(SceneDialogueScript.fromSceneText(
        'Обычная глава без атрибутированных реплик.'), isNull);
    expect(() => SceneDialogueScript.fromSignedTurns(const []),
        throwsFormatException);
  });

  test('legacy pilot item, lock, ending and save model are engine-owned', () {
    const initial = GameProgress();
    expect(initial.choiceLockReason('unlock_cellar'), isNotNull);
    expect(initial.choiceLockReason('open_secret'), isNotNull);
    final searched = initial.apply('search_drawer');
    expect(searched.items, contains('key'));
    expect(searched.choiceLockReason('unlock_cellar'), isNull);
    final foundMap = searched.apply('take_map');
    expect(foundMap.items, contains('map'));
    expect(foundMap.choiceLockReason('open_secret'), isNull);
    final ending = foundMap.apply('preserve_story');
    expect(ending.endingId, 'preserve_story');
    expect(ending.endingTitle, isNotEmpty);
    final roundtrip = GameProgress.fromJson(ending.toJson());
    expect(roundtrip.items, unorderedEquals(ending.items));
    expect(roundtrip.endingId, 'preserve_story');
    final save = GameSaveRecord('safe_snapshot', const ['found map'],
        roundtrip, 1);
    expect(save.progress.items, contains('map'));
    expect(save.rulesVersion, 1);
    expect(PilotSaveCodec.format, 'ai_story_pilot_bwsave_v1');
    expect(PilotSaveCodec.format,
        isNot(BookworldCampaignStore.saveFormat)); // different contracts
  });
}
