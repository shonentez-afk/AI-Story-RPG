import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';

/// M2c: editorial review is local and explicit. Model suggestions do not
/// trigger decide(). Even CANON_CANDIDATE is not accepted game-world truth
/// before continuity, identity, temporal and causal checks.
enum SemanticEditorialVerdict {
  passageOnly,
  canonCandidate,
  disputed,
  rejected,
}

class SemanticEditorialReviewSession {
  SemanticEditorialReviewSession._({
    required this.sourceFingerprint,
    required this.catalogSha256,
    required Map<String, SemanticEditorialVerdict> verdicts,
  }) : verdicts = Map.unmodifiable(verdicts);

  static const format = 'ai_story_semantic_editorial_m2c_v1';
  static const maxCheckpointBytes = 1024 * 1024;
  final String sourceFingerprint;
  final String catalogSha256;
  final Map<String, SemanticEditorialVerdict> verdicts;

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _catalogHash(SourceSemanticCatalog catalog) =>
      _hash(catalog.encode());

  factory SemanticEditorialReviewSession.create(
      BookSourceIndex index, SourceSemanticCatalog catalog) {
    if (index.sourceFingerprint != catalog.sourceFingerprint) {
      throw const FormatException('Чужой смысловой каталог');
    }
    return SemanticEditorialReviewSession._(
      sourceFingerprint: index.sourceFingerprint,
      catalogSha256: _catalogHash(catalog),
      verdicts: const {},
    );
  }

  int get reviewedCount => verdicts.length;
  int get canonCandidates => verdicts.values
      .where((value) => value == SemanticEditorialVerdict.canonCandidate)
      .length;
  bool get canPublishBookworld => false;
  bool get isWorldCanon => false;

  bool matches(BookSourceIndex index, SourceSemanticCatalog catalog) =>
      sourceFingerprint == index.sourceFingerprint &&
      sourceFingerprint == catalog.sourceFingerprint &&
      catalogSha256 == _catalogHash(catalog);

  SemanticEditorialReviewSession decide(
      SourceSemanticCatalog catalog, String assertionId,
      SemanticEditorialVerdict? verdict) {
    if (sourceFingerprint != catalog.sourceFingerprint ||
        catalogSha256 != _catalogHash(catalog) ||
        !catalog.assertions.any((a) => a.id == assertionId)) {
      throw const FormatException('Устаревшее или неизвестное утверждение');
    }
    final next = Map<String, SemanticEditorialVerdict>.from(verdicts);
    if (verdict == null) {
      next.remove(assertionId);
    } else {
      next[assertionId] = verdict;
    }
    return SemanticEditorialReviewSession._(
      sourceFingerprint: sourceFingerprint,
      catalogSha256: catalogSha256,
      verdicts: next,
    );
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': sourceFingerprint,
    'catalog_sha256': catalogSha256,
    'status': 'EDITORIAL_CANDIDATES_ONLY',
    'can_publish_bookworld': false,
    'gameplay_coverage': 0,
    'verdicts': {
      for (final entry in verdicts.entries)
        entry.key: entry.value.name.toUpperCase(),
    },
  };

  String encode() {
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _hash(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой редакторский checkpoint');
    }
    return raw;
  }

  static SemanticEditorialReviewSession decode(
      BookSourceIndex index, SourceEvidenceGraph graph,
      SourceSemanticCatalog catalog, String raw) {
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой редакторский checkpoint');
    }
    try {
      if (index.sourceFingerprint != graph.sourceFingerprint ||
          graph.sourceFingerprint != catalog.sourceFingerprint) {
        throw const FormatException('Устарела редакция книги');
      }
      // No persisted verdict may bypass the exact source citations.
      for (final item in catalog.assertions) {
        SourceSemanticAssertion.fromJson(index, graph, item.toJson());
      }
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const keys = {
        'source_fingerprint', 'catalog_sha256', 'status',
        'can_publish_bookworld', 'gameplay_coverage', 'verdicts',
      };
      if (root.length != 3 ||
          !root.keys.toSet().containsAll({'format', 'payload', 'sha256'}) ||
          root['format'] != format || payload.length != keys.length ||
          !payload.keys.toSet().containsAll(keys) ||
          root['sha256'] != _hash(jsonEncode(payload)) ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['catalog_sha256'] != _catalogHash(catalog) ||
          payload['status'] != 'EDITORIAL_CANDIDATES_ONLY' ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Повреждён редакторский checkpoint');
      }
      final rawVerdicts = Map<String, dynamic>.from(
          payload['verdicts'] as Map);
      if (rawVerdicts.length > catalog.assertions.length) {
        throw const FormatException('Лишние редакторские решения');
      }
      final available = {for (final a in catalog.assertions) a.id};
      final verdicts = <String, SemanticEditorialVerdict>{};
      for (final entry in rawVerdicts.entries) {
        if (!available.contains(entry.key)) {
          throw const FormatException('Решение ссылается на чужой факт');
        }
        final selected = SemanticEditorialVerdict.values.where(
            (v) => v.name.toUpperCase() == entry.value).toList();
        if (selected.length != 1) {
          throw const FormatException('Неизвестный редакторский вердикт');
        }
        verdicts[entry.key] = selected.single;
      }
      final session = SemanticEditorialReviewSession._(
        sourceFingerprint: index.sourceFingerprint,
        catalogSha256: _catalogHash(catalog),
        verdicts: verdicts,
      );
      if (session.encode() != raw) {
        throw const FormatException('Неканонический редакторский checkpoint');
      }
      return session;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неизвестный формат редакторского checkpoint');
    }
  }
}
