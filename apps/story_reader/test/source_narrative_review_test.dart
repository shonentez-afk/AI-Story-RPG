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

  test('unnamed fairy-tale roles yield only source-cited suggestions', () {
    const folk = ImportedBook(
      title: 'Мастерская и тайна', author: 'Автор тестового текста',
      chapters: [
        'Жил сапожник. Сапожник сделал сундук. '
            'Принцесса увидела сундук. '
            'Фрейлины обступили её. Свинопас получил подарок.',
        'Принц и свинопас могли быть разными людьми. '
            '«Смотри!» — принцесса сказала подруге.',
      ],
    );
    final index = BookSourceIndexer.index(folk);
    final first = index.chunks.first;
    final claims = SourceNarrativeExtractor.claimsInChunk(index, first);
    expect(claims.map((e) => e.evidence.label),
        containsAll(['Сапожник сделал сундук',
          'Принцесса увидела сундук', 'Фрейлины обступили её',
          'Свинопас получил подарок']));
    expect(claims.every((e) => e.evidence.kind == EvidenceKind.event), true);
    expect(claims.every((e) => e.evidence.status == EvidenceStatus.inferred),
        true);
    final roles = SourceNarrativeExtractor.roleMentionsInChunk(index, first);
    expect(roles.map((e) => e.label),
        containsAll(['сапожник', 'Принцесса', 'Фрейлины', 'Свинопас']));
    expect(roles.map((e) => e.label.toLowerCase()).toSet().length,
        roles.length);
    final proposals = SourceNarrativeExtractor.extractChunk(index, first);
    for (final evidence in proposals) {
      evidence.validate(index);
      expect(first.text.substring(
          evidence.startUtf16 - first.startUtf16,
          evidence.endUtf16 - first.startUtf16), evidence.label);
    }
    final reviewed = StoryEvidenceReviewSession.create(index).scanNext(index);
    expect(reviewed.graph.records, isNotEmpty);
    expect(reviewed.graph.records.every(
        (e) => e.status == EvidenceStatus.inferred), true);
    expect(reviewed.graph.visibleToPlayer(currentChapter: 99), isEmpty);
    expect(reviewed.canPublishBookworld, false);
    expect(StoryEvidenceReviewSession.decode(index, reviewed.encode())
        .encode(), reviewed.encode());
  });

  test('role spelling never proves actor identity or a negated event', () {
    final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Роли и оговорки', author: '', chapters: [
        'Принцесса увидела сундук. '
            'Принц не увидел сундук. '
            'Свинопас сделал подарок. '
            'Непринцесса увидела сундук.'
      ],
    ));
    final chunk = index.chunks.first;
    final claims = SourceNarrativeExtractor.claimsInChunk(index, chunk);
    expect(claims.map((x) => x.evidence.label),
        contains('Принцесса увидела сундук'));
    expect(claims.map((x) => x.evidence.label),
        contains('Свинопас сделал подарок'));
    expect(claims.any((x) => x.evidence.label.contains('не увидел')),
        isFalse);
    // The pre-existing proper-name matcher can still nominate an unknown
    // capitalized word. The NEW role matcher must not treat a prefix as a
    // known role; neither matcher automatically establishes a character.
    final roles = SourceNarrativeExtractor.roleMentionsInChunk(index, chunk);
    expect(roles.any((e) => e.label == 'Непринцесса'), isFalse);
    expect(roles.map((x) => x.label),
        containsAll(['Принцесса', 'Принц', 'Свинопас']));
    expect(roles.every((e) => e.status == EvidenceStatus.inferred), true);
    // There is deliberately no SAME-person decision for role mentions.
    expect(SourceNarrativeExtractor.explicitAliasHints(
        index, StoryEvidenceReviewSession.create(index).scanNext(index).graph),
        isEmpty);
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

  test('animal and fairy-tale roles produce exact untrusted citations, '
      'not merged identities or duplicated named/role events', () {
    const animal = ImportedBook(
      title: 'Птичий двор', author: 'Оригинальная тестовая сказка',
      chapters: [
        'Утенок увидел лебедя. Жаба встретила крота. '
        'Ласточка подарила перо. Курица сказала коту правду. '
        'Кот сидел у окна. Утки прошли мимо.',
      ],
    );
    final index = BookSourceIndexer.index(animal);
    final chunk = index.chunks.first;
    final mentions = SourceNarrativeExtractor.roleMentionsInChunk(index, chunk);
    expect(mentions.map((m) => m.label), containsAll([
      'Утенок', 'Жаба', 'Ласточка', 'Курица', 'Кот', 'Утки'
    ]));
    for (final item in mentions) {
      item.validate(index);
      expect(item.status, EvidenceStatus.inferred);
    }
    final claims = SourceNarrativeExtractor.claimsInChunk(index, chunk);
    expect(claims.where((x) =>
        x.evidence.label == 'Утенок увидел лебедя'), hasLength(1));
    expect(claims.map((x) => x.evidence.label),
        contains('Жаба встретила крота'));
    final review = StoryEvidenceReviewSession.create(index).scanNext(index);
    expect(review.graph.records, isNotEmpty);
    expect(review.graph.records
        .every((e) => e.status == EvidenceStatus.inferred), isTrue);
    expect(review.graph.visibleToPlayer(currentChapter: 10), isEmpty);
    expect(review.canPublishBookworld, false);
  });

}
