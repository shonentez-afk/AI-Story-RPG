import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/quick_rpg_builder.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SourceAnalysisCheckpointRepository {
  String? value;
  @override
  Future<String?> read(String fingerprint) async => value;
  @override
  Future<void> write(String fingerprint, String text) async { value = text; }
  @override
  Future<void> delete(String fingerprint) async { value = null; }
}

BookSourceIndex _story([String suffix = '']) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'История событий' + suffix,
      author: 'Пример',
      chapters: [
        'Путник обнаружил потерянный компас в высокой траве '
            'и решил отправиться на поиски старого дворца.',
        'После долгой дороги путник встретил сторожа возле моста '
            'и получил у него карту неизвестных земель.',
        'В последней главе путник вернулся к дому с хорошими '
            'новостями и передал найденный компас друзьям.',
      ],
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real public-domain Frog Prince FB2 can use exact AI-style '
      'event anchors in the private runtime (without real network)', () async {
    final path = Platform.environment['AI_RPG_FROG_PRINCE_FB2_PATH'];
    if (path == null) return;
    final book = BookImporter.parse(
        'frog_prince_ci.fb2', Uint8List.fromList(
            await File(path).readAsBytes()));
    final index = BookSourceIndexer.index(book);
    final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
    expect(manifest.plannedRequests, greaterThan(0));
    final memory = _Store();
    final analyzer = ZaiAutoWholeBookAnalysis(
      repository: memory,
      preview: (index, window, token, includeTitle) async {
        final found = [
          for (final chunk in window.chunks)
            if (chunk.blockKind.name == 'paragraph' && chunk.text.length >= 60)
              SemanticCandidate.propose(
                index, chunk,
                category: SemanticCategory.event,
                startUtf16: chunk.startUtf16,
                endUtf16: chunk.startUtf16 + 60,
                label: 'Отрывок для проверки события',
                uncertainty: 'Проверена только точность текста, '
                    'не смысл события.',
              ),
        ];
        final entries = found.isEmpty ? <SemanticCandidate>[] : [found.first];
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final c in window.chunks) c.id],
            candidates: entries,
          ),
          totalSuggestions: entries.length,
          rejectedCount: 0,
          rejectedNonRussian: 0,
        );
      },
    );
    var result = await analyzer.read(index);
    var batches = 0;
    while (!result.complete && batches < 64) {
      result = await analyzer.analyze(
        index: index,
        approvedManifestDigest: manifest.approvalDigest,
        explicitWholeBookConsent: true,
        maxWindowsPerRun: 64,
      );
      batches++;
    }
    expect(result.complete, true);
    final outline = ZaiWholeBookEventOutline.build(result);
    expect(outline.events.length, greaterThanOrEqualTo(2));
    final plan = QuickRpgBuilder.proposeFromEventOutline(index, outline);
    final compiled = await QuickRpgBuilder.compile(
      plan: plan,
      allQuotesReviewedByUser: true,
      privateUseConfirmed: true,
    );
    final checked = const PrivateBookworldImporter().inspect(compiled.archive);
    expect(checked.sourceFingerprint, index.sourceFingerprint);
    expect(checked.requiresNetwork, false);
    expect(checked.canDistributePublicly, false);
  });

  test('all book event quotes compile to a private, playable '
      'two-mode source-verified world', () async {
    final index = _story();
    final memory = _Store();
    final service = ZaiAutoWholeBookAnalysis(
      repository: memory,
      preview: (index, window, token, title) async {
        final source = window.chunks.first;
        final finding = SemanticCandidate.propose(
          index, source,
          category: SemanticCategory.event,
          startUtf16: source.startUtf16,
          endUtf16: source.startUtf16 + 60,
          label: 'Найден эпизод из текста',
          uncertainty: 'Смысл события требует проверки по контексту.',
        );
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final c in window.chunks) c.id],
            candidates: [finding],
          ),
          totalSuggestions: 1,
          rejectedCount: 0,
          rejectedNonRussian: 0,
        );
      },
    );
    final fingerprint = ZaiWholeBookConsentManifest.fromIndex(index)
        .approvalDigest;
    final partial = await service.analyze(
      index: index,
      approvedManifestDigest: fingerprint,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 1,
    );
    expect(() => QuickRpgBuilder.proposeFromEventOutline(
          index, ZaiWholeBookEventOutline.build(partial)),
        throwsFormatException);

    final done = await service.analyze(
      index: index,
      approvedManifestDigest: fingerprint,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 2,
    );
    final outline = ZaiWholeBookEventOutline.build(done);
    expect(outline.analysisComplete, true);
    expect(outline.events, hasLength(3));
    final plan = QuickRpgBuilder.proposeFromEventOutline(index, outline);
    expect(plan.sourceScenes, 3);
    for (var i = 0; i < plan.anchors.length; i++) {
      expect(plan.anchors[i].quote, outline.events[i].quote);
      expect(plan.anchors[i].startUtf16, outline.events[i].startUtf16);
    }
    await expectLater(QuickRpgBuilder.compile(
      plan: plan,
      allQuotesReviewedByUser: false,
      privateUseConfirmed: true,
    ), throwsFormatException);
    final archive = await QuickRpgBuilder.compile(
      plan: plan,
      allQuotesReviewedByUser: true,
      privateUseConfirmed: true,
    );
    final world = const PrivateBookworldImporter().inspect(archive.archive);
    expect(world.bookworldId, archive.bookworldId);
    expect(world.sourceFingerprint, index.sourceFingerprint);
    expect(world.requiresNetwork, false);
    expect(world.canDistributePublicly, false);
    expect(world.blueprint.scenes.length, greaterThan(plan.anchors.length));
    for (var i = 0; i < plan.anchors.length; i++) {
      expect(world.blueprint.scenes['episode_${i+1}']!.text,
          contains(plan.anchors[i].quote));
    }

    final follow = QuickRpgBuilder.proposeFromEventOutline(
        index, outline, mode: QuickRpgMode.followBook);
    expect(follow.endings, 2);
    expect(follow.sourceScenes, 3);
    expect(() => QuickRpgBuilder.proposeFromEventOutline(
          _story(' другой источник'), outline),
        throwsFormatException);
  });
}
