import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_relation_review.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// A possible relationship suggested by a semantic assertion matching the
/// character's written name. A name match never establishes actor identity.
class CharacterRelationshipHint {
  const CharacterRelationshipHint({
    required this.assertion,
    required this.chapterIndex,
    required this.citation,
    required this.verdict,
  });

  final SourceSemanticAssertion assertion;
  final int chapterIndex;
  final String citation;
  final SemanticEditorialVerdict? verdict;

  bool get provesCharacterRelationship => false;
}

/// A read-only view of character *mentions*, never an NPC/world actor.
/// Only human-reviewed SAME identity edges can combine two mentions.
class SourceCharacterDossier {
  const SourceCharacterDossier({
    required this.id,
    required this.labels,
    required this.mentions,
    required this.identityHints,
    required this.aliasHints,
    required this.relationshipHints,
  });

  /// Deterministic representative evidence ID (not a permanent actor ID).
  final String id;
  final List<String> labels;
  final List<SourceEvidence> mentions;
  final List<IdentityRelationReview> identityHints;
  final List<SourceSemanticAssertion> aliasHints;
  final List<CharacterRelationshipHint> relationshipHints;

  int get confirmedQuotes => mentions
      .where((e) => e.status == EvidenceStatus.confirmed).length;
  int get firstChapter => mentions.first.chapterIndex;
  int get lastChapter => mentions.last.chapterIndex;
  bool get isCanonicalNpc => false;
  bool get identityIsFullyResolved =>
      identityHints.isNotEmpty &&
      identityHints.every((e) => e.decision != IdentityDecision.unresolved);
}

/// A derived index: no new save file, no world edits, no model calls.
/// No two same-name quotes are silently merged. Decisions come solely from
/// SourceRelationReviewSession and are re-validated against exact source spans.
class SourceCharacterDossierIndex {
  const SourceCharacterDossierIndex._(this.sourceFingerprint, this.dossiers,
      this.totalCharacterMentions, this.pendingIdentityHints);

  final String sourceFingerprint;
  final List<SourceCharacterDossier> dossiers;
  final int totalCharacterMentions;
  final int pendingIdentityHints;

  int get possibleCharacterGroups => dossiers.length;
  bool get canPublishNpcCanon => false;

  static String _normal(String s) => s.trim().toLowerCase()
      .replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ');

  static SourceCharacterDossierIndex build(
    BookSourceIndex index,
    SourceEvidenceGraph graph,
    SourceRelationReviewSession relations,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
  ) {
    if (graph.sourceFingerprint != index.sourceFingerprint ||
        relations.sourceFingerprint != index.sourceFingerprint ||
        catalog.sourceFingerprint != index.sourceFingerprint ||
        !editorial.matches(index, catalog)) {
      throw const FormatException('Карточки относятся к другой редакции книги');
    }
    // Do not trust a stale/rejected same edge. The existing session decoder
    // enforces source quote validity and transitive SAME/DIFFERENT consistency.
    final review = SourceRelationReviewSession.decode(
        index, graph, relations.encode());
    final mentionById = <String, SourceEvidence>{};
    for (final e in graph.records) {
      e.validate(index);
      if (e.kind == EvidenceKind.character &&
          e.status != EvidenceStatus.rejected) {
        mentionById[e.id] = e;
      }
    }

    final parent = <String, String>{
      for (final id in mentionById.keys) id: id,
    };
    String root(String id) {
      var current = id;
      while (parent[current] != current) {
        current = parent[current]!;
      }
      var step = id;
      while (step != current) {
        final next = parent[step]!;
        parent[step] = current;
        step = next;
      }
      return current;
    }

    for (final hint in review.hints) {
      if (hint.sourceKind != EvidenceKind.character ||
          review.decisionFor(hint.id) != IdentityDecision.same) continue;
      final left = mentionById[hint.firstId];
      final right = mentionById[hint.secondId];
      if (left == null || right == null ||
          left.status != EvidenceStatus.confirmed ||
          right.status != EvidenceStatus.confirmed) {
        throw const FormatException(
            'Нельзя объединять имена без двух подтверждённых цитат');
      }
      final a = root(left.id);
      final b = root(right.id);
      if (a != b) parent[a.compareTo(b) < 0 ? b : a] =
          a.compareTo(b) < 0 ? a : b;
    }

    final groups = <String, List<SourceEvidence>>{};
    for (final e in mentionById.values) {
      groups.putIfAbsent(root(e.id), () => []).add(e);
    }
    final hints = review.proposedRelations
        .where((r) => r.hint.sourceKind == EvidenceKind.character)
        .toList();
    final hintByMention = <String, List<IdentityRelationReview>>{};
    for (final hint in hints) {
      for (final id in {hint.hint.firstId, hint.hint.secondId}) {
        hintByMention.putIfAbsent(id, () => []).add(hint);
      }
    }
    final aliasByMention = <String, List<SourceSemanticAssertion>>{};
    final relationByName = <String, List<CharacterRelationshipHint>>{};
    final byEvidence = {for (final e in graph.records) e.id: e};
    for (final claim in catalog.assertions) {
      if (claim.kind == SemanticAssertionKind.alias) {
        for (final id in claim.evidenceIds) {
          if (mentionById.containsKey(id)) {
            aliasByMention.putIfAbsent(id, () => []).add(claim);
          }
        }
      } else if (claim.kind == SemanticAssertionKind.relation &&
          claim.evidenceIds.isNotEmpty) {
        final refs = [
          for (final id in claim.evidenceIds)
            if (byEvidence.containsKey(id)) byEvidence[id]!,
        ];
        if (refs.length != claim.evidenceIds.length ||
            refs.any((e) => e.status == EvidenceStatus.rejected)) continue;
        refs.sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
        final event = CharacterRelationshipHint(
          assertion: claim,
          chapterIndex: refs.first.chapterIndex,
          citation: refs.map((e) => e.label).join(' / '),
          verdict: editorial.verdicts[claim.id],
        );
        for (final name in {
          _normal(claim.subject), _normal(claim.object),
        }) {
          relationByName.putIfAbsent(name, () => []).add(event);
        }
      }
    }
    final dossiers = <SourceCharacterDossier>[];
    for (final mentions in groups.values) {
      mentions.sort((a, b) {
        final chapter = a.chapterIndex.compareTo(b.chapterIndex);
        if (chapter != 0) return chapter;
        final offset = a.startUtf16.compareTo(b.startUtf16);
        if (offset != 0) return offset;
        return a.id.compareTo(b.id);
      });
      final labels = <String>[];
      for (final m in mentions) {
        if (!labels.contains(m.label)) labels.add(m.label);
      }
      final hintIds = <String>{};
      final linkedHints = <IdentityRelationReview>[];
      final aliasIds = <String>{};
      final aliasHints = <SourceSemanticAssertion>[];
      final relationIds = <String>{};
      final relationships = <CharacterRelationshipHint>[];
      for (final mention in mentions) {
        for (final edge in hintByMention[mention.id] ??
            const <IdentityRelationReview>[]) {
          if (hintIds.add(edge.hint.id)) linkedHints.add(edge);
        }
        for (final alias in aliasByMention[mention.id] ??
            const <SourceSemanticAssertion>[]) {
          if (aliasIds.add(alias.id)) aliasHints.add(alias);
        }
      }
      for (final label in labels) {
        for (final candidate in relationByName[_normal(label)] ??
            const <CharacterRelationshipHint>[]) {
          if (relationIds.add(candidate.assertion.id)) {
            relationships.add(candidate);
          }
        }
      }
      dossiers.add(SourceCharacterDossier(
        id: (mentions.map((e) => e.id).toList()..sort()).first,
        labels: List.unmodifiable(labels),
        mentions: List.unmodifiable(mentions),
        identityHints: List.unmodifiable(linkedHints),
        aliasHints: List.unmodifiable(aliasHints),
        relationshipHints: List.unmodifiable(relationships),
      ));
    }
    dossiers.sort((a, b) {
      final chapter = a.firstChapter.compareTo(b.firstChapter);
      if (chapter != 0) return chapter;
      final offset = a.mentions.first.startUtf16
          .compareTo(b.mentions.first.startUtf16);
      if (offset != 0) return offset;
      return a.id.compareTo(b.id);
    });
    return SourceCharacterDossierIndex._(
      index.sourceFingerprint, List.unmodifiable(dossiers),
      mentionById.length,
      hints.where((h) => h.decision == IdentityDecision.unresolved).length,
    );
  }
}
