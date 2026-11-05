import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_connection.dart';
import 'narrative_book_model.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'story_plan_dilemma_generator.dart';
import 'story_plan_quality_gate.dart';
import 'zai_story_dilemma_proposal.dart';

/// A small PRIVATE checkpoint after one explicitly approved GLM request.
/// Only the model's *suggested* dilemma text and source-event identifiers
/// are saved. No original book chapters, quotes, secrets or campaigns are
/// serialized here. A cached proposal NEVER inherits consent for new POSTs.
///
/// This prevents repeating paid analysis merely because the app restarted.
class StoryPlanDraftCheckpointStore {
  StoryPlanDraftCheckpointStore({
    SourceAnalysisCheckpointRepository? repository,
  }) : repository = repository ??
       const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.zaiStoryPlanPreview);

  final SourceAnalysisCheckpointRepository repository;

  static const format = 'ai_story_glm_dilemma_checkpoint_m2g3f_v1';
  static const promptVersion = 'm2g3b_source_dilemma_v1';
  static const maxCheckpointBytes = 22 * 1024;

  static String _sampleFingerprint(NarrativeBookModel book) {
    final selected = ZaiStoryDilemmaProposalService.samples(book);
    final samples = [
      for (final e in selected)
        {
          'event_id': e.id,
          'chunk_id': e.source.chunkId,
          'chapter_index': e.source.chapterIndex,
          'start_utf16': e.source.startUtf16,
          'end_utf16': e.source.endUtf16,
          // No plaintext quote is kept in the stored checkpoint.
          'source_sha256': sha256.convert(
              utf8.encode(e.source.quote)).toString(),
        },
    ];
    return sha256.convert(utf8.encode(jsonEncode(samples))).toString();
  }

  static Map<String, Object?> _body({
    required NarrativeBookModel book,
    required ZaiStoryDilemmaPreview preview,
  }) {
    final eventCount =
        ZaiStoryDilemmaProposalService.samples(book).length;
    if (!book.analysisComplete ||
        preview.sampledEventCount != eventCount ||
        preview.foundCandidate !=
            (preview.proposal != null && preview.plan != null)) {
      throw const FormatException('Нельзя сохранить чужой сценарий.');
    }
    if (preview.foundCandidate) {
      // Regeneration + causal audit ensures that a changed model/UI graph
      // cannot silently become a trusted checkpoint.
      final report = StoryPlanQualityGate.assess(
          book: book, preview: preview);
      if (!report.passedFormalPreflight) {
        throw const FormatException(
            'Нельзя сохранить формально неверный сценарий.');
      }
    } else if (preview.proposal != null || preview.plan != null) {
      throw const FormatException('Неполный сценарный кандидат.');
    }
    return {
      'format': format,
      'status': 'DRAFT_ONLY',
      'source_fingerprint': book.sourceFingerprint,
      'sample_signature': _sampleFingerprint(book),
      'model': ZaiModel.id,
      'prompt_version': promptVersion,
      'sampled_event_count': eventCount,
      'has_candidate': preview.foundCandidate,
      'proposal_json': preview.proposal?.encode(),
      'ready_to_play': false,
    };
  }

  /// Always finish writing the same-edition checkpoint BEFORE telling the UI
  /// it will survive a restart. Storage errors must be reported honestly.
  Future<void> save(
      NarrativeBookModel book, ZaiStoryDilemmaPreview preview) async {
    final body = _body(book: book, preview: preview);
    final raw = jsonEncode(body);
    final record = jsonEncode({
      'body': body,
      'checksum_sha256': sha256.convert(utf8.encode(raw)).toString(),
    });
    if (utf8.encode(record).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой черновик для сохранения.');
    }
    await repository.write(book.sourceFingerprint, record);
  }

  /// A malformed, mismatched or manipulated checkpoint FAILS CLOSED. No
  /// network calls occur; caller can show a local restore error and ask
  /// whether to retry with a NEW explicit consent.
  Future<ZaiStoryDilemmaPreview?> read(NarrativeBookModel book) async {
    final raw = await repository.read(book.sourceFingerprint);
    if (raw == null) return null;
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Повреждён локальный сценарный черновик.');
    }
    try {
      final container = Map<String, dynamic>.from(
          jsonDecode(raw) as Map);
      if (container.keys.toSet().length != 2 ||
          !container.containsKey('body') ||
          !container.containsKey('checksum_sha256')) {
        throw const FormatException('Чужой формат сценарного черновика.');
      }
      final body = Map<String, dynamic>.from(
          container['body'] as Map);
      const required = {
        'format', 'status', 'source_fingerprint', 'sample_signature',
        'model', 'prompt_version', 'sampled_event_count',
        'has_candidate', 'proposal_json', 'ready_to_play',
      };
      if (body.keys.toSet().length != required.length ||
          !body.keys.toSet().containsAll(required) ||
          body['format'] != format || body['status'] != 'DRAFT_ONLY' ||
          body['model'] != ZaiModel.id ||
          body['prompt_version'] != promptVersion ||
          body['source_fingerprint'] != book.sourceFingerprint ||
          body['sample_signature'] != _sampleFingerprint(book) ||
          body['sampled_event_count'] !=
              ZaiStoryDilemmaProposalService.samples(book).length ||
          body['ready_to_play'] != false ||
          container['checksum_sha256'] !=
              sha256.convert(utf8.encode(jsonEncode(body))).toString()) {
        throw const FormatException('Черновик не соответствует этой книге.');
      }
      final hasCandidate = body['has_candidate'];
      if (hasCandidate is! bool) {
        throw const FormatException('Неверный тип сохранённого ответа.');
      }
      if (!hasCandidate) {
        if (body['proposal_json'] != null) {
          throw const FormatException('Несогласованный пустой ответ.');
        }
        return ZaiStoryDilemmaPreview(
          proposal: null, plan: null,
          sampledEventCount: body['sampled_event_count'] as int);
      }
      final encoded = body['proposal_json'];
      if (encoded is! String) {
        throw const FormatException('Отсутствует сценарное предложение.');
      }
      final proposal = StoryDilemmaProposal.decode(encoded);
      final plan = StoryPlanDilemmaGenerator.propose(book, proposal);
      final restored = ZaiStoryDilemmaPreview(
        proposal: proposal,
        plan: plan,
        sampledEventCount: body['sampled_event_count'] as int,
      );
      final report = StoryPlanQualityGate.assess(
          book: book, preview: restored);
      if (!report.passedFormalPreflight) {
        throw const FormatException(
            'В сохранённом сценарии обнаружены противоречия.');
      }
      return restored;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Повреждён или подменён локальный черновик RPG.');
    }
  }

  Future<void> delete(NarrativeBookModel book) =>
      repository.delete(book.sourceFingerprint);
}
