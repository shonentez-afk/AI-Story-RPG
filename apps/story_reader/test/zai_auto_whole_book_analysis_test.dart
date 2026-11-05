import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/source_semantic_window.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SourceAnalysisCheckpointRepository {
  String? saved;
  int writes = 0;
  @override
  Future<String?> read(String fingerprint) async => saved;
  @override
  Future<void> write(String fingerprint, String text) async {
    saved = text;
    writes++;
  }
  @override
  Future<void> delete(String fingerprint) async { saved = null; }
}

BookSourceIndex _index({String addition = ''}) {
  return BookSourceIndexer.index(ImportedBook(
    title: 'Три главы тестовой истории' + addition,
    author: 'Тестовый автор',
    chapters: [
      'В первой главе путешественник обнаружил ключ возле дома. '
          'Никто не объяснил, что именно открывает этот ключ.',
      'Во второй главе путешественник встретил старого учителя у реки. '
          'Они беседовали о пути на север и о правилах замка.',
      'В последней главе путешественник вернулся домой после долгого пути. '
          'Друг предложил ему сохранить необычные находки.',
    ],
  ));
}

ZaiSemanticPreviewResult _event(BookSourceIndex index,
    SourceSemanticWindow window) {
  final source = window.chunks.firstWhere(
      (piece) => piece.text.length > 65);
  final quoteLength = 60;
  final item = SemanticCandidate.propose(
    index, source,
    category: SemanticCategory.event,
    startUtf16: source.startUtf16,
    endUtf16: source.startUtf16 + quoteLength,
    label: 'Событие из текста',
    uncertainty: 'Модель только предложила интерпретацию; '
        'нужна проверка редактором.',
  );
  return ZaiSemanticPreviewResult(
    batch: SemanticCandidateBatch(
      providerId: ZaiSemanticPreviewService.providerId,
      providerVersion: ZaiSemanticPreviewService.providerVersion,
      sourceFingerprint: index.sourceFingerprint,
      chunkIds: [for (final chunk in window.chunks) chunk.id],
      candidates: [item],
    ),
    totalSuggestions: 1,
    rejectedCount: 0,
    rejectedNonRussian: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('whole-book permission is tied to source, edition, title and windows',
      () {
    final index = _index();
    final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
    expect(manifest.chapters, 3);
    expect(manifest.plannedRequests, 3);
    expect(manifest.approvalDigest, hasLength(64));
    expect(manifest.sourceUtf8Bytes, greaterThan(100));
    expect(manifest.approvalDigest,
        ZaiWholeBookConsentManifest.fromIndex(_index()).approvalDigest);
    expect(manifest.approvalDigest,
        isNot(ZaiWholeBookConsentManifest.fromIndex(
            _index(addition: ' (новое издание)')).approvalDigest));
  });

  test('without exact one-time whole-book consent not a single request',
      () async {
    final source = _index();
    final repo = _Store();
    var posts = 0;
    final service = ZaiAutoWholeBookAnalysis(
      repository: repo,
      preview: (i, w, token, title) async {
        posts++;
        return _event(i, w);
      },
    );
    final valid = ZaiWholeBookConsentManifest.fromIndex(source).approvalDigest;
    for (final args in [
      (false, valid), (true, 'not-the-current-book'),
    ]) {
      await expectLater(
        service.analyze(
          index: source,
          approvedManifestDigest: args.$2,
          explicitWholeBookConsent: args.$1,
        ), throwsFormatException,
      );
    }
    expect(posts, 0);
    expect(repo.writes, 0);
    expect(repo.saved, isNull);
  });

  test('one successful window persists; exact resume skips it and never '
      'promotes AI hypotheses into canon', () async {
    final source = _index();
    final repo = _Store();
    var posts = 0;
    final service = ZaiAutoWholeBookAnalysis(
      repository: repo,
      preview: (i, w, token, title) async {
        posts++;
        return _event(i, w);
      },
    );
    final manifest = ZaiWholeBookConsentManifest.fromIndex(source);
    final first = await service.analyze(
      index: source,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 1,
    );
    expect(first.complete, false);
    expect(first.progress.completed, 1);
    expect(first.progress.remaining, 2);
    expect(first.progress.eventProposals, 1);
    expect(first.canCompileBookworld, false);
    expect(first.hasAcceptedCanon, false);
    expect(first.queue.decisions, isEmpty);
    expect(repo.writes, 1);

    final again = await service.analyze(
      index: source,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 2,
    );
    expect(again.complete, true);
    expect(again.progress.completed, 3);
    expect(again.progress.eventProposals, 3);
    expect(again.queue.decisions, isEmpty);
    expect(repo.writes, 3);
    expect(posts, 3);
    final replay = await service.read(source);
    expect(replay.progress.finished, true);
    expect(replay.queue.encode(), repo.saved);
    await service.analyze(index: source,
        approvedManifestDigest: manifest.approvalDigest,
        explicitWholeBookConsent: true);
    expect(posts, 3);
    expect(repo.writes, 3);
  });

  test('corrupt private checkpoint refuses overwrite and resend', () async {
    final source = _index();
    final repo = _Store()..saved = '{bad-json';
    var posts = 0;
    final service = ZaiAutoWholeBookAnalysis(
      repository: repo,
      preview: (i, w, token, title) async {
        posts++;
        return _event(i, w);
      },
    );
    await expectLater(service.analyze(
      index: source,
      approvedManifestDigest: ZaiWholeBookConsentManifest
          .fromIndex(source).approvalDigest,
      explicitWholeBookConsent: true), throwsFormatException);
    expect(posts, 0);
    expect(repo.saved, '{bad-json');
  });

  test('one invalid response cannot be stored as valid progress', () async {
    final source = _index();
    final repo = _Store();
    final service = ZaiAutoWholeBookAnalysis(
      repository: repo,
      preview: (i, w, token, title) async => ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: i.sourceFingerprint,
          chunkIds: ['forged-source-id'],
          candidates: const [],
        ),
        totalSuggestions: 0,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      ),
    );
    await expectLater(service.analyze(
      index: source,
      approvedManifestDigest: ZaiWholeBookConsentManifest
          .fromIndex(source).approvalDigest,
      explicitWholeBookConsent: true), throwsFormatException);
    expect(repo.writes, 0);
  });
}
