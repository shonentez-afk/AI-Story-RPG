import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'source_semantic_provider.dart';
import 'zai_cross_window_evidence_graph.dart';

/// A cue for REVIEW, not a logical contradiction or an accepted statement.
/// Quotes may refer to different people, times, narrators or fictional claims.
class ZaiPossibleDiscrepancy {
  const ZaiPossibleDiscrepancy(this.first, this.second);

  final ZaiAnchoredFinding first;
  final ZaiAnchoredFinding second;

  bool get proven => false;
  String get reason =>
      'Похожая формулировка с наличием/отсутствием отрицания. '
      'Время, говорящий и контекст ещё не сопоставлены.';
}

/// Bounded, deterministic hints grounded in exact human-kept citations.
/// It never invents an assertion, entity, alias or chronology from a book.
class ZaiConsistencyHints {
  const ZaiConsistencyHints._();

  static const maxDiscrepancies = 120;

  static ({String text, bool negated})? _polarity(String raw) {
    final value = raw.toLowerCase().replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[.,!?;:«»"“”()—]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    final tokens = value.split(' ');
    if (tokens.length < 3 || tokens.length > 40) return null;
    final without = <String>[];
    var negations = 0;
    for (final word in tokens) {
      if (word == 'не' || word == 'not') {
        negations++;
      } else if (word.isNotEmpty) {
        without.add(word);
      }
    }
    // Double negation, other language particles and modal logic are NOT
    // interpreted. One explicit standalone negator is only a review cue.
    if (negations > 1 || without.length < 3) return null;
    return (text: without.join(' '), negated: negations == 1);
  }

  static List<ZaiPossibleDiscrepancy> reviewCues(
      ZaiCrossWindowEvidenceGraph graph) {
    final byWords = <String, List<({ZaiAnchoredFinding finding, bool negated})>>{};
    final output = <ZaiPossibleDiscrepancy>[];
    for (final finding in graph.statedFactsAndStates) {
      final item = _polarity(finding.quote);
      if (item == null) continue;
      final list = byWords.putIfAbsent(item.text, () => []);
      for (final previous in list) {
        if (previous.negated == item.negated ||
            previous.finding.id == finding.id) continue;
        output.add(ZaiPossibleDiscrepancy(previous.finding, finding));
        if (output.length >= maxDiscrepancies) {
          return List.unmodifiable(output);
        }
      }
      list.add((finding: finding, negated: item.negated));
    }
    return List.unmodifiable(output);
  }
}

/// Manual source-backed questions; NEVER verified facts, identity, or time.
enum ZaiConsistencyKind {
  possibleAlias,
  possibleDiscrepancy,
  possibleRelationship,
  possibleBefore,
}

class ZaiConsistencyQuestion {
  const ZaiConsistencyQuestion({
    required this.id,
    required this.kind,
    required this.firstId,
    required this.secondId,
    required this.reason,
  });

  final String id;
  final ZaiConsistencyKind kind;
  final String firstId;
  final String secondId;

  /// Untrusted user-written explanation, not proof of a story relationship.
  final String reason;

  bool get proven => false;
  bool get canPublishBookworld => false;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'first_id': firstId,
    'second_id': secondId,
    'reason': reason,
    'status': 'OPEN_EDITORIAL_QUESTION',
  };
}

/// Independent private M2f3c notebook, never changes M2f3a/b file formats.
/// Each pair needs two STILL-retained exact book citations. A saved question
/// becomes invalid if the reader rechecks a window or revokes either mark.
class ZaiEditorialConsistencyNotebook {
  ZaiEditorialConsistencyNotebook._(
      this.graph, List<ZaiConsistencyQuestion> questions)
      : questions = List.unmodifiable(questions);

  static const format = 'ai_story_zai_consistency_m2f3c_v1';
  static const maxQuestions = 600;
  static const maxBytes = 512 * 1024;
  static final _forbidden = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  final ZaiCrossWindowEvidenceGraph graph;
  final List<ZaiConsistencyQuestion> questions;

  factory ZaiEditorialConsistencyNotebook.empty(
          ZaiCrossWindowEvidenceGraph graph) =>
      ZaiEditorialConsistencyNotebook._(graph, const []);

  bool get canPublishBookworld => false;
  bool get establishesAliases => false;
  bool get establishesChronology => false;
  bool get establishesContradictions => false;

  static String _sha(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  static bool _symmetric(ZaiConsistencyKind kind) =>
      kind != ZaiConsistencyKind.possibleBefore;

  static String _key(String fingerprint, ZaiConsistencyKind kind,
      String a, String b) {
    final first = _symmetric(kind) && a.compareTo(b) > 0 ? b : a;
    final second = _symmetric(kind) && a.compareTo(b) > 0 ? a : b;
    return _sha('$fingerprint|${kind.name}|$first|$second')
        .substring(0, 32);
  }

  static String _norm(String label) =>
      label.trim().toLowerCase().replaceAll('ё', 'е')
          .replaceAll(RegExp(r'\s+'), ' ');

  Map<String, ZaiAnchoredFinding> get _findings => {
    for (final source in graph.reviewed) source.id: source,
  };

  void _verify(ZaiConsistencyQuestion item) {
    if (item.firstId == item.secondId ||
        item.id != _key(graph.index.sourceFingerprint, item.kind,
            item.firstId, item.secondId) ||
        item.reason != item.reason.trim() ||
        item.reason.length < 8 || item.reason.length > 240 ||
        _forbidden.hasMatch(item.reason)) {
      throw const FormatException('Неверная или неподтверждённая гипотеза');
    }
    final source = _findings;
    final first = source[item.firstId];
    final second = source[item.secondId];
    if (first == null || second == null) {
      throw const FormatException('Ссылка на удалённую или отклонённую цитату');
    }
    switch (item.kind) {
      case ZaiConsistencyKind.possibleAlias:
        if ((first.category != SemanticCategory.character &&
                first.category != SemanticCategory.location) ||
            first.category != second.category ||
            _norm(first.label) == _norm(second.label)) {
          throw const FormatException('Для алиаса нужны два разных имени одного типа');
        }
      case ZaiConsistencyKind.possibleDiscrepancy:
        if ((first.category != SemanticCategory.fact &&
             first.category != SemanticCategory.state) ||
            (second.category != SemanticCategory.fact &&
             second.category != SemanticCategory.state)) {
          throw const FormatException('Противоречия проверяются по фактам и состояниям');
        }
      case ZaiConsistencyKind.possibleRelationship:
        if (first.category != SemanticCategory.character ||
            second.category != SemanticCategory.character ||
            _norm(first.label) == _norm(second.label)) {
          throw const FormatException('Для отношения нужны два разных имени героев');
        }
      case ZaiConsistencyKind.possibleBefore:
        if (first.category != SemanticCategory.event ||
            second.category != SemanticCategory.event) {
          throw const FormatException('Порядок проверяется только для событий');
        }
    }
  }

  /// A cycle in proposed chronological order is internally inconsistent,
  /// even when every edge itself is explicitly marked as merely tentative.
  static void _verifyAcyclic(List<ZaiConsistencyQuestion> values) {
    final next = <String, List<String>>{};
    for (final item in values) {
      if (item.kind != ZaiConsistencyKind.possibleBefore) continue;
      final queue = <String>[item.secondId];
      final seen = <String>{};
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        if (current == item.firstId) {
          throw const FormatException('Обнаружен цикл в предполагаемой хронологии');
        }
        if (seen.add(current)) {
          queue.addAll(next[current] ?? const []);
        }
      }
      next.putIfAbsent(item.firstId, () => []).add(item.secondId);
    }
  }

  ZaiEditorialConsistencyNotebook propose(ZaiConsistencyKind kind,
      String firstId, String secondId, String reason) {
    final note = reason.trim();
    final question = ZaiConsistencyQuestion(
      id: _key(graph.index.sourceFingerprint, kind, firstId, secondId),
      kind: kind,
      firstId: firstId,
      secondId: secondId,
      reason: note,
    );
    _verify(question);
    if (questions.any((saved) => saved.id == question.id)) return this;
    if (questions.length >= maxQuestions) {
      throw const FormatException('Превышен предел редакторских вопросов');
    }
    final added = [...questions, question];
    _verifyAcyclic(added);
    return ZaiEditorialConsistencyNotebook._(graph, added);
  }

  ZaiEditorialConsistencyNotebook remove(String id) {
    if (!questions.any((item) => item.id == id)) {
      throw const FormatException('Редакторский вопрос не найден');
    }
    return ZaiEditorialConsistencyNotebook._(
        graph, questions.where((item) => item.id != id).toList());
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': graph.index.sourceFingerprint,
    'scope': 'PRIVATE_EDITORIAL_QUESTIONS_ONLY',
    'can_publish_bookworld': false,
    'questions': [for (final question in questions) question.toJson()],
  };

  String encode() {
    if (questions.length > maxQuestions ||
        questions.map((item) => item.id).toSet().length != questions.length) {
      throw const FormatException('Повтор или избыток редакторских вопросов');
    }
    for (final question in questions) {
      _verify(question);
    }
    _verifyAcyclic(questions);
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой файл редакторских вопросов');
    }
    return raw;
  }

  static ZaiEditorialConsistencyNotebook decode(
      ZaiCrossWindowEvidenceGraph graph, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой файл редакторских вопросов');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (root.length != 3 ||
          root.keys.toSet().difference({'format','payload','sha256'}).isNotEmpty ||
          root['format'] != format) {
        throw const FormatException('Неизвестный формат редакторских вопросов');
      }
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      if (payload.length != 4 ||
          payload.keys.toSet().difference({'source_fingerprint','scope',
            'can_publish_bookworld','questions'}).isNotEmpty ||
          payload['source_fingerprint'] != graph.index.sourceFingerprint ||
          payload['scope'] != 'PRIVATE_EDITORIAL_QUESTIONS_ONLY' ||
          payload['can_publish_bookworld'] != false ||
          root['sha256'] != _sha(jsonEncode(payload))) {
        throw const FormatException('Редакторские вопросы повреждены либо другая книга');
      }
      final saved = payload['questions'] as List<dynamic>;
      if (saved.length > maxQuestions) {
        throw const FormatException('Превышен предел вопросов');
      }
      final questions = <ZaiConsistencyQuestion>[];
      for (final rawItem in saved) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        if (item.length != 6 ||
            item.keys.toSet().difference({'id','kind','first_id',
              'second_id','reason','status'}).isNotEmpty ||
            item['status'] != 'OPEN_EDITORIAL_QUESTION') {
          throw const FormatException('Неизвестный статус редакторского вопроса');
        }
        questions.add(ZaiConsistencyQuestion(
          id: item['id'] as String,
          kind: ZaiConsistencyKind.values.byName(item['kind'] as String),
          firstId: item['first_id'] as String,
          secondId: item['second_id'] as String,
          reason: item['reason'] as String,
        ));
      }
      final restored = ZaiEditorialConsistencyNotebook._(graph, questions);
      if (restored.encode() != raw) {
        throw const FormatException('Неверный или неканонический checkpoint');
      }
      return restored;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Невозможно восстановить редакторские вопросы');
    }
  }
}
