import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/multi_scene_editor_page.dart';
import 'package:ai_story_reader/reviewed_story_composer.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const book = ImportedBook(
    title: 'Авторская история', author: 'Автор',
    chapters: [
      'Дверь была закрыта. Мария открыла дверь.',
      'Мария встретила Ивана. Дверь была открыта.',
    ],
  );
  final index = BookSourceIndexer.index(book);

  late MemorySourceAnalysisCheckpointRepository narrative;
  late MemorySourceAnalysisCheckpointRepository catalogStore;
  late MemorySourceAnalysisCheckpointRepository editorialStore;
  late MemorySourceAnalysisCheckpointRepository shortStore;
  late MemorySourceAnalysisCheckpointRepository multiStore;
  late StoryEvidenceReviewSession review;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late IntermediateStoryBlueprint shortDraft;

  setUp(() async {
    narrative = MemorySourceAnalysisCheckpointRepository();
    catalogStore = MemorySourceAnalysisCheckpointRepository();
    editorialStore = MemorySourceAnalysisCheckpointRepository();
    shortStore = MemorySourceAnalysisCheckpointRepository();
    multiStore = MemorySourceAnalysisCheckpointRepository();

    review = StoryEvidenceReviewSession.create(index).scanNext(index);
    for (final record in review.graph.records) {
      review = review.review(index, record.id, EvidenceStatus.confirmed);
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, review.graph);
    final byId = {for (final r in review.graph.records) r.id: r};
    final first = catalog.assertions.firstWhere((c) =>
        c.kind == SemanticAssertionKind.event &&
        byId[c.evidenceIds.first]!.chapterIndex == 0);
    final last = catalog.assertions.firstWhere((c) =>
        c.kind == SemanticAssertionKind.event &&
        byId[c.evidenceIds.first]!.chapterIndex == 1);
    editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, first.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, last.id, SemanticEditorialVerdict.canonCandidate);
    shortDraft = ReviewedStoryComposer.compose(
      index: index, evidence: review.graph,
      catalog: catalog, editorial: editorial,
      openingAssertionId: first.id, endingAssertionId: last.id,
      openingText: 'Вы стоите перед дверью.',
      endingText: 'Мария встречает Ивана.',
      alternateEndingText: 'Игрок решает уйти.',
      followBookChoice: 'Продолжить по книге',
      changeFateChoice: 'Изменить сюжет',
    );
  });

  Widget page() => MaterialApp(home: MultiSceneEditorPage(
    index: index,
    gateway: const DeviceWorldLibraryGateway(background: false),
    narrativeRepository: narrative,
    catalogRepository: catalogStore,
    editorialRepository: editorialStore,
    shortDraftRepository: shortStore,
    multiDraftRepository: multiStore,
  ));

  Future<void> seedStores({bool withShort = true}) async {
    await narrative.write(index.sourceFingerprint, review.encode());
    await catalogStore.write(index.sourceFingerprint, catalog.encode());
    await editorialStore.write(index.sourceFingerprint, editorial.encode());
    if (withShort) {
      await shortStore.write(index.sourceFingerprint, shortDraft.encode());
    }
  }

  testWidgets('unprepared book shows blocker without game creation',
      (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Конструктор многосценной RPG'), findsOneWidget);
    expect(find.textContaining('Конструктор недоступен'), findsOneWidget);
    expect(find.byKey(const Key('multi-compile-private')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short draft is copied, long edits stored independently',
      (tester) async {
    await seedStores();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('multi-copy-short')), findsOneWidget);
    expect(find.byKey(const Key('multi-compile-private')), findsNothing);
    await tester.tap(find.byKey(const Key('multi-copy-short')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сцен: 3'), findsOneWidget);
    expect(find.byKey(const Key('multi-add-authored')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('multi-add-authored')));
    await tester.tap(find.byKey(const Key('multi-add-authored')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сцен: 4'), findsOneWidget);
    await tester.ensureVisible(find.byKey(
        const Key('multi-scene-text-scene_1')));
    await tester.enterText(find.byKey(
        const Key('multi-scene-text-scene_1')),
        'Новая авторская ветка игрока.');
    await tester.ensureVisible(find.byKey(const Key('multi-save-draft')));
    await tester.tap(find.byKey(const Key('multi-save-draft')));
    await tester.pumpAndSettle();
    final saved = IntermediateStoryBlueprint.decode(
        (await multiStore.read(index.sourceFingerprint))!);
    expect(saved.scenes.length, 4);
    expect(saved.scenes.last.text, 'Новая авторская ветка игрока.');
    expect((await shortStore.read(index.sourceFingerprint))!,
        shortDraft.encode());
    expect(tester.takeException(), isNull);
  });

  testWidgets('source-backed short graph checks before consenting to play',
      (tester) async {
    await seedStores();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('multi-copy-short')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('multi-compile-private')));
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('multi-compile-private')));
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('multi-check-causality')));
    await tester.tap(find.byKey(const Key('multi-check-causality')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверено: 3 сцен'), findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('multi-compile-private'))).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('multi-private-consent')));
    await tester.tap(find.byKey(const Key('multi-private-consent')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('multi-compile-private'))).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed persistence leaves short and long drafts unchanged',
      (tester) async {
    await seedStores();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('multi-copy-short')));
    await tester.pumpAndSettle();
    multiStore.failNextWrite = true;
    await tester.ensureVisible(find.byKey(const Key('multi-save-draft')));
    await tester.tap(find.byKey(const Key('multi-save-draft')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось сохранить черновик'),
        findsOneWidget);
    expect(await multiStore.read(index.sourceFingerprint), isNull);
    expect(await shortStore.read(index.sourceFingerprint), shortDraft.encode());
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved unfinished draft loads without granting compilation',
      (tester) async {
    await seedStores();
    final partial = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      entrySceneId: shortDraft.entrySceneId,
      rights: PreparationRights.privateUse,
      flags: const [],
      initialFlags: const [],
      scenes: [
        ...shortDraft.scenes,
        DraftScene(
          id: 'scene_1', chapterIndex: 0, text: '',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: true, choices: const [],
        ),
      ],
    );
    await multiStore.write(index.sourceFingerprint, partial.encode());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.textContaining('Сцен: 4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('multi-show-spoilers')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('multi-check-causality')));
    await tester.tap(find.byKey(const Key('multi-check-causality')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сценарий ещё не готов'), findsNothing);
    expect(find.byKey(const Key('multi-compile-private')), findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('multi-compile-private'))).onPressed, isNull);
    expect(await shortStore.read(index.sourceFingerprint), shortDraft.encode());
    expect(tester.takeException(), isNull);
  });
}
