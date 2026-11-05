import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _PrivateMemory implements SourceAnalysisCheckpointRepository {
  String? data;
  @override
  Future<String?> read(String fingerprint) async => data;
  @override
  Future<void> write(String fingerprint, String text) async { data = text; }
  @override
  Future<void> delete(String fingerprint) async { data = null; }
}

BookSourceIndex _index([String addition = '']) {
  return BookSourceIndexer.index(ImportedBook(
    title: 'История с флешбеком' + addition,
    author: 'Тест',
    chapters: [
      'Путник утром обнаружил потерянный золотой ключ у старого колодца '
          'и задумался, как можно вернуть его законному владельцу.',
      'Путник встретил сторожа, который утверждал, что никогда не '
          'видел золотого ключа, но рассказчик пока не знает правду.',
      'Путник вспоминал давний год, когда друг дал обещание '
          'сохранить тайну ключа, а затем вернулся в свой дом.',
    ],
  ));
}

Future<ZaiWholeBookEventOutline> _outline(BookSourceIndex index,
    {int? firstBatch}) async {
  final service = ZaiAutoWholeBookAnalysis(
    repository: _PrivateMemory(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final proposal = SemanticCandidate.propose(
        source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16,
        endUtf16: chunk.startUtf16 + 60,
        label: 'Возможное событие из оригинала',
        uncertainty: 'Смысл события нужно проверить. '
            'В третьей главе может быть ретроспектива.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final chunk in window.chunks) chunk.id],
          candidates: [proposal],
        ),
        totalSuggestions: 1,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await service.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: firstBatch ?? 10,
  );
  return ZaiWholeBookEventOutline.build(result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M2g3a keeps exact citations but never claims model meaning, '
      'world chronology or gameplay truth', () async {
    final index = _index();
    final outline = await _outline(index);
    final model = NarrativeBookModel.fromExisting(index: index,
        outline: outline);
    expect(model.analysisComplete, true);
    expect(model.events, hasLength(3));
    expect(model.sourceFingerprint, index.sourceFingerprint);
    expect(model.hasProvenChronology, false);
    expect(model.hasCausalGraph, false);
    expect(model.hasNPCWorldTruth, false);
    expect(model.isPlayableScenario, false);
    expect(model.canPublishPublicly, false);
    expect(model.issues.join(' '), contains('флешбеки'));
    for (var i = 0; i < model.events.length; i++) {
      final event = model.events[i];
      expect(event.narrativePosition, i);
      expect(event.source.chapterIndex, i);
      expect(event.sourceProvenance, NarrativeProvenance.exactText);
      expect(event.meaningProvenance,
          NarrativeProvenance.unverifiedInterpretation);
      expect(event.timeStatus, NarrativeTemporalStatus.timeUnresolved);
      expect(event.meaningIsCanon, false);
      expect(event.isCausallyValidated, false);
      event.source.validate(index);
    }
    final json = model.toJson();
    expect(json['format'], NarrativeBookModel.format);
    expect(json['is_playable_scenario'], false);
    expect(jsonEncode(json), contains(index.sourceFingerprint));
    expect(() => model.events.add(model.events.first), throwsUnsupportedError);
    final first = model.events.first.source;
    final corrupted = NarrativeCitation(
      chunkId: first.chunkId,
      chapterIndex: first.chapterIndex,
      blockIndex: first.blockIndex,
      startUtf16: first.startUtf16,
      endUtf16: first.endUtf16,
      quote: first.quote.replaceFirst('Путник', 'Автор'),
    );
    expect(() => corrupted.validate(index), throwsFormatException);
  });

  test('reject wrong edition and partial scan; partial review is not playable',
      () async {
    final source = _index();
    final complete = await _outline(source);
    expect(() => NarrativeBookModel.fromExisting(
      index: _index(' новая редакция'),
      outline: complete,
    ), throwsFormatException);
    final partial = await _outline(source, firstBatch: 1);
    expect(() => NarrativeBookModel.fromExisting(
      index: source, outline: partial,
    ), throwsFormatException);
    final draft = NarrativeBookModel.fromExisting(
      index: source, outline: partial,
      permitIncompleteAnalysisForReview: true,
    );
    expect(draft.analysisComplete, false);
    expect(draft.isPlayableScenario, false);
    expect(draft.issues.join(' '), contains('Анализ книги не завершён'));
  });

  test('same-name actor mentions never silently merge; negated or '
      'disputed assertions remain proposals, not world truth', () async {
    final index = _index();
    final first = index.chunks.firstWhere((c) => c.chapterIndex == 0);
    final second = index.chunks.firstWhere((c) => c.chapterIndex == 1);
    final charA = SourceEvidence.propose(index,
      chunkId: first.id, kind: EvidenceKind.character,
      startUtf16: first.startUtf16, endUtf16: first.startUtf16 + 6,
    );
    final charB = SourceEvidence.propose(index,
      chunkId: second.id, kind: EvidenceKind.character,
      startUtf16: second.startUtf16, endUtf16: second.startUtf16 + 6,
    );
    final deniedQuote = SourceEvidence.propose(index,
      chunkId: second.id, kind: EvidenceKind.fact,
      startUtf16: second.startUtf16 + 23,
      endUtf16: second.startUtf16 + 68,
    );
    final graph = SourceEvidenceGraph.empty(index).addAll(index,
        [charA, charB, deniedQuote]);
    final relations = SourceRelationReviewSession.create(index, graph);
    expect(relations.unresolvedCount, greaterThan(0));
    final claim = SourceSemanticAssertion.propose(index, graph,
      kind: SemanticAssertionKind.fact,
      evidenceIds: [deniedQuote.id],
      subject: 'Сторож',
      predicate: 'видел ключ',
      object: 'золотой ключ',
      voice: AssertionVoice.reported,
      polarity: AssertionPolarity.negated,
      time: AssertionTime.flashbackPossible,
      uncertainty: 'Отрицание сообщено персонажем, может быть ложью.',
    );
    final catalog = SourceSemanticCatalog.checked(index, graph, [claim]);
    final editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, claim.id, SemanticEditorialVerdict.disputed);
    final dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    final model = NarrativeBookModel.fromExisting(
      index: index,
      outline: await _outline(index),
      dossiers: dossiers,
      catalog: catalog,
      evidence: graph,
      editorial: editorial,
    );
    expect(model.characters.length, 2);
    expect(model.characters[0].labels.first, 'Путник');
    expect(model.characters[1].labels.first, 'Путник');
    expect(model.characters.every((a) => !a.isWorldActor), true);
    expect(model.characters.every((a) => !a.identityHintsResolved), true);
    expect(model.claims, hasLength(1));
    final reported = model.claims.single;
    expect(reported.polarity, AssertionPolarity.negated);
    expect(reported.voice, AssertionVoice.reported);
    expect(reported.time, AssertionTime.flashbackPossible);
    expect(reported.verdict, SemanticEditorialVerdict.disputed);
    expect(reported.establishesWorldTruth, false);
    expect(reported.establishesActorKnowledge, false);
    expect(reported.provesCausation, false);
    final sameOutline = await _outline(index);
    expect(() => NarrativeBookModel.fromExisting(
      index: index, outline: sameOutline, catalog: catalog,
    ), throwsFormatException);
  });
}
