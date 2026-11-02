import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/source_semantic_review.dart';
import 'package:ai_story_reader/source_semantic_review_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Книга для проверки',
    author: 'Тест',
    chapters: [
      'Его звали Артем. В городе Москва встречались друзья.',
      'Её звали Анна. Она никому не рассказывала тайну.',
    ],
  );
  const provider = OfflineRuleProvider();

  Widget screen(BookSourceIndex index,
      MemorySourceAnalysisCheckpointRepository store) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SourceSemanticReviewPanel(
            index: index,
            checkpointRepository: store,
            batchProcessor: (i, s) => s.processNext(i, provider, limit: 1),
            checkpointEncoder: (s) async => s.encode(),
            checkpointDecoder: (i, raw) async =>
                SemanticReviewSession.decode(i, provider, raw),
          ),
        ),
      )));

  testWidgets('closed by default, citations hidden, checkpoint resumes',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(screen(index, store));
    await tester.pumpAndSettle();
    expect(find.text('Открыть локальный анализ'), findsOneWidget);
    expect(find.textContaining('Цитата:'), findsNothing);
    expect(await store.read(index.sourceFingerprint), isNull);

    await tester.tap(find.byKey(const Key('semantic-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обработано: 0 из 2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('semantic-batch')));
    await tester.tap(find.byKey(const Key('semantic-batch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обработано: 1 из 2'), findsOneWidget);
    expect(find.textContaining('Цитата:'), findsNothing);
    expect(await store.read(index.sourceFingerprint), isNotNull);

    await tester.ensureVisible(find.byKey(const Key('semantic-reveal')));
    await tester.tap(find.byKey(const Key('semantic-reveal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Цитата:'), findsWidgets);

    await tester.ensureVisible(find.text('Оставить для проверки').first);
    await tester.tap(find.text('Оставить для проверки').first);
    await tester.pumpAndSettle();
    final saved = SemanticReviewSession.decode(index, provider,
        (await store.read(index.sourceFingerprint))!);
    expect(saved.keptCount, 1);
    expect(saved.canPublishBookworld, isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(screen(index, store));
    await tester.pumpAndSettle();
    expect(find.textContaining('Цитата:'), findsNothing);
    await tester.tap(find.byKey(const Key('semantic-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обработано: 1 из 2'), findsOneWidget);
    expect(find.textContaining('Отмечено для проверки: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed persistence shows no phantom progress and retry works',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(screen(index, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('semantic-open')));
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.ensureVisible(find.byKey(const Key('semantic-batch')));
    await tester.tap(find.byKey(const Key('semantic-batch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обработано: 0 из 2'), findsOneWidget);
    expect(find.textContaining('Последняя успешно сохранённая'), findsOneWidget);
    expect(await store.read(index.sourceFingerprint), isNull);
    await tester.tap(find.byKey(const Key('semantic-batch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обработано: 1 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt file is not overwritten; explicit reset only',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final store = MemorySourceAnalysisCheckpointRepository();
    await store.write(index.sourceFingerprint, 'not a semantic checkpoint');
    await tester.pumpWidget(screen(index, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('semantic-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось восстановить'), findsOneWidget);
    expect(await store.read(index.sourceFingerprint),
        'not a semantic checkpoint');
    await tester.ensureVisible(find.text('Сбросить предложения'));
    await tester.tap(find.text('Сбросить предложения'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить семантические предложения?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint),
        'not a semantic checkpoint');
    await tester.tap(find.text('Сбросить предложения'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить предложения').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(find.textContaining('Обработано: 0 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
