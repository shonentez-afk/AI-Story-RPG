import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const book = ImportedBook(
    title: 'Проверка персонажей', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была закрыта.',
      'Артем встретил Анну. Дверь была открыта.',
      'Артем увидел Анну. Волк открыл ворота.',
    ],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceRelationReviewSession review;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;

  setUp(() {
    index = BookSourceIndexer.index(book);
    final evidence = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      evidence.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    graph = SourceEvidenceGraph.empty(index).addAll(index, evidence);
    for (final entry in graph.records) {
      graph = graph.review(index, entry.id, EvidenceStatus.confirmed);
    }
    review = SourceRelationReviewSession.create(index, graph);
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
  });

  SourceCharacterDossierIndex build(SourceRelationReviewSession session,
      {SourceEvidenceGraph? otherGraph}) =>
      SourceCharacterDossierIndex.build(index, otherGraph ?? graph,
          session, catalog, editorial);

  test('same spelling across chapters never silently combines NPCs', () {
    final characters = graph.records
        .where((e) => e.kind == EvidenceKind.character).toList();
    final original = build(review);
    expect(original.totalCharacterMentions, characters.length);
    expect(original.possibleCharacterGroups, characters.length);
    expect(original.canPublishNpcCanon, false);
    expect(original.pendingIdentityHints, greaterThan(0));
    for (final d in original.dossiers) {
      expect(d.mentions.length, 1);
      expect(d.isCanonicalNpc, false);
    }
    expect(original.dossiers.any((d) => d.labels.contains('Артем')), true);
  });

  test('explicit human SAME merges only selected source mentions', () {
    final pair = review.hints.firstWhere(
        (h) => h.kind == IdentityHintKind.explicitAlias &&
            h.sourceKind == EvidenceKind.character);
    final before = build(review);
    final accepted = review.decide(
        index, graph, pair.id, IdentityDecision.same);
    final after = build(accepted);
    expect(after.possibleCharacterGroups, before.possibleCharacterGroups - 1);
    final merged = after.dossiers.singleWhere((d) =>
        d.mentions.any((e) => e.id == pair.firstId));
    expect(merged.mentions.map((e) => e.id), contains(pair.secondId));
    expect(merged.confirmedQuotes, 2);
    expect(merged.identityHints.any((x) =>
        x.hint.id == pair.id &&
        x.decision == IdentityDecision.same), true);
    expect(merged.isCanonicalNpc, false);
    // Other repeated spellings of Артем stay separate unless explicitly voted.
    expect(after.dossiers.where((d) => d.labels.contains('Артем')).length,
        greaterThan(1));
    expect(SourceRelationReviewSession.decode(
        index, graph, accepted.encode()).decisionFor(pair.id),
        IdentityDecision.same);
  });

  test('human DIFFERENT leaves distinct dossiers even for an alias hint', () {
    final pair = review.hints.firstWhere(
        (h) => h.kind == IdentityHintKind.explicitAlias &&
            h.sourceKind == EvidenceKind.character);
    final separate = review.decide(
        index, graph, pair.id, IdentityDecision.different);
    final original = build(review);
    final after = build(separate);
    expect(after.possibleCharacterGroups, original.possibleCharacterGroups);
    expect(after.dossiers.any((d) => d.identityHints.any(
        (e) => e.hint.id == pair.id &&
            e.decision == IdentityDecision.different)), true);
  });

  test('relationship hints match spelling only, with exact citation', () {
    final dossiers = build(review);
    final artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    expect(artem.relationshipHints, isNotEmpty);
    for (final hint in artem.relationshipHints) {
      expect(hint.provesCharacterRelationship, false);
      expect(hint.citation, isNotEmpty);
      expect(hint.chapterIndex, greaterThanOrEqualTo(0));
      expect(hint.verdict, null);
    }
    expect(artem.aliasHints, isNotEmpty);
  });

  test('withdrawn evidence invalidates saved SAME, never silently resets', () {
    final pair = review.hints.firstWhere(
        (h) => h.kind == IdentityHintKind.explicitAlias &&
            h.sourceKind == EvidenceKind.character);
    final accepted = review.decide(
        index, graph, pair.id, IdentityDecision.same);
    final rejected = graph.review(
        index, pair.firstId, EvidenceStatus.rejected);
    expect(() => build(accepted, otherGraph: rejected),
        throwsFormatException);
  });

  test('wrong source edition is rejected rather than copied to other book', () {
    final other = BookSourceIndexer.index(const ImportedBook(
      title: 'Иное издание', author: 'Автор',
      chapters: ['Другая книга.'],
    ));
    expect(() => SourceCharacterDossierIndex.build(
        other, graph, review, catalog, editorial), throwsFormatException);
  });
}
