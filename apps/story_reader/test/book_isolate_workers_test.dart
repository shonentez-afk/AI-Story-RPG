import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show WidgetsBinding;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('book parsing with live Flutter binding uses only explicit '
      'worker arguments', () async {
    final binding = WidgetsBinding.instance;
    final bytes = Uint8List.fromList(utf8.encode(
        'Артем по прозвищу Волк открыл дверь. Дверь была открыта.'));
    // Real compute/isolate work is tested in a normal async test zone.
    // WidgetTester FakeAsync cannot reliably wait for a spawned isolate.
    final imported = await parseImportedBookInWorker('my-book.txt', bytes);
    final index = await indexImportedBookInWorker(imported);
    expect(index.chunks.single.text, contains('Дверь была открыта'));
    expect(binding, isNotNull);
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
