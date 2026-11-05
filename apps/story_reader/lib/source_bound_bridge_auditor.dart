import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// M2h7a: a source-bound *candidate* check, not a literary truth engine.
///
/// A correct quotation shows which words exist in an edition. It does not
/// establish the narrator's reliability, an NPC's knowledge, in-world
/// chronology, causation or the truth of an inferred AI claim.
enum SourceBridgeKind { causalCandidate, explicitGameFiction }

enum SourceBridgeDisposition {
  rejected,
  literaryReviewRequired,
  explicitlyFictional,
}

/// An authored proposal. The model cannot set a "canonical" or playable
/// status. User review of the meaning is a separate future workflow.
class SourceBoundBridge {
  const SourceBoundBridge({
    required this.id,
    required this.fromEventId,
    required this.toEventId,
    required this.kind,
    required this.rationale,
    this.sourceClaimIds = const [],
  });

  final String id;
  final String fromEventId;
  final String toEventId;
  final SourceBridgeKind kind;
  final String rationale;
  final List<String> sourceClaimIds;
}

class SourceBridgeFinding {
  const SourceBridgeFinding({
    required this.bridgeId,
    required this.disposition,
    required this.blockers,
    required this.textOrderReversed,
  });

  final String bridgeId;
  final SourceBridgeDisposition disposition;
  final List<String> blockers;

  /// Only source order; flashbacks may reverse chronological world time.
  final bool textOrderReversed;

  bool get anchorsRejected =>
      disposition == SourceBridgeDisposition.rejected;
  bool get isGameFiction =>
      disposition == SourceBridgeDisposition.explicitlyFictional;
  bool get needsLiteraryReview =>
      disposition == SourceBridgeDisposition.literaryReviewRequired;

  /// Even a human-marked semantic CANDIDATE cannot be made world truth by
  /// this formal source checker. A future independent meaning gate is needed.
  bool get establishesWorldTruth => false;
  bool get establishesNPCWorldKnowledge => false;
  bool get establishesWorldChronology => false;
}

class SourceBoundBridgeAudit {
  SourceBoundBridgeAudit._(List<SourceBridgeFinding> findings)
      : findings = List.unmodifiable(findings);

  final List<SourceBridgeFinding> findings;
  int get rejectedCount => findings.where((x) => x.anchorsRejected).length;
  int get fictionalCount => findings.where((x) => x.isGameFiction).length;
  int get candidatesForLiteraryReview =>
      findings.where((x) => x.needsLiteraryReview).length;

  bool get canDeclareLiteraryCausality => false;
  bool get canDeclareCanonicalRpg => false;

  /// Diagnostic only, without book text, model prompts or private excerpts.
  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_source_bound_bridge_m2h7a_v1',
    'status': 'SOURCE_ANCHORED_CANDIDATES_ONLY',
    'rejected': rejectedCount,
    'fiction_only': fictionalCount,
    'meaning_review_needed': candidatesForLiteraryReview,
    'world_causality_verified': false,
    'npc_knowledge_verified': false,
    'world_time_verified': false,
    'canonical_rpg_ready': false,
    'bridges': [
      for (final f in findings) {
        'bridge_id': f.bridgeId,
        'disposition': f.disposition.name,
        'blockers': f.blockers,
        'text_order_reversed': f.textOrderReversed,
      },
    ],
  };
}

/// Independently re-anchors every proposed bridge to this edition and the
/// existing reviewed evidence/catalog. It never infers causality from a
/// sequence of chapters, an AI label, a quoted statement or its own success.
class SourceBoundBridgeAuditor {
  const SourceBoundBridgeAuditor._();

  static final RegExp _safeId = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static bool _covers(SourceEvidence evidence, NarrativeCitation citation) =>
      evidence.chunkId == citation.chunkId &&
      evidence.chapterIndex == citation.chapterIndex &&
      evidence.blockIndex == citation.blockIndex &&
      evidence.startUtf16 <= citation.startUtf16 &&
      evidence.endUtf16 >= citation.endUtf16;

  static int _compareTextPosition(
      NarrativeCitation from, NarrativeCitation to) {
    final chapter = from.chapterIndex.compareTo(to.chapterIndex);
    if (chapter != 0) return chapter;
    final block = from.blockIndex.compareTo(to.blockIndex);
    if (block != 0) return block;
    return from.startUtf16.compareTo(to.startUtf16);
  }

  static SourceBoundBridgeAudit audit({
    required BookSourceIndex index,
    required SourceEvidenceGraph evidence,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required Iterable<NarrativeEvent> events,
    required Iterable<SourceBoundBridge> bridges,
  }) {
    if (index.sourceFingerprint != evidence.sourceFingerprint ||
        index.sourceFingerprint != catalog.sourceFingerprint ||
        !editorial.matches(index, catalog)) {
      throw const FormatException(
          'Смысловая проверка относится к другой редакции книги.');
    }
    // Do not trust a previously constructed catalog or evidence graph.
    for (final item in evidence.records) {
      item.validate(index);
    }
    SourceSemanticCatalog.checked(index, evidence, catalog.assertions);
    final byEvent = <String, NarrativeEvent>{};
    for (final event in events) {
      if (event.id.isEmpty || byEvent.containsKey(event.id)) {
        throw const FormatException('Некорректные исходные события.');
      }
      event.source.validate(index);
      byEvent[event.id] = event;
    }
    if (byEvent.isEmpty || byEvent.length > NarrativeBookModel.maxEvents) {
      throw const FormatException('Невозможен аудит пустой карты событий.');
    }
    final byClaim = {
      for (final claim in catalog.assertions) claim.id: claim,
    };
    final byEvidence = {
      for (final source in evidence.records) source.id: source,
    };
    final ids = <String>{};
    final findings = <SourceBridgeFinding>[];
    for (final bridge in bridges) {
      if (findings.length >= 128 ||
          !_safeId.hasMatch(bridge.id) || !ids.add(bridge.id) ||
          bridge.rationale.trim().length < 12 ||
          bridge.rationale.length > 400 ||
          _controls.hasMatch(bridge.rationale) ||
          bridge.sourceClaimIds.length > 8 ||
          bridge.sourceClaimIds.toSet().length !=
              bridge.sourceClaimIds.length) {
        throw const FormatException(
            'Некорректное или повторное предложение смыслового перехода.');
      }
      final earlier = byEvent[bridge.fromEventId];
      final later = byEvent[bridge.toEventId];
      final issues = <String>[];
      if (earlier == null || later == null ||
          bridge.fromEventId == bridge.toEventId) {
        issues.add('Неизвестные или совпадающие исходные события.');
      }
      final reversed = earlier != null && later != null &&
          _compareTextPosition(earlier.source, later.source) > 0;
      if (bridge.kind == SourceBridgeKind.explicitGameFiction) {
        if (bridge.sourceClaimIds.isNotEmpty) {
          issues.add('Вымышленная связь не должна имитировать '
              'доказанную литературную причинность.');
        }
        findings.add(SourceBridgeFinding(
          bridgeId: bridge.id,
          disposition: issues.isEmpty
              ? SourceBridgeDisposition.explicitlyFictional
              : SourceBridgeDisposition.rejected,
          blockers: List.unmodifiable(issues),
          textOrderReversed: reversed,
        ));
        continue;
      }
      if (bridge.sourceClaimIds.isEmpty) {
        issues.add('Нет смыслового утверждения с цитатами обеих сторон.');
      }
      var fromAnchored = false;
      var toAnchored = false;
      for (final claimId in bridge.sourceClaimIds) {
        final claim = byClaim[claimId];
        if (claim == null) {
          issues.add('Неизвестное смысловое утверждение.');
          continue;
        }
        final verdict = editorial.verdicts[claim.id];
        if (verdict != SemanticEditorialVerdict.canonCandidate) {
          issues.add('Нет отдельного решения о проверке смысла утверждения.');
        }
        if (claim.voice != AssertionVoice.narratorCandidate) {
          issues.add('Сообщение персонажа или неопределённая реплика '
              'не является объективным фактом мира.');
        }
        if (claim.polarity != AssertionPolarity.affirmative ||
            claim.kind != SemanticAssertionKind.event &&
                claim.kind != SemanticAssertionKind.fact &&
                claim.kind != SemanticAssertionKind.relation) {
          issues.add('Смысл утверждения неоднозначен или не является событием.');
        }
        for (final sourceId in claim.evidenceIds) {
          final source = byEvidence[sourceId];
          if (source == null ||
              source.status != EvidenceStatus.confirmed) {
            issues.add('Подтверждена не каждая точная цитата утверждения.');
            continue;
          }
          if (earlier != null && _covers(source, earlier.source)) {
            fromAnchored = true;
          }
          if (later != null && _covers(source, later.source)) {
            toAnchored = true;
          }
        }
      }
      if (!fromAnchored || !toAnchored) {
        issues.add('Нет подтверждённых буквальных опор для обеих сторон '
            'перехода в данном издании.');
      }
      // Never claim that time order or an editorial CANON_CANDIDATE verdict
      // validates literary dependence. Report only a reviewable candidate.
      findings.add(SourceBridgeFinding(
        bridgeId: bridge.id,
        disposition: issues.isEmpty
            ? SourceBridgeDisposition.literaryReviewRequired
            : SourceBridgeDisposition.rejected,
        blockers: List.unmodifiable(issues),
        textOrderReversed: reversed,
      ));
    }
    return SourceBoundBridgeAudit._(findings);
  }
}
