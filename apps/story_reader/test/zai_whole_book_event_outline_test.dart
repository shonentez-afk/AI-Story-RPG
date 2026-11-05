import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _PrivateMemory implements SourceAnalysisCheckpointRepository {
  String? data;
  @override
  Future<String?> read(String sourceFingerprint) async => data;
  @override
  Future<void> write(String sourceFingerprint, String checkpoint) async {
    data = checkpoint;
  }
  @override
  Future<void> delete(String sourceFingerprint) async { data = null; }
}

BookSourceIndex _story() => BookSourceIndexer.index(ImportedBook(
  title: 'История трёх глав',
  author: 'Пример',
  chapters: [
    'Ранним утром у ворот города путник обнаружил сломанную повозку '
        'и решил попросить совета у друзей из соседней деревни.',
    'В следующей главе сторож открыл ворота перед путником '
        'и предложил ему прочитать старую карту дальних земель.',
    'Позднее рассказчик возвращается к событиям далёкого прошлого '
        'и объясняет, почему мост был закрыт много лет назад.',
  ],
));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('partial book outline preserves every citation and reports gaps',
      () async {
    final source = _story();
    final repo = _PrivateMemory();
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: repo,
      preview: (index, window, token, includeTitle) async {
        final chunk = window.chunks.first;
        final candidate = SemanticCandidate.propose(index, chunk,
          category: SemanticCategory.event,
          startUtf16: chunk.startUtf16,
          endUtf16: chunk.startUtf16 + 60,
          label: 'Действие героя в оригинале',
          uncertainty: 'Цитата точна, но интерпретация не проверена.',
        );
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final source in window.chunks) source.id],
            candidates: [candidate],
          ),
          rejectedCount: 0,
          rejectedNonRussian: 0,
          totalSuggestions: 1,
        );
      },
    );
    final manifest = ZaiWholeBookConsentManifest.fromIndex(source);
    final part = await analysis.analyze(
      index: source,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 1,
    );
    final outline = ZaiWholeBookEventOutline.build(part);
    expect(outline.analysisComplete, false);
    expect(outline.plannedWindows, 3);
    expect(outline.processedWindows, 1);
    expect(outline.chaptersWithEventProposals, 1);
    expect(outline.warnings.join(' '), contains('Пропущены 2'));
    expect(outline.events.single.hasExactSourceQuote, true);
    expect(outline.events.single.isEventMeaningVerified, false);
    expect(outline.events.single.isChronologyVerified, false);
    expect(outline.events.single.hasCausalDependencies, false);
    expect(outline.isPlayableScenario, false);

    final done = await analysis.analyze(
      index: source,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 2,
    );
    final finalOutline = ZaiWholeBookEventOutline.build(done);
    expect(finalOutline.analysisComplete, true);
    expect(finalOutline.chaptersWithEventProposals, 3);
    expect(finalOutline.events, hasLength(3));
    expect(finalOutline.events.map((e) => e.chapterIndex), [0, 1, 2]);
    final quote = finalOutline.events[1];
    final chunk = source.chunks.singleWhere((c) => c.id == quote.chunkId);
    expect(chunk.text.substring(
        quote.startUtf16 - chunk.startUtf16,
        quote.startUtf16 - chunk.startUtf16 + quote.quote.length),
        quote.quote);
    final rejectedEventId = finalOutline.events.first.id;
    final reviewedQueue = done.queue.decide(
      rejectedEventId, ZaiEditorialDecision.rejected);
    final marked = ZaiWholeBookReviewResult(
      manifest: done.manifest,
      queue: reviewedQueue,
      progress: done.progress,
    );
    final filtered = ZaiWholeBookEventOutline.build(marked);
    expect(filtered.events, hasLength(2));
    expect(filtered.events.any((e) => e.id == rejectedEventId), false);
    expect(finalOutline.canInferCausality, false);
    expect(finalOutline.canPublishPublicly, false);
    // Document order, especially the flashback in chapter 3,
    // must never be presented as chronological or causal world truth.
    expect(finalOutline.warnings.join(' '), contains('хронология'));
    expect(finalOutline.warnings.join(' '), contains('Причины'));
  });

  test('empty AI candidates cannot be called gameplay completeness',
      () async {
    final source = _story();
    final service = ZaiAutoWholeBookAnalysis(
      repository: _PrivateMemory(),
      preview: (i, window, t, title) async => ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: i.sourceFingerprint,
          chunkIds: [for (final chunk in window.chunks) chunk.id],
          candidates: const [],
        ),
        totalSuggestions: 0,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      ),
    );
    final review = await service.analyze(
      index: source,
      approvedManifestDigest:
          ZaiWholeBookConsentManifest.fromIndex(source).approvalDigest,
      explicitWholeBookConsent: true,
    );
    final outline = ZaiWholeBookEventOutline.build(review);
    expect(outline.analysisComplete, true);
    expect(outline.events, isEmpty);
    expect(outline.allChaptersHaveEventProposals, false);
    expect(outline.isPlayableScenario, false);
    expect(outline.warnings.join(' '), contains('ни одного'));
  });
}
