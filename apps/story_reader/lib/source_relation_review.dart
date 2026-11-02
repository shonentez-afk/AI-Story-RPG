import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_extractor.dart';

/// M2b3c editorial identity links, NOT a canonical character model.
/// A verified source quote is not proof that an actor exists in the world.
enum IdentityHintKind { explicitAlias, repeatedName }
enum IdentityDecision { unresolved, same, different }
enum ChapterTimeDecision { unknown, forward, flashback, parallel }

class IdentityHint {
  const IdentityHint({
    required this.id,
    required this.kind,
    required this.firstId,
    required this.secondId,
    required this.firstName,
    required this.secondName,
    required this.sourceKind,
  });

  final String id;
  final IdentityHintKind kind;
  final String firstId;
  final String secondId;
  final String firstName;
  final String secondName;
  final EvidenceKind sourceKind;

  /// A name match is an editorial hypothesis, never automatic entity merge.
  bool get isAutomaticallyMerged => false;
}

class IdentityRelationReview {
  const IdentityRelationReview({
    required this.hint,
    required this.decision,
  });

  final IdentityHint hint;
  final IdentityDecision decision;

  bool get mayPublishCanonicalIdentity => false;
}

class ChapterTemporalReview {
  const ChapterTemporalReview({
    required this.beforeChapter,
    required this.afterChapter,
    required this.decision,
  });

  final int beforeChapter;
  final int afterChapter;
  final ChapterTimeDecision decision;

  /// Textual order is known; in-world chronology never inferred from it.
  bool get isAuthoritativeTimeline => false;
}

/// A separate checkpoint from both M2b1 mentions and M2b3b evidence.
/// Only human editorial decisions are persisted, with ids anchored in the
/// validated SourceEvidenceGraph. No book text is duplicated in this file.
class SourceRelationReviewSession {
  SourceRelationReviewSession._(
    this.sourceFingerprint,
    this.chapterCount,
    List<IdentityHint> hints,
    Map<String, IdentityDecision> decisions,
    Map<int, ChapterTimeDecision> chapterDecisions,
  ) : hints = List.unmodifiable(hints),
      _decisions = Map.unmodifiable(decisions),
      _chapterDecisions = Map.unmodifiable(chapterDecisions);

  static const format = 'ai_story_relation_review_m2b3c_v1';
  static const maxHints = 256;
  static const maxCheckpointBytes = 512 * 1024;

  final String sourceFingerprint;
  final int chapterCount;
  final List<IdentityHint> hints;
  final Map<String, IdentityDecision> _decisions;
  final Map<int, ChapterTimeDecision> _chapterDecisions;

  bool get canPublishBookworld => false;
  double get gameplayCoverage => 0;

  static String _sha(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _normalized(String raw) => raw.trim().toLowerCase()
      .replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ');

  static void _checkSource(BookSourceIndex index, SourceEvidenceGraph graph) {
    if (graph.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Связи относятся к другой редакции');
    }
    for (final entry in graph.records) {
      entry.validate(index);
    }
  }

  static IdentityHint _hint(
      IdentityHintKind type, SourceEvidence a, SourceEvidence b) {
    if (a.id == b.id || a.kind != b.kind ||
        (a.kind != EvidenceKind.character &&
         a.kind != EvidenceKind.location) ||
        a.status == EvidenceStatus.rejected ||
        b.status == EvidenceStatus.rejected) {
      throw const FormatException('Недопустимая пара упоминаний');
    }
    final sortedIds = [a.id, b.id]..sort();
    // Display explicit aliases in the book's textual order while the
    // relation ID remains stable regardless of endpoint ordering.
    final left = type == IdentityHintKind.explicitAlias || a.id.compareTo(b.id) <= 0
        ? a : b;
    final right = identical(left, a) ? b : a;
    return IdentityHint(
      id: _sha(type.name + '|' + sortedIds[0] + '|' + sortedIds[1])
          .substring(0, 32),
      kind: type,
      firstId: left.id,
      secondId: right.id,
      firstName: left.label,
      secondName: right.label,
      sourceKind: left.kind,
    );
  }

  /// Bound the candidate set and prefer explicit source phrases.
  /// Cross-chapter repeated spellings are linked only as adjacent hints,
  /// preventing quadratic growth for very common names in a long novel.
  static List<IdentityHint> _generate(
      BookSourceIndex index, SourceEvidenceGraph graph) {
    _checkSource(index, graph);
    final byId = {for (final item in graph.records) item.id: item};
    final hints = <IdentityHint>[];
    final seen = <String>{};

    void append(IdentityHint candidate) {
      if (seen.add(candidate.id) && hints.length < maxHints) {
        hints.add(candidate);
      }
    }

    for (final pair in SourceNarrativeExtractor.explicitAliasHints(
        index, graph, limit: maxHints)) {
      final a = byId[pair.firstId], b = byId[pair.secondId];
      if (a != null && b != null) {
        append(_hint(IdentityHintKind.explicitAlias, a, b));
      }
      if (hints.length >= maxHints) break;
    }

    final groups = <String, List<SourceEvidence>>{};
    for (final evidence in graph.records) {
      if (evidence.status == EvidenceStatus.rejected ||
          (evidence.kind != EvidenceKind.character &&
           evidence.kind != EvidenceKind.location)) continue;
      final key = evidence.kind.name + '|' + _normalized(evidence.label);
      groups.putIfAbsent(key, () => []).add(evidence);
    }
    final keys = groups.keys.toList()..sort();
    for (final key in keys) {
      final items = groups[key]!
        ..sort((a, b) {
          final cmp = a.chapterIndex.compareTo(b.chapterIndex);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
      SourceEvidence? prior;
      for (final record in items) {
        if (prior != null &&
            record.chapterIndex != prior.chapterIndex) {
          append(_hint(IdentityHintKind.repeatedName, prior, record));
        }
        prior = record;
        if (hints.length >= maxHints) break;
      }
      if (hints.length >= maxHints) break;
    }

    hints.sort((a, b) {
      final kind = a.kind.index.compareTo(b.kind.index);
      return kind != 0 ? kind : a.id.compareTo(b.id);
    });
    return List.unmodifiable(hints);
  }

  factory SourceRelationReviewSession.create(
      BookSourceIndex index, SourceEvidenceGraph graph) =>
      SourceRelationReviewSession._(
        index.sourceFingerprint, index.chapters.length,
        _generate(index, graph),
        const {}, const {},
      );

  List<IdentityRelationReview> get proposedRelations =>
      List.unmodifiable([
        for (final hint in hints)
          IdentityRelationReview(
            hint: hint,
            decision: _decisions[hint.id] ?? IdentityDecision.unresolved,
          ),
      ]);

  int get unresolvedCount => hints.where(
      (h) => !_decisions.containsKey(h.id)).length;

  IdentityDecision decisionFor(String id) =>
      _decisions[id] ?? IdentityDecision.unresolved;

  ChapterTimeDecision temporalDecision(int beforeChapter) =>
      _chapterDecisions[beforeChapter] ?? ChapterTimeDecision.unknown;

  List<ChapterTemporalReview> get chapterOrder =>
      List.unmodifiable([
        for (var chapter = 0; chapter + 1 < chapterCount; chapter++)
          ChapterTemporalReview(
            beforeChapter: chapter,
            afterChapter: chapter + 1,
            decision: temporalDecision(chapter),
          ),
      ]);

  void _check(BookSourceIndex index, SourceEvidenceGraph graph) {
    _checkSource(index, graph);
    if (index.sourceFingerprint != sourceFingerprint ||
        index.chapters.length != chapterCount) {
      throw const FormatException('Изменилась исходная книга');
    }
    final generated = _generate(index, graph);
    if (generated.length != hints.length ||
        generated.any((h) => !hints.any((v) => v.id == h.id))) {
      throw const FormatException('Основания для связей изменились');
    }
  }

  /// Refuses transitive SAME/DIFFERENT contradictions.
  /// This is consistency checking of human annotations, not entity merging.
  static void _validateDecisions(
      Iterable<IdentityHint> hints,
      Map<String, IdentityDecision> decisions) {
    final hintsById = {for (final h in hints) h.id: h};
    final parent = <String, String>{};

    String find(String id) {
      parent.putIfAbsent(id, () => id);
      var root = id;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      var step = id;
      while (step != root) {
        final next = parent[step]!;
        parent[step] = root;
        step = next;
      }
      return root;
    }

    for (final entry in decisions.entries) {
      if (entry.value == IdentityDecision.unresolved ||
          !hintsById.containsKey(entry.key)) {
        throw const FormatException('Неизвестное решение по связи');
      }
      final h = hintsById[entry.key]!;
      if (entry.value == IdentityDecision.same) {
        parent[find(h.firstId)] = find(h.secondId);
      }
    }
    for (final entry in decisions.entries) {
      if (entry.value != IdentityDecision.different) continue;
      final h = hintsById[entry.key]!;
      if (find(h.firstId) == find(h.secondId)) {
        throw const FormatException('Противоречие SAME/DIFFERENT');
      }
    }
  }

  SourceRelationReviewSession decide(
      BookSourceIndex index,
      SourceEvidenceGraph graph,
      String id,
      IdentityDecision choice) {
    _check(index, graph);
    final matched = hints.where((h) => h.id == id).toList();
    if (matched.length != 1) {
      throw ArgumentError.value(id, 'id', 'Связь не найдена');
    }
    final h = matched.single;
    if (choice != IdentityDecision.unresolved) {
      final entries = {for (final e in graph.records) e.id: e};
      if (entries[h.firstId]?.status != EvidenceStatus.confirmed ||
          entries[h.secondId]?.status != EvidenceStatus.confirmed) {
        throw StateError('Сначала подтвердите обе исходные цитаты');
      }
    }
    final next = Map<String, IdentityDecision>.from(_decisions);
    if (choice == IdentityDecision.unresolved) {
      next.remove(id);
    } else {
      next[id] = choice;
    }
    _validateDecisions(hints, next);
    return SourceRelationReviewSession._(
      sourceFingerprint, chapterCount, hints, next, _chapterDecisions);
  }

  SourceRelationReviewSession decideChapter(
      BookSourceIndex index, int before, ChapterTimeDecision choice) {
    if (sourceFingerprint != index.sourceFingerprint ||
        chapterCount != index.chapters.length ||
        before < 0 || before >= chapterCount - 1) {
      throw const FormatException('Недопустимая граница глав');
    }
    final next = Map<int, ChapterTimeDecision>.from(_chapterDecisions);
    if (choice == ChapterTimeDecision.unknown) {
      next.remove(before);
    } else {
      next[before] = choice;
    }
    return SourceRelationReviewSession._(
      sourceFingerprint, chapterCount, hints, _decisions, next);
  }

  /// Reconstruct from CURRENT verified evidence; a rejected supporting quote
  /// invalidates the saved relation instead of silently preserving SAME.
  String encode() {
    final decisions = _decisions.keys.toList()..sort();
    final order = _chapterDecisions.keys.toList()..sort();
    final payload = <String, Object>{
      'source_fingerprint': sourceFingerprint,
      'chapter_count': chapterCount,
      'stage': 'RELATION_EDITORIAL_REVIEW_ONLY',
      'gameplay_coverage': 0,
      'can_publish_bookworld': false,
      'decisions': [
        for (final id in decisions)
          {'id': id, 'decision': _decisions[id]!.name.toUpperCase()},
      ],
      'chapter_order': [
        for (final before in order)
          {'before': before,
           'decision': _chapterDecisions[before]!.name.toUpperCase()},
      ],
    };
    final text = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(text).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой checkpoint связей');
    }
    return text;
  }

  static SourceRelationReviewSession decode(
      BookSourceIndex index, SourceEvidenceGraph graph, String raw) {
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой checkpoint связей');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root.keys.toSet().length != 3 ||
          !root.keys.toSet().containsAll({'format', 'payload', 'sha256'}) ||
          root['format'] != format) {
        throw const FormatException('Неизвестный формат связей');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (payload.keys.toSet().length != 7 ||
          !payload.keys.toSet().containsAll({
            'source_fingerprint', 'chapter_count', 'stage',
            'gameplay_coverage', 'can_publish_bookworld',
            'decisions', 'chapter_order',
          }) ||
          root['sha256'] != _sha(jsonEncode(payload)) ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['chapter_count'] != index.chapters.length ||
          payload['stage'] != 'RELATION_EDITORIAL_REVIEW_ONLY' ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Связи относятся к другой книге');
      }
      final session = SourceRelationReviewSession.create(index, graph);
      final rawDecisions = payload['decisions'] as List;
      final rawOrder = payload['chapter_order'] as List;
      if (rawDecisions.length > maxHints ||
          rawOrder.length > index.chapters.length) {
        throw const FormatException('Превышен лимит решений');
      }
      final decisions = <String, IdentityDecision>{};
      for (final entry in rawDecisions) {
        final m = Map<String, dynamic>.from(entry as Map);
        if (m.keys.length != 2 ||
            !m.keys.toSet().containsAll({'id', 'decision'})) {
          throw const FormatException('Неизвестное поле связи');
        }
        final id = m['id'] as String;
        final choice = IdentityDecision.values.byName(
            (m['decision'] as String).toLowerCase());
        if (choice == IdentityDecision.unresolved ||
            decisions.containsKey(id)) {
          throw const FormatException('Повторное или пустое решение');
        }
        decisions[id] = choice;
      }
      final order = <int, ChapterTimeDecision>{};
      for (final entry in rawOrder) {
        final m = Map<String, dynamic>.from(entry as Map);
        if (m.keys.length != 2 ||
            !m.keys.toSet().containsAll({'before', 'decision'})) {
          throw const FormatException('Неизвестное поле хронологии');
        }
        final before = m['before'] as int;
        final choice = ChapterTimeDecision.values.byName(
            (m['decision'] as String).toLowerCase());
        if (choice == ChapterTimeDecision.unknown ||
            order.containsKey(before) ||
            before < 0 || before >= index.chapters.length - 1) {
          throw const FormatException('Невозможная хронология глав');
        }
        order[before] = choice;
      }
      _validateDecisions(session.hints, decisions);
      final entries = {for (final e in graph.records) e.id: e};
      final byHint = {for (final h in session.hints) h.id: h};
      for (final id in decisions.keys) {
        final hint = byHint[id];
        if (hint == null ||
            entries[hint.firstId]?.status != EvidenceStatus.confirmed ||
            entries[hint.secondId]?.status != EvidenceStatus.confirmed) {
          throw const FormatException('Опорная цитата отозвана или изменена');
        }
      }
      final restored = SourceRelationReviewSession._(
          index.sourceFingerprint, index.chapters.length,
          session.hints, decisions, order);
      // Reject non-canonical/hidden fields and corrupt edge ids.
      if (restored.encode() != raw) {
        throw const FormatException('Неоднозначная запись связей');
      }
      return restored;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённый checkpoint связей');
    }
  }
}
