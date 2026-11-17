import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

const _collection = ImportedBook(
  title: 'Народные сказки',
  author: 'Собиратель',
  chapters: [
    'Первая историческая редакция. Жили-были старик и старуха.',
    'Вторая редакция описывает других действующих лиц и события.',
  ],
  structuredChapters: [
    BookChapter(id: 'part_95', blocks: [
      BookBlock(kind: BookBlockKind.heading,
          text: 'Морозко — вариант № 95'),
      BookBlock(kind: BookBlockKind.paragraph,
          text: 'Первая историческая редакция. Жили-были старик и старуха.'),
    ]),
    BookChapter(id: 'part_96', blocks: [
      BookBlock(kind: BookBlockKind.heading,
          text: 'Морозко — вариант № 96'),
      BookBlock(kind: BookBlockKind.paragraph,
          text: 'Вторая редакция описывает других действующих лиц и события.'),
    ]),
  ],
);

void main() {
  test('alternative folk-tale editions default to one story, not one timeline',
      () {
    expect(BookSourceSelection.defaultChapter(_collection), 0);
    final selected = BookSourceSelection.selectChapter(_collection, 1);
    expect(selected.chapters, hasLength(1));
    expect(selected.chapters.single, _collection.chapters[1]);
    expect(selected.title, contains('вариант № 96'));
    expect(selected.structuredChapters, hasLength(1));
    expect(_collection.chapters, hasLength(2));
    final original = BookSourceIndexer.index(_collection);
    final edition = BookSourceIndexer.index(selected);
    expect(edition.chapterCount, 1);
    expect(edition.indexedChapterCount, 1);
    expect(edition.sourceFingerprint, isNot(original.sourceFingerprint));
    expect(edition.canPublishBookworld, false);
    expect(edition.textIndexCoverage, 1.0);
  });

  test('ordinary books stay whole until explicit chapter selection', () {
    const novel = ImportedBook(
      title: 'Повествование', author: 'Автор',
      chapters: ['Событие первой главы.', 'Событие второй главы.'],
    );
    expect(BookSourceSelection.defaultChapter(novel), isNull);
    final part = BookSourceSelection.selectChapter(novel, 0);
    expect(part.chapters, ['Событие первой главы.']);
    expect(part.title, contains('Глава 1'));
    expect(novel.chapters.length, 2);
  });

  test('invalid or empty chapter fails closed', () {
    expect(() => BookSourceSelection.selectChapter(_collection, -1),
        throwsRangeError);
    expect(() => BookSourceSelection.selectChapter(_collection, 9),
        throwsRangeError);
    const empty = ImportedBook(
        title: 'Пустой том', author: '', chapters: ['  ', 'Жила-была']);
    expect(() => BookSourceSelection.selectChapter(empty, 0),
        throwsFormatException);
  });

  test('non-variant numbered chapters retain chronological scope', () {
    const novel = ImportedBook(
      title: 'Книга', author: '',
      chapters: ['Первое событие.', 'Второе событие.'],
      structuredChapters: [
        BookChapter(id: 'c1', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Глава 1'),
        ]),
        BookChapter(id: 'c2', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Глава 2'),
        ]),
      ],
    );
    expect(BookSourceSelection.defaultChapter(novel), isNull);
  });
}
