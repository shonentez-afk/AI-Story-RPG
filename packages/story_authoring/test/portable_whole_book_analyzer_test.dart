import 'dart:convert';

import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

void main() {
  const creator = BookAuthoringEngine();

  SourceLockedBook sample() => creator.indexImported(const ImportedBook(
    title: 'Герои большой книги',
    author: 'Частный автор',
    chapters: [
      'Мария пошла по дороге и встретила друга у реки.',
      'Друг дал Марии письмо, и она вернулась в деревню.',
      'Мария прочла письмо и начала новое путешествие.',
    ],
  ));

  test('portable whole-book analysis requires consent, resumes and never'
      ' silently skips source windows', () async {
    final book = sample();
    final index = book.index;
    final consent = ZaiWholeBookConsentManifest.fromIndex(index);
    expect(consent.plannedRequests, greaterThanOrEqualTo(3));
    final saved = <String, String>{};
    var calls = 0, commits = 0;
    final analyzer = PortableWholeBookAnalyzer(
      readCheckpoint: (id) async => saved[id],
      writeCheckpoint: (id, data) async {
        saved[id] = data;
        commits++;
      },
      preview: (source, window, withTitle) async {
        calls++;
        expect(source.sourceFingerprint, index.sourceFingerprint);
        SourceSemanticWindowPlanner.validate(index, window);
        expect(withTitle, false);
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: SemanticPreviewWireContract.providerId,
            providerVersion: SemanticPreviewWireContract.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final chunk in window.chunks) chunk.id],
            candidates: const [],
          ),
          rejectedCount: 0,
          rejectedNonRussian: 0,
          totalSuggestions: 0,
        );
      },
    );

    await expectLater(analyzer.analyze(
      index: index,
      approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: false,
    ), throwsFormatException);
    expect(calls, 0);
    final partial = await analyzer.analyze(
      index: index,
      approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 1,
    );
    expect(partial.progress.completed, 1);
    expect(partial.complete, false);
    expect(commits, 1);
    expect(calls, 1);
    expect(saved[index.sourceFingerprint], isNotNull);

    final resumed = await analyzer.analyze(
      index: index,
      approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 64,
    );
    expect(resumed.complete, true);
    expect(resumed.progress.remaining, 0);
    expect(commits, consent.plannedRequests);
    expect(calls, consent.plannedRequests);
    final restored = await analyzer.read(index);
    expect(restored.progress.completed, consent.plannedRequests);
    final outline = ZaiWholeBookEventOutline.build(restored);
    expect(outline.analysisComplete, true);
    expect(outline.isPlayableScenario, false);
    expect(outline.events, isEmpty);
    expect(outline.warnings, isNotEmpty);
  });

  test('edition and untrusted provider output are checked before writes',
      () async {
    final book = sample();
    final index = book.index;
    final consent = ZaiWholeBookConsentManifest.fromIndex(index);
    final saved = <String, String>{};
    var calls = 0;
    final analyzer = PortableWholeBookAnalyzer(
      readCheckpoint: (id) async => saved[id],
      writeCheckpoint: (id, value) async { saved[id] = value; },
      preview: (source, window, withTitle) async {
        calls++;
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: 'FORGED_PROVIDER',
            providerVersion: SemanticPreviewWireContract.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final item in window.chunks) item.id],
            candidates: const [],
          ),
          rejectedCount: 0, rejectedNonRussian: 0, totalSuggestions: 0,
        );
      },
    );
    await expectLater(analyzer.analyze(
      index: index,
      approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: true,
    ), throwsFormatException);
    expect(calls, 1);
    expect(saved, isEmpty);
    await expectLater(analyzer.analyze(
      index: index,
      approvedManifestDigest: 'forged',
      explicitWholeBookConsent: true,
    ), throwsFormatException);
    expect(calls, 1);
    await expectLater(analyzer.analyze(
      index: index,
      approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: true,
      checkCancelled: () => throw StateError('Stopped'),
    ), throwsStateError);
    expect(calls, 1);
    saved[index.sourceFingerprint] = jsonEncode({'foreign': true});
    await expectLater(analyzer.read(index), throwsFormatException);
  });
}
