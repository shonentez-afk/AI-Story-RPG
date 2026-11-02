import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_narrative_review_panel.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Проверка событий', author: 'Тест',
    chapters: [
      'Артем открыл дверь. Дверь была открыта. '
          'Артем по прозвищу Волк рассматривал дом.',
      'Дверь была закрыта. Артем увидел Анну.',
    ],
  );

  Widget buildPanel(BookSourceIndex index,
      MemorySourceAnalysisCheckpointRepository repository) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SourceNarrativeReviewPanel(
            index: index,
            checkpointRepository: repository,
            scanProcessor: (index, session) async =>
                session.scanNext(index, limit: 1),
            checkpointEncoder: (session) async => session.encode(),
            checkpointDecoder: (index, raw) async =>
                StoryEvidenceReviewSession.decode(index, raw),
          ),
        ),
      )));

  testWidgets('review stays collapsed; explicit analysis and spoiler reveal',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    Widget screen() => buildPanel(index, repository);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Открыть проверку утверждений'), findsOneWidget);
    expect(find.text('Артем открыл дверь'), findsNothing);
    expect(await repository.read(index.sourceFingerprint), isNull);

    await tester.tap(find.text('Открыть проверку утверждений'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 0 из 2'), findsOneWidget);
    expect(find.text('Артем открыл дверь'), findsNothing);

    await tester.ensureVisible(find.text('Продолжить поиск'));
    await tester.tap(find.text('Продолжить поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 2 из 2'), findsOneWidget);
    expect(find.text('Артем открыл дверь'), findsNothing);
    expect(await repository.read(index.sourceFingerprint), isNotNull);

    await tester.ensureVisible(
        find.text('Показать утверждения (возможны спойлеры)'));
    await tester.tap(
        find.text('Показать утверждения (возможны спойлеры)'));
    await tester.pumpAndSettle();
    expect(find.text('Артем открыл дверь'), findsOneWidget);
    expect(find.textContaining('Возможные расхождения'), findsOneWidget);
    expect(find.textContaining('Артем — Волк'), findsOneWidget);

    await tester.ensureVisible(find.text('Подтвердить текст').first);
    await tester.tap(find.text('Подтвердить текст').first);
    await tester.pumpAndSettle();
    final persisted = StoryEvidenceReviewSession.decode(index,
        (await repository.read(index.sourceFingerprint))!);
    expect(persisted.confirmedPassageCount, 1);
    expect(persisted.canPublishBookworld, false);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Артем открыл дверь'), findsNothing);
    await tester.tap(find.text('Открыть проверку утверждений'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 2 из 2'), findsOneWidget);
    expect(find.text('Артем открыл дверь'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed write cannot show phantom progress; retry resumes',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(buildPanel(index, repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть проверку утверждений'));
    await tester.pumpAndSettle();
    repository.failNextWrite = true;
    await tester.ensureVisible(find.text('Продолжить поиск'));
    await tester.tap(find.text('Продолжить поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 0 из 2'), findsOneWidget);
    expect(find.textContaining('Последняя успешно сохранённая порция'),
        findsOneWidget);
    expect(await repository.read(index.sourceFingerprint), isNull);
    await tester.ensureVisible(find.text('Продолжить поиск'));
    await tester.tap(find.text('Продолжить поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 2 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset is explicit, only evidence checkpoint is removed',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    await repository.write(index.sourceFingerprint,
        StoryEvidenceReviewSession.create(index).scanNext(index).encode());
    await tester.pumpWidget(buildPanel(index, repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть проверку утверждений'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено фрагментов: 2 из 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Сбросить проверку'));
    await tester.tap(find.text('Сбросить проверку'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить проверку утверждений?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repository.read(index.sourceFingerprint), isNotNull);
    await tester.tap(find.text('Сбросить проверку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить проверку').last);
    await tester.pumpAndSettle();
    expect(await repository.read(index.sourceFingerprint), isNull);
    expect(find.text('Проверено фрагментов: 0 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
