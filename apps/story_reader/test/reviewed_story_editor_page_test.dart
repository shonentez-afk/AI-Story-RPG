import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/reviewed_story_editor_page.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const book = ImportedBook(title: 'Собственный рассказ', author: 'Автор',
      chapters: [
        'Дверь была закрыта. Мария открыла дверь.',
        'Дверь была открыта. Мария встретила Ивана.',
      ]);
  final index = BookSourceIndexer.index(book);

  Widget page(
      MemorySourceAnalysisCheckpointRepository narrative,
      MemorySourceAnalysisCheckpointRepository catalog) => MaterialApp(
    home: ReviewedStoryEditorPage(
      index: index,
      gateway: const DeviceWorldLibraryGateway(background: false),
      narrativeRepository: narrative,
      catalogRepository: catalog,
      editorialRepository: MemorySourceAnalysisCheckpointRepository(),
      draftRepository: MemorySourceAnalysisCheckpointRepository(),
    ),
  );

  testWidgets('without local source review editor explains the blocker',
      (tester) async {
    await tester.pumpWidget(page(
        MemorySourceAnalysisCheckpointRepository(),
        MemorySourceAnalysisCheckpointRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Редактор частного сценария'), findsOneWidget);
    expect(find.textContaining('Редактор не готов:'), findsOneWidget);
    expect(find.textContaining('Сначала выполните локальную подготовку'),
        findsOneWidget);
    expect(find.byKey(const Key('editor-compile-private')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source-backed editor hides candidate spoilers until opted in',
      (tester) async {
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final catalogStore = MemorySourceAnalysisCheckpointRepository();
    var review = StoryEvidenceReviewSession.create(index).scanNext(index);
    for (final source in review.graph.records) {
      review = review.review(index, source.id, EvidenceStatus.confirmed);
    }
    final catalog = SourceSemanticCatalog.fromLocalEvidence(
        index, review.graph);
    expect(catalog.assertions, isNotEmpty);
    await narrative.write(index.sourceFingerprint, review.encode());
    await catalogStore.write(index.sourceFingerprint, catalog.encode());
    await tester.pumpWidget(page(narrative, catalogStore));
    await tester.pumpAndSettle();

    expect(find.textContaining('Проверенных событий для выбора:'),
        findsOneWidget);
    expect(find.byKey(const Key('editor-compile-private')), findsNothing);
    await tester.tap(find.byKey(const Key('editor-show-spoilers')));
    await tester.pumpAndSettle();
    expect(find.text('Исходная сцена'), findsOneWidget);
    expect(find.byKey(const Key('editor-private-consent')), findsOneWidget);
    expect(find.byKey(const Key('editor-compile-private')), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('editor-compile-private')));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
