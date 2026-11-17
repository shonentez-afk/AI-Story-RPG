import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'story_plan.dart';
import 'whole_plan_gameplay_manifest.dart';
import 'source_locked_gameplay_candidates.dart';

/// A reproducible contradiction on one reachable route (NOT book canon).
class GameplayRouteIssue {
  const GameplayRouteIssue(this.code, this.sceneId, this.choiceId,
      this.resourceId, this.pathChoiceIds);

  final String code, sceneId, choiceId, resourceId;
  final List<String> pathChoiceIds;
}

class GameplayReachabilityReport {
  const GameplayReachabilityReport({
    required this.visitedStates,
    required this.reachedEndingIds,
    required this.checkedCandidateOperations,
    required this.issues,
  });

  final int visitedStates, checkedCandidateOperations;
  final Set<String> reachedEndingIds;
  final List<GameplayRouteIssue> issues;
  bool get hasNoRouteConflicts => issues.isEmpty;
  bool get verifiesLiteraryOwnership => false;
  bool get verifiesLiteraryCanon => false;
  bool get mayAutomaticallyChangeBookworld => false;
}

class _Node {
  const _Node(this.sceneId, this.flags, this.items, this.facts, this.path);
  final String sceneId;
  final Set<String> flags, items, facts;
  final List<String> path;
  String get key => jsonEncode([
    sceneId,
    flags.toList()..sort(), items.toList()..sort(), facts.toList()..sort(),
  ]);
}

/// Exhaustive simulation of UNTRUSTED candidate operations across game
/// flags and branches. It NEVER accepts candidates into BookWorld, performs
/// no model call and makes no persistent changes.
class GameplayCandidateReachabilityAuditor {
  const GameplayCandidateReachabilityAuditor();
  static const maxStates = 2500;
  static const maxIssues = 32;
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  GameplayReachabilityReport audit({
    required StoryPlan plan,
    required SourceLockedGameplayContext context,
    required GameplayCandidateDraft draft,
  }) {
    final perChoice = <String, List<GameplayCandidate>>{};
    final entityNames = <String, (String, String)>{};
    final operationIds = <String>{};
    final collected = <GameplayCandidate>[];
    _collect(
      plan, context, draft,
      perChoice, entityNames, operationIds, collected,
    );
    return _auditRoutes(plan, perChoice, collected);
  }

  /// Evaluate effects TOGETHER across ALL consented source batches.
  ///
  /// One batch may spend an item legitimately acquired by a choice from an
  /// earlier batch. A per-batch graph cannot prove or refute ownership;
  /// only this joint route analysis has the complete state transitions.
  ///
  /// This stage does NOT verify source meaning or grant model authority.
  GameplayReachabilityReport auditAcrossBatches({
    required StoryPlan plan,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> drafts,
  }) {
    manifest.verifyUnchanged();
    if (manifest.plan.encode() != plan.encode() ||
        manifest.index.sourceFingerprint != plan.sourceFingerprint ||
        drafts.isEmpty ||
        drafts.length != manifest.contexts.length) {
      throw const FormatException(
          'Нужны ВСЕ завершённые пакеты той же редакции и плана.');
    }
    final perChoice = <String, List<GameplayCandidate>>{};
    final entityNames = <String, (String, String)>{};
    final operationIds = <String>{};
    final collected = <GameplayCandidate>[];
    final usedEventIds = <String>{};
    for (var n = 0; n < drafts.length; n++) {
      final context = manifest.contexts[n];
      for (final event in context.excerpts) {
        if (!usedEventIds.add(event.id)) {
          throw const FormatException(
              'Один исходный фрагмент продублирован в нескольких пакетах.');
        }
      }
      _collect(plan, context, drafts[n], perChoice,
          entityNames, operationIds, collected);
    }
    return _auditRoutes(plan, perChoice, collected);
  }

  void _collect(
    StoryPlan plan,
    SourceLockedGameplayContext context,
    GameplayCandidateDraft draft,
    Map<String, List<GameplayCandidate>> perChoice,
    Map<String, (String, String)> entityNames,
    Set<String> operationIds,
    List<GameplayCandidate> collected,
  ) {
    final expectedPlanDigest =
        sha256.convert(utf8.encode(plan.encode())).toString();
    if (context.planSha256 != expectedPlanDigest ||
        context.sourceFingerprint != plan.sourceFingerprint ||
        draft.sourceFingerprint != context.sourceFingerprint ||
        draft.approvalDigest != context.approvalDigest ||
        draft.candidates.length > SourceLockedGameplayContext.maxProposals) {
      throw const FormatException(
          'Предложения относятся к другой книге, плану или согласию.');
    }
    final scenes = {for (final s in plan.situations) s.id: s};
    final anchors = {
      for (final a in context.choices) a.sceneId + '/' + a.choiceId: a,
    };
    final quotes = {
      for (final e in context.excerpts) e.id: e.source.quote.toLowerCase(),
    };
    for (final c in draft.candidates) {
      final anchor = anchors[c.sceneId + '/' + c.choiceId];
      if (anchor == null ||
          anchor.sourceEventId != c.sourceEventId ||
          scenes[c.sceneId] == null ||
          !scenes[c.sceneId]!.decisions.any((d) => d.id == c.choiceId) ||
          !_id.hasMatch(c.id) ||
          c.label.trim() != c.label ||
          c.label.length < 2 || c.label.length > 120 ||
          c.uncertainty.trim().length < 10 ||
          c.uncertainty.length > 350 ||
          !(c.kind == 'item' &&
              (c.op == 'grant_item' || c.op == 'consume_item') ||
            c.kind == 'fact' && c.op == 'learn_fact') ||
          !quotes.containsKey(c.sourceEventId) ||
          c.kind == 'item' &&
              !quotes[c.sourceEventId]!.contains(c.label.toLowerCase())) {
        throw const FormatException(
            'Предложенный предмет или знание не привязаны к цитате и выбору.');
      }
      final old = entityNames[c.id];
      if (old != null && (old.$1 != c.kind || old.$2 != c.label)) {
        throw const FormatException(
            'Один ID связывает разные предметы или знания.');
      }
      entityNames[c.id] = (c.kind, c.label);
      final signature = c.sceneId + '/' + c.choiceId + '/' +
          c.op + '/' + c.id;
      if (!operationIds.add(signature)) {
        throw const FormatException('Повтор одного и того же эффекта.');
      }
      perChoice.putIfAbsent(c.sceneId + '/' + c.choiceId, () => []).add(c);
    }

    collected.addAll(draft.candidates);
  }

  GameplayReachabilityReport _auditRoutes(
    StoryPlan plan,
    Map<String, List<GameplayCandidate>> perChoice,
    List<GameplayCandidate> candidates,
  ) {
    final scenes = {for (final s in plan.situations) s.id: s};
    final queue = <_Node>[
      _Node(plan.entrySituationId, {...plan.initialFlags},
          <String>{}, <String>{}, const <String>[]),
    ];
    final seen = <String>{};
    final terminals = <String>{};
    final reachedOperations = <String>{};
    final issues = <GameplayRouteIssue>[];
    final issueKeys = <String>{};
    void report(String code, _Node node, String choiceId,
        String itemId, List<String> path) {
      final key = code + '/' + node.sceneId + '/' + choiceId + '/' + itemId;
      if (!issueKeys.add(key) || issues.length == maxIssues) return;
      issues.add(GameplayRouteIssue(code, node.sceneId, choiceId,
          itemId, List.unmodifiable(path)));
    }

    for (var n = 0; n < queue.length; n++) {
      if (queue.length > maxStates) {
        throw const FormatException('Слишком много состояний игры.');
      }
      final node = queue[n];
      if (!seen.add(node.key)) continue;
      final scene = scenes[node.sceneId];
      if (scene == null) throw const FormatException('Чужая сцена.');
      if (scene.terminal) {
        terminals.add(scene.id);
        continue;
      }
      var available = 0;
      for (final choice in scene.decisions) {
        if (!node.flags.containsAll(choice.requires) ||
            choice.forbids.any(node.flags.contains)) continue;
        available++;
        final path = List<String>.unmodifiable(
            [...node.path, choice.id]);
        final items = {...node.items};
        final facts = {...node.facts};
        final ops = perChoice[node.sceneId + '/' + choice.id] ?? const <GameplayCandidate>[];
        final byItem = <String, Set<String>>{};
        for (final c in ops) {
          if (c.kind == 'item') {
            byItem.putIfAbsent(c.id, () => <String>{}).add(c.op);
          }
        }
        for (final entry in byItem.entries) {
          if (entry.value.length > 1) {
            report('AMBIGUOUS_SAME_CHOICE',
                node, choice.id, entry.key, path);
          }
        }
        for (final effect in ops) {
          reachedOperations.add(
              node.sceneId + '/' + choice.id + '/' +
              effect.op + '/' + effect.id);
          if (effect.op == 'grant_item') {
            if (!items.add(effect.id)) {
              report('GRANT_WHILE_OWNED',
                  node, choice.id, effect.id, path);
            }
          } else if (effect.op == 'consume_item') {
            if (!items.remove(effect.id)) {
              report('CONSUME_UNOWNED',
                  node, choice.id, effect.id, path);
            }
          } else if (effect.op == 'learn_fact') {
            facts.add(effect.id);
          }
        }
        final flags = {...node.flags, ...choice.adds}
          ..removeAll(choice.removes);
        queue.add(_Node(choice.nextSituationId, flags,
            items, facts, path));
      }
      if (available == 0) {
        report('NO_AVAILABLE_CHOICE',
            node, '', '', node.path);
      }
    }
    for (final c in candidates) {
      final signature = c.sceneId + '/' + c.choiceId + '/' +
          c.op + '/' + c.id;
      if (!reachedOperations.contains(signature)) {
        report('UNREACHABLE_EFFECT',
            _Node(c.sceneId, const <String>{},
                const <String>{}, const <String>{}, const <String>[]),
            c.choiceId, c.id, const <String>[]);
      }
    }
    if (terminals.length < 2) {
      report('ENDINGS_NOT_REACHABLE',
          _Node(plan.entrySituationId, const <String>{},
              const <String>{}, const <String>{}, const <String>[]),
          '', '', const <String>[]);
    }
    return GameplayReachabilityReport(
      visitedStates: seen.length,
      reachedEndingIds: Set.unmodifiable(terminals),
      checkedCandidateOperations: reachedOperations.length,
      issues: List.unmodifiable(issues),
    );
  }
}
