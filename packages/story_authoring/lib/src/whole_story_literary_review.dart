import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'whole_story_literary_evidence_manifest.dart';

class LiteraryReviewWireContract {
  const LiteraryReviewWireContract._();
  static const modelId = 'glm-4.7-flash';
  static const maxAttempts = 3;
}

/// A separate, EXACT and bounded user-consent scope for cross-act literary
/// criticism. All reachable transitions are included or the build FAILS.
/// Original quotations are sent only where separately verified.
class WholeStoryLiteraryReviewManifest {
  WholeStoryLiteraryReviewManifest._({
    required this.index,
    required this.book,
    required this.plan,
    required this.evidence,
    required this.claimEvidence,
    required this.approvalDigest,
    required this.maxNewRequestsPerRun,
    required List<LiteraryReviewWindow> windows,
  }) : windows = List.unmodifiable(windows);

  static const format = 'ai_story_whole_literary_review_m2h8g1b_v1';
  static const maxWindows = 32;
  static const maxNewRequests = 2;
  static const maxTransitionsPerWindow = 8;
  static const maxQuotesPerWindow = 8;
  static const maxContextBytes = 12 * 1024;

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final WholeStoryLiteraryEvidenceManifest evidence;
  final SourceEvidenceGraph? claimEvidence;
  final String approvalDigest;
  final int maxNewRequestsPerRun;
  final List<LiteraryReviewWindow> windows;

  int get totalWindows => windows.length;
  int get notCoveredEvents => evidence.uncoveredSourceEvents;
  int get totalTransitions => evidence.reachableTransitions;
  int get maxHttpAttempts => maxNewRequestsPerRun *
      LiteraryReviewWireContract.maxAttempts;
  bool get claimsLiteraryCanon => false;
  bool get permitsGameMutation => false;

  List<Map<String, dynamic>> get sentContexts => List.unmodifiable(
      [for (final window in windows) window.sentContext]);

  static WholeStoryLiteraryReviewManifest fromEvidence({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required WholeStoryLiteraryEvidenceManifest evidence,
    SourceEvidenceGraph? claimEvidence,
    int maxNewRequestsPerRun = maxNewRequests,
  }) {
    if (maxNewRequestsPerRun < 1 ||
        maxNewRequestsPerRun > maxNewRequests) {
      throw const FormatException('Недопустимый бюджет литературного аудита.');
    }
    evidence.verifyUnchanged(
        index: index, book: book, plan: plan,
        claimEvidence: claimEvidence);
    final details = evidence.toJson();
    final rows = details['all_reachable_transitions'];
    if (rows is! List || rows.isEmpty ||
        rows.length != evidence.reachableTransitions) {
      throw const FormatException('Неполная проверка игровых маршрутов.');
    }
    final eventById = {for (final event in book.events) event.id: event};
    final sceneById = {for (final scene in plan.situations) scene.id: scene};
    final groups = <LiteraryReviewWindow>[];
    var windowRows = <Map<String, dynamic>>[];

    LiteraryReviewWindow makeWindow(List<Map<String, dynamic>> entries,
        int position) {
      final used = <String>{};
      for (final transition in entries) {
        for (final key in ['scene_source_event_id',
            'choice_source_event_id']) {
          final id = transition[key];
          if (id == null) continue;
          if (id is! String || !eventById.containsKey(id)) {
            throw const FormatException('Чужая цитата в игровом маршруте.');
          }
          used.add(id);
        }
      }
      if (used.length > maxQuotesPerWindow) {
        throw const FormatException('Слишком много цитат в одном пакете.');
      }
      final quotes = <Map<String, Object?>>[];
      for (final event in book.events) {
        if (!used.contains(event.id)) continue;
        event.source.validate(index);
        quotes.add({
          'source_event_id': event.id,
          'chapter_index_in_book': event.source.chapterIndex,
          'quote': event.source.quote,
          'scope': 'EXACT_WORDS_NOT_WORLD_TRUTH',
        });
      }
      // Replay alone exposes flags, not literary motivation. Add the exact
      // user-visible draft scene goal/conflict and selected choice intent.
      // They remain UNTRUSTED GAME FICTION, not original book prose.
      final enrichedTransitions = <Map<String, Object?>>[];
      for (final entry in entries) {
        final sceneId = entry['scene_id'];
        final choiceId = entry['choice_id'];
        final scene = sceneById[sceneId];
        if (scene == null) {
          throw const FormatException('Переход ссылается на чужую сцену.');
        }
        final matches = scene.decisions.where((c) => c.id == choiceId).toList();
        if (matches.length != 1) {
          throw const FormatException('Переход ссылается на чужое решение.');
        }
        enrichedTransitions.add({
          ...entry,
          'scene_goal_game_draft': scene.goal,
          'scene_conflict_game_draft': scene.conflict,
          'choice_intent_game_draft': matches.single.intent,
          'prose_is_literary_canon': false,
        });
      }
      final payload = <String, Object?>{
        'review_kind': 'POSSIBLE_LITERARY_CONTRADICTIONS_NOT_CANON',
        'window_number': position + 1,
        'source_quotes': quotes,
        'reachable_game_transitions': enrichedTransitions,
        'uncovered_book_events_total': evidence.uncoveredSourceEvents,
        'chapter_order_is_world_time': false,
        'npc_statements_are_world_truth': false,
        'missing_context': 'UNKNOWN',
        'game_mutation_allowed': false,
      };
      final bytes = jsonEncode(payload);
      if (utf8.encode(bytes).length > maxContextBytes ||
          entries.length > maxTransitionsPerWindow) {
        throw const FormatException('Слишком большой пакет литературного аудита.');
      }
      return LiteraryReviewWindow._(
        position: position,
        encoded: bytes,
        approvalDigest: sha256.convert(utf8.encode(jsonEncode({
          'format': format,
          'source_fingerprint': index.sourceFingerprint,
          'plan_sha256': evidence.planSha256,
          'evidence_sha256': evidence.approvalDigest,
          'model': LiteraryReviewWireContract.modelId,
          'max_attempts': LiteraryReviewWireContract.maxAttempts,
          'sent_context': payload,
        }))).toString(),
      );
    }

    for (final raw in rows) {
      final entry = Map<String, dynamic>.from(raw as Map);
      if (windowRows.isEmpty) {
        windowRows = [entry];
        makeWindow(windowRows, groups.length);
        continue;
      }
      try {
        makeWindow([...windowRows, entry], groups.length);
        windowRows = [...windowRows, entry];
      } on FormatException {
        groups.add(makeWindow(windowRows, groups.length));
        if (groups.length >= maxWindows) {
          throw const FormatException(
              'Не все переходы помещаются в ограниченный литературный аудит.');
        }
        windowRows = [entry];
        makeWindow(windowRows, groups.length);
      }
    }
    if (windowRows.isNotEmpty) {
      groups.add(makeWindow(windowRows, groups.length));
    }
    if (groups.isEmpty || groups.length > maxWindows ||
        groups.fold<int>(0, (sum, w) => sum + w.transitions.length) !=
            evidence.reachableTransitions) {
      throw const FormatException('Часть игровых переходов потеряна.');
    }
    final digest = sha256.convert(utf8.encode(jsonEncode({
      'format': format,
      'source_fingerprint': index.sourceFingerprint,
      'plan_sha256': evidence.planSha256,
      'evidence_sha256': evidence.approvalDigest,
      'model': LiteraryReviewWireContract.modelId,
      'new_requests_per_consent': maxNewRequestsPerRun,
      'max_attempts_each': LiteraryReviewWireContract.maxAttempts,
      'window_digests': [for (final w in groups) w.approvalDigest],
    }))).toString();
    return WholeStoryLiteraryReviewManifest._(
      index: index, book: book, plan: plan,
      evidence: evidence,
      claimEvidence: claimEvidence,
      approvalDigest: digest,
      maxNewRequestsPerRun: maxNewRequestsPerRun,
      windows: groups,
    );
  }

  void verifyUnchanged() {
    final current = fromEvidence(
      index: index, book: book, plan: plan, evidence: evidence,
      claimEvidence: claimEvidence,
      maxNewRequestsPerRun: maxNewRequestsPerRun,
    );
    if (current.approvalDigest != approvalDigest ||
        current.totalWindows != totalWindows) {
      throw const FormatException('Изменились исходные данные ИИ-аудита.');
    }
  }
}

class LiteraryReviewWindow {
  LiteraryReviewWindow._({
    required this.position,
    required this.approvalDigest,
    required String encoded,
  }) : _encoded = encoded;

  final int position;
  final String approvalDigest;
  final String _encoded;

  Map<String, dynamic> get sentContext =>
      Map<String, dynamic>.from(jsonDecode(_encoded) as Map);
  List<Map<String, dynamic>> get transitions => [
    for (final value in sentContext['reachable_game_transitions'] as List)
      Map<String, dynamic>.from(value as Map),
  ];
  List<Map<String, dynamic>> get sourceQuotes => [
    for (final value in sentContext['source_quotes'] as List)
      Map<String, dynamic>.from(value as Map),
  ];
  String get payloadJson => _encoded;
  String get exactUserMessage => jsonEncode({
    'window_digest': approvalDigest,
    'source_locked_context': sentContext,
  });
  bool get establishesCanon => false;
}

enum WholeLiteraryFindingKind {
  unsupportedFact, actorKnowledge, itemOwnership, promise,
  worldTime, causalLink, routeState, characterMotivation, other,
}

enum WholeLiteraryFindingSeverity { low, medium, high }
enum WholeLiteraryVerdict {
  possibleConsistency, needsRevision, insufficientEvidence,
}

class WholeLiteraryFinding {
  const WholeLiteraryFinding({
    required this.kind,
    required this.severity,
    required this.sceneId,
    required this.choiceId,
    required this.sourceEventId,
    required this.problem,
  });

  final WholeLiteraryFindingKind kind;
  final WholeLiteraryFindingSeverity severity;
  final String sceneId, choiceId, problem;
  final String? sourceEventId;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'severity': severity.name,
    'scene_id': sceneId,
    'choice_id': choiceId,
    'source_event_id': sourceEventId,
    'problem': problem,
  };
}

class WholeLiteraryReviewReport {
  WholeLiteraryReviewReport._({
    required this.windowDigest,
    required this.verdict,
    required this.findings,
    required this.uncertainty,
  });

  final String windowDigest;
  final WholeLiteraryVerdict verdict;
  final List<WholeLiteraryFinding> findings;
  final String uncertainty;
  bool get provesLiteraryCanon => false;
  bool get mayModifyBookWorld => false;
  bool get isVerifiedLiteraryTruth => false;

  Map<String, Object?> toJson() => {
    'window_digest': windowDigest,
    'verdict': verdict.name,
    'uncertainty': uncertainty,
    'findings': [for (final item in findings) item.toJson()],
    'status': 'UNVERIFIED_AI_REVIEW',
  };

  static T _choice<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) throw const FormatException();
    final matches = values.where((e) => e.name == value).toList();
    if (matches.length != 1) throw const FormatException();
    return matches.single;
  }

  static final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');
  static WholeLiteraryReviewReport fromJson(
      LiteraryReviewWindow window, Map<String, dynamic> value) {
    const keys = {'window_digest', 'verdict', 'uncertainty',
      'findings', 'status'};
    if (value.keys.toSet().length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['status'] != 'UNVERIFIED_AI_REVIEW' ||
        value['window_digest'] != window.approvalDigest ||
        value['uncertainty'] is! String ||
        value['findings'] is! List) {
      throw const FormatException('Ответ литературного ИИ относится к другому пакету.');
    }
    final uncertainty = value['uncertainty'] as String;
    if (uncertainty.trim() != uncertainty ||
        uncertainty.length < 12 || uncertainty.length > 500 ||
        _controls.hasMatch(uncertainty)) {
      throw const FormatException('Повреждена неопределённость ответа.');
    }
    final verdict = _choice(WholeLiteraryVerdict.values, value['verdict']);
    final raw = value['findings'] as List;
    if (raw.length > 8) {
      throw const FormatException('Слишком много литературных замечаний.');
    }
    final valid = <String, Set<String>>{};
    for (final transition in window.transitions) {
      final key = transition['scene_id'].toString() +
          '/' + transition['choice_id'].toString();
      final sources = <String>{};
      for (final field in ['scene_source_event_id',
          'choice_source_event_id']) {
        if (transition[field] is String) sources.add(transition[field] as String);
      }
      valid.putIfAbsent(key, () => <String>{}).addAll(sources);
    }
    final seen = <String>{};
    final findings = <WholeLiteraryFinding>[];
    for (final item in raw) {
      if (item is! Map) throw const FormatException();
      final record = Map<String, dynamic>.from(item);
      const fields = {'kind', 'severity', 'scene_id', 'choice_id',
        'source_event_id', 'problem'};
      if (record.keys.toSet().length != fields.length ||
          !record.keys.toSet().containsAll(fields) ||
          record['scene_id'] is! String ||
          record['choice_id'] is! String ||
          record['problem'] is! String) {
        throw const FormatException('Некорректная литературная ссылка.');
      }
      final key = (record['scene_id'] as String) + '/' +
          (record['choice_id'] as String);
      final source = record['source_event_id'];
      final problem = record['problem'] as String;
      if (!valid.containsKey(key) ||
          source != null && (source is! String ||
              !valid[key]!.contains(source)) ||
          !seen.add(key + '/' + record['kind'].toString() + '/' +
              (source ?? 'UNKNOWN').toString()) ||
          problem.trim() != problem || problem.length < 12 ||
          problem.length > 450 || _controls.hasMatch(problem)) {
        throw const FormatException('Несуществующий выбор или цитата ИИ.');
      }
      findings.add(WholeLiteraryFinding(
        kind: _choice(WholeLiteraryFindingKind.values, record['kind']),
        severity: _choice(
            WholeLiteraryFindingSeverity.values, record['severity']),
        sceneId: record['scene_id'] as String,
        choiceId: record['choice_id'] as String,
        sourceEventId: source as String?,
        problem: problem,
      ));
    }
    if (verdict == WholeLiteraryVerdict.possibleConsistency &&
        (window.sourceQuotes.isEmpty ||
         findings.any((f) => f.severity == WholeLiteraryFindingSeverity.high))) {
      throw const FormatException('Отсутствие замечаний не доказывает канон.');
    }
    return WholeLiteraryReviewReport._(
      windowDigest: window.approvalDigest,
      verdict: verdict,
      findings: List.unmodifiable(findings),
      uncertainty: uncertainty,
    );
  }
}

