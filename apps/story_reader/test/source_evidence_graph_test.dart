import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';

void main() {
  const sample = ImportedBook(
    title: 'Проверяемая оригинальная повесть',
    author: 'Тестовый автор',
    chapters: [
      'Его звали Артем. В городе Москва началось путешествие.',
      'Его звали Артем. В городе Москва он встретил другого героя.',
      'Свидетель утверждал, что герой открыл дверь. Это надо проверить.',
    ],
  );

  test('accepted M2b1 mentions still remain inferred and not canon', () {
    final index = BookSourceIndexer.index(sample);
    var session = SourceAnalysisSession.create(index).processBatch(index);
    for (final mention in [...session.mentions]) {
      session = session.decide(mention.id, MentionDecision.accepted);
    }
    final evidence = SourceEvidenceGraph.fromReviewedMentions(index, session);
    expect(evidence.records.length, 4);
    expect(evidence.records.every((e) => e.status == EvidenceStatus.inferred),
        true);
    expect(evidence.visibleToPlayer(currentChapter: 2), isEmpty);
    expect(evidence.possibleCrossChapterMatches.length, 2);
    expect(evidence.possibleCrossChapterMatches.every(
        (match) => !match.identityConfirmed && match.requiresReview), true);
    expect(evidence.possibleCrossChapterMatches.map((m) => m.normalizedName),
        containsAll(['артем', 'москва']));
    final roundtrip = SourceEvidenceGraph.decode(index, evidence.encode());
    expect(roundtrip.encode(), evidence.encode());
    expect((jsonDecode(evidence.encode()) as Map)['format'],
        SourceEvidenceGraph.format);
  });

  test('fact and event proposals need source spans and explicit review', () {
    final index = BookSourceIndexer.index(sample);
    final chunk = index.chunks.last;
    const quote = 'герой открыл дверь';
    final start = chunk.startUtf16 + chunk.text.indexOf(quote);
    final event = SourceEvidence.propose(index,
      chunkId: chunk.id, kind: EvidenceKind.event,
      startUtf16: start, endUtf16: start + quote.length,
    );
    final fact = SourceEvidence.propose(index,
      chunkId: chunk.id, kind: EvidenceKind.fact,
      startUtf16: start, endUtf16: start + quote.length,
    );
    expect(event.status, EvidenceStatus.inferred);
    expect(event.label, quote);
    expect(event.id, isNot(fact.id));
    var graph = SourceEvidenceGraph.empty(index).addAll(index, [event, fact]);
    expect(graph.visibleToPlayer(currentChapter: 99), isEmpty);
    graph = graph.review(index, event.id, EvidenceStatus.confirmed);
    expect(graph.visibleToPlayer(currentChapter: 1), isEmpty);
    expect(graph.visibleToPlayer(currentChapter: 2).single.label, quote);
    expect(graph.records.singleWhere((e) => e.id == fact.id).status,
        EvidenceStatus.inferred);
  });

  test('spoiler gate requires BOTH chapter and confirmed event discovery', () {
    final index = BookSourceIndexer.index(sample);
    final first = index.chunks.first;
    final nameStart = first.text.indexOf('Артем');
    final proposed = SourceEvidence.propose(index,
      chunkId: first.id, kind: EvidenceKind.character,
      startUtf16: nameStart, endUtf16: nameStart + 5,
      spoilerGate: EvidenceSpoilerGate.afterEvent,
      visibleAfterChapter: 1,
      revealEventId: 'player_found_letter',
    );
    var graph = SourceEvidenceGraph.empty(index).addAll(index, [proposed]);
    graph = graph.review(index, proposed.id, EvidenceStatus.confirmed);
    final restored = SourceEvidenceGraph.decode(index, graph.encode());
    expect(restored.records.single.spoilerGate, EvidenceSpoilerGate.afterEvent);
    expect(restored.records.single.revealEventId, 'player_found_letter');
    expect(graph.visibleToPlayer(currentChapter: 0,
        knownEvents: {'player_found_letter'}), isEmpty);
    expect(graph.visibleToPlayer(currentChapter: 1), isEmpty);
    expect(graph.visibleToPlayer(currentChapter: 1,
        knownEvents: {'player_found_letter'}).single.label, 'Артем');

    final hidden = proposed.withGate(index, EvidenceSpoilerGate.hidden);
    expect(hidden.reviewed(EvidenceStatus.confirmed).playerCanSee(
        currentChapter: 20, knownEvents: {'player_found_letter'}), false);
    expect(() => SourceEvidence.propose(index, chunkId: first.id,
      kind: EvidenceKind.character, startUtf16: nameStart,
      endUtf16: nameStart + 5,
      spoilerGate: EvidenceSpoilerGate.afterEvent), throwsFormatException);
    expect(() => proposed.withGate(index, EvidenceSpoilerGate.chapter,
        chapter: -1), throwsFormatException);
  });

  test('foreign edition and post-hash tampering cannot grant confirmation', () {
    final index = BookSourceIndexer.index(sample);
    final chunk = index.chunks.first;
    final point = chunk.text.indexOf('Артем');
    final evidence = SourceEvidence.propose(index,
      chunkId: chunk.id, kind: EvidenceKind.character,
      startUtf16: point, endUtf16: point + 5,
    );
    final graph = SourceEvidenceGraph.empty(index)
        .addAll(index, [evidence])
        .review(index, evidence.id, EvidenceStatus.confirmed);
    final foreign = BookSourceIndexer.index(const ImportedBook(
      title: 'Иная редакция', author: 'Другой автор',
      chapters: ['Его звали Артем.'],
    ));
    expect(() => SourceEvidenceGraph.decode(foreign, graph.encode()),
        throwsFormatException);

    final root = jsonDecode(graph.encode()) as Map<String, dynamic>;
    final payload = root['payload'] as Map<String, dynamic>;
    final records = payload['evidence'] as List<dynamic>;
    final first = records.first as Map<String, dynamic>;
    first['label'] = 'Подмена';
    root['sha256'] = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    expect(() => SourceEvidenceGraph.decode(index, jsonEncode(root)),
        throwsFormatException);
  });

  test('invalid ranges, duplicate evidence and bad status fail closed', () {
    final index = BookSourceIndexer.index(sample);
    final chunk = index.chunks.first;
    expect(() => SourceEvidence.propose(index, chunkId: chunk.id,
      kind: EvidenceKind.event, startUtf16: 0, endUtf16: 5000),
        throwsFormatException);
    final e = SourceEvidence.propose(index, chunkId: chunk.id,
      kind: EvidenceKind.character, startUtf16: 9, endUtf16: 14);
    expect(() => SourceEvidenceGraph.empty(index).addAll(index, [e, e]),
        throwsFormatException);
    expect(() => e.reviewed(EvidenceStatus.inferred), throwsArgumentError);
    expect(e.reviewed(EvidenceStatus.conflicted).status,
        EvidenceStatus.conflicted);
    expect(e.reviewed(EvidenceStatus.rejected).playerCanSee(
        currentChapter: 100), false);
    final emoji = BookSourceIndexer.index(const ImportedBook(
      title: 'Символ', author: '', chapters: ['A😀B'],
    ));
    expect(() => SourceEvidence.propose(emoji,
      chunkId: emoji.chunks.first.id, kind: EvidenceKind.fact,
      startUtf16: 2, endUtf16: 3), throwsFormatException);
  });
}
