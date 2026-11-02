import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';

void main() {
  const original = ImportedBook(
    title: 'Дверь и свидетель', author: 'Оригинальный тест',
    chapters: [
      'Артем открыл дверь. Дверь была открыта. '
          'Артем по прозвищу Волк ждал у дома.',
      'Дверь была закрыта. По словам героя, Артем встретил Анну.',
      'Его звали Артем. В городе Москва он увидел свет.',
    ],
  );

  test('narrow local patterns yield exact inferred fact/event/alias spans',
      () {
    final index = BookSourceIndexer.index(original);
    final first = index.chunks.first;
    final events = SourceNarrativeExtractor.claimsInChunk(index, first);
    expect(events.length, 2);
    expect(events.map((e) => e.evidence.label),
        containsAll(['Артем открыл дверь', 'Дверь была открыта']));
    expect(events.singleWhere((e) => e.evidence.kind == EvidenceKind.fact)
        .value, 'open');
    expect(events.every((e) => !e.isReported), true);
    final aliases = SourceNarrativeExtractor.aliasesInChunk(index, first);
    expect(aliases.map((e) => e.label), ['Артем', 'Волк']);
    final proposals = SourceNarrativeExtractor.extractChunk(index, first);
    expect(proposals.length, 4);
    expect(proposals.every((x) => x.status == EvidenceStatus.inferred), true);
    for (final evidence in proposals) {
      evidence.validate(index);
      expect(first.text.substring(
          evidence.startUtf16 - first.startUtf16,
          evidence.endUtf16 - first.startUtf16), evidence.label);
    }
    expect(SourceNarrativeExtractor.claimsInChunk(index, index.chunks[1])
        .singleWhere((e) => e.evidence.kind == EvidenceKind.event)
        .isReported, true);
  });

  test('progress/resume and conflicts stay unconfirmed across chapters', () {
    final index = BookSourceIndexer.index(original);
    var current = StoryEvidenceReviewSession.create(index);
    current = current.scanNext(index, limit: 1);
    expect(current.scannedChunks, 1);
    expect(current.graph.records.length, 4);
    final restored = StoryEvidenceReviewSession.decode(index, current.encode());
    expect(restored.encode(), current.encode());
    expect(restored.scannedChunks, 1);
    current = restored.scanNext(index, limit: 1);
    expect(current.scannedChunks, 2);
    final changes = SourceNarrativeExtractor.possibleConflicts(current.graph);
    expect(changes, hasLength(1));
    expect(changes.single.subject, 'дверь');
    expect(changes.single.mightBePlotProgression, true);
    expect(changes.single.isProvenContradiction, false);
    expect(current.graph.visibleToPlayer(currentChapter: 99), isEmpty);
    final aliases = SourceNarrativeExtractor.explicitAliasHints(
        index, current.graph);
    expect(aliases, hasLength(1));
    expect(aliases.single.firstName, 'Артем');
    expect(aliases.single.secondName, 'Волк');
    expect(aliases.single.confirmedSamePerson, false);
    final fact = current.graph.records.singleWhere((e) =>
        e.kind == EvidenceKind.fact &&
        e.label == 'Дверь была открыта');
    final confirmed = current.review(index, fact.id, EvidenceStatus.confirmed);
    expect(confirmed.confirmedPassageCount, 1);
    expect(confirmed.graph.visibleToPlayer(currentChapter: 0).single.id,
        fact.id);
    expect(confirmed.canPublishBookworld, false);
    expect(confirmed.gameplayCoverage, 0);
    expect(StoryEvidenceReviewSession.decode(index, confirmed.encode())
        .confirmedPassageCount, 1);
  });

  test('late accepted mention synchronizes without replacing human decisions',
      () {
    final index = BookSourceIndexer.index(original);
    var session = SourceAnalysisSession.create(index).processBatch(index);
    final hit = session.mentions.firstWhere((m) => m.label == 'Артем');
    session = session.decide(hit.id, MentionDecision.accepted);
    var review = StoryEvidenceReviewSession.create(index).scanNext(index);
    final before = review.graph.records.length;
    review = review.syncAcceptedMentions(index, session);
    expect(review.graph.records.length, before + 1);
    final added = review.graph.records.singleWhere((e) =>
        e.kind == EvidenceKind.character &&
        e.chapterIndex == hit.chapterIndex &&
        e.startUtf16 == hit.startUtf16 &&
        e.label == hit.label);
    expect(added.status, EvidenceStatus.inferred);
    review = review.review(index, added.id, EvidenceStatus.confirmed);
    final repeat = review.syncAcceptedMentions(index, session);
    expect(repeat.graph.records.length, review.graph.records.length);
    expect(repeat.graph.records.singleWhere((e) => e.id == added.id).status,
        EvidenceStatus.confirmed);
  });

  test('invalid checkpoint and foreign source fail closed', () {
    final index = BookSourceIndexer.index(original);
    final review = StoryEvidenceReviewSession.create(index)
        .scanNext(index, limit: 2);
    final different = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая книга', author: '', chapters: ['Другая версия.'],
    ));
    expect(() => StoryEvidenceReviewSession.decode(
        different, review.encode()), throwsFormatException);
    final root = jsonDecode(review.encode()) as Map<String, dynamic>;
    final payload = root['payload'] as Map<String, dynamic>;
    payload['scanned_chunks'] = 0;
    root['sha256'] = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    expect(() => StoryEvidenceReviewSession.decode(index, jsonEncode(root)),
        throwsFormatException);
    expect(() => StoryEvidenceReviewSession.create(index).scanNext(
        index, limit: 0), throwsRangeError);
    expect(() => StoryEvidenceReviewSession.create(index).scanNext(
        index, limit: 65), throwsRangeError);
  });

  test('unsupported statements never become facts and explicit quotes stay '
      'untrusted', () {
    final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Ограничения', author: '',
      chapters: [
        'Он не открыл дверь. Может быть, окно открыто. '
            'Артем открыл дверь. '
            'Говорили, что Артем увидел врага.',
      ],
    ));
    final detected = SourceNarrativeExtractor.claimsInChunk(
        index, index.chunks.first);
    expect(detected.any((e) => e.evidence.label == 'Он не открыл дверь'), false);
    expect(detected.any((e) => e.evidence.label == 'Артем открыл дверь'), true);
    expect(detected.any((e) => e.isReported), true);
    expect(detected.every((e) => e.evidence.status ==
        EvidenceStatus.inferred), true);
  });

  test('M2b1 and evidence checkpoints live in distinct private folders',
      () async {
    final directory = await Directory.systemTemp.createTemp('evidence-m2b3b-');
    addTearDown(() => directory.delete(recursive: true));
    final a = FileSourceAnalysisCheckpointRepository(
      rootDirectory: () async => directory,
    );
    final b = FileSourceAnalysisCheckpointRepository(
      rootDirectory: () async => directory,
      scope: SourceCheckpointScope.narrativeEvidence,
    );
    final index = BookSourceIndexer.index(original);
    final mentions = SourceAnalysisSession.create(index).encode();
    final story = StoryEvidenceReviewSession.create(index).encode();
    await a.write(index.sourceFingerprint, mentions);
    await b.write(index.sourceFingerprint, story);
    expect(await a.read(index.sourceFingerprint), mentions);
    expect(await b.read(index.sourceFingerprint), story);
    await b.delete(index.sourceFingerprint);
    expect(await a.read(index.sourceFingerprint), mentions);
    expect(await b.read(index.sourceFingerprint), isNull);
  });
}
