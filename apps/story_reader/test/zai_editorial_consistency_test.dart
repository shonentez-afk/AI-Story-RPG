import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index([String extra = '']) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Русская сказка $extra',
      author: 'НЕ СОХРАНЯТЬ И НЕ ОТПРАВЛЯТЬ',
      chapters: [
        'Кай пришёл. Кай живёт в деревне. Герда ждала.',
        'Снежный король сказал: Кай не живёт в деревне. '
            'Снежный король ушёл.',
        'Герда вернулась. Друг Кая помог Герде.',
      ],
      structuredChapters: const [
        BookChapter(id: 'first', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Кай пришёл. Кай живёт в деревне. Герда ждала.'),
        ]),
        BookChapter(id: 'second', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Снежный король сказал: Кай не живёт в деревне. '
                  'Снежный король ушёл.'),
        ]),
        BookChapter(id: 'third', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Герда вернулась. Друг Кая помог Герде.'),
        ]),
      ],
    ));

SemanticCandidate _candidate(BookSourceIndex index, int i,
    SemanticCategory category, String quote, String label) {
  final chunk = index.chunks[i];
  final offset = chunk.text.indexOf(quote);
  expect(offset, greaterThanOrEqualTo(0));
  return SemanticCandidate.propose(
    index, chunk,
    category: category,
    startUtf16: chunk.startUtf16 + offset,
    endUtf16: chunk.startUtf16 + offset + quote.length,
    label: label,
    uncertainty: 'Проверить время и достоверность источника',
  );
}

ZaiSemanticPreviewResult _batch(
    BookSourceIndex index, int i, List<SemanticCandidate> candidates) =>
    ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [index.chunks[i].id],
        candidates: candidates,
      ),
      totalSuggestions: candidates.length,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    );

({ZaiWindowReviewQueue queue, Map<String, SemanticCandidate> items})
_fixture() {
  final index = _index();
  final items = <String, SemanticCandidate>{
    'kay': _candidate(index, 0, SemanticCategory.character, 'Кай', 'Кай'),
    'arrival': _candidate(index, 0, SemanticCategory.event,
        'Кай пришёл.', 'Кай появился'),
    'isHere': _candidate(index, 0, SemanticCategory.fact,
        'Кай живёт в деревне.', 'Кай живёт в деревне'),
    'gerda': _candidate(index, 0, SemanticCategory.character, 'Герда', 'Герда'),
    'unverified': _candidate(index, 0, SemanticCategory.fact,
        'Герда ждала.', 'Герда ожидала'),
    'king': _candidate(index, 1, SemanticCategory.character,
        'Снежный король', 'Снежный король'),
    'notHere': _candidate(index, 1, SemanticCategory.fact,
        'Кай не живёт в деревне.', 'Кай отсутствует'),
    'departure': _candidate(index, 1, SemanticCategory.event,
        'Снежный король ушёл.', 'Король ушёл'),
    'return': _candidate(index, 2, SemanticCategory.event,
        'Герда вернулась.', 'Герда вернулась'),
    'friend': _candidate(index, 2, SemanticCategory.character,
        'Друг Кая', 'Друг Кая'),
    'gerda2': _candidate(index, 2, SemanticCategory.character,
        'Герде', 'Герда'),
    'rejected': _candidate(index, 2, SemanticCategory.fact,
        'Друг Кая помог Герде.', 'Друг помог'),
  };
  var queue = ZaiWindowReviewQueue.empty(index);
  for (var i = 0; i < 3; i++) {
    final sameWindow = items.values
        .where((item) => item.chunkId == index.chunks[i].id).toList();
    queue = queue.record(i, _batch(index, i, sameWindow));
  }
  for (final entry in items.entries) {
    if (entry.key == 'rejected') {
      queue = queue.decide(entry.value.id, ZaiEditorialDecision.rejected);
    } else if (entry.key != 'unverified') {
      queue = queue.decide(
          entry.value.id, ZaiEditorialDecision.keepForReview);
    }
  }
  return (queue: queue, items: items);
}

ZaiCrossWindowEvidenceGraph _graph() =>
    ZaiCrossWindowEvidenceGraph.fromQueue(_fixture().queue);

String _id(Map<String, SemanticCandidate> m, String key) => m[key]!.id;

void main() {
  test('real source quotes create only cautious possible discrepancy hints',
      () {
    final setup = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final hints = ZaiConsistencyHints.reviewCues(graph);
    expect(hints, hasLength(1));
    expect(hints.single.first.quote, 'Кай живёт в деревне.');
    expect(hints.single.second.quote, 'Кай не живёт в деревне.');
    expect(hints.single.proven, false);
    expect(graph.reviewed.any((e) =>
        e.id == setup.items['rejected']!.id), false);
    expect(graph.reviewed.any((e) =>
        e.id == setup.items['unverified']!.id), false);
    expect(graph.hasVerifiedStoryChronology, false);
  });

  test('four explicit review question types roundtrip with anchored sources',
      () {
    final setup = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final m = setup.items;
    var notebook = ZaiEditorialConsistencyNotebook.empty(graph);
    notebook = notebook.propose(
        ZaiConsistencyKind.possibleAlias, _id(m, 'kay'), _id(m, 'king'),
        'Проверить, относится ли прозвище к этому герою.');
    notebook = notebook.propose(
        ZaiConsistencyKind.possibleRelationship, _id(m, 'kay'),
        _id(m, 'gerda'), 'Проверить указанные в книге отношения.');
    notebook = notebook.propose(
        ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'isHere'), _id(m, 'notHere'),
        'Могли ли оба высказывания быть правдой в разное время?');
    // Flashback: story order MAY be opposite of document order.
    notebook = notebook.propose(
        ZaiConsistencyKind.possibleBefore, _id(m, 'return'),
        _id(m, 'arrival'), 'Проверить, не является ли прибытие воспоминанием.');
    expect(notebook.questions, hasLength(4));
    expect(notebook.establishesAliases, false);
    expect(notebook.establishesChronology, false);
    expect(notebook.establishesContradictions, false);
    expect(notebook.canPublishBookworld, false);
    expect(notebook.questions.every((e) => !e.proven), true);
    final encoded = notebook.encode();
    expect(encoded, isNot(contains('НЕ СОХРАНЯТЬ И НЕ ОТПРАВЛЯТЬ')));
    expect(encoded, isNot(contains('Кай живёт в деревне.')));
    final decoded = ZaiEditorialConsistencyNotebook.decode(graph, encoded);
    expect(decoded.encode(), encoded);
    expect(decoded.questions, hasLength(4));
    expect(decoded.propose(ZaiConsistencyKind.possibleAlias,
        _id(m, 'king'), _id(m, 'kay'), 'Другое обоснование.').encode(),
        encoded);
    final removed = decoded.remove(decoded.questions.first.id);
    expect(removed.questions.length, 3);
    expect(ZaiEditorialConsistencyNotebook.decode(
        graph, removed.encode()).questions, hasLength(3));
  });

  test('provisional timeline rejects direct and transitive cycles', () {
    final setup = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final m = setup.items;
    var book = ZaiEditorialConsistencyNotebook.empty(graph);
    book = book.propose(ZaiConsistencyKind.possibleBefore,
        _id(m, 'departure'), _id(m, 'arrival'),
        'Возможная ретроспектива в начале истории.');
    book = book.propose(ZaiConsistencyKind.possibleBefore,
        _id(m, 'arrival'), _id(m, 'return'),
        'Возможное дальнейшее событие истории.');
    expect(() => book.propose(ZaiConsistencyKind.possibleBefore,
        _id(m, 'return'), _id(m, 'departure'),
        'Проверить ещё один момент сюжета.'), throwsFormatException);
    expect(() => book.propose(ZaiConsistencyKind.possibleBefore,
        _id(m, 'arrival'), _id(m, 'departure'),
        'Противоположный порядок.'), throwsFormatException);
    expect(book.questions.length, 2);
  });

  test('wrong types, duplicate names, hidden evidence and weak reason fail',
      () {
    final setup = _fixture();
    final m = setup.items;
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final n = ZaiEditorialConsistencyNotebook.empty(graph);
    expect(() => n.propose(ZaiConsistencyKind.possibleAlias,
        _id(m, 'gerda'), _id(m, 'gerda2'),
        'Разные лица с одним именем?'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleAlias,
        _id(m, 'kay'), _id(m, 'arrival'),
        'Смешаны персонаж и событие.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleRelationship,
        _id(m, 'king'), _id(m, 'notHere'),
        'Персонаж и утверждение.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'arrival'), _id(m, 'departure'),
        'Это два разных события.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleBefore,
        _id(m, 'kay'), _id(m, 'departure'),
        'Персонаж не есть событие.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'isHere'), _id(m, 'rejected'),
        'Отклонённый отрывок.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'isHere'), _id(m, 'unverified'),
        'Непроверенная цитата.'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'isHere'), _id(m, 'notHere'), 'мало'), throwsFormatException);
    expect(() => n.propose(ZaiConsistencyKind.possibleDiscrepancy,
        _id(m, 'isHere'), _id(m, 'notHere'), 'Причина\u0000контроль'),
        throwsFormatException);
  });

  test('edition changes, revoked decisions and recomputed tampering fail shut',
      () {
    final setup = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final m = setup.items;
    final saved = ZaiEditorialConsistencyNotebook.empty(graph)
        .propose(ZaiConsistencyKind.possibleDiscrepancy,
          _id(m, 'isHere'), _id(m, 'notHere'),
          'Разные версии сведений о деревне.').encode();
    expect(ZaiEditorialConsistencyNotebook.decode(graph, saved).encode(), saved);
    expect(() => ZaiEditorialConsistencyNotebook.decode(graph, '$saved '),
        throwsFormatException);
    final tampered = jsonDecode(saved) as Map<String, dynamic>;
    (tampered['payload'] as Map<String, dynamic>)['can_publish_bookworld'] = true;
    expect(() => ZaiEditorialConsistencyNotebook.decode(
        graph, jsonEncode(tampered)), throwsFormatException);
    final without = setup.queue.decide(
        _id(m, 'notHere'), ZaiEditorialDecision.rejected);
    final outdatedGraph = ZaiCrossWindowEvidenceGraph.fromQueue(without);
    expect(() => ZaiEditorialConsistencyNotebook.decode(
        outdatedGraph, saved), throwsFormatException);
    final foreign = ZaiCrossWindowEvidenceGraph.fromQueue(
        ZaiWindowReviewQueue.empty(_index('new edition')));
    expect(() => ZaiEditorialConsistencyNotebook.decode(
        foreign, saved), throwsFormatException);
    expect(() => ZaiEditorialConsistencyNotebook.decode(
        graph, 'a' * (ZaiEditorialConsistencyNotebook.maxBytes + 1)),
        throwsFormatException);
    expect(setup.queue.encode(), ZaiWindowReviewQueue.decode(
        setup.queue.index, setup.queue.encode()).encode());
  });

  test('long actual-book source with no manually retained facts invents nothing',
      () {
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(
        ZaiWindowReviewQueue.empty(_index()));
    expect(ZaiConsistencyHints.reviewCues(graph), isEmpty);
    final notebook = ZaiEditorialConsistencyNotebook.empty(graph);
    expect(notebook.questions, isEmpty);
    expect(notebook.canPublishBookworld, false);
    expect(ZaiEditorialConsistencyNotebook.decode(
        graph, notebook.encode()).questions, isEmpty);
  });
}
