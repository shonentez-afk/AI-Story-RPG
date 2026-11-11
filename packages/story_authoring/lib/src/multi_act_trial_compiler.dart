import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_campaign_contract.dart';
import 'bookwide_storyplan_composer.dart';
import 'rpg_creation_contract.dart';
import 'multi_act_trial_plan_composer.dart';
import 'branch_continuity_auditor.dart';
import 'compiled_campaign_causal_gate.dart';
import 'source_world_time_auditor.dart';
import 'source_bound_bridge_auditor.dart';
import 'cross_act_consequence_gate.dart';
import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'narrative_book_model.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_plan.dart';
import 'story_plan_trial_compiler.dart';
import 'reviewed_prose_scene_overlay.dart';
import 'reviewed_hero_role.dart';
import 'reviewed_hero_source_action.dart';
import 'whole_story_literary_bounded_repair.dart';
import 'whole_story_literary_unchanged_approval.dart';

/// A playable *PRIVATE* and *FICTIONAL* multi-act trial, never the full
/// literary CANON. This uses the original M2c compiler, BookWorld importer
/// and SQLite runtime, rather than inventing another rules/save format.
class MultiActTrialCompiler {
  const MultiActTrialCompiler._();

  static Future<StoryPlanTrialCompilation> compile({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required MultiActStoryPlanDraft draft,
    CrossActContinuityDraft? continuity,
    WholeStoryLiteraryRecheckApproval? recheckedRepair,
    WholeStoryLiteraryUnchangedApproval? unchangedReview,
    required Set<String> sourceEventIdsReviewedByUser,
    required bool privateUseConfirmed,
    required bool fictionalTrialAcknowledged,
    /// UI-only name of the player protagonist; never guesses an NPC identity.
    String heroName = 'Игрок',
    /// An existing human-reviewed permanent character_id, never an
    /// identity guessed from names. Its flag becomes real story_core state.
    ReviewedHeroRole? selectedHeroRole,
    /// A source-anchored, opt-in ROLE -> OBSERVE -> RECALL sequence.
    /// Does not give player any NPC secrets or literary claims.
    bool reviewedHeroSourceAction = false,
    /// Explicit, source-checked and user-reviewed NPC meeting, never canon.
    ReviewedHeroRole? npcEncounterRole,
    bool reviewedNpcEncounter = false,
    String npcPlayerLine = '',
    String npcReplyLine = '',
    /// Explicit source-event observations; each is shown before consent.
    Set<String> reviewedInteractiveEventIds = const {},
    List<ReviewedProseSceneApproval> reviewedProse = const [],
    /// Explicit v4: never silently promote ordinary v3 campaigns.
    bool expanded = false,
  }) async {
    RpgCreationPolicy.inspect(
      RpgCreationIntent.reviewedAlterFate(
        hero: selectedHeroRole == null
            ? RpgCreationHero.freePlayer
            : RpgCreationHero.reviewedCharacterIdentity),
      sourceFingerprint: index.sourceFingerprint,
      reviewedHero: selectedHeroRole,
    ).requireSupported();
    if (reviewedNpcEncounter &&
        (npcEncounterRole == null ||
         npcEncounterRole.sourceFingerprint != index.sourceFingerprint ||
         npcEncounterRole.characterId == selectedHeroRole?.characterId)) {
      throw const FormatException(
          'Нужна отдельная подтверждённая личность NPC, не персонаж игрока.');
    }
    if (reviewedNpcEncounter &&
        (unchangedReview != null || recheckedRepair != null ||
         reviewedProse.isNotEmpty)) {
      throw const FormatException(
          'Диалог NPC меняет сюжет; старый литературный отзыв нужно снять.');
    }
    if (reviewedHeroSourceAction && selectedHeroRole == null) {
      throw const FormatException(
          'Ролевое действие требует проверенного постоянного character_id.');
    }
    if (reviewedHeroSourceAction &&
        (unchangedReview != null || recheckedRepair != null ||
         reviewedProse.isNotEmpty)) {
      throw const FormatException(
          'Старое литературное согласование не покрывает новые '
          'ролевые игровые действия.');
    }
    if (selectedHeroRole != null &&
        (selectedHeroRole.sourceFingerprint != index.sourceFingerprint ||
         selectedHeroRole.displayName != heroName)) {
      throw const FormatException(
          'Имя и постоянная личность героя не совпали с проверенной картой.');
    }
    if (heroName.isEmpty || heroName.length > 90 ||
        heroName.trim() != heroName ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(heroName)) {
      throw const FormatException(
          'Имя героя должно быть подтверждено и не длиннее 90 символов.');
    }
    if (!privateUseConfirmed || !fictionalTrialAcknowledged) {
      throw const FormatException(
          'Подтвердите частный характер игры и то, что '
          'её сюжетные связи пока являются вымышленной адаптацией.');
    }
    if (index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        bookMap.sourceFingerprint != index.sourceFingerprint ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        !book.analysisComplete ||
        draft.parts.length < 2 ||
        draft.expanded != expanded ||
        draft.parts.length > (expanded
            ? BookwideStoryPlanComposer.maxExtendedDraftActs
            : BookwideStoryPlanComposer.maxDraftActs) ||
        !draft.formalRulesPassed ||
        draft.formalAudit.counterexamples.isNotEmpty) {
      throw const FormatException(
          'Многоактовый черновик не прошёл проверку своей редакции.');
    }
    // g2b repaired-plan evidence and a clean UNCHANGED review are mutually
    // exclusive. The latter must not silently carry over to changed
    // causal rules, artwork/prose or interactive effects.
    if (reviewedInteractiveEventIds.isNotEmpty &&
        (unchangedReview != null || recheckedRepair != null ||
         reviewedProse.isNotEmpty)) {
      throw const FormatException(
          'Рецензия для старого плана не действует для новых игровых сцен.');
    }
    if (unchangedReview != null) {
      if (recheckedRepair != null || continuity != null ||
          reviewedProse.isNotEmpty) {
        throw const FormatException(
            'Заключение для исходного плана устарело после изменения '
            'сцен, текста или правил. Требуется новый литературный аудит.');
      }
      unchangedReview.verifyForCompiler(
          index: index, book: book, plan: draft.plan);
    }
    if (recheckedRepair != null && continuity != null) {
      throw const FormatException(
          'Не смешивайте разные редакции причинных правил без новой рецензии.');
    }
    if (recheckedRepair != null) {
      recheckedRepair.verifyForCompiler(
          index: index, book: book, originalPlan: draft.plan);
      if (reviewedProse.isNotEmpty) {
        throw const FormatException(
            'Художественные правки для старого плана нужно подтвердить заново.');
      }
    }
    final composed = MultiActTrialPlanComposer.compose(
      index: index, book: book, bookMap: bookMap, draft: draft,
      continuity: continuity, recheckedRepair: recheckedRepair,
      reviewedInteractiveEventIds: reviewedInteractiveEventIds,
      selectedHeroRole: selectedHeroRole,
      reviewedHeroSourceAction: reviewedHeroSourceAction,
      npcEncounterRole: npcEncounterRole,
      reviewedNpcEncounter: reviewedNpcEncounter,
      npcPlayerLine: npcPlayerLine, npcReplyLine: npcReplyLine,
      fictionalTrialAcknowledged: fictionalTrialAcknowledged,
      expanded: expanded,
    );
    final plan = composed.plan;
    final npcArc = composed.npcArc;
    if (continuity != null &&
        (!continuity.hasEnforcedContinuity ||
         continuity.audit.counterexamples.isNotEmpty ||
         continuity.coverage.allEvents != book.events.length)) {
      throw const FormatException(
          'Переходы между актами не прошли проверку последствий.');
    }
    final result = plan.validate(book, expanded: expanded);
    if (!result.isStructurallySound ||
        !result.branchChangesState ||
        result.terminalSituations != 2) {
      throw const FormatException('Есть недостижимые или ошибочные развязки.');
    }
    // Recalculate source coverage from the actual typed plan; never trust a
    // cached count or a model-provided readiness flag.
    final coverage = BookwideActPlanner.compareWithStoryPlan(
        bookMap: bookMap, book: book, story: plan, expanded: expanded);
    // Extended campaigns must represent ALL confirmed source events through
    // real executable source decisions. No silent first-48 subset or citation
    // shortcut may be called a full-book game.
    if (expanded && (!coverage.allDetectedEventsReferenced ||
        !coverage.allChaptersCovered)) {
      throw const FormatException('Полная RPG v4 не покрывает события или главы книги');
    }
    if (coverage.referencedEvents < 2 ||
        draft.parts.any((part) =>
            !bookMap.acts.any((act) =>
                act.id == part.actId &&
                act.events.any((e) => e.id == part.setupEventId) &&
                act.events.any((e) => e.id == part.outcomeEventId)))) {
      throw const FormatException('Исходные акты не привязаны к этой книге.');
    }

    final expected = <String>{};
    for (final part in draft.parts) {
      if (!expected.add(part.setupEventId) ||
          !expected.add(part.outcomeEventId)) {
        throw const FormatException('Повторно использована исходная цитата.');
      }
    }
    for (final id in reviewedInteractiveEventIds) {
      if (!expected.add(id)) {
        throw const FormatException('Повторно использована исходная цитата.');
      }
    }
    if (sourceEventIdsReviewedByUser.length != expected.length ||
        !sourceEventIdsReviewedByUser.containsAll(expected)) {
      throw const FormatException(
          'Перед запуском нужно проверить все исходные цитаты актов.');
    }
    // One acceptance for every source anchor, reviewed encounter, and both
    // act-bridge choices. The importer and StoryWorld audit prove execution.
    final campaignContract = BookwideCampaignContract.fromPlan(
      book: book, draft: draft, plan: plan,
      reviewedInteractiveEventIds: reviewedInteractiveEventIds,
    );

    // Confirm quoted SOURCE WORDS ONLY; this is not independent acceptance of
    // a character's claims, causal relations, knowledge or world chronology.
    final byId = {for (final e in book.events) e.id: e};
    final citations = <String, (NarrativeEvent, SourceEvidence)>{};
    final proposed = <SourceEvidence>[];
    for (final id in expected) {
      final event = byId[id];
      if (event == null) {
        throw const FormatException('Нет исходного события в книге.');
      }
      final q = event.source;
      q.validate(index);
      final literal = SourceEvidence.propose(index,
        chunkId: q.chunkId,
        kind: EvidenceKind.fact,
        startUtf16: q.startUtf16,
        endUtf16: q.endUtf16,
      );
      if (literal.label != q.quote ||
          literal.chapterIndex != q.chapterIndex) {
        throw const FormatException(
            'Цитата изменилась после отдельного подтверждения.');
      }
      citations[id] = (event, literal);
      proposed.add(literal);
    }
    var evidence = SourceEvidenceGraph.empty(index).addAll(index, proposed);
    for (final literal in proposed) {
      evidence = evidence.review(index, literal.id, EvidenceStatus.confirmed);
    }

    final claims = <SourceSemanticAssertion>[];
    final eventsInTextOrder = [
      for (final e in book.events)
        if (citations.containsKey(e.id)) e,
    ];
    for (var i = 0; i < eventsInTextOrder.length; i++) {
      final source = citations[eventsInTextOrder[i].id]!.$2;
      claims.add(SourceSemanticAssertion.propose(index, evidence,
        kind: SemanticAssertionKind.fact,
        evidenceIds: [source.id],
        subject: 'Текст загруженной книги',
        predicate: 'содержит проверенную цитату',
        object: 'Отрывок ' + (i + 1).toString(),
        voice: AssertionVoice.narratorCandidate,
        polarity: AssertionPolarity.affirmative,
        time: AssertionTime.textOrderOnly,
        uncertainty: 'Подтверждены только дословные слова, '
            'не причинность, знания NPC, личности или художественный смысл.',
      ));
    }
    final catalog = SourceSemanticCatalog.checked(index, evidence, claims);
    var editorial = SemanticEditorialReviewSession.create(index, catalog);
    final claimForEvent = <String, String>{
      for (var i = 0; i < eventsInTextOrder.length; i++)
        eventsInTextOrder[i].id: claims[i].id,
    };
    for (final claim in claims) {
      editorial = editorial.decide(catalog, claim.id,
          SemanticEditorialVerdict.canonCandidate);
    }

    // M2h7a integration: each cross-act transition is checked against
    // this edition and is explicitly labeled GAME_FICTION. Exact quotes
    // must never be mistaken for a verified literary causal connection.
    final bridgeAudit = SourceBoundBridgeAuditor.audit(
      index: index,
      evidence: evidence,
      catalog: catalog,
      editorial: editorial,
      events: book.events,
      bridges: [
        for (var i = 1; i < draft.parts.length; i++)
          SourceBoundBridge(
            id: 'private_trial_bridge_' + i.toString(),
            sourceFingerprint: index.sourceFingerprint,
            fromEventId: draft.parts[i - 1].outcomeEventId,
            toEventId: draft.parts[i].setupEventId,
            kind: SourceBridgeKind.explicitGameFiction,
            rationale: 'Вымышленный переход между актами '
                'частной пробной игры, а не факт оригинальной книги.',
          ),
      ],
    );
    if (bridgeAudit.rejectedCount != 0 ||
        bridgeAudit.fictionalCount != draft.parts.length - 1 ||
        bridgeAudit.canDeclareLiteraryCausality) {
      throw const FormatException(
          'Непроверенная связь между актами не может считаться каноном.');
    }

    // M2h7b: legacy per-act promise ledgers remain EXACTLY unchanged for
    // old 2..6 act .bworld files. On >6 acts the three local process flags
    // are reused: a global unique-grant ledger would falsely reject them.
    // The BookwideCampaignContract ABOVE instead enforces the exact scoped
    // grant/require/forbid for EVERY act, verifies both bridge resets, then
    // the REAL imported StoryWorld BELOW proves all executable paths.
    if (draft.parts.length <= 6) {
      final promiseRules = <BranchContinuityRule>[];
      for (var i = 0; i < draft.parts.length; i++) {
        final prefix = 'act_' + (i + 1).toString() + '_';
        final accepted = plan.flags.where((flag) =>
            flag.startsWith(prefix) && flag.endsWith('_accepted')).toList();
        if (accepted.length != 1) {
          throw const FormatException(
              'Не найдено однозначное состояние принятия игрового условия.');
        }
        promiseRules.add(BranchContinuityRule(
          id: prefix + 'promise_gate',
          sourceFingerprint: index.sourceFingerprint,
          kind: ContinuityLedgerKind.promise,
          subjectId: 'player',
          resourceId: prefix + 'fictional_offer',
          sourceEventId: draft.parts[i].setupEventId,
          stateFlag: accepted.single,
          grantDecisionId: prefix + 'accept_offer',
          protectedDecisionIds: [prefix + 'honor_condition'],
          refusalDecisionIds: [prefix + 'refuse_offer'],
          reviewedAsGameFiction: true,
        ));
      }
      final continuityCheck = BranchContinuityAuditor.audit(
        index: index, book: book, plan: plan, rules: promiseRules,
        expanded: expanded);
      if (!continuityCheck.passedFormalStateAudit ||
          continuityCheck.verifiesBookMeaning ||
          continuityCheck.canPublishCanonicalRpg) {
        throw const FormatException('Игровое обязательство возникает '
            'без согласия, после отказа или без проверенного состояния.');
      }
    }

    // Page order is not historical world time. Keep all inferred act-to-act
    // timelines explicitly UNKNOWN until separately reviewed as fiction.
    final timeReport = SourceWorldTimeAuditor.audit(
      index: index, book: book,
      links: [
        for (var i = 1; i < draft.parts.length; i++)
          SourceWorldTimeLink(
            id: 'act_time_' + i.toString(),
            sourceFingerprint: index.sourceFingerprint,
            fromEventId: draft.parts[i - 1].outcomeEventId,
            toEventId: draft.parts[i].setupEventId,
            relation: GameWorldTimeRelation.unknown,
          ),
      ],
    );
    if (timeReport.unknownWorldOrderLinks != draft.parts.length - 1 ||
        timeReport.establishesBookWorldChronology) {
      throw const FormatException('Порядок текста нельзя выдавать '
          'за проверенную хронологию мира книги.');
    }

    // The text overlay changes only scene prose, never source evidence,
    // choice IDs, requires/forbids/adds/removes or SQLite state.
    // An overlay approved for the old plan fails closed if a new
    // cross-act rule changes the final plan after the user's review.
    final reviewedProseTexts = ReviewedProseSceneOverlay.validate(
      index: index,
      book: book,
      finalPlan: plan,
      approvals: reviewedProse,
      expanded: expanded,
    );

    final sourceSceneIds = <String>{
      for (var i = 0; i < draft.parts.length; i++) ...[
        'act_' + (i + 1).toString() + '_turning_point',
        'act_' + (i + 1).toString() + '_accept_path',
      ],
    };
    final scenes = <DraftScene>[];
    for (final scene in plan.situations) {
      final sourceScene = sourceSceneIds.contains(scene.id) ||
          (scene.sourceEventId != null &&
           reviewedInteractiveEventIds.contains(scene.sourceEventId));
      final reference = sourceScene ? citations[scene.sourceEventId] : null;
      final claimId = sourceScene
          ? claimForEvent[scene.sourceEventId] : null;
      if (sourceScene &&
          (scene.route != StoryRoute.canonicalProposal ||
           reference == null || claimId == null ||
           scene.chapterIndex != reference.$1.source.chapterIndex)) {
        throw const FormatException(
            'Исходная сцена не соответствует проверенной цитате.');
      }
      final words = sourceScene
          ? 'ДОСЛОВНЫЙ ОТРЫВОК ОРИГИНАЛА:\n«' +
              reference!.$1.source.quote +
              '»\n\nДАЛЕЕ — ВЫМЫШЛЕННАЯ ИГРОВАЯ ИНТЕРПРЕТАЦИЯ:\n'
          : 'ВЫМЫШЛЕННАЯ ИГРОВАЯ АДАПТАЦИЯ, НЕ ТЕКСТ КНИГИ:\n';
      final approvedText = reviewedProseTexts[scene.id];
      final body = approvedText == null
          ? words + scene.goal + '\n\n' + scene.conflict
          : words + 'ХУДОЖЕСТВЕННАЯ ЧАСТНАЯ АДАПТАЦИЯ '
              '(ЯВНО ОДОБРЕННЫЙ ЧЕРНОВИК, НЕ КАНОН):\n' +
              approvedText;
      scenes.add(DraftScene(
        id: scene.id,
        chapterIndex: scene.chapterIndex,
        text: body,
        origin: sourceScene
            ? DraftSceneOrigin.sourcePassage
            : DraftSceneOrigin.explicitAdaptation,
        assertionIds: sourceScene ? [claimId!] : const [],
        terminal: scene.terminal,
        choices: [
          for (final choice in scene.decisions)
            DraftChoice(
              id: choice.id, label: choice.intent,
              nextSceneId: choice.nextSituationId,
              requires: choice.requires,
              forbids: choice.forbids,
              adds: choice.adds,
              removes: choice.removes,
            ),
        ],
      ));
    }
    final intermediate = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      entrySceneId: plan.entrySituationId,
      rights: PreparationRights.privateUse,
      flags: plan.flags,
      initialFlags: plan.initialFlags,
      scenes: scenes,
    );
    // M2c preflight, independent compiler and actual ZIP/SQLite importer
    // are REQUIRED; no upload/publication or mutation of existing campaigns.
    // Same source-reviewed multi-act plan, now packaged in ONE rich v3
    // format. No forced/fabricated items, stats, knowledge or cloud calls.
    final sceneTitles = {
      for (final scene in plan.situations) scene.id: scene.goal,
    };
    final archive = expanded
        ? await compileReviewedExtendedPrivateBookworldInWorker(
            index, evidence, catalog, editorial, intermediate,
            heroName: heroName, sceneTitles: sceneTitles,
            reviewedNpcArc: npcArc?.writerReview)
        : await compileReviewedRichPrivateBookworldInWorker(
            index, evidence, catalog, editorial, intermediate,
            heroName: heroName, sceneTitles: sceneTitles,
            reviewedNpcArc: npcArc?.writerReview);
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    if (inspected.formatVersion != (expanded ? 4 : 3) ||
        inspected.sourceFingerprint != index.sourceFingerprint ||
        inspected.requiresNetwork ||
        inspected.canDistributePublicly ||
        inspected.blueprint.scenes.length != scenes.length ||
        inspected.blueprint.scenes.length < 14 ||
        inspected.presentation['hero'] is! Map ||
        (inspected.presentation['hero'] as Map)['name'] != heroName ||
        (selectedHeroRole != null &&
         inspected.blueprint.initial.flags[
             selectedHeroRole.playerIdentityFlag] != true) ||
        (reviewedHeroSourceAction &&
         !inspected.blueprint.initial.flags.containsKey(
             ReviewedHeroSourceAction.observedFlag)) ||
        (npcArc != null &&
         (!inspected.blueprint.actors.contains(npcArc.role.characterId) ||
          inspected.npcSocialRulebook == null))) {
      throw const FormatException(
          'Частный многоактовый пакет не прошёл независимую проверку.');
    }
    // Final pass on the EXACT independently imported world, not on a
    // convenient graph of StoryPlan situations. Reject reachable softlocks
    // and structurally connected but impossible endings before installation.
    final campaignReport = CompiledCampaignCausalGate.verify(
      blueprint: inspected.blueprint,
      expanded: expanded,
      socialRules: inspected.npcSocialRulebook,
      requiredChoiceIds: [
        ...campaignContract.requiredChoiceIds,
        if (npcArc != null) ...npcArc.requiredChoiceIds,
      ],
    );
    campaignContract.verifyWitnesses(campaignReport);
    if (npcArc != null) {
      for (final id in npcArc.requiredChoiceIds) {
        final witness = campaignReport.choiceWitnesses[id];
        if (witness == null || witness.isEmpty ||
            witness.last.choiceId != id) {
          throw FormatException('Нет исполнимой NPC-реплики: ' + id);
        }
      }
    }
    return StoryPlanTrialCompilation(
      archive: archive,
      sourceFingerprint: index.sourceFingerprint,
      bookworldId: inspected.bookworldId,
      archiveSha256: inspected.archiveSha256,
      sceneCount: inspected.blueprint.scenes.length,
      sourceQuoteCount: expected.length,
      sourceEventsTotal: coverage.allEvents,
      sourceEventsRepresented: coverage.referencedEvents,
      unrepresentedSourceEventIds:
          List.unmodifiable(coverage.eventIdsStillUnrepresented),
      uncoveredSourceChapters:
          List.unmodifiable(coverage.chaptersNotCovered),
      chaptersWithoutSourceEvents:
          List.unmodifiable(coverage.chaptersWithoutEventProposals),
      selectedHeroLabel: heroName,
      selectedHeroCharacterId: selectedHeroRole?.characterId,
      verifiedSourceChoices: campaignContract.sourceDecisions.length,
      verifiedActBridges: campaignContract.bridgeDecisions.length,
      verifiedNpcActions: npcArc == null ? 0 : npcArc.requiredChoiceIds.length,
    );
  }
}
