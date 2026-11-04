import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'source_semantic_provider.dart';
import 'story_evidence_review_session.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_semantic_review_queue.dart';

/// M2f3g: one independently reviewed source quotation and one *human-written*
/// candidate assertion. This is NOT a machine-generated canon decision.
class ZaiManuallyAlignedEvent {
  const ZaiManuallyAlignedEvent({
    required this.findingId,
    required this.subject,
    required this.predicate,
    required this.object,
  });

  final String findingId;
  final String subject;
  final String predicate;
  final String object;

  Map<String, Object> toJson() => {
        'finding_id': findingId,
        'subject': subject,
        'predicate': predicate,
        'object': object,
        'review': 'EXPLICIT_HUMAN_QUOTE_AND_NARRATOR_CANDIDATE',
      };

  factory ZaiManuallyAlignedEvent.fromJson(Map<String, dynamic> json) {
    const keys = {'finding_id', 'subject', 'predicate', 'object', 'review'};
    if (json.length != keys.length ||
        !json.keys.toSet().containsAll(keys) ||
        json['review'] != 'EXPLICIT_HUMAN_QUOTE_AND_NARRATOR_CANDIDATE') {
      throw const FormatException('Неизвестный ручной источник M2f3g.');
    }
    return ZaiManuallyAlignedEvent(
      findingId: json['finding_id'] as String,
      subject: json['subject'] as String,
      predicate: json['predicate'] as String,
      object: json['object'] as String,
    );
  }
}

/// A read-only snapshot of the independently prepared, pre-existing M2c
/// repositories. The alignment is stored in ONE separate local checkpoint,
/// avoiding a partially committed 3-file narrative/catalog/editorial update.
class ZaiSourceAlignmentBaseline {
  const ZaiSourceAlignmentBaseline({
    required this.narrative,
    required this.catalog,
    required this.editorial,
  });

  final StoryEvidenceReviewSession narrative;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;

  static Future<ZaiSourceAlignmentBaseline> load({
    required BookSourceIndex index,
    required SourceAnalysisCheckpointRepository narrativeRepository,
    required SourceAnalysisCheckpointRepository catalogRepository,
    required SourceAnalysisCheckpointRepository editorialRepository,
  }) async {
    final fingerprint = index.sourceFingerprint;
    final narrativeText = await narrativeRepository.read(fingerprint);
    if (narrativeText == null) {
      throw const FormatException(
          'Сначала завершите независимый анализ событий M2b/M2c.');
    }
    final narrative = StoryEvidenceReviewSession.decode(index, narrativeText);
    if (narrative.scannedChunks != index.chunks.length) {
      throw const FormatException(
          'Не все исходные фрагменты прошли локальный анализ.');
    }
    final catalogText = await catalogRepository.read(fingerprint);
    if (catalogText == null) {
      throw const FormatException(
          'Не подготовлен независимый смысловой каталог M2c.');
    }
    final catalog =
        SourceSemanticCatalog.decode(index, narrative.graph, catalogText);
    final editorialText = await editorialRepository.read(fingerprint);
    final editorial = editorialText == null
        ? SemanticEditorialReviewSession.create(index, catalog)
        : SemanticEditorialReviewSession.decode(
            index, narrative.graph, catalog, editorialText);
    return ZaiSourceAlignmentBaseline(
      narrative: narrative, catalog: catalog, editorial: editorial);
  }
}

class ZaiAppliedSourceAlignment {
  const ZaiAppliedSourceAlignment({
    required this.evidence,
    required this.catalog,
    required this.editorial,
    required this.assertionByFinding,
  });

  final SourceEvidenceGraph evidence;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final Map<String, String> assertionByFinding;

  bool get canPublishBookworld => false;
  bool get provesNpcKnowledge => false;
}

/// An isolated, reversible, edition-bound review overlay. No changes to the
/// historical narrative, semantic catalog, original FB2, old campaigns, or
/// hidden model credentials. A signature here detects corruption and stale
/// baselines; it is NOT an authentication signature or copyright clearance.
class ZaiManualSourceAlignment {
  ZaiManualSourceAlignment._(
    this.sourceFingerprint,
    this.baselineDigest,
    List<ZaiManuallyAlignedEvent> entries,
  ) : entries = List.unmodifiable(entries);

  static const format = 'ai_story_manual_source_alignment_m2f3g_v1';
  static const maxBytes = 512 * 1024;
  static const maxEvents = 192;
  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  final String sourceFingerprint;
  final String baselineDigest;
  final List<ZaiManuallyAlignedEvent> entries;

  bool get canPublishBookworld => false;
  bool get canSendToCloud => false;
  bool get isAutomaticCanon => false;

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _baselineSignature(
      BookSourceIndex index, ZaiSourceAlignmentBaseline baseline) {
    if (baseline.narrative.sourceFingerprint != index.sourceFingerprint ||
        baseline.catalog.sourceFingerprint != index.sourceFingerprint ||
        !baseline.editorial.matches(index, baseline.catalog)) {
      throw const FormatException(
          'Базовые документы M2c не относятся к одной редакции.');
    }
    return _digest([
      index.sourceFingerprint,
      baseline.narrative.encode(),
      baseline.catalog.encode(),
      baseline.editorial.encode(),
    ].join('\n--M2F3G--\n'));
  }

  factory ZaiManualSourceAlignment.empty(
          BookSourceIndex index, ZaiSourceAlignmentBaseline baseline) =>
      ZaiManualSourceAlignment._(
          index.sourceFingerprint, _baselineSignature(index, baseline), const []);

  static void _checkHumanText(String text) {
    if (text.trim() != text ||
        text.isEmpty ||
        text.length > 160 ||
        _controls.hasMatch(text)) {
      throw const FormatException('Недопустимое ручное утверждение.');
    }
  }

  void _check({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
  }) {
    final index = queue.index;
    if (sourceFingerprint != index.sourceFingerprint ||
        baselineDigest != _baselineSignature(index, baseline) ||
        entries.length > maxEvents ||
        entries.map((e) => e.findingId).toSet().length != entries.length) {
      throw const FormatException(
          'Ручные соответствия устарели или относятся к другой книге.');
    }
    final findings = {
      for (final finding in ZaiCrossWindowEvidenceGraph.fromQueue(queue).reviewed)
        finding.id: finding,
    };
    for (final entry in entries) {
      _checkHumanText(entry.subject);
      _checkHumanText(entry.predicate);
      _checkHumanText(entry.object);
      final finding = findings[entry.findingId];
      if (finding == null || finding.category != SemanticCategory.event ||
          finding.quote.trim().isEmpty ||
          finding.quote.length > 180) {
        throw const FormatException(
            'Ручное соответствие ссылается на отсутствующее событие.');
      }
    }
  }

  /// Two independent, unchecked-by-default UI consents are required: the
  /// reader checked the EXACT quote, and separately chose a narrator
  /// assertion with their own subject/predicate/object. The result is only
  /// a canon *candidate* and still must pass the existing M2c compiler gates.
  ZaiManualSourceAlignment accept({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
    required String findingId,
    required String subject,
    required String predicate,
    required String object,
    required bool quoteConfirmedByReader,
    required bool narratorAssertionConfirmedByReader,
  }) {
    _check(queue: queue, baseline: baseline);
    if (!quoteConfirmedByReader || !narratorAssertionConfirmedByReader) {
      throw const FormatException(
          'Нужны два явных подтверждения: точная цитата и смысл события.');
    }
    final candidate = ZaiManuallyAlignedEvent(
      findingId: findingId,
      subject: subject.trim(),
      predicate: predicate.trim(),
      object: object.trim(),
    );
    final updated = ZaiManualSourceAlignment._(
        sourceFingerprint,
        baselineDigest,
        [
          for (final entry in entries)
            if (entry.findingId != findingId) entry,
          candidate,
        ]);
    updated._check(queue: queue, baseline: baseline);
    // Refuse an attempt to override a previously rejected/disputed quote.
    updated.apply(queue: queue, baseline: baseline);
    return updated;
  }

  ZaiManualSourceAlignment remove({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
    required String findingId,
  }) {
    _check(queue: queue, baseline: baseline);
    final next = ZaiManualSourceAlignment._(sourceFingerprint, baselineDigest,
        entries.where((e) => e.findingId != findingId).toList());
    next._check(queue: queue, baseline: baseline);
    return next;
  }

  ZaiAppliedSourceAlignment apply({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
  }) {
    _check(queue: queue, baseline: baseline);
    final index = queue.index;
    final findings = {
      for (final f in ZaiCrossWindowEvidenceGraph.fromQueue(queue).reviewed)
        f.id: f,
    };
    var graph = baseline.narrative.graph;
    final records = {for (final item in graph.records) item.id: item};
    final newClaims = <SourceSemanticAssertion>[];
    final mapping = <String, String>{};
    final existingClaims = {
      for (final claim in baseline.catalog.assertions) claim.id: claim,
    };

    for (final link in entries) {
      final candidate = findings[link.findingId]!.candidate;
      final proposed = SourceEvidence.propose(
        index,
        chunkId: candidate.chunkId,
        kind: EvidenceKind.event,
        startUtf16: candidate.startUtf16,
        endUtf16: candidate.endUtf16,
      );
      if (proposed.evidenceSha256 != candidate.quoteSha256 ||
          proposed.label != candidate.quote) {
        throw const FormatException(
            'Цитата M2c не совпала с источниковым диапазоном Z.ai.');
      }
      final old = records[proposed.id];
      if (old != null &&
          old.status != EvidenceStatus.confirmed &&
          old.status != EvidenceStatus.inferred) {
        throw const FormatException(
            'Цитата отклонена в независимом M2c. Снимите конфликт вручную.');
      }
      if (old == null) {
        graph = graph.addAll(index, [proposed]);
        records[proposed.id] = proposed;
      }
      if (old?.status != EvidenceStatus.confirmed) {
        graph = graph.review(index, proposed.id, EvidenceStatus.confirmed);
      }
      final statement = SourceSemanticAssertion.propose(
        index,
        graph,
        kind: SemanticAssertionKind.event,
        evidenceIds: [proposed.id],
        subject: link.subject,
        predicate: link.predicate,
        object: link.object,
        voice: AssertionVoice.narratorCandidate,
        polarity: AssertionPolarity.affirmative,
        time: AssertionTime.textOrderOnly,
        uncertainty: 'Ручное редакторское предложение; '
            'проверка причинности и знаний персонажей остаётся отдельной.',
      );
      if (existingClaims.containsKey(statement.id)) {
        final verdict = baseline.editorial.verdicts[statement.id];
        if (verdict != null &&
            verdict != SemanticEditorialVerdict.canonCandidate) {
          throw const FormatException(
              'Нельзя повысить ранее отклонённое или спорное утверждение.');
        }
      } else if (!newClaims.any((claim) => claim.id == statement.id)) {
        newClaims.add(statement);
      }
      mapping[link.findingId] = statement.id;
    }

    final catalog = SourceSemanticCatalog.checked(
        index, graph, [...baseline.catalog.assertions, ...newClaims]);
    var editorial = SemanticEditorialReviewSession.create(index, catalog);
    for (final verdict in baseline.editorial.verdicts.entries) {
      editorial = editorial.decide(catalog, verdict.key, verdict.value);
    }
    for (final id in mapping.values) {
      editorial = editorial.decide(
          catalog, id, SemanticEditorialVerdict.canonCandidate);
    }
    // Independently validate serialised forms before returning them to
    // the already accepted compiler; do not accept forged in-memory objects.
    SourceEvidenceGraph.decode(index, graph.encode());
    SourceSemanticCatalog.decode(index, graph, catalog.encode());
    SemanticEditorialReviewSession.decode(
        index, graph, catalog, editorial.encode());
    return ZaiAppliedSourceAlignment(
      evidence: graph,
      catalog: catalog,
      editorial: editorial,
      assertionByFinding: Map.unmodifiable(mapping),
    );
  }

  String encode({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
  }) {
    _check(queue: queue, baseline: baseline);
    final payload = {
      'source_fingerprint': sourceFingerprint,
      'baseline_digest': baselineDigest,
      'status': 'EXPLICIT_PRIVATE_REVIEW_NOT_GAME',
      'entries': [
        for (final item in entries) item.toJson(),
      ],
    };
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _digest(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой журнал цитат M2f3g.');
    }
    return raw;
  }

  static ZaiManualSourceAlignment decode({
    required ZaiWindowReviewQueue queue,
    required ZaiSourceAlignmentBaseline baseline,
    required String raw,
  }) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint M2f3g.');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const roots = {'format', 'payload', 'sha256'};
      if (root.length != roots.length ||
          !root.keys.toSet().containsAll(roots) ||
          root['format'] != format) {
        throw const FormatException('Неизвестная версия M2f3g.');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const fields = {
        'source_fingerprint', 'baseline_digest', 'status', 'entries',
      };
      if (payload.length != fields.length ||
          !payload.keys.toSet().containsAll(fields) ||
          payload['status'] != 'EXPLICIT_PRIVATE_REVIEW_NOT_GAME' ||
          root['sha256'] != _digest(jsonEncode(payload))) {
        throw const FormatException('Изменён журнал редакторских цитат.');
      }
      final saved = ZaiManualSourceAlignment._(
        payload['source_fingerprint'] as String,
        payload['baseline_digest'] as String,
        [
          for (final item in payload['entries'] as List)
            ZaiManuallyAlignedEvent.fromJson(
                Map<String, dynamic>.from(item as Map)),
        ],
      );
      saved._check(queue: queue, baseline: baseline);
      if (saved.encode(queue: queue, baseline: baseline) != raw) {
        throw const FormatException('Неканонический checkpoint M2f3g.');
      }
      saved.apply(queue: queue, baseline: baseline);
      return saved;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён журнал M2f3g.');
    }
  }
}
