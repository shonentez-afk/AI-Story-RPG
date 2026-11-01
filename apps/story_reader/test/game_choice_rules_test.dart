import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/main.dart';
import 'package:story_engine/story_engine.dart';

void main() {
  test('choice prerequisites depend on actual acquired items', () {
    final start = const GameProgress();
    expect(start.choiceLockReason('unlock_cellar'), isNotNull);
    expect(start.choiceLockReason('open_secret'), isNotNull);
    expect(start.choiceLockReason('face_shadow'), isNotNull);
    expect(start.choiceLockReason('preserve_story'), isNotNull);
    expect(start.choiceLockReason('reveal_story'), isNotNull);
    expect(start.choiceLockReason('enter'), isNull);

    final withKey = start.apply('search_drawer');
    expect(withKey.choiceLockReason('unlock_cellar'), isNull);
    expect(withKey.choiceLockReason('open_secret'), isNotNull);

    final withMap = withKey.apply('take_map');
    expect(withMap.choiceLockReason('open_secret'), isNull);
    expect(withMap.choiceLockReason('face_shadow'), isNull);
    expect(withMap.choiceLockReason('preserve_story'), isNull);
    expect(withMap.choiceLockReason('reveal_story'), isNotNull);

    final withLetter = start.apply('inspect_letter');
    expect(withLetter.choiceLockReason('face_shadow'), isNull);
    expect(withLetter.choiceLockReason('reveal_story'), isNull);
  });

  test('two different endings remain attainable through validated choices', () {
    GameProgress play(List<String> ids) {
      final project = makePilotStory();
      expect(StoryValidator.validate(project).hasErrors, isFalse);
      final engine = StoryEngine(project: project)..start();
      var world = const GameProgress();
      for (final id in ids) {
        expect(engine.availableChoices.any((choice) => choice.id.value == id),
            isTrue, reason: 'Story choice missing: $id');
        expect(world.choiceLockReason(id), isNull,
            reason: 'Choice locked by world state: $id');
        engine.choose(StoryChoiceId(id));
        world = world.apply(id);
      }
      expect(engine.status, StoryEngineStatus.terminated);
      return world;
    }

    final keptSecret = play([
      'enter', 'search_drawer', 'take_map', 'unlock_cellar',
      'open_secret', 'preserve_story',
    ]);
    expect(keptSecret.items, containsAll(['key', 'map']));
    expect(keptSecret.items, isNot(contains('letter')));

    final exposedSecret = play([
      'enter', 'inspect_letter', 'follow_steps', 'climb_tower',
      'face_shadow', 'reveal_story',
    ]);
    expect(exposedSecret.items, contains('letter'));
    expect(exposedSecret.courage, 2);
  });

  test('locked conditions cannot be unlocked by duplicated item awards', () {
    final world = const GameProgress().apply('inspect_letter')
        .apply('inspect_letter').apply('take_map').apply('take_map');
    expect(world.items, ['letter', 'map']);
    expect(world.choiceLockReason('unlock_cellar'), isNotNull);
    expect(world.choiceLockReason('reveal_story'), isNull);
  });
}
