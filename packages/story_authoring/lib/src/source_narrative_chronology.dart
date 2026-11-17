import 'book_source_index.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_extractor.dart';

/// A report/rumour is not the narrator's confirmed assertion.
enum ClaimVoice { narratorCandidate, reportedSpeech, uncertain }
enum ClaimPolarity { affirmative, negated }

class NarrativeObservation {
  const NarrativeObservation({
    required this.evidence,
    required this.voice,
    required this.polarity,
    required this.subject,
    required this.predicate,
    required this.object,
    required this.isReviewed,
  });

  final SourceEvidence evidence;
  final ClaimVoice voice;
  final ClaimPolarity polarity;
  final String subject;
  final String predicate;
  final String object;

  /// "Reviewed" means the quote was verified, not that its content is true.
  final bool isReviewed;
  bool get claimsVerifiedWorldTruth => false;
  bool get establishesInWorldTime => false;
}

/// Chapter/block/source offsets define order of *text* only.
/// Flashbacks and testimony make narrative/world chronology distinct.
class SourceNarrativeChronology {
  const SourceNarrativeChronology._(this.observations);

  static const maxObservations = 3000;
  final List<NarrativeObservation> observations;

  static final RegExp _negatedEvent = RegExp(
    r'(?:^|[\s.!?«(])([А-ЯЁ][а-яё-]{1,35}\s+не\s+'
    r'(?:открыл|открыла|закрыл|закрыла|нашёл|нашел|нашла|'
    r'встретил|встретила|увидел|увидела|покинул|покинула)\s+'
    r'[А-ЯЁа-яё-]{2,36})(?=$|[\s.,!?»])', unicode: true,
  );

  static final RegExp _negatedState = RegExp(
    r'(?:^|[\s.!?«(])((?:[Дд]верь|[Оо]кно|[Вв]орота)\s+'
    r'(?:(?:была|было|были)\s+)?не\s+'
    r'(?:открыта|закрыта|открыто|закрыто|открыты|закрыты))'
    r'(?=$|[\s.,!?»])', unicode: true,
  );

  static final RegExp _negatedParts = RegExp(
    r'^([А-ЯЁ][а-яё-]{1,35})\s+не\s+'
    r'([а-яё-]{3,35})\s+([А-ЯЁа-яё-]{2,36})$', unicode: true,
  );

  static final RegExp _negatedStateParts = RegExp(
    r'^(дверь|окно|ворота)\s+'
    r'(?:(?:была|было|были)\s+)?не\s+'
    r'(открыта|закрыта|открыто|закрыто|открыты|закрыты)$',
    caseSensitive: false, unicode: true,
  );

  static String _normal(String text) => text.trim().toLowerCase()
      .replaceAll('ё', 'е');

  static ClaimVoice _voice(String text, int before) {
    final preceding = text.substring(0, before);
    var start = preceding.lastIndexOf(RegExp(r'[.!?\n]'));
    if (start < 0) start = 0;
    final local = preceding.substring(start).toLowerCase();
    if (RegExp(r'(по словам|утверждал[,\s]+что|утверждала[,\s]+что|'
        r'говорили[,\s]+что|говорят[,\s]+что|сказал[,\s]+что|'
        r'сказала[,\s]+что|«|")', unicode: true).hasMatch(local)) {
      return ClaimVoice.reportedSpeech;
    }
    if (RegExp(r'(возможно|вероятно|казалось|якобы|по-видимому|'
        r'могло быть|мог быть|кажется)', unicode: true).hasMatch(local)) {
      return ClaimVoice.uncertain;
    }
    return ClaimVoice.narratorCandidate;
  }

  static SourceEvidence _negativeEvidence(
      BookSourceIndex index, SourceChunk chunk,
      EvidenceKind kind, RegExpMatch match) {
    final source = match.group(1)!;
    final relativeStart = match.start + match.group(0)!.lastIndexOf(source);
    return SourceEvidence.propose(index,
      chunkId: chunk.id,
      kind: kind,
      startUtf16: chunk.startUtf16 + relativeStart,
      endUtf16: chunk.startUtf16 + relativeStart + source.length,
    );
  }

  /// Derived from exact source passages; nothing is saved as game truth.
  /// Positive candidates come only from current validated evidence graph;
  /// negative clauses are independent INFERRED quotations, not mutations to
  /// M2b3b checkpoints or automatic negation of prior claims.
  factory SourceNarrativeChronology.build(
      BookSourceIndex index, SourceEvidenceGraph graph) {
    if (index.sourceFingerprint != graph.sourceFingerprint) {
      throw const FormatException('Хронология другой редакции');
    }
    final supported = <String, SourceEvidence>{};
    for (final record in graph.records) {
      record.validate(index);
      if (record.status != EvidenceStatus.rejected &&
          (record.kind == EvidenceKind.event ||
           record.kind == EvidenceKind.fact)) {
        supported[record.id] = record;
      }
    }
    final entries = <NarrativeObservation>[];
    final seen = <String>{};
    for (final chunk in index.chunks) {
      final claims = SourceNarrativeExtractor.claimsInChunk(index, chunk);
      for (final claim in claims) {
        final evidence = supported[claim.evidence.id];
        if (evidence == null || !seen.add(evidence.id)) continue;
        final relative = evidence.startUtf16 - chunk.startUtf16;
        entries.add(NarrativeObservation(
          evidence: evidence,
          voice: _voice(chunk.text, relative),
          polarity: ClaimPolarity.affirmative,
          subject: claim.subject,
          predicate: claim.attribute,
          object: claim.value,
          isReviewed: evidence.status == EvidenceStatus.confirmed,
        ));
        if (entries.length >= maxObservations) {
          return SourceNarrativeChronology._(
              List.unmodifiable(_sort(entries)));
        }
      }

      for (final match in _negatedEvent.allMatches(chunk.text)) {
        final source = match.group(1)!;
        final parts = _negatedParts.firstMatch(source);
        if (parts == null) continue;
        final evidence = _negativeEvidence(
            index, chunk, EvidenceKind.event, match);
        if (!seen.add(evidence.id)) continue;
        entries.add(NarrativeObservation(
          evidence: evidence,
          voice: _voice(chunk.text,
              evidence.startUtf16 - chunk.startUtf16),
          polarity: ClaimPolarity.negated,
          subject: _normal(parts.group(1)!),
          predicate: _normal(parts.group(2)!),
          object: _normal(parts.group(3)!),
          isReviewed: false,
        ));
      }
      for (final match in _negatedState.allMatches(chunk.text)) {
        final phrase = match.group(1)!;
        final parts = _negatedStateParts.firstMatch(phrase);
        if (parts == null) continue;
        final evidence = _negativeEvidence(
            index, chunk, EvidenceKind.fact, match);
        if (!seen.add(evidence.id)) continue;
        entries.add(NarrativeObservation(
          evidence: evidence,
          voice: _voice(chunk.text,
              evidence.startUtf16 - chunk.startUtf16),
          polarity: ClaimPolarity.negated,
          subject: _normal(parts.group(1)!),
          predicate: 'physical_state',
          object: _normal(parts.group(2)!),
          isReviewed: false,
        ));
      }
      if (entries.length >= maxObservations) {
        return SourceNarrativeChronology._(
            List.unmodifiable(_sort(entries).take(maxObservations)));
      }
    }
    return SourceNarrativeChronology._(List.unmodifiable(_sort(entries)));
  }

  static List<NarrativeObservation> _sort(
      List<NarrativeObservation> entries) {
    entries.sort((a, b) {
      final ch = a.evidence.chapterIndex.compareTo(b.evidence.chapterIndex);
      if (ch != 0) return ch;
      final block = a.evidence.blockIndex.compareTo(b.evidence.blockIndex);
      if (block != 0) return block;
      final span = a.evidence.startUtf16.compareTo(b.evidence.startUtf16);
      if (span != 0) return span;
      return a.evidence.id.compareTo(b.evidence.id);
    });
    return entries;
  }
}
