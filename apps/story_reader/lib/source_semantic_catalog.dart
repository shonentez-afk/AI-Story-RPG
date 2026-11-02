import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_extractor.dart';

/// Model-independent M2b4b staging. A citation is evidence of words on a
/// page, NOT evidence that the proposition describes the true story world.
enum SemanticAssertionKind { character, location, event, fact, relation, alias }
enum AssertionVoice { narratorCandidate, reported, uncertain }
enum AssertionPolarity { affirmative, negated, ambiguous }
enum AssertionTime { textOrderOnly, flashbackPossible, unresolved }

class SourceSemanticAssertion {
  SourceSemanticAssertion._({
    required this.id,
    required this.kind,
    required this.evidenceIds,
    required this.subject,
    required this.predicate,
    required this.object,
    required this.voice,
    required this.polarity,
    required this.time,
    required this.uncertainty,
  });

  final String id;
  final SemanticAssertionKind kind;
  final List<String> evidenceIds;
  final String subject;
  final String predicate;
  final String object;
  final AssertionVoice voice;
  final AssertionPolarity polarity;
  final AssertionTime time;
  final String uncertainty;

  /// Model output cannot set these to true. Explicit editorial validation and
  /// the later story compiler are separate gates.
  bool get isVerifiedWorldTruth => false;
  bool get establishesIdentity => false;
  bool get canPublishBookworld => false;

  static final RegExp _safeValue =
      RegExp(r'^[^\x00-\x08\x0b\x0c\x0e-\x1f]{1,160}$', unicode: true);

  static String _digest(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  static String _identity(Map<String, Object> payload) =>
      _digest(jsonEncode(payload)).substring(0, 32);

  static Map<String, Object> _fields({
    required SemanticAssertionKind kind,
    required List<String> evidenceIds,
    required String subject,
    required String predicate,
    required String object,
    required AssertionVoice voice,
    required AssertionPolarity polarity,
    required AssertionTime time,
    required String uncertainty,
  }) => {
    'kind': kind.name.toUpperCase(),
    'evidence_ids': evidenceIds,
    'subject': subject,
    'predicate': predicate,
    'object': object,
    'voice': voice.name.toUpperCase(),
    'polarity': polarity.name.toUpperCase(),
    'time': time.name.toUpperCase(),
    'uncertainty': uncertainty,
    'status': 'INFERRED',
  };

  factory SourceSemanticAssertion.propose(
    BookSourceIndex index,
    SourceEvidenceGraph graph, {
    required SemanticAssertionKind kind,
    required List<String> evidenceIds,
    required String subject,
    required String predicate,
    required String object,
    required AssertionVoice voice,
    required AssertionPolarity polarity,
    required AssertionTime time,
    required String uncertainty,
  }) {
    if (graph.sourceFingerprint != index.sourceFingerprint ||
        evidenceIds.isEmpty || evidenceIds.length > 3 ||
        evidenceIds.toSet().length != evidenceIds.length ||
        !_safeValue.hasMatch(subject) || subject.trim().isEmpty ||
        !_safeValue.hasMatch(predicate) || predicate.trim().isEmpty ||
        object.length > 160 || uncertainty.trim().isEmpty ||
        uncertainty.length > 240 ||
        (kind == SemanticAssertionKind.relation && object.trim().isEmpty)) {
      throw const FormatException('Некорректное смысловое предложение');
    }
    if (object.isNotEmpty && !_safeValue.hasMatch(object)) {
      throw const FormatException('Недопустимое значение утверждения');
    }
    final sources = {for (final e in graph.records) e.id: e};
    for (final evidenceId in evidenceIds) {
      final record = sources[evidenceId];
      if (record == null || record.status == EvidenceStatus.rejected) {
        throw const FormatException('Нет исходного подтверждения цитаты');
      }
      record.validate(index);
      if (kind == SemanticAssertionKind.event &&
          record.kind != EvidenceKind.event ||
          kind == SemanticAssertionKind.fact &&
          record.kind != EvidenceKind.fact ||
          (kind == SemanticAssertionKind.character ||
              kind == SemanticAssertionKind.alias) &&
          record.kind != EvidenceKind.character ||
          kind == SemanticAssertionKind.location &&
          record.kind != EvidenceKind.location) {
        throw const FormatException('Тип утверждения не совпадает с цитатой');
      }
    }
    final payload = _fields(
      kind: kind, evidenceIds: evidenceIds, subject: subject,
      predicate: predicate, object: object, voice: voice,
      polarity: polarity, time: time, uncertainty: uncertainty,
    );
    return SourceSemanticAssertion._(
      id: _identity(payload), kind: kind,
      evidenceIds: List.unmodifiable(evidenceIds),
      subject: subject, predicate: predicate, object: object,
      voice: voice, polarity: polarity, time: time,
      uncertainty: uncertainty,
    );
  }

  Map<String, Object> toJson() {
    final result = _fields(
      kind: kind, evidenceIds: evidenceIds, subject: subject,
      predicate: predicate, object: object, voice: voice,
      polarity: polarity, time: time, uncertainty: uncertainty,
    );
    return {'id': id, ...result};
  }

  factory SourceSemanticAssertion.fromJson(
      BookSourceIndex index, SourceEvidenceGraph graph,
      Map<String, dynamic> json) {
    const requiredKeys = {
      'id', 'kind', 'evidence_ids', 'subject', 'predicate', 'object',
      'voice', 'polarity', 'time', 'uncertainty', 'status',
    };
    if (json.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(json.keys.toSet()).isNotEmpty ||
        json['status'] != 'INFERRED') {
      throw const FormatException('Неизвестный формат или статус утверждения');
    }
    try {
      T parse<T extends Enum>(List<T> values, Object? value) {
        return values.firstWhere(
            (item) => item.name.toUpperCase() == value);
      }
      final proposed = SourceSemanticAssertion.propose(index, graph,
        kind: parse(SemanticAssertionKind.values, json['kind']),
        evidenceIds: (json['evidence_ids'] as List)
            .map((e) => e as String).toList(growable: false),
        subject: json['subject'] as String,
        predicate: json['predicate'] as String,
        object: json['object'] as String,
        voice: parse(AssertionVoice.values, json['voice']),
        polarity: parse(AssertionPolarity.values, json['polarity']),
        time: parse(AssertionTime.values, json['time']),
        uncertainty: json['uncertainty'] as String,
      );
      if (proposed.id != json['id'] ||
          jsonEncode(proposed.toJson()) != jsonEncode(json)) {
        throw const FormatException('Подмена смыслового утверждения');
      }
      return proposed;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неверные поля смыслового утверждения');
    }
  }
}

class PossibleSemanticDiscrepancy {
  const PossibleSemanticDiscrepancy(this.firstId, this.secondId,
      this.subject, this.predicate);

  final String firstId;
  final String secondId;
  final String subject;
  final String predicate;

  /// A state changed in time is not necessarily a contradiction.
  bool get isProvenContradiction => false;
}

class SourceSemanticCatalog {
  SourceSemanticCatalog._(this.sourceFingerprint, this.assertions);

  static const format = 'ai_story_source_semantic_catalog_m2b4b_v1';
  static const maxAssertions = 6000;
  static const maxUtf8Bytes = 6 * 1024 * 1024;

  final String sourceFingerprint;
  final List<SourceSemanticAssertion> assertions;

  bool get canPublishBookworld => false;
  double get gameplayCoverage => 0;

  static String _digest(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  factory SourceSemanticCatalog.checked(
      BookSourceIndex index, SourceEvidenceGraph graph,
      List<SourceSemanticAssertion> assertions) {
    if (graph.sourceFingerprint != index.sourceFingerprint ||
        assertions.length > maxAssertions) {
      throw const FormatException('Неверный источник смыслового каталога');
    }
    final ids = <String>{};
    for (final item in assertions) {
      if (!ids.add(item.id)) {
        throw const FormatException('Дублирующиеся смысловые предложения');
      }
      // Rebuild identity, citations and statuses for all input paths, even
      // if a future LLM fabricated the object.
      SourceSemanticAssertion.fromJson(index, graph, item.toJson());
    }
    return SourceSemanticCatalog._(
        index.sourceFingerprint, List.unmodifiable(assertions));
  }

  /// Reuse already detected exact narrative quotations. Do not fabricate
  /// identities, world truth, temporal order or entity relations.
  factory SourceSemanticCatalog.fromLocalEvidence(
      BookSourceIndex index, SourceEvidenceGraph graph) {
    if (graph.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Чужая редакция книги');
    }
    final accepted = {
      for (final e in graph.records)
        if (e.status != EvidenceStatus.rejected) e.id: e,
    };
    final proposals = <SourceSemanticAssertion>[];
    for (final chunk in index.chunks) {
      if (proposals.length >= maxAssertions) {
        throw const FormatException('Превышено число смысловых предложений');
      }
      for (final claim in SourceNarrativeExtractor.claimsInChunk(index, chunk)) {
        if (!accepted.containsKey(claim.evidence.id)) continue;
        final evidence = accepted[claim.evidence.id]!;
        final kind = evidence.kind == EvidenceKind.event
            ? SemanticAssertionKind.event : SemanticAssertionKind.fact;
        proposals.add(SourceSemanticAssertion.propose(index, graph,
          kind: kind, evidenceIds: [evidence.id],
          subject: claim.subject, predicate: claim.attribute,
          object: claim.value,
          voice: claim.isReported
              ? AssertionVoice.reported : AssertionVoice.uncertain,
          polarity: AssertionPolarity.ambiguous,
          time: AssertionTime.textOrderOnly,
          uncertainty: 'Локальный шаблон. Нужны проверка контекста и времени.',
        ));
      }
    }
    return SourceSemanticCatalog.checked(index, graph, proposals);
  }

  /// Differences are warnings, not fact conflicts or retcons. A door can
  /// be opened in one chapter and closed normally in the next.
  List<PossibleSemanticDiscrepancy> get possibleDiscrepancies {
    final seen = <String, SourceSemanticAssertion>{};
    final output = <PossibleSemanticDiscrepancy>[];
    for (final item in assertions) {
      if (item.kind != SemanticAssertionKind.fact ||
          item.polarity != AssertionPolarity.ambiguous) continue;
      final key = item.subject.toLowerCase().trim() + ':' +
          item.predicate.toLowerCase().trim();
      final previous = seen[key];
      if (previous != null && previous.object != item.object &&
          output.length < 100) {
        output.add(PossibleSemanticDiscrepancy(
            previous.id, item.id, item.subject, item.predicate));
      }
      seen[key] = item;
    }
    return List.unmodifiable(output);
  }

  String encode() {
    final payload = <String, Object>{
      'source_fingerprint': sourceFingerprint,
      'status': 'PROPOSALS_ONLY',
      'gameplay_coverage': 0,
      'can_publish_bookworld': false,
      'assertions': assertions.map((a) => a.toJson()).toList(),
    };
    final raw = jsonEncode({
      'format': format, 'payload': payload,
      'sha256': _digest(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxUtf8Bytes) {
      throw const FormatException('Слишком большой смысловой каталог');
    }
    return raw;
  }

  static SourceSemanticCatalog decode(
      BookSourceIndex index, SourceEvidenceGraph graph, String raw) {
    if (utf8.encode(raw).length > maxUtf8Bytes) {
      throw const FormatException('Слишком большой смысловой каталог');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const keys = {
        'source_fingerprint', 'status', 'gameplay_coverage',
        'can_publish_bookworld', 'assertions',
      };
      if (root.length != 3 || !root.keys.toSet().containsAll(
          {'format', 'payload', 'sha256'}) ||
          root['format'] != format || payload.length != keys.length ||
          !payload.keys.toSet().containsAll(keys) ||
          root['sha256'] != _digest(jsonEncode(payload)) ||
          payload['status'] != 'PROPOSALS_ONLY' ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['gameplay_coverage'] != 0 ||
          payload['can_publish_bookworld'] != false) {
        throw const FormatException('Повреждён смысловой каталог');
      }
      final rawEntries = payload['assertions'] as List;
      if (rawEntries.length > maxAssertions) {
        throw const FormatException('Слишком много смысловых записей');
      }
      return SourceSemanticCatalog.checked(index, graph, [
        for (final item in rawEntries)
          SourceSemanticAssertion.fromJson(
              index, graph, Map<String, dynamic>.from(item as Map)),
      ]);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неверный формат смыслового каталога');
    }
  }
}
