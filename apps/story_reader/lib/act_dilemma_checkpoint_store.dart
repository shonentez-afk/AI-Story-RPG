import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_connection.dart';
import 'bookwide_act_dilemma_gateway.dart';
import 'bookwide_act_planner.dart';
import 'narrative_book_model.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'story_plan_dilemma_generator.dart';
import 'story_plan_quality_gate.dart';
import 'zai_story_dilemma_proposal.dart';

/// Stores model *proposals*, not confirmed literary events or new user
/// consent. A restart NEVER authorizes an additional Z.ai request.
/// Raw source quotations, full chapters, API keys and saves are not stored.
class ActDilemmaCheckpointStore {
  ActDilemmaCheckpointStore({
    SourceAnalysisCheckpointRepository? repository,
  }) : repository = repository ??
         const FileSourceAnalysisCheckpointRepository(
           scope: SourceCheckpointScope.zaiActDilemmaDrafts);

  final SourceAnalysisCheckpointRepository repository;

  static const format = 'ai_story_act_proposal_checkpoint_m2h4_v1';
  static const promptVersion = 'm2g3b_source_dilemma_v1';
  static const maxStoredActs = 6;
  static const maxBytes = 128 * 1024;

  static Map<String, dynamic> _asMap(Object? v) {
    if (v is! Map) {
      throw const FormatException('Повреждён формат локального черновика.');
    }
    return Map<String, dynamic>.from(v);
  }

  static void _exactKeys(Map<String, dynamic> data, Set<String> keys) {
    if (data.keys.toSet().length != keys.length ||
        !data.keys.toSet().containsAll(keys)) {
      throw const FormatException('Недопустимые поля локального черновика.');
    }
  }

  static ActDilemmaCandidate _validateCandidate({
    required NarrativeBookModel book,
    required ActDilemmaConsentManifest manifest,
    required ActDilemmaCandidate candidate,
  }) {
    final preview = candidate.preview;
    if (candidate.actId != manifest.actId ||
        preview.sampledEventCount != manifest.eventIds.length) {
      throw const FormatException('Черновик относится к другой части.');
    }
    if (!preview.foundCandidate) {
      if (preview.plan != null || preview.proposal != null ||
          candidate.quality != null) {
        throw const FormatException('Несогласованный пустой ответ модели.');
      }
      return candidate;
    }
    final proposal = preview.proposal!;
    if (proposal.sourceFingerprint != book.sourceFingerprint ||
        !manifest.eventIds.contains(proposal.setupEventId) ||
        !manifest.eventIds.contains(proposal.outcomeEventId) ||
        preview.plan == null) {
      throw const FormatException('Сценарий ссылается на чужие цитаты.');
    }
    final checked = StoryPlanQualityGate.assess(
        book: book, preview: preview);
    if (!checked.passedFormalPreflight) {
      throw const FormatException(
          'Черновой сценарий содержит нарушения игровых условий.');
    }
    return ActDilemmaCandidate(
        actId: manifest.actId, preview: preview, quality: checked);
  }

  Future<List<ActDilemmaCandidate>> readAll({
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
  }) async {
    final raw = await repository.read(book.sourceFingerprint);
    if (raw == null) return const <ActDilemmaCandidate>[];
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Локальный черновик превышает лимит.');
    }
    try {
      final envelope = _asMap(jsonDecode(raw));
      _exactKeys(envelope, {'body', 'sha256'});
      final body = _asMap(envelope['body']);
      _exactKeys(body, {
        'format', 'source_fingerprint', 'model', 'prompt_version',
        'status', 'entries',
      });
      if (body['format'] != format ||
          body['source_fingerprint'] != book.sourceFingerprint ||
          body['model'] != ZaiModel.id ||
          body['prompt_version'] != promptVersion ||
          body['status'] != 'DRAFT_ONLY' ||
          envelope['sha256'] !=
              sha256.convert(utf8.encode(jsonEncode(body))).toString()) {
        throw const FormatException(
            'Сохранённый сценарий не соответствует текущей редакции.');
      }
      final rawEntries = body['entries'];
      if (rawEntries is! List || rawEntries.length > maxStoredActs) {
        throw const FormatException('Слишком много записей черновика.');
      }
      final ids = <String>{};
      final results = <ActDilemmaCandidate>[];
      for (final rawEntry in rawEntries) {
        final entry = _asMap(rawEntry);
        _exactKeys(entry, {
          'act_id', 'excerpt_digest', 'samples',
          'has_candidate', 'proposal_json',
        });
        final id = entry['act_id'];
        if (id is! String || !ids.add(id)) {
          throw const FormatException(
              'Часть книги продублирована в сохранённом черновике.');
        }
        final manifest = ActDilemmaConsentManifest.fromAct(
            book: book, bookMap: bookMap, actId: id);
        if (manifest.approvalDigest != entry['excerpt_digest'] ||
            manifest.eventIds.length != entry['samples']) {
          throw const FormatException(
              'После сохранения изменились исходные цитаты части.');
        }
        final present = entry['has_candidate'];
        if (present is! bool) {
          throw const FormatException('Неизвестный тип ответа модели.');
        }
        ZaiStoryDilemmaPreview preview;
        if (!present) {
          if (entry['proposal_json'] != null) {
            throw const FormatException('Некорректный пустой ответ.');
          }
          preview = ZaiStoryDilemmaPreview(
              proposal: null, plan: null,
              sampledEventCount: manifest.eventIds.length);
        } else {
          final encoded = entry['proposal_json'];
          if (encoded is! String) {
            throw const FormatException('Отсутствует предложенный сценарий.');
          }
          final proposal = StoryDilemmaProposal.decode(encoded);
          final plan = StoryPlanDilemmaGenerator.propose(book, proposal);
          preview = ZaiStoryDilemmaPreview(
            proposal: proposal, plan: plan,
            sampledEventCount: manifest.eventIds.length);
        }
        results.add(_validateCandidate(
          book: book,
          manifest: manifest,
          candidate: ActDilemmaCandidate(
            actId: id, preview: preview,
            quality: present
                ? StoryPlanQualityGate.assess(book: book, preview: preview)
                : null,
          ),
        ));
      }
      final order = {
        for (var i = 0; i < bookMap.acts.length; i++)
          bookMap.acts[i].id: i,
      };
      results.sort((a, b) => order[a.actId]!.compareTo(order[b.actId]!));
      return List.unmodifiable(results);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Локальный сценарный черновик повреждён. '
          'Повторного запроса к Z.ai не было.');
    }
  }

  /// An atomic same-edition update; a failed write does not overwrite
  /// earlier successfully saved act proposals.
  Future<void> save({
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required ActDilemmaCandidate candidate,
  }) async {
    final manifest = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: bookMap, actId: candidate.actId);
    final checked = _validateCandidate(
        book: book, manifest: manifest, candidate: candidate);
    final existing = await readAll(book: book, bookMap: bookMap);
    final current = [
      for (final item in existing)
        if (item.actId != checked.actId) item,
      checked,
    ];
    if (current.length > maxStoredActs) {
      throw const FormatException(
          'Достигнут лимит частей одного приватного черновика.');
    }
    final order = {
      for (var i = 0; i < bookMap.acts.length; i++)
        bookMap.acts[i].id: i,
    };
    current.sort((a, b) => order[a.actId]!.compareTo(order[b.actId]!));
    final body = {
      'format': format,
      'source_fingerprint': book.sourceFingerprint,
      'model': ZaiModel.id,
      'prompt_version': promptVersion,
      'status': 'DRAFT_ONLY',
      'entries': [
        for (final candidate in current)
          {
            'act_id': candidate.actId,
            'excerpt_digest': ActDilemmaConsentManifest.fromAct(
                book: book, bookMap: bookMap,
                actId: candidate.actId).approvalDigest,
            'samples': candidate.preview.sampledEventCount,
            'has_candidate': candidate.foundCandidate,
            'proposal_json': candidate.preview.proposal?.encode(),
          },
      ],
    };
    final record = jsonEncode({
      'body': body,
      'sha256': sha256.convert(
          utf8.encode(jsonEncode(body))).toString(),
    });
    if (utf8.encode(record).length > maxBytes) {
      throw const FormatException('Черновик слишком большой для сохранения.');
    }
    await repository.write(book.sourceFingerprint, record);
  }

  Future<void> delete(NarrativeBookModel book) =>
      repository.delete(book.sourceFingerprint);
}
