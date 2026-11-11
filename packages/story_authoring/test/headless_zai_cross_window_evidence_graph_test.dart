// Runs the same source-reviewed causal RPG checks as Flutter on ordinary
// Dart only. Source evidence and editorial notebooks must have NO UI API.
import 'package:story_authoring/story_authoring.dart';

import 'dart:convert';

import 'package:test/test.dart';

BookSourceIndex _index([String last = 'Кай открыл дверь. Герда побежала.']) {
  return BookSourceIndexer.index(ImportedBook(
    title: 'Сказка о Кае',
    author: 'Только локально',
    chapters: [
      'Кай вошёл в дом. Герда ждала.',
      'Кай нашёл ключ. Наступил вечер.',
      last,
    ],
    structuredChapters: [
      const BookChapter(id: 'one', blocks: [
        BookBlock(kind: BookBlockKind.paragraph,
            text: 'Кай вошёл в дом. Герда ждала.'),
      ]),
      const BookChapter(id: 'two', blocks: [
        BookBlock(kind: BookBlockKind.paragraph,
            text: 'Кай нашёл ключ. Наступил вечер.'),
      ]),
      BookChapter(id: 'three', blocks: [
        BookBlock(kind: BookBlockKind.paragraph, text: last),
      ]),
    ],
  ));
}

SemanticCandidate _candidate(BookSourceIndex index, int position,
    SemanticCategory category, String quote, String label) {
  final chunk = index.chunks[position];
  final offset = chunk.text.indexOf(quote);
  expect(offset, isNonNegative);
  return SemanticCandidate.propose(
    index, chunk,
    category: category,
    startUtf16: chunk.startUtf16 + offset,
    endUtf16: chunk.startUtf16 + offset + quote.length,
    label: label,
    uncertainty: 'Нужно подтвердить точный контекст',
  );
}

ZaiSemanticPreviewResult _preview(BookSourceIndex index, int position,
    List<SemanticCandidate> candidates) {
  return ZaiSemanticPreviewResult(
    batch: SemanticCandidateBatch(
      providerId: SemanticPreviewWireContract.providerId,
      providerVersion: SemanticPreviewWireContract.providerVersion,
      sourceFingerprint: index.sourceFingerprint,
      chunkIds: [index.chunks[position].id],
      candidates: candidates,
    ),
    totalSuggestions: candidates.length,
    rejectedCount: 0,
    rejectedNonRussian: 0,
  );
}

({ZaiWindowReviewQueue queue, List<SemanticCandidate> items}) _reviewed() {
  final index = _index();
  final items = [
    _candidate(index, 0, SemanticCategory.character, 'Кай', 'Кай'),
    _candidate(index, 0, SemanticCategory.event,
        'Кай вошёл в дом.', 'Кай покинул двор'),
    _candidate(index, 0, SemanticCategory.fact,
        'Герда ждала.', 'Герда ждала Кая'),
    _candidate(index, 1, SemanticCategory.character, 'Кай', 'кай'),
    _candidate(index, 1, SemanticCategory.event,
        'Кай нашёл ключ.', 'Кай покинул двор'),
    _candidate(index, 1, SemanticCategory.state,
        'Наступил вечер.', 'Смена времени суток'),
    _candidate(index, 2, SemanticCategory.character, 'Кай', 'Кай'),
    _candidate(index, 2, SemanticCategory.event,
        'Кай открыл дверь.', 'Кай открыл дверь'),
    _candidate(index, 2, SemanticCategory.character, 'Герда', 'Герда'),
  ];
  var queue = ZaiWindowReviewQueue.empty(index);
  expect(queue.windows.length, 3);
  queue = queue.record(0, _preview(index, 0, items.sublist(0, 3)));
  queue = queue.record(1, _preview(index, 1, items.sublist(3, 6)));
  queue = queue.record(2, _preview(index, 2, items.sublist(6, 9)));
  for (final i in [0, 1, 3, 4, 6, 7, 8]) {
    queue = queue.decide(
        items[i].id, ZaiEditorialDecision.keepForReview);
  }
  queue = queue.decide(items[2].id, ZaiEditorialDecision.rejected);
  // State at index 5 intentionally remains undecided.
  return (queue: queue, items: items);
}

void main() {
  test('cross-window identities are only possible same-name hints; '
      'events never merged even with identical labels', () {
    final data = _reviewed();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(data.queue);
    expect(graph.reviewed.length, 7);
    expect(graph.possibleNames.length, 1);
    final kai = graph.possibleNames.single;
    expect(kai.displayName, 'Кай');
    expect(kai.findings.length, 3);
    expect(kai.sameIdentityProven, false);
    expect(kai.findings.map((e) => e.windowPosition), [0, 1, 2]);
    expect(graph.textOrderedEvents.length, 3);
    expect(graph.textOrderedEvents.map((e) => e.label).toList(),
        ['Кай покинул двор', 'Кай покинул двор', 'Кай открыл дверь']);
    expect(graph.statedFactsAndStates, isEmpty);
    expect(graph.hasProvenCausality, false);
    expect(graph.hasVerifiedStoryChronology, false);
    expect(graph.canPublishBookworld, false);
    expect(graph.reviewed.every((e) => !e.confirmed && !e.knownStoryTime),
        true);
    // Every quote is an exact substring with unchanged UTF-16 source location.
    for (final entry in graph.reviewed) {
      final chunk = data.queue.index.chunks.firstWhere(
          (c) => c.id == entry.candidate.chunkId);
      expect(chunk.text.substring(
          entry.candidate.startUtf16 - chunk.startUtf16,
          entry.candidate.endUtf16 - chunk.startUtf16), entry.quote);
    }
  });

  test('no automatic collapse of same label within one window', () {
    final index = _index();
    final first = _candidate(
        index, 0, SemanticCategory.character, 'Кай', 'Кай');
    final q = ZaiWindowReviewQueue.empty(index)
        .record(0, _preview(index, 0, [first]))
        .decide(first.id, ZaiEditorialDecision.keepForReview);
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(q);
    expect(graph.possibleNames, isEmpty);
  });

  test('manual identity and cause hypotheses persist with two source anchors',
      () {
    final data = _reviewed();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(data.queue);
    var notebook = ZaiCrossWindowLinkNotebook.empty(graph);
    final initial = notebook.encode();
    expect(initial, isNot(contains('Только локально')));
    notebook = notebook.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[0].id, data.items[3].id);
    notebook = notebook.propose(ZaiProposedLinkKind.possibleCause,
        data.items[1].id, data.items[4].id);
    expect(notebook.links.length, 2);
    expect(notebook.allRelationsProvisional, true);
    expect(notebook.canPublishBookworld, false);
    expect(notebook.links.every((e) => !e.proven), true);
    final raw = notebook.encode();
    final replay = ZaiCrossWindowLinkNotebook.decode(graph, raw);
    expect(replay.encode(), raw);
    expect(replay.links.length, 2);
    expect(replay.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[3].id, data.items[0].id).links.length, 2);
    final after = replay.remove(replay.links.first.id);
    expect(after.links.length, 1);
    expect(ZaiCrossWindowLinkNotebook.decode(graph, after.encode())
        .links.length, 1);
  });

  test('reject same-window, mixed type, backward causation, forgery and '
      'stale editorial decisions without destroying M2f3a queue', () {
    final data = _reviewed();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(data.queue);
    final blank = ZaiCrossWindowLinkNotebook.empty(graph);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[0].id, data.items[1].id), throwsFormatException);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[0].id, data.items[6].id), returnsNormally);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[0].id, data.items[8].id), returnsNormally);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleCause,
        data.items[4].id, data.items[1].id), throwsFormatException);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleCause,
        data.items[1].id, data.items[7].id), returnsNormally);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleCause,
        data.items[1].id, data.items[2].id), throwsFormatException);
    expect(() => blank.propose(ZaiProposedLinkKind.possibleCause,
        data.items[1].id, 'forged'), throwsFormatException);
    final withLink = blank.propose(ZaiProposedLinkKind.possibleIdentity,
        data.items[0].id, data.items[3].id);
    final raw = withLink.encode();
    final forged = jsonDecode(raw) as Map<String, dynamic>;
    (forged['payload'] as Map<String, dynamic>)['can_publish_bookworld'] = true;
    expect(() => ZaiCrossWindowLinkNotebook.decode(graph, jsonEncode(forged)),
        throwsFormatException);
    expect(() => ZaiCrossWindowLinkNotebook.decode(graph, raw + ' '),
        throwsFormatException);
    final queueWithoutDecision =
        data.queue.decide(data.items[3].id, ZaiEditorialDecision.rejected);
    final graphWithout = ZaiCrossWindowEvidenceGraph.fromQueue(
        queueWithoutDecision);
    expect(() => ZaiCrossWindowLinkNotebook.decode(graphWithout, raw),
        throwsFormatException);
    final anotherEdition = ZaiCrossWindowEvidenceGraph.fromQueue(
        ZaiWindowReviewQueue.empty(_index('Совершенно другая глава.')));
    expect(() => ZaiCrossWindowLinkNotebook.decode(anotherEdition, raw),
        throwsFormatException);
    expect(data.queue.encode(),
        ZaiWindowReviewQueue.decode(data.queue.index, data.queue.encode())
            .encode());
  });

  test('empty real-book context cannot invent graph or causal links', () {
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(
        ZaiWindowReviewQueue.empty(_index()));
    expect(graph.reviewed, isEmpty);
    expect(graph.possibleNames, isEmpty);
    expect(graph.textOrderedEvents, isEmpty);
    expect(ZaiCrossWindowLinkNotebook.empty(graph).links, isEmpty);
  });
}
