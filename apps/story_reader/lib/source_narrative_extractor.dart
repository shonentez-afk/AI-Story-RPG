import 'book_source_index.dart';
import 'source_evidence_graph.dart';

/// M2b3b offline baseline: intentionally narrow Russian-language rules.
/// Every match is just a passage proposal, never a confirmed world fact.
class DetectedSourceClaim {
  const DetectedSourceClaim({
    required this.evidence,
    required this.subject,
    required this.attribute,
    required this.value,
    required this.isReported,
  });

  final SourceEvidence evidence;
  final String subject;
  final String attribute;
  final String value;
  /// Nearby reported speech is a warning, NOT permission to trust a claim.
  final bool isReported;
}

class PossibleStateConflict {
  const PossibleStateConflict({
    required this.subject,
    required this.firstId,
    required this.secondId,
    required this.firstValue,
    required this.secondValue,
  });

  final String subject;
  final String firstId;
  final String secondId;
  final String firstValue;
  final String secondValue;

  /// A door may legitimately change between chapters. Never auto-resolve.
  bool get mightBePlotProgression => true;
  bool get isProvenContradiction => false;
}

class PossibleAliasRelation {
  const PossibleAliasRelation({
    required this.firstId,
    required this.secondId,
    required this.firstName,
    required this.secondName,
  });

  final String firstId;
  final String secondId;
  final String firstName;
  final String secondName;
  bool get confirmedSamePerson => false;
  bool get requiresReview => true;
}

class SourceNarrativeExtractor {
  const SourceNarrativeExtractor._();

  static final RegExp _state = RegExp(
    r'(?:^|[\s.!?«(])((?:[Дд]верь|[Оо]кно|[Вв]орота)\s+'
    r'(?:(?:была|было|были|стала|стало|стали)\s+)?'
    r'(?:открыта|закрыта|открыто|закрыто|открыты|закрыты))'
    r'(?=$|[\s.,!?»])', unicode: true,
  );
  static final RegExp _event = RegExp(
    r'(?:^|[\s.!?«(])([А-ЯЁ][а-яё-]{1,35}\s+'
    r'(?:открыл|открыла|закрыл|закрыла|нашёл|нашел|нашла|'
    r'встретил|встретила|увидел|увидела|покинул|покинула)\s+'
    r'[А-ЯЁа-яё-]{2,36})(?=$|[\s.,!?»])', unicode: true,
  );
  static final RegExp _alias = RegExp(
    r'(?:^|[\s.!?«(])([А-ЯЁ][а-яё-]{1,35})\s+'
    r'(?:по прозвищу|также известный как)\s+'
    r'([А-ЯЁ][а-яё-]{1,35})(?=$|[\s.,!?»])',
    unicode: true,
  );
  /// In many fairy tales the protagonists are known only by their role.
  /// These are *text mentions*, not unique or confirmed identities. Restrict
  /// matching to a small explicit role vocabulary; never infer aliases.
  static const _role = r'(?:принцесса|принц|император|свинопас|'
      r'фрейлина|фрейлины|королева|король|царь|царица|'
      r'солдат|сапожник|мельник|купец)';
  static final RegExp _roleMention = RegExp(
    '(?:^|[\\s.!?«(—-])($_role)(?=$|[\\s.,!?»):—-])',
    unicode: true, caseSensitive: false,
  );

  /// Strict, short surface-pattern only: a role, an overt action verb and an
  /// overt object. No coreference, complex syntax or assumed plot causality.
  static const _roleVerb = r'(?:получил|получила|сделал|сделала|'
      r'обступили|отправил|отправила|сказал|сказала|'
      r'увидел|увидела|нашёл|нашел|нашла|встретил|встретила|'
      r'подарил|подарила|послал|послала|открыл|открыла|'
      r'закрыл|закрыла|взял|взяла|спросил|спросила|позвал|позвала)';
  static final RegExp _roleEvent = RegExp(
    '(?:^|[\\s.!?«(—-])($_role\\s+$_roleVerb\\s+[А-ЯЁа-яё-]{2,36})'
    '(?=$|[\\s.,!?»):—-])',
    unicode: true, caseSensitive: false,
  );
  static final RegExp _roleEventParts = RegExp(
    '^($_role)\\s+($_roleVerb)\\s+([А-ЯЁа-яё-]{2,36})\$',
    unicode: true, caseSensitive: false,
  );

  static final RegExp _stateParts = RegExp(
    r'^(дверь|окно|ворота)\s+'
    r'(?:(?:была|было|были|стала|стало|стали)\s+)?'
    r'(открыта|закрыта|открыто|закрыто|открыты|закрыты)$',
    caseSensitive: false, unicode: true,
  );
  static final RegExp _eventParts = RegExp(
    r'^([А-ЯЁ][а-яё-]{1,35})\s+'
    r'(открыл|открыла|закрыл|закрыла|нашёл|нашел|нашла|'
    r'встретил|встретила|увидел|увидела|покинул|покинула)\s+'
    r'([А-ЯЁа-яё-]{2,36})$', unicode: true,
  );

  static String _normalize(String raw) => raw.toLowerCase()
      .replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isReported(String text, int offset) {
    // Conservative warning only; the remainder is still INFERRED.
    final start = offset > 90 ? offset - 90 : 0;
    final preceding = text.substring(start, offset).toLowerCase();
    return preceding.contains('по словам') ||
        preceding.contains('утверждал, что') ||
        preceding.contains('сказал, что') ||
        preceding.contains('говорили, что') ||
        preceding.contains('говорят, что') ||
        preceding.contains('«') || preceding.contains('"');
  }

  static SourceEvidence _passage(BookSourceIndex index, SourceChunk chunk,
      EvidenceKind kind, RegExpMatch match, String phrase) {
    final relative = match.start + match.group(0)!.lastIndexOf(phrase);
    return SourceEvidence.propose(index,
      chunkId: chunk.id, kind: kind,
      startUtf16: chunk.startUtf16 + relative,
      endUtf16: chunk.startUtf16 + relative + phrase.length,
    );
  }

  /// No pronoun resolution, no inference from absent/negated clauses, and
  /// no generic NER masquerading as verified book knowledge.
  static List<DetectedSourceClaim> claimsInChunk(
      BookSourceIndex index, SourceChunk chunk) {
    final result = <DetectedSourceClaim>[];
    for (final match in _state.allMatches(chunk.text)) {
      final phrase = match.group(1)!;
      final parts = _stateParts.firstMatch(phrase);
      if (parts == null) continue;
      final subject = _normalize(parts.group(1)!);
      final value = _normalize(parts.group(2)!);
      result.add(DetectedSourceClaim(
        evidence: _passage(index, chunk, EvidenceKind.fact, match, phrase),
        subject: subject,
        attribute: 'physical_state',
        value: value.startsWith('откры') ? 'open' : 'closed',
        isReported: _isReported(chunk.text, match.start),
      ));
    }
    for (final match in _event.allMatches(chunk.text)) {
      final phrase = match.group(1)!;
      final parts = _eventParts.firstMatch(phrase);
      if (parts == null) continue;
      result.add(DetectedSourceClaim(
        evidence: _passage(index, chunk, EvidenceKind.event, match, phrase),
        subject: _normalize(parts.group(1)!),
        attribute: _normalize(parts.group(2)!),
        value: _normalize(parts.group(3)!),
        isReported: _isReported(chunk.text, match.start),
      ));
    }
    final knownEventIds = {
      for (final item in result) item.evidence.id,
    };
    for (final match in _roleEvent.allMatches(chunk.text)) {
      final phrase = match.group(1)!;
      final parts = _roleEventParts.firstMatch(phrase);
      if (parts == null) continue;
      final evidence = _passage(
          index, chunk, EvidenceKind.event, match, phrase);
      if (!knownEventIds.add(evidence.id)) continue;
      result.add(DetectedSourceClaim(
        evidence: evidence,
        subject: _normalize(parts.group(1)!),
        attribute: _normalize(parts.group(2)!),
        value: _normalize(parts.group(3)!),
        isReported: _isReported(chunk.text, match.start),
      ));
    }
    result.sort((a, b) =>
        a.evidence.startUtf16.compareTo(b.evidence.startUtf16));
    return List.unmodifiable(result);
  }

  /// An alias phrase gives two exact character spans, not one merged NPC.
  static List<SourceEvidence> aliasesInChunk(
      BookSourceIndex index, SourceChunk chunk) {
    final result = <SourceEvidence>[];
    for (final match in _alias.allMatches(chunk.text)) {
      final full = match.group(0)!;
      final first = match.group(1)!;
      final second = match.group(2)!;
      final firstStart = match.start + full.indexOf(first);
      final secondStart = match.start + full.lastIndexOf(second);
      for (final (label, offset) in [
        (first, firstStart), (second, secondStart),
      ]) {
        result.add(SourceEvidence.propose(index,
          chunkId: chunk.id, kind: EvidenceKind.character,
          startUtf16: chunk.startUtf16 + offset,
          endUtf16: chunk.startUtf16 + offset + label.length,
        ));
      }
    }
    return List.unmodifiable(result);
  }

  /// At most one citation per normalized role spelling per source chunk.
  /// A title such as «принц» does NOT identify the same person across the
  /// chapter or prove that «свинопас» and «принц» are the same actor.
  static List<SourceEvidence> roleMentionsInChunk(
      BookSourceIndex index, SourceChunk chunk) {
    final result = <SourceEvidence>[];
    final seen = <String>{};
    for (final match in _roleMention.allMatches(chunk.text)) {
      final role = match.group(1)!;
      if (!seen.add(_normalize(role))) continue;
      result.add(SourceEvidence.propose(index,
        chunkId: chunk.id,
        kind: EvidenceKind.character,
        startUtf16: chunk.startUtf16 +
            match.start + match.group(0)!.lastIndexOf(role),
        endUtf16: chunk.startUtf16 +
            match.start + match.group(0)!.lastIndexOf(role) + role.length,
      ));
    }
    return List.unmodifiable(result);
  }

  static List<SourceEvidence> extractChunk(
      BookSourceIndex index, SourceChunk chunk) {
    final result = <SourceEvidence>[];
    final seen = <String>{};
    for (final item in claimsInChunk(index, chunk)) {
      if (seen.add(item.evidence.id)) result.add(item.evidence);
    }
    for (final item in aliasesInChunk(index, chunk)) {
      if (seen.add(item.id)) result.add(item);
    }
    for (final item in roleMentionsInChunk(index, chunk)) {
      if (seen.add(item.id)) result.add(item);
    }
    return List.unmodifiable(result);
  }

  /// A changed state across chapters is a potential discrepancy *or* a
  /// normal timeline transition. No inferred match is promoted to truth.
  static List<PossibleStateConflict> possibleConflicts(
      SourceEvidenceGraph graph, {int limit = 60}) {
    final bySubject = <String, List<SourceEvidence>>{};
    for (final record in graph.records) {
      if (record.kind != EvidenceKind.fact ||
          record.status == EvidenceStatus.rejected) continue;
      final match = _stateParts.firstMatch(record.label);
      if (match == null) continue;
      bySubject.putIfAbsent(_normalize(match.group(1)!), () => [])
          .add(record);
    }
    final result = <PossibleStateConflict>[];
    final keys = bySubject.keys.toList()..sort();
    for (final key in keys) {
      final records = bySubject[key]!;
      records.sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
      for (var i = 0; i < records.length; i++) {
        for (var j = i + 1; j < records.length; j++) {
          if (records[i].chapterIndex == records[j].chapterIndex) continue;
          final first = _stateParts.firstMatch(records[i].label)!.group(2)!;
          final second = _stateParts.firstMatch(records[j].label)!.group(2)!;
          final a = _normalize(first).startsWith('откры') ? 'open' : 'closed';
          final b = _normalize(second).startsWith('откры') ? 'open' : 'closed';
          if (a == b) continue;
          result.add(PossibleStateConflict(
            subject: key, firstId: records[i].id,
            secondId: records[j].id, firstValue: a, secondValue: b,
          ));
          if (result.length >= limit) return List.unmodifiable(result);
        }
      }
    }
    return List.unmodifiable(result);
  }

  /// A literal alias phrase is stronger than similar spelling but still
  /// requires a human decision. This method does NOT combine identities.
  static List<PossibleAliasRelation> explicitAliasHints(
      BookSourceIndex index, SourceEvidenceGraph graph, {int limit = 40}) {
    final byId = {for (final e in graph.records) e.id: e};
    final results = <PossibleAliasRelation>[];
    for (final chunk in index.chunks) {
      for (final match in _alias.allMatches(chunk.text)) {
        final full = match.group(0)!;
        final first = match.group(1)!;
        final second = match.group(2)!;
        final startA = chunk.startUtf16 + match.start + full.indexOf(first);
        final startB = chunk.startUtf16 + match.start + full.lastIndexOf(second);
        final a = SourceEvidence.propose(index,
          chunkId: chunk.id, kind: EvidenceKind.character,
          startUtf16: startA, endUtf16: startA + first.length,
        );
        final b = SourceEvidence.propose(index,
          chunkId: chunk.id, kind: EvidenceKind.character,
          startUtf16: startB, endUtf16: startB + second.length,
        );
        if (byId[a.id] == null || byId[b.id] == null ||
            byId[a.id]!.status == EvidenceStatus.rejected ||
            byId[b.id]!.status == EvidenceStatus.rejected) continue;
        results.add(PossibleAliasRelation(
          firstId: a.id, secondId: b.id,
          firstName: first, secondName: second,
        ));
        if (results.length >= limit) return List.unmodifiable(results);
      }
    }
    return List.unmodifiable(results);
  }
}
