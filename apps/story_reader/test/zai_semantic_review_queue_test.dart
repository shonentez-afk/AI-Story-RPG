import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _book([String second = 'Анна открыла дверь.']) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Частная сказка',
      author: 'НЕ ПЕРЕДАВАТЬ',
      chapters: ['Анна вошла в дом.', second],
      structuredChapters: [
        const BookChapter(id: 'first', blocks: [
          BookBlock(kind: BookBlockKind.paragraph, text: 'Анна вошла в дом.'),
        ]),
        BookChapter(id: 'second', blocks: [
          BookBlock(kind: BookBlockKind.paragraph, text: second),
        ]),
      ],
    ));

ZaiSemanticPreviewResult _preview(BookSourceIndex index, int position) {
  final piece = index.chunks[position];
  final label = position == 0 ? 'Анна вошла в дом' : 'Анна открыла дверь';
  final candidate = SemanticCandidate.propose(index, piece,
      category: SemanticCategory.event,
      startUtf16: piece.startUtf16,
      endUtf16: piece.endUtf16,
      label: label,
      uncertainty: 'Сверить обстоятельства события');
  final batch = SemanticCandidateBatch(
    providerId: ZaiSemanticPreviewService.providerId,
    providerVersion: ZaiSemanticPreviewService.providerVersion,
    sourceFingerprint: index.sourceFingerprint,
    chunkIds: [piece.id],
    candidates: [candidate],
  );
  return ZaiSemanticPreviewResult(
    batch: batch, totalSuggestions: 2, rejectedCount: 1,
    rejectedNonRussian: 0,
  );
}

void main() {
  test('per-window review queue resumes by exact source and never makes canon',
      () {
    final book = _book();
    final empty = ZaiWindowReviewQueue.empty(book);
    expect(empty.windows.length, 2);
    expect(empty.completedCount, 0);
    expect(empty.nextPendingAfter(1), 0);
    expect(empty.canPublishBookworld, false);

    final one = empty.record(0, _preview(book, 0));
    expect(one.completedCount, 1);
    expect(one.pendingCount, 1);
    expect(one.nextPendingAfter(0), 1);
    final id = one.allCandidates.single.id;
    final reviewed = one.decide(id, ZaiEditorialDecision.keepForReview);
    expect(reviewed.keptForReviewCount, 1);
    expect(reviewed.pendingReviewCount, 0);
    expect(reviewed.canPublishBookworld, false);
    final saved = reviewed.encode();
    expect(saved, isNot(contains('НЕ ПЕРЕДАВАТЬ')));
    expect(saved, contains('Анна вошла в дом.')); // Exact source quote is deliberately kept locally.
    final restored = ZaiWindowReviewQueue.decode(book, saved);
    expect(restored.encode(), saved);
    expect(restored.decisions[id], ZaiEditorialDecision.keepForReview);
    expect(restored.completedCount, 1);

    final second = restored.record(1, _preview(book, 1));
    expect(second.completedCount, 2);
    expect(second.nextPendingAfter(1), isNull);
    expect(second.pendingReviewCount, 1);
    final replaced = second.record(0, _preview(book, 0));
    expect(replaced.decisions, isEmpty);
    expect(replaced.candidateCount, 2);
    expect(replaced.canPublishBookworld, false);
  });

  test('forged source edition and checksum fail closed', () {
    final book = _book();
    final queue = ZaiWindowReviewQueue.empty(book).record(0, _preview(book, 0));
    final raw = queue.encode();
    expect(() => ZaiWindowReviewQueue.decode(
        _book('Анна никогда не открывала дверь.'), raw), throwsFormatException);
    final altered = jsonDecode(raw) as Map<String, dynamic>;
    (altered['payload'] as Map<String, dynamic>)['can_publish_bookworld'] = true;
    expect(() => ZaiWindowReviewQueue.decode(book, jsonEncode(altered)),
        throwsFormatException);
    expect(() => ZaiWindowReviewQueue.decode(book, raw + ' '),
        throwsFormatException);
    expect(() => queue.decide('forged', ZaiEditorialDecision.rejected),
        throwsFormatException);
  });

  test('wrong window or provider cannot be recorded', () {
    final book = _book();
    final queue = ZaiWindowReviewQueue.empty(book);
    expect(() => queue.record(1, _preview(book, 0)), throwsFormatException);
    expect(() => queue.record(-1, _preview(book, 0)), throwsRangeError);
    final one = queue.record(0, _preview(book, 0));
    final decoded = jsonDecode(one.encode()) as Map<String, dynamic>;
    final payload = decoded['payload'] as Map<String, dynamic>;
    final results = payload['results'] as List;
    (results.single as Map<String, dynamic>)['chunk_ids'] = ['forged'];
    expect(() => ZaiWindowReviewQueue.decode(book, jsonEncode(decoded)),
        throwsFormatException);
  });
}
