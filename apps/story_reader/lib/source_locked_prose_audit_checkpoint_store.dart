import 'dart:convert';

import 'source_analysis_checkpoint_repository.dart';
import 'zai_source_locked_prose_audit.dart';

/// Local-private model critiques, separate from the book, generated prose,
/// cloud keys and existing SQLite campaigns. Files are NOT E2E encrypted.
/// Reopen the same prose/plan to avoid a repeated charged model request.
class SourceLockedProseAuditCheckpointStore {
  SourceLockedProseAuditCheckpointStore({
    SourceAnalysisCheckpointRepository? repository,
  }) : repository = repository ??
          const FileSourceAnalysisCheckpointRepository(
            scope: SourceCheckpointScope.zaiProseAuditDrafts,
          );

  final SourceAnalysisCheckpointRepository repository;

  static const format = 'ai_story_prose_audit_checkpoint_m2h7c5_v1';
  static const maxEntries = 128;
  static const maxUtf8Bytes = 512 * 1024;
  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static void _fields(Map<String, dynamic> map, Set<String> keys) {
    if (map.keys.toSet().length != keys.length ||
        !map.keys.toSet().containsAll(keys)) {
      throw const FormatException('Неизвестная схема проверки сцены.');
    }
  }

  static T _enum<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) throw const FormatException();
    final matches = values.where((x) => x.name == raw).toList();
    if (matches.length != 1) throw const FormatException();
    return matches.single;
  }

  static Map<String, Object?> _encode(AiProseAuditReport report) => {
    'scene_id': report.sceneId,
    'context_digest': report.contextDigest,
    'verdict': report.verdict.name,
    'uncertainty': report.uncertainty,
    'findings': [
      for (final finding in report.findings)
        {
          'kind': finding.kind.name,
          'severity': finding.severity.name,
          'problem': finding.problem,
          'evidence_quote': finding.evidenceQuote,
        },
    ],
    'status': 'UNVERIFIED_MODEL_CRITIQUE',
  };

  static AiProseAuditReport _decode(
      Map<String, dynamic> value, String fingerprint) {
    _fields(value, {
      'scene_id', 'context_digest', 'verdict',
      'uncertainty', 'findings', 'status',
    });
    if (value['status'] != 'UNVERIFIED_MODEL_CRITIQUE' ||
        value['scene_id'] is! String ||
        value['context_digest'] is! String ||
        value['uncertainty'] is! String ||
        value['findings'] is! List ||
        !_id.hasMatch(value['scene_id'] as String) ||
        !_sha.hasMatch(value['context_digest'] as String)) {
      throw const FormatException('Подменён результат проверки сцены.');
    }
    final uncertainty = value['uncertainty'] as String;
    if (uncertainty.trim() != uncertainty ||
        uncertainty.length < 12 || uncertainty.length > 500 ||
        _controls.hasMatch(uncertainty)) {
      throw const FormatException('Повреждена неопределённость проверки.');
    }
    final rawFindings = value['findings'] as List;
    if (rawFindings.length > 6) throw const FormatException();
    final findings = <AiProseAuditFinding>[];
    for (final raw in rawFindings) {
      final finding = Map<String, dynamic>.from(raw as Map);
      _fields(finding, {'kind', 'severity', 'problem', 'evidence_quote'});
      if (finding['problem'] is! String) throw const FormatException();
      final problem = finding['problem'] as String;
      final quote = finding['evidence_quote'];
      if (problem.trim() != problem ||
          problem.length < 12 || problem.length > 450 ||
          _controls.hasMatch(problem) ||
          quote != null && (quote is! String ||
              quote.length > 180 || _controls.hasMatch(quote))) {
        throw const FormatException('Повреждён вывод ИИ о сцене.');
      }
      findings.add(AiProseAuditFinding(
        kind: _enum(AiProseFindingKind.values, finding['kind']),
        severity: _enum(
            AiProseFindingSeverity.values, finding['severity']),
        problem: problem,
        evidenceQuote: quote as String?,
      ));
    }
    return AiProseAuditReport(
      sourceFingerprint: fingerprint,
      sceneId: value['scene_id'] as String,
      contextDigest: value['context_digest'] as String,
      verdict: _enum(AiProseAuditVerdict.values, value['verdict']),
      findings: List.unmodifiable(findings),
      uncertainty: uncertainty,
    );
  }

  static void _validateForContext(
      SourceLockedProseAuditContext context, AiProseAuditReport report) {
    if (report.sourceFingerprint != context.scene.index.sourceFingerprint ||
        report.sceneId != context.scene.situation.id ||
        report.contextDigest != context.approvalDigest ||
        report.verdict == AiProseAuditVerdict.possibleConsistency &&
            (context.scene.sourceEvent == null ||
             report.hasHighRiskFinding) ||
        report.findings.any((finding) =>
            finding.evidenceQuote != null &&
            finding.evidenceQuote !=
                context.scene.sourceEvent?.source.quote)) {
      throw const FormatException(
          'Устаревшее или неподтверждённое заключение ИИ.');
    }
    // Round-trip through strict decode so externally constructed report
    // objects can never bypass text, limits or model-status checks.
    _decode(Map<String, dynamic>.from(_encode(report)),
        context.scene.index.sourceFingerprint);
  }

  Future<List<AiProseAuditReport>> _load(
      SourceLockedProseAuditContext context) async {
    final raw = await repository.read(context.scene.index.sourceFingerprint);
    if (raw == null) return [];
    if (utf8.encode(raw).length > maxUtf8Bytes) {
      throw const FormatException('Слишком большой checkpoint ИИ-проверок.');
    }
    try {
      final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _fields(record, {'format', 'source_fingerprint', 'entries'});
      if (record['format'] != format ||
          record['source_fingerprint'] !=
              context.scene.index.sourceFingerprint ||
          record['entries'] is! List) {
        throw const FormatException('Неверная редакция checkpoint.');
      }
      final entries = record['entries'] as List;
      if (entries.length > maxEntries) throw const FormatException();
      final seen = <String>{};
      final result = <AiProseAuditReport>[];
      for (final entry in entries) {
        final report = _decode(
          Map<String, dynamic>.from(entry as Map),
          context.scene.index.sourceFingerprint,
        );
        if (!seen.add(report.sceneId)) {
          throw const FormatException('Повторён ID аудита сцены.');
        }
        result.add(report);
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён локальный отчёт ИИ.');
    }
  }

  Future<AiProseAuditReport?> read(
      SourceLockedProseAuditContext context) async {
    final results = await _load(context);
    for (final report in results) {
      if (report.sceneId == context.scene.situation.id &&
          report.contextDigest == context.approvalDigest) {
        _validateForContext(context, report);
        return report;
      }
    }
    return null;
  }

  Future<void> save({
    required SourceLockedProseAuditContext context,
    required AiProseAuditReport report,
  }) async {
    _validateForContext(context, report);
    final saved = await _load(context);
    if (saved.any((existing) =>
        existing.sceneId == report.sceneId &&
        existing.contextDigest == report.contextDigest)) {
      return;
    }
    final next = [
      for (final item in saved)
        if (item.sceneId != report.sceneId) item,
      report,
    ];
    if (next.length > maxEntries) throw const FormatException();
    final value = jsonEncode({
      'format': format,
      'source_fingerprint': context.scene.index.sourceFingerprint,
      'entries': [for (final item in next) _encode(item)],
    });
    if (utf8.encode(value).length > maxUtf8Bytes) {
      throw const FormatException('Превышен предел локального отчёта.');
    }
    await repository.write(context.scene.index.sourceFingerprint, value);
  }

  Future<void> delete(SourceLockedProseAuditContext context) async {
    final all = await _load(context);
    final rest = all.where(
        (report) => report.sceneId != context.scene.situation.id).toList();
    if (all.length == rest.length) return;
    if (rest.isEmpty) {
      await repository.delete(context.scene.index.sourceFingerprint);
      return;
    }
    await repository.write(context.scene.index.sourceFingerprint, jsonEncode({
      'format': format,
      'source_fingerprint': context.scene.index.sourceFingerprint,
      'entries': [for (final item in rest) _encode(item)],
    }));
  }
}
