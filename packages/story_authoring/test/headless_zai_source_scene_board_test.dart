// Runs the same source-reviewed causal RPG checks as Flutter on ordinary
// Dart only. Source evidence and editorial notebooks must have NO UI API.
import 'package:story_authoring/story_authoring.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

BookSourceIndex _index([String suffix = '']) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Русская сказка$suffix',
      author: 'Личный файл — не публиковать',
      chapters: [
        'Кай вошёл в дом. Герда открыла дверь. Герда была здесь.',
        'Старик сказал, что мост закрыт. Кай вернулся позднее.',
        'Герда ушла из дома. Мост снова открыт.',
      ],
      structuredChapters: const [
        BookChapter(id: 'first', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Кай вошёл в дом. Герда открыла дверь. Герда была здесь.'),
        ]),
        BookChapter(id: 'second', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Старик сказал, что мост закрыт. Кай вернулся позднее.'),
        ]),
        BookChapter(id: 'third', blocks: [
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Герда ушла из дома. Мост снова открыт.'),
        ]),
      ],
    ));

SemanticCandidate _candidate(BookSourceIndex index, int position,
    SemanticCategory category, String quote, String label) {
  final chunk = index.chunks[position];
  final at = chunk.text.indexOf(quote);
  expect(at, greaterThanOrEqualTo(0));
  return SemanticCandidate.propose(
    index, chunk,
    category: category,
    startUtf16: chunk.startUtf16 + at,
    endUtf16: chunk.startUtf16 + at + quote.length,
    label: label, uncertainty: 'Нужна контекстная редакторская проверка',
  );
}

({ZaiWindowReviewQueue queue, Map<String, SemanticCandidate> data})
    _fixture() {
  final index = _index();
  final data = <String, SemanticCandidate>{
    'enter': _candidate(index, 0, SemanticCategory.event,
        'Кай вошёл в дом.', 'Кай вошёл'),
    'door': _candidate(index, 0, SemanticCategory.event,
        'Герда открыла дверь.', 'Герда открыла дверь'),
    'state': _candidate(index, 0, SemanticCategory.state,
        'Герда была здесь.', 'Герда присутствовала'),
    'reported': _candidate(index, 1, SemanticCategory.fact,
        'Старик сказал, что мост закрыт.', 'Мост закрыт'),
    'return': _candidate(index, 1, SemanticCategory.event,
        'Кай вернулся позднее.', 'Кай вернулся'),
    'leave': _candidate(index, 2, SemanticCategory.event,
        'Герда ушла из дома.', 'Герда ушла'),
    'unknown': _candidate(index, 2, SemanticCategory.fact,
        'Мост снова открыт.', 'Мост открыт'),
  };
  var queue = ZaiWindowReviewQueue.empty(index);
  expect(queue.windows.length, 3);
  for (var position = 0; position < 3; position++) {
    final selected = data.values.where(
        (item) => item.chunkId == index.chunks[position].id).toList();
    queue = queue.record(position, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: SemanticPreviewWireContract.providerId,
        providerVersion: SemanticPreviewWireContract.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [index.chunks[position].id],
        candidates: selected,
      ),
      totalSuggestions: selected.length,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
    for (final item in selected) {
      if (item.id != data['unknown']!.id) {
        queue = queue.decide(item.id, ZaiEditorialDecision.keepForReview);
      }
    }
  }
  return (queue: queue, data: data);
}

String _id(Map<String, SemanticCandidate> data, String name) =>
    data[name]!.id;

void main() {
  test('scene board uses multiple exact events in ONE chapter, manual '
      'order and source context; never promotes canon', () {
    final fixture = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(fixture.queue);
    final data = fixture.data;
    var board = ZaiSourceSceneBoard.empty(graph);
    expect(board.scenes, isEmpty);
    expect(board.canPublishBookworld, false);
    board = board.addScene([
      _id(data, 'enter'), _id(data, 'door'),
    ], 'Встреча героев', 'Требуется проверить время встречи.');
    board = board.addScene([
      _id(data, 'return'),
    ], 'Возвращение Кая', 'Проверить обстоятельства возвращения.');
    board = board.addScene([
      _id(data, 'leave'),
    ], 'Уход Герды', 'Это только предположение о сцене.');
    board = board.noteContext(
        _id(data, 'reported'), ZaiClaimContext.characterSpeech,
        'Слова старика не обязательно соответствуют миру книги.');
    expect(board.scenes, hasLength(3));
    expect(board.scenes.first.eventIds, hasLength(2));
    expect(board.contexts, hasLength(1));
    expect(board.contexts.values.single.isVerifiedWorldTruth, false);
    expect(board.scenes.every((e) => !e.isPlayable && !e.hasVerifiedCausality),
        true);
    final raw = board.encode();
    expect(raw, isNot(contains('Личный файл — не публиковать')));
    expect(raw, isNot(contains('Герда открыла дверь.')));
    final restored = ZaiSourceSceneBoard.decode(graph, raw);
    expect(restored.encode(), raw);
    expect(restored.scenes[0].title, 'Встреча героев');
    expect(restored.scenes[0].chapterIndex, 0);
    expect(restored.contexts[_id(data, 'reported')]!.context,
        ZaiClaimContext.characterSpeech);
    final shifted = restored.moveScene(restored.scenes.last.id, 0);
    expect(shifted.scenes.first.title, 'Уход Герды');
    expect(shifted.scenes.last.title, 'Возвращение Кая');
    final without = shifted.removeScene(shifted.scenes.first.id);
    expect(without.scenes.length, 2);
    final cleared = without.removeContext(_id(data, 'reported'));
    expect(cleared.contexts, isEmpty);
    expect(board.encode(), raw);
  });

  test('scene source cannot cross chapter, reuse event or invent quote', () {
    final setup = _fixture();
    final board = ZaiSourceSceneBoard.empty(
        ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue));
    final e = setup.data;
    expect(() => board.addScene([
      _id(e, 'enter'), _id(e, 'return'),
    ], 'Ложная сцена', 'События из двух разных глав.'),
        throwsFormatException);
    expect(() => board.addScene([
      _id(e, 'enter'), _id(e, 'enter'),
    ], 'Ложная сцена', 'Повтор события в сцене.'),
        throwsFormatException);
    expect(() => board.addScene([
      _id(e, 'state'),
    ], 'Ложная сцена', 'Состояние вместо события.'),
        throwsFormatException);
    expect(() => board.addScene([
      _id(e, 'unknown'),
    ], 'Ложная сцена', 'Не оставлено на проверку.'),
        throwsFormatException);
    expect(() => board.addScene([
      'forged',
    ], 'Ложная сцена', 'Нет ссылки на исходный текст.'),
        throwsFormatException);
    expect(() => board.addScene([
      _id(e, 'enter'),
    ], 'А', 'Короткое название.'),
        throwsFormatException);
    expect(() => board.noteContext(
      _id(e, 'enter'), ZaiClaimContext.narratorText,
      'Событие не факт или состояние.'), throwsFormatException);
    expect(() => board.noteContext(
      _id(e, 'unknown'), ZaiClaimContext.unknown,
      'Неоставленная цитата не допускается.'), throwsFormatException);
    expect(() => board.noteContext(
      _id(e, 'reported'), ZaiClaimContext.narratorText,
      'мало'), throwsFormatException);
    final one = board.addScene([
      _id(e, 'enter'),
    ], 'Первый эпизод', 'Проверить цитату до компиляции.');
    expect(() => one.addScene([
      _id(e, 'enter'),
    ], 'Ещё один эпизод', 'Второе использование события.'),
        throwsFormatException);
    expect(() => one.moveScene('forged', 0), throwsFormatException);
  });

  test('preflight explains missing scenes, unreviewed citations, contradictions '
      'and cannot unlock unsupported BookWorld', () {
    final data = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(data.queue);
    final empty = ZaiSourceSceneBoard.empty(graph);
    final initial = ZaiScenePreflight.assess(data.queue, empty);
    expect(initial.canPublishBookworld, false);
    expect(initial.canStartPlayableRpg, false);
    expect(initial.eventCoverage, 0);
    expect(initial.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.noScenes));
    expect(initial.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.unreviewedCandidates));
    expect(initial.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.productionCompilerDisconnected));
    var draft = empty.addScene([
      _id(data.data, 'enter'), _id(data.data, 'door'),
    ], 'Сцена начала', 'Возможное начало книги.');
    draft = draft.addScene([
      _id(data.data, 'return'),
    ], 'Сцена возвращения', 'Вторая сцена по тексту.');
    draft = draft.addScene([
      _id(data.data, 'leave'),
    ], 'Сцена ухода', 'Третья сцена по тексту.');
    final chronology = ZaiEditorialConsistencyNotebook.empty(graph).propose(
      ZaiConsistencyKind.possibleBefore,
      _id(data.data, 'leave'), _id(data.data, 'enter'),
      'Возможно уход происходил до первой встречи.');
    final preflight = ZaiScenePreflight.assess(
        data.queue, draft, consistency: chronology);
    expect(preflight.sceneCount, 3);
    expect(preflight.totalEvents, 4);
    expect(preflight.coveredEvents, 4);
    expect(preflight.eventCoverage, 1.0);
    expect(preflight.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.sceneOrderVsProposedTimeline));
    expect(preflight.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.openConsistencyQuestions));
    expect(preflight.canStartPlayableRpg, false);
    final corrected = draft.moveScene(draft.scenes.last.id, 0);
    final withoutOrderConflict = ZaiScenePreflight.assess(
        data.queue, corrected, consistency: chronology);
    expect(withoutOrderConflict.findings
        .any((e) => e.issue ==
            ZaiSceneGateIssue.sceneOrderVsProposedTimeline), false);
    expect(withoutOrderConflict.canPublishBookworld, false);
  });

  test('tampering, swapped editions and revoked decisions fail closed', () {
    final fixture = _fixture();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(fixture.queue);
    final one = ZaiSourceSceneBoard.empty(graph).addScene([
      _id(fixture.data, 'enter'),
    ], 'Вступительная сцена', 'Проверить чтение отрывка.');
    final raw = one.encode();
    final forged = jsonDecode(raw) as Map<String, dynamic>;
    (forged['payload'] as Map<String, dynamic>)['can_publish_bookworld'] = true;
    expect(() => ZaiSourceSceneBoard.decode(graph, jsonEncode(forged)),
        throwsFormatException);
    final changed = jsonDecode(raw) as Map<String, dynamic>;
    final payload = changed['payload'] as Map<String, dynamic>;
    final scenes = payload['scenes'] as List<dynamic>;
    (scenes.first as Map<String, dynamic>)['event_ids'] = ['forged'];
    changed['sha256'] = sha256.convert(
        utf8.encode(jsonEncode(payload))).toString();
    expect(() => ZaiSourceSceneBoard.decode(graph, jsonEncode(changed)),
        throwsFormatException);
    expect(() => ZaiSourceSceneBoard.decode(graph, '$raw '),
        throwsFormatException);
    final revoked = ZaiCrossWindowEvidenceGraph.fromQueue(
        fixture.queue.decide(
          _id(fixture.data, 'enter'), ZaiEditorialDecision.rejected));
    expect(() => ZaiSourceSceneBoard.decode(revoked, raw),
        throwsFormatException);
    final different = ZaiCrossWindowEvidenceGraph.fromQueue(
        ZaiWindowReviewQueue.empty(_index(' - другая редакция')));
    expect(() => ZaiSourceSceneBoard.decode(different, raw),
        throwsFormatException);
    expect(() => ZaiSourceSceneBoard.decode(graph,
        'X' * (ZaiSourceSceneBoard.maxBytes + 1)), throwsFormatException);
    final restored = ZaiSourceSceneBoard.decode(graph, raw);
    expect(restored.scenes.single.eventIds.single,
        _id(fixture.data, 'enter'));
  });

  test('no AI-retained quotes on a real book cannot invent scenes or truth',
      () {
    final index = _index();
    final queue = ZaiWindowReviewQueue.empty(index);
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    final board = ZaiSourceSceneBoard.empty(graph);
    final report = ZaiScenePreflight.assess(queue, board);
    expect(board.scenes, isEmpty);
    expect(board.contexts, isEmpty);
    expect(report.totalEvents, 0);
    expect(report.canStartPlayableRpg, false);
    expect(report.findings.map((f) => f.issue),
        contains(ZaiSceneGateIssue.unfinishedWindows));
    expect(ZaiSourceSceneBoard.decode(graph, board.encode())
        .scenes, isEmpty);
  });
}
