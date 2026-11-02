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
      scrollOffset: 421.5,
      bookmarks: [1, 3],
    ));
    final restored = await BookReadingStore().load('book-A');
    expect(restored.chapter, 3);
    expect(restored.scrollOffset, 421.5);
    expect(restored.bookmarks, [1, 3]);
    final other = await store.load('book-B');
    expect(other.chapter, 0);
    expect(other.bookmarks, isEmpty);
  });


  test('semantic paragraph anchor persists; old records stay readable',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_old': '{"chapter":2,'
          '"scrollOffset":96.5,"bookmarks":[0,2]}',
    });
    final store = BookReadingStore();
    final old = await store.load('old');
    expect(old.anchor, isNull);
    expect(old.scrollOffset, 96.5);
    await store.save('old', old.copyWith(
      anchor: const BookTextAnchor(blockIndex: 43, fraction: 0.375),
    ));
    final upgraded = await BookReadingStore().load('old');
    expect(upgraded.anchor!.blockIndex, 43);
    expect(upgraded.anchor!.fraction, 0.375);
    expect(upgraded.scrollOffset, 96.5);
    expect(upgraded.bookmarks, [0, 2]);
    final cleared = upgraded.copyWith(clearAnchor: true, chapter: 3);
    await store.save('old', cleared);
    final changed = await store.load('old');
    expect(changed.anchor, isNull);
    expect(changed.chapter, 3);
  });

  test('invalid semantic anchors fall back to legacy pixels, not loss of book',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_badAnchor': '{"chapter":1,'
          '"scrollOffset":125,"anchorBlock":1000000000,'
          '"anchorFraction":0.5,"bookmarks":[1]}',
    });
    final state = await BookReadingStore().load('badAnchor');
    expect(state.anchor, isNull);
    expect(state.chapter, 1);
    expect(state.scrollOffset, 125);
    expect(state.bookmarks, [1]);
  });

  test('invalid reading state falls back without modifying game saves', () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_broken': '{bad json',
      'ai_story_m1_snapshot_v1': 'existing-game-save',
    });
    final state = await BookReadingStore().load('broken');
    expect(state.chapter, 0);
    expect(state.scrollOffset, 0);
    expect(state.bookmarks, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_story_m1_snapshot_v1'), 'existing-game-save');
  });
}
