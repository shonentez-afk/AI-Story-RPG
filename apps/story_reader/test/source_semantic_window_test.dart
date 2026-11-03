import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_semantic_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const beginning = 'Жил-был бедный принц. '
      'Королевство у него было маленькое-премаленькое. '
      'Принц хотел жениться на дочери императора.';
  const story = ImportedBook(
    title: 'Свинопас',
    author: 'Автор хранится локально',
    chapters: [beginning, 'Другой раздел истории.'],
    structuredChapters: [
      BookChapter(id: 'chapter_A', blocks: [
        BookBlock(kind: BookBlockKind.heading, text: 'СВИНОПАС'),
        BookBlock(kind: BookBlockKind.paragraph, text: beginning),
        BookBlock(kind: BookBlockKind.paragraph,
            text: 'Послушаем же, как было дело.'),
      ]),
      BookChapter(id: 'chapter_B', blocks: [
        BookBlock(kind: BookBlockKind.heading, text: 'Вторая часть'),
        BookBlock(kind: BookBlockKind.paragraph,
            text: 'Принц направился к замку.'),
      ]),
    ],
  );

  test('semantic windows join adjacent FB2 blocks without losing '
      'the heading kind, chapter boundary, source identity or fingerprint',
      () {
    final index = BookSourceIndexer.index(story);
    final originalIndexJson = index.toJson();
    final originalFingerprint = index.sourceFingerprint;
    expect(index.chunks.first.blockKind, BookBlockKind.heading);
    expect(index.chunks[1].blockKind, BookBlockKind.paragraph);

    final windows = SourceSemanticWindowPlanner.plan(index);
    expect(windows.length, 2);
    expect(windows.first.chunks.length, 3);
    expect(windows.last.chunks.length, 2);
    expect(windows.first.sourcePieces.first['kind'], 'heading');
    expect(windows.first.sourcePieces[1]['kind'], 'paragraph');
    expect(windows.first.sourcePieces.first['text'], 'СВИНОПАС');
    expect(windows.first.displayText, contains(beginning));
    expect(windows.first.chapterIndex, 0);
    expect(windows.last.chapterIndex, 1);
    expect(windows.first.sourcePieces.first['source_id'],
        index.chunks.first.id);

    for (final window in windows) {
      SourceSemanticWindowPlanner.validate(index, window);
    }
    expect(windows.expand((x) => x.chunks).toList(), index.chunks);
    expect(index.sourceFingerprint, originalFingerprint);
    expect(index.toJson(), originalIndexJson);
    // No heading classification is added to the persisted source schema.
    expect(index.chunks.first.toJson().containsKey('block_kind'), isFalse);
  });

  test('long chapters split into non-overlapping bounded windows, '
      'no context crosses into the next chapter', () {
    final text = List.filled(35, 'Жил-был принц в маленьком городе. ').join();
    final book = ImportedBook(
      title: 'Тест границ',
      author: 'Не передавать',
      chapters: [text, text],
      structuredChapters: [
        BookChapter(id: 'first', blocks: [
          for (var i = 0; i < 16; i++)
            BookBlock(kind: BookBlockKind.paragraph, text: text),
        ]),
        BookChapter(id: 'second', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Часть 2'),
          BookBlock(kind: BookBlockKind.paragraph, text: text),
        ]),
      ],
    );
    final index = BookSourceIndexer.index(book);
    final windows = SourceSemanticWindowPlanner.plan(index);
    expect(windows.length, greaterThan(2));
    final allIds = <String>[];
    for (final w in windows) {
      SourceSemanticWindowPlanner.validate(index, w);
      expect(w.utf16Length,
          lessThanOrEqualTo(SourceSemanticWindowPlanner.maxWindowUtf16));
      expect(w.utf8Length,
          lessThanOrEqualTo(SourceSemanticWindowPlanner.maxWindowUtf8));
      expect(w.chunks.length,
          lessThanOrEqualTo(SourceSemanticWindowPlanner.maxSourceChunks));
      expect(w.chunks.every((c) => c.chapterIndex == w.chapterIndex), true);
      allIds.addAll(w.chunks.map((c) => c.id));
    }
    expect(allIds, index.chunks.map((c) => c.id).toList());
    expect(allIds.toSet().length, allIds.length);
  });

  test('refuses heading-only, reordered and forged source windows', () {
    final index = BookSourceIndexer.index(story);
    final heading = SourceSemanticWindow([index.chunks.first]);
    expect(heading.hasNarrativeText, false);
    expect(() => SourceSemanticWindowPlanner.validate(index, heading),
        throwsFormatException);

    final swapped = SourceSemanticWindow(
        [index.chunks[1], index.chunks.first]);
    expect(() => SourceSemanticWindowPlanner.validate(index, swapped),
        throwsFormatException);

    final duplicate = SourceSemanticWindow(
        [index.chunks[1], index.chunks[1]]);
    expect(() => SourceSemanticWindowPlanner.validate(index, duplicate),
        throwsFormatException);

    final crossed = SourceSemanticWindow(
        [index.chunks[2], index.chunks[3]]);
    expect(() => SourceSemanticWindowPlanner.validate(index, crossed),
        throwsFormatException);
  });
}
