import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart' show canonicalJson;

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'cross_act_consequence_gate.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'story_plan_causal_audit.dart';
import 'story_plan_dilemma_generator.dart';

String unifiedStoryHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

void _fields(Map<String, dynamic> value, Set<String> allowed) {
  if (value.length != allowed.length || !value.keys.toSet().containsAll(allowed)) {
    throw const FormatException('Неизвестные или отсутствующие поля общего сюжета.');
  }
}

String _russian(Object? value, {int min = 12, int max = 600}) {
  if (value is! String || value.trim() != value || value.length < min ||
      value.length > max || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
      !RegExp(r'[А-Яа-яЁё]').hasMatch(value)) {
    throw const FormatException('Нужен содержательный русский текст общего сюжета.');
  }
  return value;
}

/// Exact scope for ONE shared story proposal. Every detected event and every
/// mapped act is shown; no sampling silently turns a partial scan into a book.
/// Includes only reviewed character names/IDs and cited mentions, not secrets.
class UnifiedBookStoryContext {
  UnifiedBookStoryContext._(this.index, this.book, this.bookMap, this.roles,
      this.shownText, this.sourceBinding, this.approvalDigest);

  static const format = 'ai_story_unified_book_context_v1';
  static const maxRequestBytes = 160 * 1024;
  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final List<ReviewedHeroRole> roles;
  final String shownText, sourceBinding, approvalDigest;
  int get actCount => bookMap.acts.length;
  int get eventCount => book.events.length;
  Map<String, dynamic> get shownData => jsonDecode(shownText) as Map<String, dynamic>;
  String get storageKey => unifiedStoryHash({'scope': format, 'binding': sourceBinding});

  factory UnifiedBookStoryContext.create({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    List<ReviewedHeroRole> roles = const [],
  }) {
    if (!book.analysisComplete || index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title || index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 || bookMap.hasSourceGaps ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        bookMap.acts.length < 2 || bookMap.acts.length > BookwideStoryPlanComposer.maxDraftActs ||
        bookMap.acts.any((act) => act.events.length < 2) || roles.length > 15) {
      throw const FormatException('Общий сюжет требует полной карты из 2–12 актов '
          'без пропущенных глав; в каждой части нужны минимум два события.');
    }
    final flattened = [for (final act in bookMap.acts) ...act.events];
    if (flattened.length != book.events.length ||
        flattened.map((e) => e.id).toSet().length != flattened.length) {
      throw const FormatException('Карта книги потеряла или повторила события.');
    }
    for (var i = 0; i < flattened.length; i++) {
      final mapped = flattened[i], original = book.events[i];
      mapped.source.validate(index); original.source.validate(index);
      if (mapped.id != original.id || mapped.source.quote != original.source.quote ||
          mapped.source.chunkId != original.source.chunkId ||
          mapped.source.startUtf16 != original.source.startUtf16 ||
          mapped.source.endUtf16 != original.source.endUtf16) {
        throw const FormatException('Карта и исходная редакция книги не совпали.');
      }
    }
    final sortedRoles = [...roles]..sort((a, b) => a.characterId.compareTo(b.characterId));
    if (sortedRoles.map((r) => r.characterId).toSet().length != sortedRoles.length) {
      throw const FormatException('Повторная личность в общем сюжете.');
    }
    final cast = <Map<String, dynamic>>[];
    for (final role in sortedRoles) {
      if (role.sourceFingerprint != book.sourceFingerprint || role.confirmedMentions.isEmpty) {
        throw const FormatException('Карточка персонажа относится к другой книге.');
      }
      for (final mention in role.confirmedMentions) { mention.validate(index); }
      final events = [for (final event in book.events)
        if (role.confirmedMentions.any((m) => m.status == EvidenceStatus.confirmed &&
            m.kind == EvidenceKind.character && m.chunkId == event.source.chunkId &&
            m.startUtf16 < event.source.endUtf16 && event.source.startUtf16 < m.endUtf16)) event.id];
      if (events.isEmpty) continue; // Explicitly unrepresented profile is not sent.
      cast.add({'character_id': role.characterId, 'display_name': role.displayName,
        'source_event_ids': events});
    }
    final shown = canonicalJson({
      'format': format,
      'scope': 'ALL_DETECTED_EVENTS_NOT_FULL_ORIGINAL_TEXT',
      'plot_mode': 'PRIVATE_ALTER_FATE_PROPOSAL',
      'literary_canon_verified': false,
      'source_order_is_world_chronology': false,
      'actors': cast,
      'acts': [for (final act in bookMap.acts) {
        'act_id': act.id, 'source_chapter': act.chapterIndex,
        'events': [for (final event in act.events) {
          'event_id': event.id, 'position': event.narrativePosition,
          'quote': event.source.quote,
        }],
      }],
    });
    if (utf8.encode(shown).length > maxRequestBytes) {
      throw const FormatException('Общий контекст превышает безопасный размер. '
          'События не были молча отброшены.');
    }
    final binding = unifiedStoryHash({
      'source': book.sourceFingerprint, 'shown': shown,
      'roles': [for (final r in sortedRoles) {
        'id': r.characterId, 'group': r.groupDigest, 'name': r.displayName,
        'mentions': [for (final m in r.confirmedMentions) {
          'id': m.id, 'status': m.status.name, 'chunk': m.chunkId,
          'start': m.startUtf16, 'end': m.endUtf16,
        }],
      }],
    });
    return UnifiedBookStoryContext._(index, book, bookMap, List.unmodifiable(sortedRoles),
      shown, binding, unifiedStoryHash({'binding': binding, 'shown': shown}));
  }

  void verifyCurrent(List<ReviewedHeroRole> freshRoles) {
    final fresh = UnifiedBookStoryContext.create(
        index: index, book: book, bookMap: bookMap, roles: freshRoles);
    if (fresh.approvalDigest != approvalDigest) {
      throw const FormatException('Книга или карточки изменились после согласования общего сюжета.');
    }
  }
}

class UnifiedStoryMotivation {
  UnifiedStoryMotivation._(this.characterId, this.goal, this.reason, List<String> events)
      : sourceEventIds = List.unmodifiable(events);
  final String characterId, goal, reason;
  final List<String> sourceEventIds;
}

class UnifiedStoryAct {
  const UnifiedStoryAct._(this.actId, this.purpose, this.proposal);
  final String actId, purpose;
  final StoryDilemmaProposal proposal;
}

class UnifiedStoryLink {
  const UnifiedStoryLink._(this.fromActId, this.toActId, this.outcome, this.reason);
  final String fromActId, toActId, reason;
  final CrossActPriorOutcome outcome;
}

/// A model result is an inert narrative draft. Only accept() constructs real
/// cross-act restrictions, using the EXISTING audited consequence gate.
class UnifiedBookStoryDraft {
  UnifiedBookStoryDraft._({required this.contextDigest, required this.responseJson,
    required this.applicable, required this.reason, required this.goal,
    required this.conflict, required List<UnifiedStoryAct> acts,
    required List<UnifiedStoryMotivation> motivations,
    required List<UnifiedStoryLink> links})
      : acts = List.unmodifiable(acts), motivations = List.unmodifiable(motivations),
        links = List.unmodifiable(links),
        reviewDigest = unifiedStoryHash({'context': contextDigest, 'answer': responseJson});

  static const maxAnswerBytes = 56 * 1024;
  final String contextDigest, responseJson, reviewDigest, reason, goal, conflict;
  final bool applicable;
  final List<UnifiedStoryAct> acts;
  final List<UnifiedStoryMotivation> motivations;
  final List<UnifiedStoryLink> links;
  bool get isCanon => false;
  bool get canInstallDirectly => false;

  factory UnifiedBookStoryDraft.parse(UnifiedBookStoryContext context, String raw) {
    if (utf8.encode(raw).length > maxAnswerBytes) {
      throw const FormatException('Ответ общего сценария слишком большой.');
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['applicable'] == false) {
        _fields(map, {'applicable', 'reason'});
        return UnifiedBookStoryDraft._(contextDigest: context.approvalDigest,
          responseJson: canonicalJson(map), applicable: false,
          reason: _russian(map['reason']), goal: '', conflict: '',
          acts: const [], motivations: const [], links: const []);
      }
      _fields(map, {'applicable', 'campaign_goal', 'central_conflict', 'motivations', 'acts', 'links'});
      if (map['applicable'] != true) throw const FormatException();
      final goal = _russian(map['campaign_goal'], max: 360);
      final conflict = _russian(map['central_conflict']);
      final allowedActors = {for (final row in context.shownData['actors'] as List)
        row['character_id'] as String: (row['source_event_ids'] as List).cast<String>().toSet()};
      final usedActors = <String>{};
      final motivations = <UnifiedStoryMotivation>[];
      for (final rawMotive in map['motivations'] as List) {
        final motive = rawMotive as Map<String, dynamic>;
        _fields(motive, {'character_id', 'goal', 'reason', 'source_event_ids'});
        final id = motive['character_id'] as String;
        final events = (motive['source_event_ids'] as List).cast<String>();
        if (!allowedActors.containsKey(id) || !usedActors.add(id) || events.isEmpty ||
            events.length > 4 || events.toSet().length != events.length ||
            !allowedActors[id]!.containsAll(events)) throw const FormatException();
        motivations.add(UnifiedStoryMotivation._(id,
          _russian(motive['goal'], max: 360), _russian(motive['reason']), events));
      }
      if (usedActors.length != allowedActors.length) {
        throw const FormatException('В общем сюжете пропущена показанная карточка NPC.');
      }
      final rows = map['acts'] as List;
      if (rows.length != context.actCount) {
        throw const FormatException('Общий сценарий потерял части книги.');
      }
      final acts = <UnifiedStoryAct>[];
      const proposalKeys = {'setup_event_id', 'outcome_event_id', 'kind', 'dilemma',
        'accept_intent', 'refuse_intent', 'followup_goal', 'finish_original_intent',
        'original_ending', 'alternative_search_goal', 'search_intent',
        'alternative_discovery', 'use_discovery_intent', 'alternative_ending'};
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] as Map<String, dynamic>, sourceAct = context.bookMap.acts[i];
        _fields(row, {'act_id', 'purpose', 'proposal'});
        if (row['act_id'] != sourceAct.id) throw const FormatException('Переставлены части книги.');
        final proposal = row['proposal'] as Map<String, dynamic>;
        _fields(proposal, proposalKeys);
        final eventIds = sourceAct.events.map((e) => e.id).toSet();
        if (!eventIds.contains(proposal['setup_event_id']) ||
            !eventIds.contains(proposal['outcome_event_id'])) throw const FormatException();
        for (final key in proposalKeys.difference({'setup_event_id', 'outcome_event_id', 'kind'})) {
          _russian(proposal[key], min: 8, max: 360);
        }
        final parsed = StoryDilemmaProposal.decode(canonicalJson({
          'format': StoryDilemmaProposal.format, 'status': 'UNREVIEWED_PROPOSAL',
          'source_fingerprint': context.book.sourceFingerprint, ...proposal,
        }));
        // Reconstruct typed rules rather than accepting model-supplied effects.
        StoryPlanDilemmaGenerator.propose(context.book, parsed);
        acts.add(UnifiedStoryAct._(sourceAct.id, _russian(row['purpose']), parsed));
      }
      final linkRows = map['links'] as List;
      if (linkRows.length != acts.length - 1) {
        throw const FormatException('Каждой поздней части нужна явная связь с предыдущими событиями.');
      }
      final order = {for (var i = 0; i < acts.length; i++) acts[i].actId: i};
      final reached = <String>{acts.first.actId};
      final links = <UnifiedStoryLink>[];
      // Exactly one forward dependency for every later act. The model cannot
      // constrain both initial choices; the refusal route is left available.
      for (var i = 1; i < acts.length; i++) {
        final row = linkRows[i - 1] as Map<String, dynamic>;
        _fields(row, {'from_act_id', 'to_act_id', 'required_outcome', 'reason'});
        final from = row['from_act_id'] as String, to = row['to_act_id'] as String;
        if (to != acts[i].actId || !reached.contains(from) || order[from]! >= i) {
          throw const FormatException('Циклическая или обратная сюжетная связь.');
        }
        final outcome = switch (row['required_outcome']) {
          'original' => CrossActPriorOutcome.original,
          'alternative' => CrossActPriorOutcome.alternative,
          _ => throw const FormatException('Неизвестное последствие сюжета.'),
        };
        links.add(UnifiedStoryLink._(from, to, outcome, _russian(row['reason'], min: 20, max: 400)));
        reached.add(to);
      }
      // The entire base plan must already meet existing formal contracts.
      BookwideStoryPlanComposer.compose(index: context.index, book: context.book,
          bookMap: context.bookMap, actProposals: acts.map((a) => a.proposal).toList());
      return UnifiedBookStoryDraft._(contextDigest: context.approvalDigest,
        responseJson: canonicalJson(map), applicable: true, reason: '', goal: goal,
        conflict: conflict, acts: acts, motivations: motivations, links: links);
    } on FormatException { rethrow; }
    catch (_) { throw const FormatException('Общий сюжет не прошёл проверку источников и полей.'); }
  }

  MultiActStoryPlanDraft accept({
    required UnifiedBookStoryContext context,
    required List<ReviewedHeroRole> freshRoles,
    required String approvedReviewDigest,
    required bool allShownQuotesAndStoryReviewed,
    required bool fictionalConsequencesConfirmed,
  }) {
    if (!applicable || !allShownQuotesAndStoryReviewed || !fictionalConsequencesConfirmed ||
        context.approvalDigest != contextDigest || approvedReviewDigest != reviewDigest) {
      throw const FormatException('Общий сюжет и его игровые последствия не подтверждены.');
    }
    context.verifyCurrent(freshRoles);
    // Reparse immutable bytes at the acceptance boundary; never accept a
    // separately constructed list of changed links or imported approval bits.
    final checked = UnifiedBookStoryDraft.parse(context, responseJson);
    final base = BookwideStoryPlanComposer.compose(index: context.index, book: context.book,
      bookMap: context.bookMap, actProposals: checked.acts.map((a) => a.proposal).toList());
    final partOrder = {for (var i = 0; i < base.parts.length; i++) base.parts[i].actId: i};
    final continuity = CrossActConsequenceGate.apply(index: context.index, book: context.book,
      bookMap: context.bookMap, draft: base, rules: [for (var i = 0; i < checked.links.length; i++)
        CrossActConsequenceRule(id: 'unified_story_link_${i + 1}',
          earlierActId: checked.links[i].fromActId, laterActId: checked.links[i].toActId,
          earlierSourceEventId: base.parts[partOrder[checked.links[i].fromActId]!].outcomeEventId,
          laterSourceEventId: base.parts[partOrder[checked.links[i].toActId]!].setupEventId,
          laterDecisionId: 'act_${partOrder[checked.links[i].toActId]! + 1}_accept_offer',
          priorOutcome: checked.links[i].outcome,
          mode: CrossActRuleMode.requiresPriorOutcome,
          reviewedAsGameFiction: true, privateReviewReason: checked.links[i].reason),
      ]);
    if (!continuity.hasEnforcedContinuity) {
      throw const FormatException('Сюжетные связи не меняют реальное прохождение.');
    }
    return _ReviewedUnifiedDraft(base, continuity);
  }
}

/// A view of the existing independently checked plan after its approved
/// cross-act gate. This is NOT a new compiler, model-selected runtime, or a
/// second save format. The ordinary hero/items/NPC editor consumes this type.
class _ReviewedUnifiedDraft implements MultiActStoryPlanDraft {
  _ReviewedUnifiedDraft(this.base, this.continuity);
  final MultiActStoryPlanDraft base;
  final CrossActContinuityDraft continuity;
  @override StoryPlan get plan => continuity.plan;
  @override bool get expanded => base.expanded;
  @override StoryCausalContract get causalContract => base.causalContract;
  @override StoryCausalAudit get formalAudit => continuity.audit;
  @override BookwideStoryCoverage get coverage => continuity.coverage;
  @override List<MultiActDilemmaPart> get parts => base.parts;
  @override List<MultiActFictionalBridge> get fictionalBridges => base.fictionalBridges;
  @override List<String> get blockers => base.blockers;
  @override bool get hasFormalCounterexamples => formalAudit.counterexamples.isNotEmpty;
  @override bool get formalRulesPassed => base.formalRulesPassed && continuity.hasEnforcedContinuity;
  @override bool get hasConfirmedLiteraryMeaning => false;
  @override bool get hasConfirmedWorldChronology => false;
  @override bool get hasConfirmedActorKnowledge => false;
  @override bool get hasSourceProvenCausalBridges => false;
  @override bool get isReadyToInstall => false;
  @override bool get isFullBookRpg => false;
  @override bool get canPublish => false;
  @override Map<String, Object> toDiagnosticJson() => {
    ...base.toDiagnosticJson(), 'enforced_story_links': continuity.impacts.length,
    'rules_affect_available_choices': continuity.hasEnforcedContinuity,
  };
}
