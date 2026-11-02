import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/book_source_analysis.dart';

void main() {
  const book = ImportedBook(
    title: 'Исходная повесть', author: 'Тест',
    chapters: ['Его звали Артем. В городе Москва он встретил человека.',
      'Девушку звали Анна. В деревне Березовка случилась встреча.'],
  );

  test('offline queue is deterministic, evidence-bound, review-only', () {
    final index = BookSourceIndexer.index(book);
    final initial = SourceAnalysisSession.create(index);
    expect(initial.pendingCount, index.chunks.length);
    expect(initial.canPublishBookworld, false);
    expect(initial.gameplayCoverage, 0);
    final session = initial.processBatch(index);
    expect(session.pendingCount, 0);
    expect(session.mentions.map((m) => m.label),
        containsAll(['Артем', 'Москва', 'Анна', 'Березовка']));
    expect(session.mentions.every((m) => m.decision == MentionDecision.review),
        true);
    for (final hit in session.mentions) {
      final chunk = index.chunks.singleWhere((c) => c.id == hit.chunkId);
      expect(chunk.text.substring(hit.startUtf16 - chunk.startUtf16,
          hit.endUtf16 - chunk.startUtf16), hit.label);
    }
    final restored = SourceAnalysisSession.decode(index, session.encode());
    expect(restored.encode(), session.encode());
  });

  test('interrupted work resumes pending without phantom completion', () {
    final index = BookSourceIndexer.index(book);
    final running = SourceAnalysisSession.create(index).startNext();
    final resumed = SourceAnalysisSession.decode(index, running.encode());
    expect(resumed.pendingCount, index.chunks.length);
    expect(resumed.mentions, isEmpty);
    final complete = resumed.processBatch(index, limit: 1);
    expect(complete.processedCount, 1);
  });

  test('review decision never upgrades gameplay coverage', () {
    final index = BookSourceIndexer.index(book);
    final session = SourceAnalysisSession.create(index).processBatch(index);
    final accepted = session.decide(session.mentions.first.id,
        MentionDecision.accepted);
    expect(accepted.reviewCount, session.reviewCount - 1);
    expect(accepted.canPublishBookworld, false);
    expect(accepted.gameplayCoverage, 0);
    expect(SourceAnalysisSession.decode(index, accepted.encode()).reviewCount,
        accepted.reviewCount);
  });

  test('tampering and wrong edition fail closed', () {
    final index = BookSourceIndexer.index(book);
    final session = SourceAnalysisSession.create(index).processBatch(index);
    expect(() => SourceAnalysisSession.decode(
      BookSourceIndexer.index(const ImportedBook(
          title: 'Другое издание', author: 'Тест', chapters: ['Другая книга'])),
      session.encode()), throwsFormatException);
    final root = jsonDecode(session.encode()) as Map<String, dynamic>;
    final payload = root['payload'] as Map<String, dynamic>;
    final mentions = payload['mentions'] as List<dynamic>;
    (mentions.first as Map<String, dynamic>)['label'] = 'Подмена';
    expect(() => SourceAnalysisSession.decode(index, jsonEncode(root)),
        throwsFormatException);
  });

  test('explicit failure/retry and bounded batch', () {
    final index = BookSourceIndexer.index(book);
    final failed = SourceAnalysisSession.create(index)
        .startNext().failRunning();
    expect(failed.failedCount, 1);
    final retried = failed.retryFailed().processBatch(index, limit: 1);
    expect(retried.failedCount, 0);
    expect(retried.processedCount, 1);
    expect(() => retried.processBatch(index, limit: 0), throwsRangeError);
  });
}
