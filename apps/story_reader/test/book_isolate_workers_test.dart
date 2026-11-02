import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/book_isolate_workers.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';

class _BookOpenProbe extends StatefulWidget {
  const _BookOpenProbe({super.key});
  @override
  State<_BookOpenProbe> createState() => _BookOpenProbeState();
}

class _BookOpenProbeState extends State<_BookOpenProbe> {
  final controller = ScrollController();
  final completer = Completer<BookSourceIndex>();
  Future<void> open() async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(
          'Артем по прозвищу Волк открыл дверь. Дверь была открыта.'));
      final parsed = await parseImportedBookInWorker('my-book.txt', bytes);
      final indexed = await indexImportedBookInWorker(parsed);
      completer.complete(indexed);
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Открыть настоящую книгу')),
    body: ListView(controller: controller, children: [
      FilledButton(onPressed: open, child: const Text('Открыть книгу')),
      const Text('Живой экран Flutter с состоянием и деревом элементов'),
    ]),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('book opens from live Flutter State without sending UI '
      'objects into isolates', (tester) async {
    final key = GlobalKey<_BookOpenProbeState>();
    await tester.pumpWidget(MaterialApp(home: _BookOpenProbe(key: key)));
    await tester.pumpAndSettle();
    // Flutter widget tests run in FakeAsync. Start and await a real native
    // isolate within runAsync; do not strand the job in the fake clock.
    final state = key.currentState!;
    expect(find.text('Открыть книгу'), findsOneWidget);
    final index = await tester.runAsync(() async {
      await state.open();
      return state.completer.future.timeout(const Duration(seconds: 25));
    });
    expect(index, isNotNull);
    expect(index!.chunks.single.text, contains('Дверь была открыта'));
    expect(tester.takeException(), isNull);
  });

  test('isolates accept only book/analysis model data and keep citations '
      'intact', () async {
    final bytes = Uint8List.fromList(utf8.encode(
        'Артем по прозвищу Волк открыл дверь. Дверь была открыта.'));
    final book = await parseImportedBookInWorker('история.txt', bytes);
    expect(book.title, contains('история'));
    final index = await indexImportedBookInWorker(book);
    expect(index.chunks, isNotEmpty);
    var mentions = SourceAnalysisSession.create(index);
    mentions = await processSourceBatchInWorker(index, mentions);
    final encodedMentions = await encodeSourceAnalysisInWorker(mentions);
    expect((await decodeSourceAnalysisInWorker(index, encodedMentions)).encode(),
        mentions.encode());

    var review = StoryEvidenceReviewSession.create(index);
    review = await scanNarrativeEvidenceInWorker(index, review);
    expect(review.graph.records, isNotEmpty);
    final encodedEvidence = await encodeNarrativeEvidenceInWorker(review);
    final decoded = await decodeNarrativeEvidenceInWorker(
        index, encodedEvidence);
    expect(decoded.encode(), review.encode());
    final chronology = await buildSourceChronologyInWorker(
        index, decoded.graph);
    expect(chronology.observations, isNotEmpty);

    var graph = decoded.graph;
    final alias = SourceNarrativeExtractor.aliasesInChunk(
        index, index.chunks.first);
    expect(alias, hasLength(2));
    for (final entry in alias) {
      graph = graph.review(index, entry.id, EvidenceStatus.confirmed);
    }
    final relations = await createRelationReviewInWorker(index, graph);
    expect(relations.hints, isNotEmpty);
    final reviewed = await decideRelationInWorker(index, graph,
        relations, relations.hints.first.id, IdentityDecision.same);
    final encodedRelations = await encodeRelationReviewInWorker(reviewed);
    final restored = await decodeRelationReviewInWorker(index, graph,
        encodedRelations);
    expect(restored.decisionFor(relations.hints.first.id),
        IdentityDecision.same);
    expect(restored.canPublishBookworld, false);
  });

  test('stored library scan uses a data-only worker and preserves files',
      () async {
    final root = await Directory.systemTemp.createTemp('story-isolate-');
    addTearDown(() => root.delete(recursive: true));
    final storage = BookStorage(rootDirectory: () async => root);
    const book = ImportedBook(
        title: 'Проверка открытия',
        author: '',
        chapters: ['Сохранённый текст.']);
    await storage.add(book);
    final scanned = await storage.scan();
    expect(scanned.books, hasLength(1));
    expect(scanned.books.single.book.chapters.single, 'Сохранённый текст.');
    expect(scanned.unreadableCount, 0);
  });
}
