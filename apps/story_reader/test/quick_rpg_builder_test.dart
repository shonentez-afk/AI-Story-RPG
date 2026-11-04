import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/quick_rpg_builder.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter_test/flutter_test.dart';

const example = '<FictionBook><description><title-info><book-title>Тест</book-title>'
  '</title-info></description><body><section>'
  '<p>Один герой начал путешествие из старого дома, который стоял на самом краю деревни.</p>'
  '<p>Вторая часть книги описывала прогулку героя вдоль тёмного леса и небольшой реки.</p>'
  '<p>Следующая сцена рассказывала о добром знакомстве с новым путешественником на дороге.</p>'
  '<p>Последний эпизод повествовал о завершении путешествия и возвращении домой.</p>'
  '</section></body></FictionBook>';

BookSourceIndex sample() => BookSourceIndexer.index(
    BookImporter.parse('sample.fb2',
      Uint8List.fromList(utf8.encode(example))));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('quick plan keeps exact quotes and needs consent', () async {
    final index = sample();
    final plan = QuickRpgBuilder.propose(index);
    expect(plan.anchors.length, greaterThanOrEqualTo(2));
    expect(plan.isCompleteRpgFromBook, false);
    for (final anchor in plan.anchors) {
      final chunk = index.chunks.singleWhere((c) => c.id == anchor.chunkId);
      expect(chunk.text.substring(
        anchor.startUtf16 - chunk.startUtf16,
        anchor.endUtf16 - chunk.startUtf16), anchor.quote);
    }
    await expectLater(QuickRpgBuilder.compile(
      plan: plan, allQuotesReviewedByUser: false,
      privateUseConfirmed: true), throwsFormatException);
    final built = await QuickRpgBuilder.compile(
      plan: plan, allQuotesReviewedByUser: true,
      privateUseConfirmed: true);
    final parsed = const PrivateBookworldImporter().inspect(built.archive);
    expect(parsed.bookworldId, built.bookworldId);
    expect(parsed.canDistributePublicly, false);
    expect(parsed.requiresNetwork, false);
    expect(parsed.blueprint.scenes.length, greaterThanOrEqualTo(3));
  });
}
