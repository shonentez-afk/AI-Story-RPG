import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_semantic_provider.dart';
import 'zai_semantic_review_queue.dart';

/// Exact, source-anchored evidence kept only for further editorial review.
/// Being included here does NOT make an assertion canon or a playable event.
class ZaiAnchoredFinding {
  const ZaiAnchoredFinding({
    required this.candidate,
    required this.windowPosition,
    required this.chapterIndex,
    required this.blockIndex,
  });

  final SemanticCandidate candidate;
  final int windowPosition;
  final int chapterIndex;
  final int blockIndex;

  String get id => candidate.id;
  String get label => candidate.label;
  String get quote => candidate.quote;
  SemanticCategory get category => candidate.category;
  bool get confirmed => false;
  bool get knownStoryTime => false;
}

class ZaiPossibleSameName {
  ZaiPossibleSameName(this.category, this.displayName,
      List<ZaiAnchoredFinding> proposed)
      : findings = List.unmodifiable(proposed);

  final SemanticCategory category;
  final String displayName;
  final List<ZaiAnchoredFinding> findings;

  /// Exact normalized name equality is a search hint, not an identity proof.
  bool get sameIdentityProven => false;
  bool get requiresManualReview => true;
}

/// Deterministic read-only, edition-bound projection of the M2f3a checkpoint.
///
/// No cloud calls, no inferred pronoun resolution, no guessing aliases,
/// no false causal edges, and no conversion to BookWorld/campaigns.
class ZaiCrossWindowEvidenceGraph {
  ZaiCrossWindowEvidenceGraph._({
    required this.index,
    required List<ZaiAnchoredFinding> reviewed,
    required List<ZaiPossibleSameName> possibleNames,
  }) : reviewed = List.unmodifiable(reviewed),
       possibleNames = List.unmodifiable(possibleNames);

  final BookSourceIndex index;
  final List<ZaiAnchoredFinding> reviewed;
  final List<ZaiPossibleSameName> possibleNames;

  bool get canPublishBookworld => false;
  bool get hasVerifiedStoryChronology => false;
  bool get hasProvenCausality => false;

  Iterable<ZaiAnchoredFinding> get textOrderedEvents =>
      reviewed.where((e) => e.category == SemanticCategory.event);
  Iterable<ZaiAnchoredFinding> get statedFactsAndStates =>
      reviewed.where((e) => e.category == SemanticCategory.fact ||
          e.category == SemanticCategory.state);
  Iterable<ZaiAnchoredFinding> get allCharactersAndPlaces =>
      reviewed.where((e) => e.category == SemanticCategory.character ||
          e.category == SemanticCategory.location);

  static String _normalizedName(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  factory ZaiCrossWindowEvidenceGraph.fromQueue(ZaiWindowReviewQueue queue) {
    final index = queue.index;
    final chunks = {for (final chunk in index.chunks) chunk.id: chunk};
    final reviewed = <ZaiAnchoredFinding>[];

    for (var position = 0; position < queue.windows.length; position++) {
      final result = queue.results[position];
      if (result == null) continue;
      final currentWindow = queue.windows[position];
      final allowedIds = currentWindow.chunks.map((chunk) => chunk.id).toSet();
      for (final candidate in result.candidates) {
        if (queue.decisions[candidate.id] !=
            ZaiEditorialDecision.keepForReview) continue;
        final chunk = chunks[candidate.chunkId];
        if (chunk == null) {
          throw const FormatException('У гипотезы отсутствует исходная цитата');
        }
        SemanticCandidateValidator.validateCandidate(
          index,
          candidate,
          allowedChunkIds: allowedIds,
          categories: ZaiSemanticPreviewServiceCategories.all,
          sourceChunk: chunk,
        );
        reviewed.add(ZaiAnchoredFinding(
          candidate: candidate,
          windowPosition: position,
          chapterIndex: chunk.chapterIndex,
          blockIndex: chunk.blockIndex,
        ));
      }
    }

    // Source order is narrative-document order only, not diegetic time.
    reviewed.sort((a, b) {
      var compare = a.chapterIndex.compareTo(b.chapterIndex);
      if (compare != 0) return compare;
      compare = a.blockIndex.compareTo(b.blockIndex);
      if (compare != 0) return compare;
      compare = a.candidate.startUtf16.compareTo(b.candidate.startUtf16);
      if (compare != 0) return compare;
      return a.id.compareTo(b.id);
    });

    final byName = <String, List<ZaiAnchoredFinding>>{};
    for (final finding in reviewed) {
      if (finding.category != SemanticCategory.character &&
          finding.category != SemanticCategory.location) continue;
      final normalized = _normalizedName(finding.label);
      if (normalized.length < 2) continue;
      final key = '${finding.category.name}|$normalized';
      byName.putIfAbsent(key, () => []).add(finding);
    }
    final possibleNames = <ZaiPossibleSameName>[];
    for (final list in byName.values) {
      if (list.length < 2 ||
          list.map((item) => item.windowPosition).toSet().length < 2) {
        continue;
      }
      possibleNames.add(ZaiPossibleSameName(
          list.first.category, list.first.label, list));
    }
    possibleNames.sort((a, b) {
      final byChapter = a.findings.first.chapterIndex
          .compareTo(b.findings.first.chapterIndex);
      return byChapter != 0 ? byChapter :
          a.displayName.compareTo(b.displayName);
    });
    return ZaiCrossWindowEvidenceGraph._(
        index: index, reviewed: reviewed, possibleNames: possibleNames);
  }
}

/// The categories already accepted by the existing Z.ai provider.
/// This is not an independent provider gate and does not enable cloud mode.
class ZaiSemanticPreviewServiceCategories {
  const ZaiSemanticPreviewServiceCategories._();
  static const all = <SemanticCategory>{
    SemanticCategory.character,
    SemanticCategory.location,
    SemanticCategory.event,
    SemanticCategory.fact,
    SemanticCategory.state,
  };
}

/// Explicit, separately stored editorial hypothesis connecting TWO exact
/// source-backed findings. Even a human-entered link remains provisional:
/// it does not establish identity, narrative causality or chronology.
enum ZaiProposedLinkKind { possibleIdentity, possibleCause }

class ZaiProposedLink {
  const ZaiProposedLink({
    required this.id,
    required this.kind,
    required this.firstId,
    required this.secondId,
  });

  final String id;
  final ZaiProposedLinkKind kind;
  final String firstId;
  final String secondId;

  bool get proven => false;
  bool get canPublishBookworld => false;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'first': firstId,
    'second': secondId,
    'status': 'EDITORIAL_HYPOTHESIS',
  };
}

/// Private link checkpoint: isolated from old M2f3a queue format and saves.
/// On restore, every endpoint must still be individually marked for review
/// and validated against the SAME original book edition.
class ZaiCrossWindowLinkNotebook {
  ZaiCrossWindowLinkNotebook._(
      this.graph, List<ZaiProposedLink> links)
      : links = List.unmodifiable(links);

  static const format = 'ai_story_zai_links_m2f3b_v1';
  static const maxBytes = 256 * 1024;
  static const maxLinks = 800;

  final ZaiCrossWindowEvidenceGraph graph;
  final List<ZaiProposedLink> links;

  factory ZaiCrossWindowLinkNotebook.empty(
          ZaiCrossWindowEvidenceGraph graph) =>
      ZaiCrossWindowLinkNotebook._(graph, const []);

  bool get canPublishBookworld => false;
  bool get allRelationsProvisional => true;

  static String _hash(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  static String _id(
      String fingerprint, ZaiProposedLinkKind kind, String first, String second) {
    final a = kind == ZaiProposedLinkKind.possibleIdentity &&
            first.compareTo(second) > 0 ? second : first;
    final b = kind == ZaiProposedLinkKind.possibleIdentity &&
            first.compareTo(second) > 0 ? first : second;
    return _hash('$fingerprint|${kind.name}|$a|$b').substring(0, 32);
  }

  void _validate(ZaiProposedLink link) {
    if (link.firstId == link.secondId ||
        link.id != _id(graph.index.sourceFingerprint, link.kind,
            link.firstId, link.secondId)) {
      throw const FormatException('Неверная связь источников');
    }
    final byId = {for (final item in graph.reviewed) item.id: item};
    final first = byId[link.firstId];
    final second = byId[link.secondId];
    if (first == null || second == null) {
      throw const FormatException('Связь без действующих ручных решений');
    }
    if (link.kind == ZaiProposedLinkKind.possibleIdentity) {
      final type = first.category;
      if ((type != SemanticCategory.character &&
           type != SemanticCategory.location) ||
          type != second.category ||
          first.windowPosition == second.windowPosition) {
        throw const FormatException('Совпадение требует два исходных окна и один тип');
      }
    } else {
      if (first.category != SemanticCategory.event ||
          second.category != SemanticCategory.event ||
          first.windowPosition == second.windowPosition) {
        throw const FormatException('Причинная гипотеза требует два разных события');
      }
      // A causal guess in this prototype always points forward through
      // DOCUMENT order only. This does NOT establish plot chronology.
      final ordered = graph.reviewed;
      if (ordered.indexWhere((item) => item.id == first.id) >=
          ordered.indexWhere((item) => item.id == second.id)) {
        throw const FormatException('Поменяйте местами события по тексту');
      }
    }
  }

  ZaiCrossWindowLinkNotebook propose(
      ZaiProposedLinkKind kind, String firstId, String secondId) {
    final link = ZaiProposedLink(
      id: _id(graph.index.sourceFingerprint, kind, firstId, secondId),
      kind: kind, firstId: firstId, secondId: secondId,
    );
    _validate(link);
    if (links.any((item) => item.id == link.id)) return this;
    if (links.length >= maxLinks) {
      throw const FormatException('Слишком много предложенных связей');
    }
    return ZaiCrossWindowLinkNotebook._(graph, [...links, link]);
  }

  ZaiCrossWindowLinkNotebook remove(String id) {
    if (!links.any((item) => item.id == id)) {
      throw const FormatException('Неизвестная связь');
    }
    return ZaiCrossWindowLinkNotebook._(
        graph, links.where((link) => link.id != id).toList());
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': graph.index.sourceFingerprint,
    'status': 'PRIVATE_EDITORIAL_HYPOTHESES_ONLY',
    'can_publish_bookworld': false,
    'links': [for (final link in links) link.toJson()],
  };

  String encode() {
    if (links.length > maxLinks ||
        links.map((link) => link.id).toSet().length != links.length) {
      throw const FormatException('Повтор или избыток редакторских связей');
    }
    for (final link in links) {
      _validate(link);
    }
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _hash(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint связей');
    }
    return raw;
  }

  static ZaiCrossWindowLinkNotebook decode(
      ZaiCrossWindowEvidenceGraph graph, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint связей');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root.length != 3 ||
          root.keys.toSet().difference({'format', 'payload', 'sha256'}).isNotEmpty ||
          root['format'] != format) {
        throw const FormatException('Неизвестный формат ссылок');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (payload.length != 4 ||
          payload.keys.toSet().difference({'source_fingerprint',
            'status','can_publish_bookworld','links'}).isNotEmpty ||
          payload['source_fingerprint'] != graph.index.sourceFingerprint ||
          payload['status'] != 'PRIVATE_EDITORIAL_HYPOTHESES_ONLY' ||
          payload['can_publish_bookworld'] != false ||
          root['sha256'] != _hash(jsonEncode(payload))) {
        throw const FormatException('Повреждённые связи или другая редакция');
      }
      final entries = payload['links'] as List<dynamic>;
      if (entries.length > maxLinks) {
        throw const FormatException('Слишком много связей');
      }
      final links = <ZaiProposedLink>[];
      for (final entry in entries) {
        final item = Map<String, dynamic>.from(entry as Map);
        if (item.length != 5 ||
            item.keys.toSet().difference({'id','kind','first','second','status'}).isNotEmpty ||
            item['status'] != 'EDITORIAL_HYPOTHESIS') {
          throw const FormatException('Подменена редакторская связь');
        }
        links.add(ZaiProposedLink(
          id: item['id'] as String,
          kind: ZaiProposedLinkKind.values.byName(item['kind'] as String),
          firstId: item['first'] as String,
          secondId: item['second'] as String,
        ));
      }
      final decoded = ZaiCrossWindowLinkNotebook._(graph, links);
      if (decoded.encode() != raw) {
        throw const FormatException('Checkpoint связей не канонический');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Не удалось проверить связи книги');
    }
  }
}
