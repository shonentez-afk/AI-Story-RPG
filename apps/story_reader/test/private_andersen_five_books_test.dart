import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local opt-in QA for the user's FIVE separated FB2 files.
/// Their bytes, text, embedded pictures and annotations are never committed to
/// this PUBLIC repository or uploaded as a CI artifact.
///
/// Windows PowerShell, in apps/story_reader:
///   $env:AI_RPG_PRIVATE_FAIRYTALES_DIR="C:\books\Andersen_FB2_skazki"
///   flutter test test/private_andersen_five_books_test.dart --reporter expanded
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['AI_RPG_PRIVATE_FAIRYTALES_DIR'];
  test('five original FB2 files import with intact artwork and '
      'seven numbered Snow Queen parts', () async {
    const cases = [
      (file: '01_Ognivo.fb2', title: 'Огниво', parts: 1,
          appendix: 0, art: 15),
      (file: '02_Dyuymovochka.fb2', title: 'Дюймовочка',
          parts: 1, appendix: 0, art: 14),
      (file: '03_Novoe_plate_korolya.fb2',
          title: 'Новое платье короля', parts: 1, appendix: 1, art: 4),
      (file: '05_Gadkiy_utenok.fb2', title: 'Гадкий утенок',
          parts: 1, appendix: 0, art: 7),
      (file: '06_Snezhnaya_koroleva.fb2', title: 'Снежная королева',
          parts: 7, appendix: 1, art: 21),
    ];
    for (final item in cases) {
      final bytes = await File(dir! + '/' + item.file).readAsBytes();
      final book = BookImporter.parse(item.file, bytes);
      expect(book.title, item.title, reason: item.file);
      expect(book.structuredChapters, hasLength(item.parts + item.appendix),
          reason: item.file);
      expect(book.images, hasLength(item.art), reason: item.file);
      expect(book.cover, isNotNull, reason: item.file);
      final imageRefs = book.structuredChapters
          .expand((c) => c.blocks)
          .where((b) => b.kind == BookBlockKind.image)
          .map((b) => b.resourceId).whereType<String>().toList();
      expect(imageRefs, hasLength(item.art), reason: item.file);
      expect(imageRefs.every(book.images.containsKey), isTrue,
          reason: item.file);
      final index = BookSourceIndexer.index(book);
      expect(index.chapterCount, item.parts + item.appendix,
          reason: item.file);
      expect(index.indexedChapterCount, index.chapterCount,
          reason: item.file);
      expect(index.textIndexCoverage, 1.0, reason: item.file);
      expect(index.unindexedMediaBlocks, item.art, reason: item.file);
      expect(index.canPublishBookworld, false);
      final roleHints = index.chunks.expand(
          (chunk) => SourceNarrativeExtractor.roleMentionsInChunk(index, chunk));
      expect(roleHints, isNotEmpty, reason: item.file);
      if (item.appendix != 0) {
        expect(book.structuredChapters.last.blocks.first.text, 'Примечания');
      }
      if (item.parts == 7) {
        const titles = [
          'Рассказ первый', 'Рассказ второй', 'Рассказ третий',
          'Рассказ четвертый', 'Рассказ пятый',
          'Рассказ шестой', 'Рассказ седьмой',
        ];
        for (var i = 0; i < titles.length; i++) {
          expect(book.chapters[i], contains(titles[i]));
        }
      }
    }
  }, skip: dir == null || dir.isEmpty
      ? 'User books are not uploaded to GitHub CI; set '
          'AI_RPG_PRIVATE_FAIRYTALES_DIR locally.'
      : false);
}
