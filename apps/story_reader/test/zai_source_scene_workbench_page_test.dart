import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_cross_window_review_page.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:ai_story_reader/zai_source_scene_workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index() => BookSourceIndexer.index(const ImportedBook(
  title: 'Сказка для проверки сцен',
  author: 'Частный файл',
  chapters: [
    'Кай вошёл. Герда нашла ключ. Герда ждала.',
    'Кай раскрыл тайну. Герда вернулась.',
  ],
  structuredChapters: [
    BookChapter(id: 'one', blocks: [
      BookBlock(kind: BookBlockKind.paragraph,
        text: 'Кай вошёл. Герда нашла ключ. Герда ждала.'),
    ]),
    BookChapter(id: 'two', blocks: [
      BookBlock(kind: BookBlockKind.paragraph,
        text: 'Кай раскрыл тайну. Герда вернулась.'),
    ]),
  ],
));

({ZaiWindowReviewQueue queue, List<SemanticCandidate> events}) _review() {
  final index = _index();
  final events = <SemanticCandidate>[];
  var queue = ZaiWindowReviewQueue.empty(index);
  for (var i = 0; i < 2; i++) {
    final chunk = index.chunks[i];
    final strings = i == 0 ?
        ['Кай вошёл.', 'Герда нашла ключ.'] :
        ['Кай раскрыл тайну.', 'Герда вернулась.'];
    final items = <SemanticCandidate>[];
    for (final quote in strings) {
      final at = chunk.text.indexOf(quote);
      final c = SemanticCandidate.propose(index, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16 + at,
        endUtf16: chunk.startUtf16 + at + quote.length,
        label: quote, uncertainty: 'Проверить сюжетную последовательность',
      );
      items.add(c);
      events.add(c);
    }
    queue = queue.record(i, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [chunk.id], candidates: items,
      ),
      totalSuggestions: items.length,
      rejectedCount: 0, rejectedNonRussian: 0,
    ));
    for (final item in items) {
      queue = queue.decide(item.id, ZaiEditorialDecision.keepForReview);
    }
  }
  return (queue: queue, events: events);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('source scene creation is explicitly confirmed and '
      'future-chapter quotes stay hidden until opt-in', (tester) async {
    final setup = _review();
    final sceneRepo = MemorySourceAnalysisCheckpointRepository();
    final consistencyRepo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiSourceSceneWorkbenchPage(
        queue: setup.queue,
        scenesRepository: sceneRepo,
        consistencyRepository: consistencyRepo,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-scene-title')), findsOneWidget);
    expect(find.textContaining('Кай раскрыл тайну'), findsNothing);

    final choose = find.byKey(Key('zai-scene-event-${setup.events.first.id}'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    final title = find.byKey(const Key('zai-scene-name-input'));
    await tester.scrollUntilVisible(title, 140,
        scrollable: find.byType(Scrollable).first, maxScrolls: 35);
    await tester.pumpAndSettle();
    await tester.enterText(title, 'Сцена встречи');
    final add = find.byKey(const Key('zai-scene-add'));
    await tester.scrollUntilVisible(add, 130,
        scrollable: find.byType(Scrollable).first, maxScrolls: 35);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('zai-scene-confirm-save'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await sceneRepo.read(setup.queue.index.sourceFingerprint), isNull);

    await tester.tap(add);
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const Key('zai-scene-confirm-check'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final saved = await sceneRepo.read(setup.queue.index.sourceFingerprint);
    expect(saved, isNotNull);
    expect(saved, isNot(contains('Частный файл')));
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(setup.queue);
    final board = ZaiSourceSceneBoard.decode(graph, saved!);
    expect(board.scenes.single.title, 'Сцена встречи');
    expect(board.scenes.single.eventIds, [setup.events.first.id]);
    expect(board.canPublishBookworld, false);
    expect(find.textContaining('Кай раскрыл тайну'), findsNothing);

    final reveal = find.byKey(const Key('zai-scene-reveal-future'));
    await tester.scrollUntilVisible(reveal, -160,
        scrollable: find.byType(Scrollable).first, maxScrolls: 45);
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(find.text('Открыть цитаты следующих глав?'), findsOneWidget);
    await tester.tap(find.text('Не показывать'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Кай раскрыл тайну'), findsNothing);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-scene-spoilers-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Показать будущие главы'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupted scene checkpoint cannot overwrite itself, reset '
      'requires explicit second confirmation', (tester) async {
    final setup = _review();
    final sceneRepo = MemorySourceAnalysisCheckpointRepository();
    await sceneRepo.write(setup.queue.index.sourceFingerprint, '{broken');
    await tester.pumpWidget(MaterialApp(
      home: ZaiSourceSceneWorkbenchPage(
        queue: setup.queue,
        scenesRepository: sceneRepo,
        consistencyRepository: MemorySourceAnalysisCheckpointRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-scene-error')), findsOneWidget);
    final reset = find.byKey(const Key('zai-scene-reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('Удалить только черновик сцен M2f3d?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await sceneRepo.read(setup.queue.index.sourceFingerprint),
        '{broken');
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-scene-reset-confirm')));
    await tester.pumpAndSettle();
    expect(await sceneRepo.read(setup.queue.index.sourceFingerprint),
        isNull);
    expect(find.byKey(const Key('zai-scene-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross-window review opens new offline storyboard and '
      'does not request provider or alter existing private reviews',
      (tester) async {
    final setup = _review();
    final sceneRepo = MemorySourceAnalysisCheckpointRepository();
    final consistencyRepo = MemorySourceAnalysisCheckpointRepository();
    final oldReview = setup.queue.encode();
    await tester.pumpWidget(MaterialApp(
      home: ZaiCrossWindowReviewPage(
        queue: setup.queue,
        linksRepository: MemorySourceAnalysisCheckpointRepository(),
        consistencyRepository: consistencyRepo,
        scenesRepository: sceneRepo,
      ),
    ));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('zai-open-scene-workbench'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-scene-title')), findsOneWidget);
    final preflight = find.byKey(const Key('zai-scene-preflight-title'));
    await tester.scrollUntilVisible(preflight, 150,
        scrollable: find.byType(Scrollable).first, maxScrolls: 45);
    await tester.pumpAndSettle();
    expect(preflight, findsOneWidget);
    expect(await sceneRepo.read(setup.queue.index.sourceFingerprint), isNull);
    expect(setup.queue.encode(), oldReview);
    expect(tester.takeException(), isNull);
  });
}
