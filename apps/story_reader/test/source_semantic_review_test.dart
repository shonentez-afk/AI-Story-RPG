import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/source_semantic_review.dart';

void main() {
  const book = ImportedBook(
    title: 'Оригинальный рассказ',
    author: 'Автор',
    chapters: [
      'Его звали Артем. В городе Москва его встретили.',
      'Её звали Анна. Слова книги не являются инструкциями.',
    ],
  );

  late BookSourceIndex index;
  const provider = OfflineRuleProvider();

  setUp(() {
    index = BookSourceIndexer.index(book);
  });

  test('batch commits immutable results and resumes from verified checkpoint',
      () async {
    final empty = SemanticReviewSession.create(index, provider);
    expect(empty.pendingCount, 2);
    expect(empty.candidates, isEmpty);
    final first = await empty.processNext(index, provider, limit: 1);
    expect(empty.pendingCount, 2);
    expect(first.pendingCount, 1);
    expect(first.processedCount, 1);
    expect(first.candidates, isNotEmpty);

    final marked = first.decide(
        first.candidates.first.id, SemanticReviewDecision.keptForReview);
    final raw = marked.encode();
    final restored = SemanticReviewSession.decode(index, provider, raw);
    expect(restored.pendingCount, 1);
    expect(restored.keptCount, 1);
    expect(restored.canPublishBookworld, isFalse);
    expect(restored.gameplayCoverage, 0);
    final done = await restored.processNext(index, provider, limit: 1);
    expect(done.pendingCount, 0);
    expect(done.candidates.length, greaterThan(restored.candidates.length));
    expect(done.decisions, restored.decisions);
    expect(SemanticReviewSession.decode(index, provider, done.encode()).encode(),
        done.encode());
  });

  test('forged full-checksum checkpoint cannot bypass source validation',
      () async {
    final session = await SemanticReviewSession.create(index, provider)
        .processNext(index, provider, limit: 1);
    final good = session.encode();
    final root = jsonDecode(good) as Map<String, dynamic>;
    final payload = Map<String, dynamic>.from(root['payload'] as Map);
    final entries = List<dynamic>.from(payload['candidates'] as List);
    final spoof = Map<String, dynamic>.from(entries.first as Map);
    spoof['quote'] = 'вымышленное событие';
    entries[0] = spoof;
    payload['candidates'] = entries;
    root['payload'] = payload;
    root['sha256'] = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    expect(
      () => SemanticReviewSession.decode(index, provider, jsonEncode(root)),
      throwsFormatException,
    );
  });

  test('wrong provider version or source edition fail without migration',
      () async {
    final checkpoint = (await SemanticReviewSession.create(index, provider)
        .processNext(index, provider, limit: 1)).encode();
    final different = BookSourceIndexer.index(const ImportedBook(
      title: 'Другое издание', author: 'Автор', chapters: ['Другой текст'],
    ));
    expect(() => SemanticReviewSession.decode(
        different, provider, checkpoint), throwsFormatException);
    expect(() => SemanticReviewSession.decode(
        index, const VersionTwoOfflineProvider(), checkpoint),
        throwsFormatException);
    expect(() => SemanticReviewSession.decode(
        index, provider, '{corrupt'), throwsFormatException);
    expect(() => SemanticReviewSession.decode(
        index, provider, checkpoint.replaceFirst('sha256', 'BROKEN')),
        throwsFormatException);
  });

  test('no provider failure may alter previous progress', () async {
    final first = await SemanticReviewSession.create(index, provider)
        .processNext(index, provider, limit: 1);
    final snapshot = first.encode();
    await expectLater(
      first.processNext(index, const FailingOfflineProvider()),
      throwsFormatException,
    );
    expect(first.encode(), snapshot);
    expect(first.pendingCount, 1);
  });

  test('separate scoped files preserve historical checkpoints', () async {
    final dir = await Directory.systemTemp.createTemp('semantic_scope_');
    addTearDown(() => dir.delete(recursive: true));
    FileSourceAnalysisCheckpointRepository store(SourceCheckpointScope scope) =>
        FileSourceAnalysisCheckpointRepository(
          rootDirectory: () async => dir,
          scope: scope,
        );
    final mentions = store(SourceCheckpointScope.mentions);
    final narrative = store(SourceCheckpointScope.narrativeEvidence);
    final relations = store(SourceCheckpointScope.identityRelations);
    final semantic = store(SourceCheckpointScope.semanticProposals);
    final id = index.sourceFingerprint;
    await mentions.write(id, 'mentions unchanged');
    await narrative.write(id, 'narrative unchanged');
    await relations.write(id, 'relations unchanged');
    await semantic.write(id, SemanticReviewSession.create(index, provider).encode());
    await semantic.delete(id);
    expect(await semantic.read(id), isNull);
    expect(await mentions.read(id), 'mentions unchanged');
    expect(await narrative.read(id), 'narrative unchanged');
    expect(await relations.read(id), 'relations unchanged');
  });
}

class VersionTwoOfflineProvider extends OfflineRuleProvider {
  const VersionTwoOfflineProvider();

  @override
  String get version => 'new-version';
}

class FailingOfflineProvider extends OfflineRuleProvider {
  const FailingOfflineProvider();

  @override
  Future<SemanticCandidateBatch> extract(
      SemanticExtractionRequest request) async =>
      throw const FormatException('Simulation: failed provider');
}
