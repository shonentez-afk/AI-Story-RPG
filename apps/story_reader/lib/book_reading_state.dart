import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading progress is separate from gameplay snapshots.
class BookReadingState {
  const BookReadingState({this.chapter = 0, this.bookmarks = const []});
  final int chapter;
  final List<int> bookmarks;

  BookReadingState copyWith({int? chapter, List<int>? bookmarks}) =>
      BookReadingState(
        chapter: chapter ?? this.chapter,
        bookmarks: bookmarks ?? this.bookmarks,
      );
}

class BookReadingStore {
  static String _key(String bookId) => 'ai_story_book_state_v1_$bookId';

  Future<BookReadingState> load(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(bookId));
    if (raw == null) return const BookReadingState();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BookReadingState(
        chapter: ((map['chapter'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
        bookmarks: ((map['bookmarks'] as List?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value >= 0)
            .toSet()
            .toList()..sort(),
      );
    } catch (_) {
      return const BookReadingState();
    }
  }

  Future<void> save(String bookId, BookReadingState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(bookId), jsonEncode({
      'chapter': state.chapter,
      'bookmarks': state.bookmarks,
    }));
  }
}
