import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_causal_choice_notebook.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:ai_story_reader/zai_source_scene_workbench_page.dart';
import 'package:ai_story_reader/zai_causal_choices_page.dart';
import 'package:ai_story_reader/zai_private_compilation_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

({ZaiWindowReviewQueue queue, ZaiSourceSceneBoard board,
    ZaiEditorialConsistencyNotebook consistency}) _setup() {
  final index = BookSourceIndexer.index(const ImportedBook(
    title: 'Ручная проверка развилок',
    author: 'НЕ ПУБЛИКОВАТЬ',
    chapters: [
      'Герда вошла. Кай открыл дверь. Герда ушла.',
      'Старик открыл тайну. Кай понял секрет.',
    ],
  ));
  var queue = ZaiWindowReviewQueue.empty(index);
  final events = <SemanticCandidate>[];
  for (var i = 0; i < 2; i++) {
    final chunk = index.chunks[i];
    final quotes = i == 0 ?
      ['Герда вошла.', 'Кай открыл дверь.', 'Герда ушла.'] :
      ['Старик открыл тайну.'];
    final batch = <SemanticCandidate>[];
    for (final quote in quotes) {
      final at = chunk.text.indexOf(quote);
      final c = SemanticCandidate.propose(index, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16 + at,
        endUtf16: chunk.startUtf16 + at + quote.length,
        label: quote,
        uncertainty: 'Проверка правил сюжета',
      );
      batch.add(c);
      events.add(c);
    }
    queue = queue.record(i, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [chunk.id],
        candidates: batch,
      ),
      totalSuggestions: batch.length,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
    for (final candidate in batch) {
      queue = queue.decide(
          candidate.id, ZaiEditorialDecision.keepForReview);
    }
  }
  final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
  var board = ZaiSourceSceneBoard.empty(graph);
  for (var i = 0; i < events.length; i++) {
    board = board.addScene([events[i].id], 'Сцена ${i + 1}',
        'Явный частный план по конкретной цитате.');
  }
  return (
    queue: queue,
    board: board,
    consistency: ZaiEditorialConsistencyNotebook.empty(graph),
  );
}

Future<void> _scroll(WidgetTester tester, Finder item,
    {double step = 130}) async {
  await tester.scrollUntilVisible(item, step,
      scrollable: find.byType(Scrollable).first, maxScrolls: 70);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('private choice is not saved without checkbox, '
      'has two source citations and never enables BookWorld', (tester) async {
    final f = _setup();
    final repo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiCausalChoicesPage(
        queue: f.queue, board: f.board, consistency: f.consistency,
        repository: repo,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-causal-title')), findsOneWidget);
    expect(find.textContaining('Старик открыл тайну'), findsNothing);

    final from = find.byKey(const ValueKey('zai-causal-from-none-safe'));
    await _scroll(tester, from);
    await tester.tap(from);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Гл. 1 · Сцена 1').last);
    await tester.pumpAndSettle();
    final to = find.byKey(const ValueKey('zai-causal-to-none-safe'));
    await _scroll(tester, to);
    await tester.tap(to);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Гл. 1 · Сцена 2').last);
    await tester.pumpAndSettle();

    final label = find.byKey(const Key('zai-causal-label-input'));
    await _scroll(tester, label);
    await tester.enterText(label, 'Открыть дверь самостоятельно');
    final reason = find.byKey(const Key('zai-causal-reason-input'));
    await _scroll(tester, reason);
    await tester.enterText(reason, 'Явный придуманный выбор для частной версии.');
    final add = find.byKey(const Key('zai-causal-add-choice'));
    await _scroll(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('zai-causal-consent-save'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.textContaining('Герда вошла.'), findsWidgets);
    expect(find.textContaining('Кай открыл дверь.'), findsWidgets);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repo.read(f.queue.index.sourceFingerprint), isNull);

    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-causal-consent-check')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final raw = await repo.read(f.queue.index.sourceFingerprint);
    expect(raw, isNotNull);
    expect(raw, isNot(contains('НЕ ПУБЛИКОВАТЬ')));
    final saved = ZaiCausalChoiceNotebook.decode(f.board, raw!);
    expect(saved.choices, hasLength(1));
    expect(saved.choices.single.canPublishBookworld, false);
    expect(saved.canStartPlayableRpg, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('future chapter titles remain masked until specific consent',
      (tester) async {
    final f = _setup();
    final repo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiCausalChoicesPage(
        queue: f.queue, board: f.board, consistency: f.consistency,
        repository: repo,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Старик открыл тайну'), findsNothing);
    final reveal = find.byKey(const Key('zai-causal-reveal'));
    await _scroll(tester, reveal);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(find.text('Показать сцены будущих глав?'), findsOneWidget);
    await tester.tap(find.text('Оставить скрытыми'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Старик открыл тайну'), findsNothing);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-causal-spoiler-confirm')));
    await tester.pumpAndSettle();
    final from = find.byKey(const ValueKey('zai-causal-from-none-all'));
    await _scroll(tester, from);
    await tester.tap(from);
    await tester.pumpAndSettle();
    expect(find.text('Гл. 2 · Сцена 4'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt M2f3e notebook requires an explicit reset and '
      'cannot delete M2f3d scenes', (tester) async {
    final f = _setup();
    final repo = MemorySourceAnalysisCheckpointRepository();
    await repo.write(f.queue.index.sourceFingerprint, '{corrupt');
    await tester.pumpWidget(MaterialApp(
      home: ZaiCausalChoicesPage(
        queue: f.queue, board: f.board, consistency: f.consistency,
        repository: repo,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-causal-error')), findsOneWidget);
    final reset = find.byKey(const Key('zai-causal-reset'));
    await _scroll(tester, reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repo.read(f.queue.index.sourceFingerprint), '{corrupt');
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-causal-reset-confirm')));
    await tester.pumpAndSettle();
    expect(await repo.read(f.queue.index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('zai-causal-error')), findsNothing);
    expect(f.board.scenes, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('M2f3f2 opens from causal editor and saves only '
      'source-linked private prose without a world install', (tester) async {
    final f = _setup();
    final causal = MemorySourceAnalysisCheckpointRepository();
    final privateDraft = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(home: ZaiCausalChoicesPage(
      queue: f.queue,
      board: f.board,
      consistency: f.consistency,
      repository: causal,
      privateDraftRepository: privateDraft,
      privateNarrativeRepository: MemorySourceAnalysisCheckpointRepository(),
      privateCatalogRepository: MemorySourceAnalysisCheckpointRepository(),
      privateEditorialRepository: MemorySourceAnalysisCheckpointRepository(),
    )));
    await tester.pumpAndSettle();

    final open = find.byKey(const Key('zai-open-private-compiler'));
    await _scroll(tester, open, step: 210);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-private-title')), findsOneWidget);
    expect(find.textContaining('Нет независимого анализа'), findsOneWidget);
    expect(find.byKey(const Key('zai-private-installed')), findsNothing);
    expect(await privateDraft.read(f.queue.index.sourceFingerprint), isNull);

    final source = find.byKey(const Key('zai-private-source-toggle'));
    await _scroll(tester, source, step: 180);
    await tester.tap(source);
    await tester.pumpAndSettle();
    final prose = find.byKey(const Key('zai-private-scene-prose'));
    await _scroll(tester, prose, step: 170);
    await tester.enterText(prose, 'Мой частный текст сцены без копирования книги.');
    final save = find.byKey(const Key('zai-private-save-text'));
    await _scroll(tester, save, step: 170);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final raw = await privateDraft.read(f.queue.index.sourceFingerprint);
    expect(raw, isNotNull);
    final restored = ZaiPrivateCompilationDraft.decode(
        ZaiCausalChoiceNotebook.empty(f.board), raw!);
    expect(restored.sourceSceneIds, contains(f.board.scenes.first.id));
    expect(restored.authoredSceneTexts[f.board.scenes.first.id],
        'Мой частный текст сцены без копирования книги.');
    expect(await causal.read(f.queue.index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('zai-private-installed')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old M2f3d UI opens the new editor without changing '
      'the scene checkpoint on entry', (tester) async {
    final f = _setup();
    final sceneRepo = MemorySourceAnalysisCheckpointRepository();
    final causalRepo = MemorySourceAnalysisCheckpointRepository();
    await sceneRepo.write(
        f.queue.index.sourceFingerprint, f.board.encode());
    await tester.pumpWidget(MaterialApp(
      home: ZaiSourceSceneWorkbenchPage(
        queue: f.queue,
        scenesRepository: sceneRepo,
        consistencyRepository: MemorySourceAnalysisCheckpointRepository(),
        choicesRepository: causalRepo,
      ),
    ));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('zai-open-causal-editor'));
    await _scroll(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-causal-title')), findsOneWidget);
    expect(await causalRepo.read(f.queue.index.sourceFingerprint), isNull);
    expect(await sceneRepo.read(f.queue.index.sourceFingerprint),
        f.board.encode());
    expect(tester.takeException(), isNull);
  });
}
