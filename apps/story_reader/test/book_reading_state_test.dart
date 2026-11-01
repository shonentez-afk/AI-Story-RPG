import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_reading_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('per-book reading chapter and bookmarks survive restart', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BookReadingStore();
    await store.save('book-A', const BookReadingState(
      chapter: 3,
      bookmarks: [1, 3],
    ));
    final restored = await BookReadingStore().load('book-A');
    expect(restored.chapter, 3);
    expect(restored.bookmarks, [1, 3]);
    final other = await store.load('book-B');
    expect(other.chapter, 0);
    expect(other.bookmarks, isEmpty);
  });

  test('invalid reading state falls back without modifying game saves', () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_broken': '{bad json',
      'ai_story_m1_snapshot_v1': 'existing-game-save',
    });
    final state = await BookReadingStore().load('broken');
    expect(state.chapter, 0);
    expect(state.bookmarks, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_story_m1_snapshot_v1'), 'existing-game-save');
  });
}
