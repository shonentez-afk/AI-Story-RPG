import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_narrative_chronology.dart';
import 'package:ai_story_reader/source_relation_review.dart';

void main() {
  const story = ImportedBook(
    title: 'Два имени и четыре цитаты',
    author: 'Автор тестовых историй',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. '
          'Дверь была открыта. Артем не открыл окно.',
      'Волк по прозвищу Артем встретил друга. '
          'По словам свидетеля, Артем увидел Анну. '
          'Возможно, Дверь была закрыта.',
      'Дверь была не открыта. Говорят, что Артем нашел письмо.',
    ],
  );

  SourceEvidenceGraph graphWithNames(BookSourceIndex index) {
    final names = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      names.addAll(SourceNarrativeExtractor.aliasesInChunk(index, chunk));
    }
    var graph = SourceEvidenceGraph.empty(index).addAll(index, names);
    for (final record in graph.records) {
      graph = graph.review(index, record.id, EvidenceStatus.confirmed);
    }
    return graph;
  }

  test('explicit aliases and repeating names never merge automatically', () {
    final index = BookSourceIndexer.index(story);
    final graph = graphWithNames(index);
    final session = SourceRelationReviewSession.create(index, graph);
    expect(session.hints.where(
        (h) => h.kind == IdentityHintKind.explicitAlias).length, 2);
    expect(session.hints.where(
        (h) => h.kind == IdentityHintKind.repeatedName).length, 2);
    expect(session.hints.every((h) => !h.isAutomaticallyMerged), true);
    expect(session.unresolvedCount, session.hints.length);
    expect(session.canPublishBookworld, false);
    expect(session.gameplayCoverage, 0);
    expect(session.proposedRelations.every((e) =>
        !e.mayPublishCanonicalIdentity), true);
  });

  test('human SAME/DIFFERENT validated against a transitive cycle', () {
    final index = BookSourceIndexer.index(story);
    final graph = graphWithNames(index);
    var session = SourceRelationReviewSession.create(index, graph);
    final alias = session.hints.where(
        (h) => h.kind == IdentityHintKind.explicitAlias).toList();
    final repeat = session.hints.where(
        (h) => h.kind == IdentityHintKind.repeatedName).toList();
    expect(alias.length, 2);
    expect(repeat.length, 2);

    session = session.decide(index, graph, alias[0].id, IdentityDecision.same);
    session = session.decide(index, graph, alias[1].id, IdentityDecision.same);
    session = session.decide(index, graph, repeat[0].id, IdentityDecision.same);
    // The fourth edge closes the cycle and may not contradict the first 3.
    expect(() => session.decide(index, graph, repeat[1].id,
        IdentityDecision.different), throwsFormatException);
    final accepted = session.decide(index, graph, repeat[1].id,
        IdentityDecision.same);
    expect(accepted.unresolvedCount, 0);
    expect(accepted.decisionFor(repeat[1].id), IdentityDecision.same);
    expect(SourceRelationReviewSession.decode(index, graph,
        accepted.encode()).encode(), accepted.encode());
    final restored = accepted.decide(index, graph, repeat[1].id,
        IdentityDecision.unresolved);
    expect(restored.unresolvedCount, 1);
  });

  test('no decision without two human-verified text citations', () {
    final index = BookSourceIndexer.index(story);
    final records = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      records.addAll(SourceNarrativeExtractor.aliasesInChunk(index, chunk));
    }
    final graph = SourceEvidenceGraph.empty(index).addAll(index, records);
    final review = SourceRelationReviewSession.create(index, graph);
    expect(review.hints, isNotEmpty);
    expect(() => review.decide(index, graph, review.hints.first.id,
        IdentityDecision.same), throwsStateError);
    expect(review.decisionFor(review.hints.first.id),
        IdentityDecision.unresolved);
  });

  test('withdrawn citation invalidates stored identity without erasing it', () {
    final index = BookSourceIndexer.index(story);
    final graph = graphWithNames(index);
    var session = SourceRelationReviewSession.create(index, graph);
    final hint = session.hints.first;
    session = session.decide(index, graph, hint.id, IdentityDecision.same);
    final raw = session.encode();
    final invalid = graph.review(index, hint.firstId,
        EvidenceStatus.rejected);
    expect(() => SourceRelationReviewSession.decode(index, invalid, raw),
        throwsFormatException);
    expect(SourceRelationReviewSession.decode(index, graph, raw)
        .decisionFor(hint.id), IdentityDecision.same);
  });

  test('chapter votes are editorial annotations, not world chronology', () {
    final index = BookSourceIndexer.index(story);
    final graph = graphWithNames(index);
    var session = SourceRelationReviewSession.create(index, graph);
    expect(session.chapterOrder.length, 2);
    expect(session.chapterOrder.every((v) =>
        v.decision == ChapterTimeDecision.unknown &&
        !v.isAuthoritativeTimeline), true);
    session = session.decideChapter(index, 0, ChapterTimeDecision.flashback)
        .decideChapter(index, 1, ChapterTimeDecision.parallel);
    final roundtrip = SourceRelationReviewSession.decode(
        index, graph, session.encode());
    expect(roundtrip.temporalDecision(0), ChapterTimeDecision.flashback);
    expect(roundtrip.temporalDecision(1), ChapterTimeDecision.parallel);
    expect(() => session.decideChapter(index, 2,
        ChapterTimeDecision.forward), throwsFormatException);
    expect(session.decideChapter(index, 0, ChapterTimeDecision.unknown)
        .temporalDecision(0), ChapterTimeDecision.unknown);
  });

  test('invalid checkpoint, wrong edition, unknown id and forged decisions '
      'fail closed', () {
    final index = BookSourceIndexer.index(story);
    final graph = graphWithNames(index);
    final session = SourceRelationReviewSession.create(index, graph);
    final foreign = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая редакция',
      author: 'Автор тестовых историй',
      chapters: ['Совсем другой текст.'],
    ));
    expect(() => SourceRelationReviewSession.decode(
        foreign, SourceEvidenceGraph.empty(foreign), session.encode()),
        throwsFormatException);
    expect(() => session.decide(index, graph, 'unknown id',
        IdentityDecision.same), throwsArgumentError);

    final root = jsonDecode(session.encode()) as Map<String, dynamic>;
    final payload = root['payload'] as Map<String, dynamic>;
    payload['decisions'] = [
      {'id': 'a' * 32, 'decision': 'SAME'}
    ];
    root['sha256'] =
        sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    expect(() => SourceRelationReviewSession.decode(
        index, graph, jsonEncode(root)), throwsFormatException);
    expect(() => SourceRelationReviewSession.decode(index, graph,
        session.encode() + 'garbage'), throwsFormatException);
  });

  test('quotes, negation, uncertainty and witness speech stay distinct', () {
    final index = BookSourceIndexer.index(story);
    final all = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      all.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    final graph = SourceEvidenceGraph.empty(index).addAll(index, all);
    final history = SourceNarrativeChronology.build(index, graph);
    expect(history.observations, isNotEmpty);
    expect(history.observations.every(
        (v) => !v.claimsVerifiedWorldTruth &&
            !v.establishesInWorldTime), true);
    final negated = history.observations.where(
        (v) => v.polarity == ClaimPolarity.negated).toList();
    expect(negated.map((x) => x.evidence.label),
        containsAll(['Артем не открыл окно', 'Дверь была не открыта']));
    for (final item in negated) {
      expect(item.isReviewed, false);
      item.evidence.validate(index);
    }
    final witness = history.observations.firstWhere(
        (v) => v.evidence.label == 'Артем увидел Анну');
    expect(witness.voice, ClaimVoice.reportedSpeech);
    final uncertain = history.observations.firstWhere(
        (v) => v.evidence.label == 'Дверь была закрыта');
    expect(uncertain.voice, ClaimVoice.uncertain);
    final first = history.observations.first;
    expect(first.evidence.chapterIndex, 0);
    expect(first.polarity, ClaimPolarity.affirmative);
    final foreign = BookSourceIndexer.index(const ImportedBook(
      title: 'Иная версия', author: '', chapters: ['Тест.'],
    ));
    expect(() => SourceNarrativeChronology.build(foreign, graph),
        throwsFormatException);
  });
}
