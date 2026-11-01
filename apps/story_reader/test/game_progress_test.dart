import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:ai_story_reader/main.dart';
import 'package:story_engine/story_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seven playable scenes and multiple endings validate', () {
    final story = makePilotStory();
    expect(StoryValidator.validate(story).hasErrors, isFalse);
    expect(story.events.length, greaterThanOrEqualTo(6));
    final terminalChoices = story.events
        .expand((event) => event.choices)
        .where((choice) => choice.transition is StoryTerminalTransition);
    expect(terminalChoices.length, greaterThanOrEqualTo(2));
  });

  test('choice effects are deterministic and items unique', () {
    final state = const GameProgress()
        .apply('enter')
        .apply('inspect_letter')
        .apply('inspect_letter')
        .apply('take_map')
        .apply('unlock_cellar');
    expect(state.courage, 2);
    expect(state.insight, 3);
    expect(state.items, ['letter', 'map']);
  });

  test('character and inventory persist with same snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = const GameProgress().apply('enter').apply('search_drawer');
    await SaveStore().writeGame('snapshot', ['gate: enter'], progress);
    final saved = await SaveStore().readGame();
    expect(saved!.snapshot, 'snapshot');
    expect(saved.journal, ['gate: enter']);
    expect(saved.progress.courage, 1);
    expect(saved.progress.items, ['key']);
  });
}
