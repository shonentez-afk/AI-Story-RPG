import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'whole_story_literary_review.dart';
import 'zai_semantic_preview.dart';

class WholeLiteraryReviewProgress {
  const WholeLiteraryReviewProgress({
    required this.total,
    required this.completed,
    required this.recovered,
    required this.newRequests,
    required this.uncoveredBookEvents,
  });
  final int total, completed, recovered, newRequests, uncoveredBookEvents;
  int get remaining => total - completed;
  bool get complete => remaining == 0;
  bool get verifiesCanon => false;
}

typedef WholeLiteraryPreview = Future<WholeLiteraryReviewReport> Function(
    LiteraryReviewWindow window, ZaiPreviewCancellation cancellation);

/// Exact-consent, bounded, resumable *read-only* literary suggestions.
/// Already completed windows are never sent again under the same manifest.
/// Checkpoints store IDs and brief findings, never full book quotes or keys.
class WholeStoryLiteraryBatchService {
  WholeStoryLiteraryBatchService({
    SourceAnalysisCheckpointRepository? repository,
    ZaiWholeStoryLiteraryCritic? critic,
    WholeLiteraryPreview? previewOverride,
  }) : repository = repository ??
            const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.zaiWholeStoryLiteraryReviews,
            ),
       critic = critic ?? ZaiWholeStoryLiteraryCritic(),
       previewOverride = previewOverride;

  final SourceAnalysisCheckpointRepository repository;
  final ZaiWholeStoryLiteraryCritic critic;
  final WholeLiteraryPreview? previewOverride;

  static const format = 'ai_story_whole_literary_checkpoint_m2h8g1b_v1';
  static const maxCheckpointBytes = 512 * 1024;
  static final _active = <String>{};
  static final _sha = RegExp(r'^[a-f0-9]{64}$');

  static WholeLiteraryReviewReport _validate(
      LiteraryReviewWindow window, WholeLiteraryReviewReport report) {
    return WholeLiteraryReviewReport.fromJson(
        window, Map<String, dynamic>.from(report.toJson()));
  }

  Future<List<WholeLiteraryReviewReport>> _load(
      WholeStoryLiteraryReviewManifest manifest) async {
    manifest.verifyUnchanged();
    final raw = await repository.read(manifest.index.sourceFingerprint);
    if (raw == null) return const [];
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Слишком большой checkpoint литературного аудита.');
    }
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const keys = {
        'format', 'source_fingerprint', 'manifest_digest',
        'saved', 'sha256',
      };
      if (data.keys.toSet().length != keys.length ||
          !data.keys.toSet().containsAll(keys) ||
          data['format'] != format ||
          data['source_fingerprint'] != manifest.index.sourceFingerprint ||
          data['manifest_digest'] != manifest.approvalDigest ||
          data['sha256'] is! String ||
          !_sha.hasMatch(data['sha256'] as String)) {
        throw const FormatException('Checkpoint другой редакции или плана.');
      }
      final checksum = data.remove('sha256');
      if (checksum != sha256.convert(utf8.encode(jsonEncode(data))).toString()) {
        throw const FormatException('Повреждена контрольная сумма checkpoint.');
      }
      final rawSaved = data['saved'];
      if (rawSaved is! List || rawSaved.length > manifest.windows.length) {
        throw const FormatException('Неверное количество заключений ИИ.');
      }
      final reports = <WholeLiteraryReviewReport>[];
      for (var i = 0; i < rawSaved.length; i++) {
        final record = Map<String, dynamic>.from(rawSaved[i] as Map);
        final report = WholeLiteraryReviewReport.fromJson(
            manifest.windows[i], record);
        reports.add(report);
      }
      return List.unmodifiable(reports);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён результат литературного аудита.');
    }
  }

  Future<void> _save(
      WholeStoryLiteraryReviewManifest manifest,
      List<WholeLiteraryReviewReport> reports) async {
    if (reports.length > manifest.windows.length) {
      throw const FormatException('Превышен лимит литературных отчётов.');
    }
    final payload = <String, Object?>{
      'format': format,
      'source_fingerprint': manifest.index.sourceFingerprint,
      'manifest_digest': manifest.approvalDigest,
      'saved': [
        for (var i = 0; i < reports.length; i++)
          _validate(manifest.windows[i], reports[i]).toJson(),
      ],
    };
    final digest = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    final encoded = jsonEncode({...payload, 'sha256': digest});
    if (utf8.encode(encoded).length > maxCheckpointBytes) {
      throw const FormatException('Checkpoint литературного аудита переполнен.');
    }
    await repository.write(manifest.index.sourceFingerprint, encoded);
  }

  Future<WholeLiteraryReviewProgress> inspect(
      WholeStoryLiteraryReviewManifest manifest) async {
    final done = (await _load(manifest)).length;
    return WholeLiteraryReviewProgress(
      total: manifest.totalWindows,
      completed: done,
      recovered: done,
      newRequests: 0,
      uncoveredBookEvents: manifest.notCoveredEvents,
    );
  }

  Future<List<WholeLiteraryReviewReport>> read(
      WholeStoryLiteraryReviewManifest manifest) => _load(manifest);

  /// No network before user approved EXACT digest and request budget.
  /// Each separate explicit action accepts <=2 NEW calls and <=3 attempts
  /// each; cancelled or failed writes do not claim a saved paid request.
  Future<WholeLiteraryReviewProgress> generate({
    required WholeStoryLiteraryReviewManifest manifest,
    required String approvedManifestDigest,
    required bool explicitBatchConsent,
    ZaiPreviewCancellation? cancellation,
    void Function(WholeLiteraryReviewProgress progress)? onProgress,
  }) async {
    if (!explicitBatchConsent ||
        approvedManifestDigest != manifest.approvalDigest) {
      throw const FormatException(
          'Пользователь не подтвердил точные цитаты и бюджет аудита.');
    }
    final fingerprint = manifest.index.sourceFingerprint;
    if (!_active.add(fingerprint)) {
      throw const FormatException(
          'По этой книге уже выполняется литературный аудит.');
    }
    try {
      final token = cancellation ?? ZaiPreviewCancellation();
      token.check();
      final saved = [...await _load(manifest)];
      final recovered = saved.length;
      var newRequests = 0;
      WholeLiteraryReviewProgress progress() => WholeLiteraryReviewProgress(
        total: manifest.totalWindows,
        completed: saved.length,
        recovered: recovered,
        newRequests: newRequests,
        uncoveredBookEvents: manifest.notCoveredEvents,
      );
      onProgress?.call(progress());
      for (var n = saved.length; n < manifest.windows.length; n++) {
        token.check();
        if (newRequests >= manifest.maxNewRequestsPerRun) break;
        final window = manifest.windows[n];
        final report = await (previewOverride?.call(window, token) ??
            critic.review(
              window: window, approvedDigest: window.approvalDigest,
              explicitReviewConsent: true, cancellation: token,
            ));
        token.check();
        _validate(window, report);
        await _save(manifest, [...saved, report]);
        token.check();
        saved.add(report);
        newRequests++;
        onProgress?.call(progress());
      }
      return progress();
    } finally {
      _active.remove(fingerprint);
    }
  }
}
