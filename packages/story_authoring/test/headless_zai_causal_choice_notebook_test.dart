// Runs the same source-reviewed causal RPG checks as Flutter on ordinary
// Dart only. Source evidence and editorial notebooks must have NO UI API.
import 'package:story_authoring/story_authoring.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

BookSourceIndex _index([String edition = '']) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Сказка о ключе $edition',
      author: 'ПРИВАТНЫЙ АВТОР НЕ ПЕРЕДАВАТЬ',
      chapters: [
        'Герда вошла. Кай открыл дверь. Герда вернулась. '
            'Герда держала ключ.',
        'Старик рассказал тайну. Герда узнала тайну.',
      ],
    ));

SemanticCandidate _suggest(BookSourceIndex index, int chunk,
    SemanticCategory category, String quote, String label) {
  final source = index.chunks[chunk];
  final offset = source.text.indexOf(quote);
  expect(offset, greaterThanOrEqualTo(0));
  return SemanticCandidate.propose(
    index, source, category: category,
    startUtf16: source.startUtf16 + offset,
    endUtf16: source.startUtf16 + offset + quote.length,
    label: label, uncertainty: 'Рассказчик может быть ненадёжен',
  );
}

({ZaiWindowReviewQueue queue, Map<String, SemanticCandidate> items})
    _fixture() {
  final index = _index();
  final m = <String, SemanticCandidate>{
    'a': _suggest(index, 0, SemanticCategory.event,
        'Герда вошла.', 'Герда вошла'),
    'b': _suggest(index, 0, SemanticCategory.event,
        'Кай открыл дверь.', 'Кай открыл дверь'),
    'c': _suggest(index, 0, SemanticCategory.event,
        'Герда вернулась.', 'Герда вернулась'),
    'npc': _suggest(index, 0, SemanticCategory.character,
        'Герда', 'Герда'),
    'fact': _suggest(index, 0, SemanticCategory.fact,
        'Герда держала ключ.', 'Герда держала ключ'),
    'd': _suggest(index, 1, SemanticCategory.event,
        'Старик рассказал тайну.', 'Старик рассказал тайну'),
    'future': _suggest(index, 1, SemanticCategory.fact,
        'Герда узнала тайну.', 'Герда узнала тайну'),
  };
  var queue = ZaiWindowReviewQueue.empty(index);
  expect(queue.windows.length, 2);
  for (var i = 0; i < 2; i++) {
    final candidates = m.values
        .where((v) => v.chunkId == index.chunks[i].id).toList();
    queue = queue.record(i, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: SemanticPreviewWireContract.providerId,
        providerVersion: SemanticPreviewWireContract.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [index.chunks[i].id], candidates: candidates,
      ),
      totalSuggestions: candidates.length,
      rejectedCount: 0, rejectedNonRussian: 0,
    ));
    for (final item in candidates) {
      queue = queue.decide(item.id, ZaiEditorialDecision.keepForReview);
    }
  }
  return (queue: queue, items: m);
}

ZaiSourceSceneBoard _board(ZaiWindowReviewQueue queue,
    Map<String, SemanticCandidate> m) {
  var b = ZaiSourceSceneBoard.empty(
      ZaiCrossWindowEvidenceGraph.fromQueue(queue));
  for (final name in ['a', 'b', 'c', 'd']) {
    b = b.addScene([m[name]!.id],
        'Черновая сцена $name', 'Редакторская заметка о событии.');
  }
  return b;
}

void main() {
  test('explicit branching reuses real M2c state simulator; no canon',
      () {
    final f = _fixture();
    final board = _board(f.queue, f.items);
    final a = board.scenes[0].id;
    final b = board.scenes[1].id;
    final c = board.scenes[2].id;
    var n = ZaiCausalChoiceNotebook.empty(board).addFlag('has_key');
    n = n.addChoice(from: a, to: b,
        label: 'Взять ключ и открыть дверь',
        reason: 'Редактор добавляет проверяемое игровое действие.',
        adds: ['has_key']);
    n = n.addChoice(from: a, to: c,
        label: 'Уйти без ключа',
        reason: 'Игрок может отказаться от предмета и изменить исход.');
    expect(n.choices, hasLength(2));
    expect(n.flags, ['has_key']);
    expect(n.canPublishBookworld, false);
    expect(n.hasVerifiedCausality, false);
    expect(n.choices.every((c) => !c.isVerifiedCausality), true);

    final preview = n.toM2cStructuralPreview();
    expect(preview.canPublishBookworld, false);
    expect(preview.rights, PreparationRights.unknown);
    expect(preview.scenes.every((s) =>
        s.origin == DraftSceneOrigin.explicitAdaptation &&
        s.assertionIds.isEmpty), true);
    expect(preview.scenes.first.text, contains('Редакторский план:'));
    expect(preview.scenes.first.text, isNot(contains('Герда вошла.')));
    final e = SourceEvidenceGraph.empty(f.queue.index);
    final catalog = SourceSemanticCatalog.checked(
        f.queue.index, e, const []);
    // The preview is structurally incomplete because the fourth source scene
    // is unreachable. That is detected by the unchanged M2c validator.
    expect(() => preview.validate(f.queue.index, e, catalog),
        throwsFormatException);
    n = n.addChoice(from: b, to: board.scenes[3].id,
        label: 'Продолжить путь после ключа',
        reason: 'Действие переводит игрока к следующей главе.',
        requires: ['has_key']);
    final report = ZaiCausalPreflight.assess(f.queue, n);
    expect(report.canPublishBookworld, false);
    expect(report.canStartPlayableRpg, false);
    expect(report.blockers, contains(ZaiCausalBlocker.futureChapterDisclosure));
    expect(report.isStructurallyCausal, true);
    expect(report.reachableEndings, 2);
    expect(report.reachableScenes, 4);
    expect(report.reachableStates, greaterThanOrEqualTo(4));
    expect(report.blockers,
        contains(ZaiCausalBlocker.missingSemanticAcceptance));
    expect(report.blockers,
        contains(ZaiCausalBlocker.notPublishedOrPlayable));
  });

  test('states, conditions and effects cannot conflict or reference unknown',
      () {
    final f = _fixture();
    final board = _board(f.queue, f.items);
    final from = board.scenes[0].id;
    final to = board.scenes[1].id;
    final n = ZaiCausalChoiceNotebook.empty(board)
        .addFlag('has_key', active: true);
    expect(n.initiallyActive, ['has_key']);
    expect(n.setInitiallyActive('has_key', false).initiallyActive, isEmpty);
    expect(() => n.addFlag('has_key'), throwsFormatException);
    expect(() => n.addFlag('НЕвалидный'), throwsFormatException);
    expect(() => n.addChoice(from: from, to: to, label: 'Открыть дверь',
        reason: 'Неизвестное состояние запрещено.',
        requires: ['other']), throwsFormatException);
    expect(() => n.addChoice(from: from, to: to, label: 'Открыть дверь',
        reason: 'Противоречит условиям.',
        requires: ['has_key'], forbids: ['has_key']),
        throwsFormatException);
    expect(() => n.addChoice(from: from, to: to, label: 'Открыть дверь',
        reason: 'Противоречит эффектам.',
        adds: ['has_key'], removes: ['has_key']),
        throwsFormatException);
    expect(() => n.addChoice(from: 'forged', to: to,
        label: 'Сделать ход', reason: 'Из несуществующей сцены.'),
        throwsFormatException);
    expect(() => n.addChoice(from: from, to: to,
        label: 'Да', reason: 'Слишком короткий текст.'), throwsFormatException);
    final saved = n.addChoice(from: from, to: to,
        label: 'Открыть дверь',
        reason: 'Ветвление требует наличия ключа.',
        requires: ['has_key']);
    expect(() => saved.removeFlag('has_key'), throwsFormatException);
    expect(() => saved.addChoice(from: from, to: to,
        label: 'Открыть дверь',
        reason: 'Повтор другого объяснения.',
        requires: ['has_key']), throwsFormatException);
    final removed = saved.removeChoice(saved.choices.first.id);
    expect(removed.removeFlag('has_key').flags, isEmpty);
  });

  test('NPC disclosure must be backed by two citations already available '
      'in the originating chapter, never future knowledge', () {
    final f = _fixture();
    final board = _board(f.queue, f.items);
    final start = board.scenes.first.id;
    final to = board.scenes[1].id;
    final n = ZaiCausalChoiceNotebook.empty(board);
    expect(() => n.addChoice(from: start, to: to,
        label: 'Спросить Герду', reason: 'Проверить слова персонажа.',
        npcFindingId: f.items['npc']!.id), throwsFormatException);
    expect(() => n.addChoice(from: start, to: to,
        label: 'Спросить Герду', reason: 'Нельзя знать будущую тайну.',
        npcFindingId: f.items['npc']!.id,
        knowledgeFindingId: f.items['future']!.id),
        throwsFormatException);
    final withPair = n.addChoice(from: start, to: to,
        label: 'Спросить Герду о ключе',
        reason: 'Редактор проверяет, знает ли она о найденном ключе.',
        npcFindingId: f.items['npc']!.id,
        knowledgeFindingId: f.items['fact']!.id);
    expect(withPair.choices.single.knowsThisFact, false);
    expect(withPair.establishesNpcKnowledge, false);
    final report = ZaiCausalPreflight.assess(f.queue, withPair);
    expect(report.blockers,
        contains(ZaiCausalBlocker.npcKnowledgeUnverified));
  });

  test('conditional dead states and closed loops are rejected by M2c',
      () {
    final f = _fixture();
    final board = _board(f.queue, f.items);
    final n = ZaiCausalChoiceNotebook.empty(board)
        .addFlag('key');
    final loop = n.addChoice(
        from: board.scenes[0].id, to: board.scenes[1].id,
        label: 'Начать путь',
        reason: 'Пример недопустимой цепочки без концовок.')
        .addChoice(
        from: board.scenes[1].id, to: board.scenes[0].id,
        label: 'Вернуться назад',
        reason: 'Цикл не приводит к игровому результату.');
    final report = ZaiCausalPreflight.assess(f.queue, loop);
    expect(report.isStructurallyCausal, false);
    expect(report.blockers,
        contains(ZaiCausalBlocker.causalSimulationFailed));
    final blocked = n.addChoice(
        from: board.scenes[0].id, to: board.scenes[1].id,
        label: 'Войти с ключом',
        reason: 'Условие не выполняется в начальном состоянии.',
        requires: ['key']);
    expect(ZaiCausalPreflight.assess(f.queue, blocked).blockers,
        contains(ZaiCausalBlocker.causalSimulationFailed));
  });

  test('canonical checkpoint roundtrip is source-lock, private and '
      'tamper proof even if checksum is recomputed', () {
    final f = _fixture();
    final board = _board(f.queue, f.items);
    final n = ZaiCausalChoiceNotebook.empty(board)
        .addFlag('key')
        .addChoice(from: board.scenes[0].id, to: board.scenes[1].id,
          label: 'Зайти в комнату', reason: 'Явный личный вариант игрока.',
          adds: ['key']);
    final encoded = n.encode();
    expect(encoded, isNot(contains('ПРИВАТНЫЙ АВТОР НЕ ПЕРЕДАВАТЬ')));
    expect(encoded, isNot(contains('Герда вошла.')));
    expect(ZaiCausalChoiceNotebook.decode(board, encoded).encode(),
        encoded);
    expect(() => ZaiCausalChoiceNotebook.decode(board, '$encoded '),
        throwsFormatException);
    final changed = jsonDecode(encoded) as Map<String, dynamic>;
    final payload = changed['payload'] as Map<String, dynamic>;
    (payload['choices'] as List).first['to_scene_id'] = 'forged';
    changed['sha256'] = sha256.convert(
        utf8.encode(jsonEncode(payload))).toString();
    expect(() => ZaiCausalChoiceNotebook.decode(board,
        jsonEncode(changed)), throwsFormatException);
    final otherBoard = board.moveScene(board.scenes[2].id, 0);
    expect(() => ZaiCausalChoiceNotebook.decode(otherBoard, encoded),
        throwsFormatException);
    final revokedQueue = f.queue.decide(
        f.items['a']!.id, ZaiEditorialDecision.rejected);
    final revokedGraph = ZaiCrossWindowEvidenceGraph.fromQueue(revokedQueue);
    expect(() => ZaiSourceSceneBoard.decode(
        revokedGraph, board.encode()), throwsFormatException);
    expect(() => ZaiCausalChoiceNotebook.decode(board,
        'X' * (ZaiCausalChoiceNotebook.maxUtf8Bytes + 1)),
        throwsFormatException);
    expect(n.board.encode(), board.encode());
  });

  test('unknown rights, unresolved identity and empty real-book review '
      'never unlock RPG', () {
    final index = _index();
    final queue = ZaiWindowReviewQueue.empty(index);
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    final board = ZaiSourceSceneBoard.empty(graph);
    final choices = ZaiCausalChoiceNotebook.empty(board);
    final result = ZaiCausalPreflight.assess(
      queue, choices,
      consistency: ZaiEditorialConsistencyNotebook.empty(graph),
    );
    expect(result.canCompileBookworld, false);
    expect(result.canStartPlayableRpg, false);
    expect(result.blockers, contains(ZaiCausalBlocker.emptySourceScenes));
    expect(result.blockers, contains(ZaiCausalBlocker.unfinishedSourceReview));
    expect(result.isStructurallyCausal, false);
    expect(choices.toM2cStructuralPreview, throwsFormatException);
  });
}
