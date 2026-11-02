import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Location within a single paragraph/heading/image in the current chapter.
/// Unlike a pixel offset, this survives font-size and viewport reflow.
class BookTextAnchor {
  const BookTextAnchor({required this.blockIndex, this.fraction = 0});
  final int blockIndex;
  final double fraction;
}

/// Reading progress is separate from gameplay and legacy demonstration saves.
/// Null [anchor] means an older pixel-only record or the start of the chapter.
/// Every write retains the legacy fields so previous app versions can open it.
class BookReadingState {
  const BookReadingState({
    this.chapter = 0,
    this.scrollOffset = 0,
    this.bookmarks = const [],
    this.anchor,
  });
  final int chapter;
  final double scrollOffset;
  final List<int> bookmarks;
  final BookTextAnchor? anchor;

  BookReadingState copyWith({
    int? chapter,
    double? scrollOffset,
    List<int>? bookmarks,
    BookTextAnchor? anchor,
    bool clearAnchor = false,
  }) => BookReadingState(
    chapter: chapter ?? this.chapter,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    bookmarks: bookmarks ?? this.bookmarks,
    anchor: clearAnchor ? null : (anchor ?? this.anchor),
  );
}

class BookReadingStore {
  static String _key(String bookId) => 'ai_story_book_state_v1_$bookId';

  // A quick chapter change, bookmark tap, route pop and subsequent reopen
  // must never allow an older write to overwrite the latest reading place.
  // The queue is scoped by book ID so unrelated books do not block each other.
  static final Map<String, Future<void>> _pending = {};

  Future<BookReadingState> load(String bookId) async {
    final pending = _pending[bookId];
    if (pending != null) {
      // A failed write must not prevent a read of the last good value.
      try { await pending; } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(bookId));
    if (raw == null) return const BookReadingState();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rawIndex = map['anchorBlock'];
      final rawFraction = map['anchorFraction'];
      BookTextAnchor? anchor;
      // Fail safe: a partially corrupted anchor never hides the book or
      // invalidates existing chapter/bookmark/pixel-only data.
      if (rawIndex is int && rawIndex >= 0 && rawIndex < 1000000 &&
          rawFraction is num && rawFraction.isFinite &&
          rawFraction >= 0 && rawFraction <= 1) {
        anchor = BookTextAnchor(
          blockIndex: rawIndex, fraction: rawFraction.toDouble(),
        );
      }
      final offset = (map['scrollOffset'] as num?)?.toDouble() ?? 0;
      return BookReadingState(
        chapter: ((map['chapter'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
        scrollOffset: offset.isFinite
            ? offset.clamp(0.0, 100000000.0).toDouble() : 0,
        bookmarks: ((map['bookmarks'] as List?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value >= 0)
            .toSet()
            .toList()..sort(),
        anchor: anchor,
      );
    } catch (_) {
      return const BookReadingState();
    }
  }

  Future<void> save(String bookId, BookReadingState state) {
    // Serialize immutable bytes NOW, not the mutable UI at write time.
    final payload = jsonEncode({
      'chapter': state.chapter,
      'scrollOffset': state.scrollOffset.isFinite
          ? state.scrollOffset : 0,
      'bookmarks': state.bookmarks,
      if (state.anchor != null) ...{
        'anchorBlock': state.anchor!.blockIndex,
        'anchorFraction': state.anchor!.fraction,
      },
    });
    final previous = _pending[bookId] ?? Future<void>.value();
    final operation = previous.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(bookId), payload);
    });
    _pending[bookId] = operation;
    // Clean up after both successful and failed writes, with no unhandled
    // future errors; callers still receive the original failure.
    operation.then((_) {
      if (identical(_pending[bookId], operation)) _pending.remove(bookId);
    }, onError: (Object _) {
      if (identical(_pending[bookId], operation)) _pending.remove(bookId);
    });
    return operation;
  }
}
