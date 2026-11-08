import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:story_core/story_core.dart';

import 'src/free_text_action_gate.dart';
export 'src/free_text_action_gate.dart';
export 'src/legacy_pilot_progress.dart';
export 'src/legacy_pilot_save_record.dart';
export 'src/legacy_pilot_save_codec.dart';
export 'src/scene_dialogue_script.dart';

/// Flutter-independent RPG application API.
///
/// story_core owns all causal decisions, story_runtime_adapter owns runtime
/// navigation, campaign_manager owns durable SQLite state. This module owns
/// replay-derived hero, inventory, NPC dialogue, relationships and journal
/// projections; it never writes a rule, opens a cloud connection or reads
/// a platform path. UI and any other client consume the same results.

/// Transport-only view models; game rules, scene transitions, and writes
/// are owned exclusively by campaign_manager/story_runtime_adapter.
class WorldLibraryItem {
  const WorldLibraryItem({
    required this.archiveHash, required this.bookworldId,
    required this.title,
  });

  final String archiveHash;
  final String bookworldId;
  final String title;
}

class WorldCampaignItem {
  const WorldCampaignItem({
    required this.id, required this.worldHash, required this.revision,
    required this.savedAt, this.parentId,
  });

  final String id;
  final String worldHash;
  final int revision;
  final String savedAt;
  final String? parentId;
}

/// Safe, replay-verified metadata shown before a portable import.
/// Contains no book text and does not represent a committed campaign.
class WorldSavePreview {
  const WorldSavePreview({
    required this.sourceCampaignId,
    required this.worldHash,
    required this.revision,
    required this.stateHash,
    required this.isTerminal,
  });

  final String sourceCampaignId;
  final String worldHash;
  final int revision;
  final String stateHash;
  final bool isTerminal;
}

class WorldChoiceView {
  const WorldChoiceView({
    required this.id, required this.label, this.lockReason,
  });

  final String id;
  final String label;
  final String? lockReason;
  bool get enabled => lockReason == null;

  /// Game mechanics own the lock. The view must never reveal an unreached
  /// knowledge-gated reply through its button label or accessibility text.
  /// Check all conditions against the exact SQLite-replayed actor knowledge,
  /// even if the engine first reports a different missing condition.
  static WorldChoiceView fromVerifiedRules({
    required BlueprintChoice signedChoice,
    required String? lockReason,
    required Map<String, Set<String>> verifiedKnowledge,
    String? reviewedSpokenReply,
  }) {
    final knowledgeSensitive = signedChoice.conditions
        .any((rule) => rule.op == 'knows_fact');
    final missing = signedChoice.conditions.any((rule) =>
        rule.op == 'knows_fact' &&
        !(verifiedKnowledge[rule.actor]?.contains(rule.id) ?? false));
    if (missing && lockReason == null) {
      throw const FormatException(
          'Проверка знания расходится с доступностью решения.');
    }
    return WorldChoiceView(
      id: signedChoice.id,
      // If another gate (identity, presence, a flag, or time) is still
      // closed, don't reveal a knowledge-sensitive reply prematurely.
      label: reviewedSpokenReply != null
          ? (lockReason == null
              ? 'Игрок: «' + reviewedSpokenReply + '»'
              : 'Ответ недоступен до выполнения условий')
          : (knowledgeSensitive && lockReason != null
              ? 'Реплика скрыта до выполнения условий'
              : signedChoice.label),
      lockReason: lockReason,
    );
  }
}

class WorldEventView {
  const WorldEventView({
    required this.sequence, required this.sceneId,
    required this.choiceLabel, this.sceneTitle, this.changes = const [],
  });

  final int sequence;
  final String sceneId;
  final String choiceLabel;
  final String? sceneTitle;
  /// Only state differences confirmed by replay, never model-invented actions.
  final List<String> changes;
}

/// Read-only, replay-derived NPC state. A displayed name never proves a
/// personality, a future event, or access to an unpublished book secret.
class NpcRelationView {
  const NpcRelationView({
    required this.actorId, required this.displayName,
    required this.directedScore, required this.memoryCount,
    required this.memoryKinds, this.lifeState,
  });

  final String actorId;
  final String displayName;
  /// A signed action changed NPC -> player, not player -> NPC.
  final int directedScore;
  final int memoryCount;
  final Map<String, int> memoryKinds;
  /// Null if the signed world has no lifecycle events for this actor.
  final String? lifeState;
}

class WorldGameView {
  const WorldGameView({
    required this.campaignId, required this.worldTitle,
    required this.sceneId, required this.sceneText,
    required this.revision, required this.tick, required this.isTerminal,
    required this.stats, required this.inventory,
    required this.flags, required this.knownFacts,
    required this.choices, required this.journal,
    this.heroName, this.heroDescription,
    this.itemNames = const {}, this.itemDescriptions = const {},
    this.statNames = const {}, this.factNames = const {},
    this.sceneNames = const {},
    this.sceneDialogueTurns,
    this.sceneSpeakerIdentityReviewed = false,
    this.visibleSpeakerActorIds = const {},
    this.npcItemOwners = const {},
    this.npcDisplayNames = const {},
    this.npcLifeStates = const {},
    this.npcRelations = const [],
  });

  final String campaignId;
  final String worldTitle;
  final String sceneId;
  final String sceneText;
  final int revision;
  final int tick;
  final bool isTerminal;
  final Map<String, int> stats;
  final List<String> inventory;
  final Map<String, bool> flags;
  final List<String> knownFacts;
  final List<WorldChoiceView> choices;
  final List<WorldEventView> journal;
  final String? heroName;
  final String? heroDescription;
  final Map<String, String> itemNames;
  final Map<String, String> itemDescriptions;
  final Map<String, String> statNames;
  final Map<String, String> factNames;
  final Map<String, String> sceneNames;
  /// Exact, importer-verified speaker turns. Null for older worlds or prose.
  final List<RichDialogueTurn>? sceneDialogueTurns;

  /// True only when the importer has validated per-turn speaker IDs for
  /// the current signed scene and runtime has applied every causal gate.
  /// A redacted NPC line must never inherit a portrait by display name.
  final bool sceneSpeakerIdentityReviewed;

  /// Visible, source-reviewed scene speaker -> permanent actor ID. Actors
  /// whose names collide or whose lines are still gated are NOT present.
  final Map<String, String> visibleSpeakerActorIds;

  /// Resolve the ONLY permitted portrait storage key for this speaker.
  /// Reviewed NPC dialogue uses actor identity; legacy v1/v2 name-based
  /// portraits remain locally compatible without changing their archives.
  String? portraitStorageKeyFor(String speaker) {
    if (sceneSpeakerIdentityReviewed) {
      return visibleSpeakerActorIds[speaker];
    }
    final matching = npcRelations
        .where((npc) => npc.displayName == speaker)
        .map((npc) => npc.actorId).toSet();
    if (matching.length > 1) return null;
    return matching.isEmpty ? speaker : matching.single;
  }

  /// Item -> encountered NPC character_id, derived only from replayed
  /// committed events. Future custodians remain in the trusted engine ledger
  /// but are NEVER copied into the public reader projection.
  final Map<String, String> npcItemOwners;
  /// Only encountered or presently speaking reviewed NPC identities.
  final Map<String, String> npcDisplayNames;
  /// Event-replayed NPC life states, only for already encountered actors.
  final Map<String, String> npcLifeStates;
  /// Only already-met actors with signed NPC witness/event evidence.
  /// Derived from the committed SQLite event chain, never cloud prose.
  final List<NpcRelationView> npcRelations;
}

class WorldChoiceResult {
  const WorldChoiceResult({
    required this.applied, required this.view,
    this.reason, this.duplicate = false,
  });

  final bool applied;
  final bool duplicate;
  final String? reason;
  final WorldGameView view;
}

abstract class WorldLibraryGateway {
  Future<List<WorldLibraryItem>> worlds();
  Future<WorldLibraryItem> install(Uint8List archive);
  Future<List<WorldCampaignItem>> campaigns({String? worldHash});
  Future<String> start(String worldHash, {String? parentCampaignId});
  Future<WorldGameView> load(String campaignId);
  Future<WorldChoiceResult> choose(String campaignId, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  });
  Future<String> exportSave(String campaignId);
  Future<WorldSavePreview> previewSave(String text, {
    required String expectedWorldHash,
  });
  Future<void> deleteCampaign(String campaignId, {required int expectedRevision});
  Future<Uint8List> exportWorld(String worldHash);
  Future<void> deleteWorld(String worldHash);
  Future<String> importSave(String text, {required String expectedWorldHash});
}

/// Standalone RPG game service; no platform dependencies at all.
class RpgGameplayEngine {
  const RpgGameplayEngine(this._store);
  final BookworldCampaignStore _store;

  static WorldLibraryItem _world(WorldCatalogEntry entry) => WorldLibraryItem(
    archiveHash: entry.archiveHash,
    bookworldId: entry.bookworldId,
    title: entry.title,
  );

  static WorldCampaignItem _campaign(CampaignSnapshot entry) =>
      WorldCampaignItem(
        id: entry.id, worldHash: entry.worldHash,
        parentId: entry.parentId, revision: entry.revision,
        savedAt: entry.savedAt,
      );

  static ({
    Map<String, dynamic> presentation,
    NpcSocialRulebook? social,
  }) _verifiedRichContent(
      BookworldCampaignStore store, String worldHash) {
    // The store first verifies exact saved ZIP/SQLite. Only the new v3
    // importer can return rich presentation; legacy v1/v2 stay untouched.
    final bytes = store.exportBookworld(worldHash);
    try {
      final rich = const RichPrivateBookworldImporter().inspect(bytes);
      return (presentation: rich.presentation, social: rich.npcSocialRulebook);
    } on FormatException {
      // An invalid v3 NPC review must NEVER be downgraded to raw scene
      // text; that would bypass actor/fact gates and leak sealed dialogue.
      // Only an independently verified legacy v2 or v1 archive may render
      // without a signed rich presentation.
      try {
        const PrivateBookworldImporter().inspect(bytes);
        return (presentation: const <String, dynamic>{}, social: null);
      } on FormatException {
        const BookworldImporter().inspect(bytes);
        return (presentation: const <String, dynamic>{}, social: null);
      }
    }
  }

  static WorldGameView _view(CampaignRecord record,
      {Map<String, dynamic> presentation = const {},
       NpcSocialRulebook? socialRules}) {
    final coordinator = record.coordinator;
    final blueprint = coordinator.blueprint;
    final state = coordinator.state;
    final current = blueprint.scenes[coordinator.sceneId]!;
    // The SQLite store already checked all events. Independently recompute
    // social memory from the exact replayed head, never from UI labels.
    final social = socialRules == null ? null : NpcSocialLedger.inspect(
      StoryWorld.replay(
        blueprint, coordinator.events.map((event) => event.toJson()),
        expectedSequence: state.revision,
        expectedStateHash: state.stateHash,
        socialRulebook: socialRules,
      ),
      socialRules,
    );
    Map<String, String> names(String field) {
      final value = presentation[field];
      return value is Map<String, dynamic>
          ? Map.unmodifiable(value.cast<String, String>())
          : const {};
    }
    final items = names('item_names');
    final itemDescriptions = names('item_descriptions');
    final stats = names('stat_names');
    final facts = names('fact_names');
    final scenes = names('scene_names');
    final npcDisplayNames = <String, String>{};
    final allReviewedSpeakers = presentation['scene_dialogue_knowledge'];
    if (allReviewedSpeakers is Map<String, dynamic>) {
      for (final turns in allReviewedSpeakers.values) {
        if (turns is! List) continue;
        for (final entry in turns) {
          if (entry is! Map) continue;
          final actor = entry['actor_id'];
          final speaker = entry['speaker'];
          if (actor is String && actor != 'player' &&
              blueprint.actors.contains(actor) &&
              speaker is String && speaker.trim().isNotEmpty) {
            npcDisplayNames.putIfAbsent(actor, () => speaker);
          }
        }
      }
    }
    // No separate NPC identity or gameplay is trusted here. The v3 importer
    // has already compared each projection to the exact signed scene text.
    // Recheck the currently displayed scene so nothing else can override it.
    List<RichDialogueTurn>? signedTurns;
    final allDialogues = presentation['scene_dialogues'];
    if (allDialogues is Map<String, dynamic> &&
        allDialogues.containsKey(current.id)) {
      signedTurns = RichSceneDialogue.verify(
          allDialogues[current.id], current.text);
    }
    final guards = presentation['scene_dialogue_knowledge'];
    final hasReviewedNpcTurns = guards is Map<String, dynamic> &&
        guards.containsKey(current.id);
    if (hasReviewedNpcTurns) {
      if (signedTurns == null || guards[current.id] is! List) {
        throw const FormatException('Отсутствует проверенный диалог NPC');
      }
      // The importer already verified EVERY signed line and reviewed actor ID.
      // Only the replay-verified campaign state decides which words reach UI.
      signedTurns = RichNpcDialogueKnowledge.redact(
          signedTurns, guards[current.id] as List, state.knowledge,
          social: social, committedEvents: coordinator.events,
          sceneId: current.id);
    }
    // Do not list unencountered cast members from future signed chapters.
    // An NPC is visible here only after a committed memory event, or when
    // its actual, knowledge-verified spoken turn is visible right now.
    final visibleSpeakers = <String>{};
    final reviewedSpeakerIds = <String, Set<String>>{};
    if (hasReviewedNpcTurns && signedTurns != null) {
      for (final raw in guards[current.id] as List) {
        if (raw is! Map || raw['actor_id'] is! String ||
            raw['turn_index'] is! int) continue;
        final i = raw['turn_index'] as int;
        if (i < 0 || i >= signedTurns.length ||
            signedTurns[i].speaker == null ||
            signedTurns[i].speaker != raw['speaker'] ||
            signedTurns[i].text == RichNpcDialogueKnowledge.unavailableLine) {
          continue;
        }
        final actor = raw['actor_id'] as String;
        // Include player speaker identities in the collision check, but
        // never assign an NPC portrait to the hero's spoken lines.
        reviewedSpeakerIds
            .putIfAbsent(signedTurns[i].speaker!, () => <String>{})
            .add(actor);
        if (actor != 'player') visibleSpeakers.add(actor);
      }
    }
    final visibleSpeakerActorIds = Map<String, String>.unmodifiable({
      for (final entry in reviewedSpeakerIds.entries)
        if (entry.value.length == 1 && entry.value.single != 'player')
          entry.key: entry.value.single,
    });
    final npcRelations = <NpcRelationView>[];
    if (social != null && socialRules != null) {
      final actors = blueprint.actors.where((id) => id != 'player').toList()
        ..sort();
      for (final actor in actors) {
        final memories = social.memoriesFor(actor);
        if (memories.isEmpty && !visibleSpeakers.contains(actor)) continue;
        final kinds = <String, int>{};
        for (final memory in memories) {
          kinds.update(memory.kind.name, (count) => count + 1,
              ifAbsent: () => 1);
        }
        final hasLifeReview = socialRules.lifeTransitions
            .any((change) => change.actorId == actor);
        npcRelations.add(NpcRelationView(
          actorId: actor,
          displayName: npcDisplayNames[actor] ?? 'Персонаж истории',
          directedScore: social.directedScore(actor, 'player'),
          memoryCount: memories.length,
          memoryKinds: Map.unmodifiable(kinds),
          lifeState: hasLifeReview ? social.lifeState(actor).name : null,
        ));
      }
    }
    final hero = presentation['hero'];
    final heroName = hero is Map<String, dynamic> ? hero['name'] as String? : null;
    final heroDescription =
        hero is Map<String, dynamic> ? hero['description'] as String? : null;

    // Journal is reconstructed from the committed, replay-verified event log.
    // Actual before/after deltas keep even idempotent effects from being
    // misrepresented as newly acquired items or facts.
    final playback = presentation.isNotEmpty
        ? StoryWorld(blueprint, socialRulebook: socialRules)
        : null;
    final journal = <WorldEventView>[];
    for (final event in coordinator.events) {
      final scene = blueprint.scenes[event.sceneId]!;
      final choice = scene.choices
          .firstWhere((option) => option.id == event.choiceId);
      final changes = <String>[];
      if (playback != null) {
        final before = playback.state;
        final activeSocialRules = socialRules?.rules.where((rule) =>
            rule.sceneId == event.sceneId &&
            rule.choiceId == event.choiceId).toList() ?? [];
        final beforeSocial = activeSocialRules.isNotEmpty
            ? NpcSocialLedger.inspect(playback, socialRules!) : null;
        final beforeLife = socialRules != null &&
            socialRules.lifeTransitions.isNotEmpty
            ? NpcSocialLedger.inspect(playback, socialRules) : null;
        final committed = playback.apply(
          actionId: event.actionId,
          choiceId: event.choiceId,
          expectedRevision: before.revision,
        );
        if (!committed.applied || committed.event?.hash != event.hash) {
          throw const FormatException('Журнал игры не совпадает с сохранением');
        }
        final after = playback.state;
        if (beforeSocial != null) {
          final afterSocial = NpcSocialLedger.inspect(playback, socialRules!);
          final recorded = <String>{};
          for (final rule in activeSocialRules) {
            final actor = rule.observerId;
            final label = npcDisplayNames[actor] ?? actor;
            if (!beforeSocial.hasMemory(actor, rule.memoryId) &&
                afterSocial.hasMemory(actor, rule.memoryId)) {
              changes.add(label + ': запомнил событие разговора');
            }
            if (rule.relatedActorId == 'player' &&
                recorded.add(actor)) {
              final delta = afterSocial.directedScore(actor, 'player') -
                  beforeSocial.directedScore(actor, 'player');
              if (delta != 0) {
                changes.add(label + ': отношение к герою ' +
                    (delta > 0 ? '+' : '') + delta.toString());
              }
            }
          }
        }
        if (beforeLife != null) {
          final afterLife = NpcSocialLedger.inspect(playback, socialRules!);
          for (final actor in socialRules.lifeTransitions
              .map((event) => event.actorId).toSet()) {
            final previous = beforeLife.lifeState(actor);
            final current = afterLife.lifeState(actor);
            if (previous != current) {
              final label = npcDisplayNames[actor] ?? actor;
              final stateLabel = switch (current) {
                NpcLifeState.present => 'вернулся',
                NpcLifeState.absent => 'ушёл',
                NpcLifeState.dead => 'погиб',
              };
              changes.add('$label: $stateLabel');
            }
          }
        }
        final reviewedTransfers = socialRules?.itemTransfers.where(
          (transfer) => transfer.sceneId == event.sceneId &&
              transfer.choiceId == event.choiceId).toList() ??
            <NpcItemTransfer>[];
        for (final id in (after.inventory.difference(before.inventory).toList()..sort())) {
          final returned = reviewedTransfers.where((transfer) =>
              transfer.itemId == id && transfer.toActorId == 'player').toList();
          changes.add((returned.isNotEmpty
              ? 'Получено от персонажа: ' : 'Получено: ') + (items[id] ?? id));
        }
        for (final id in (before.inventory.difference(after.inventory).toList()..sort())) {
          final given = reviewedTransfers.where((transfer) =>
              transfer.itemId == id && transfer.fromActorId == 'player').toList();
          changes.add((given.isNotEmpty
              ? 'Передано персонажу: ' : 'Использовано: ') + (items[id] ?? id));
        }
        for (final id in (after.stats.keys.toList()..sort())) {
          final amount = after.stats[id]! - before.stats[id]!;
          if (amount != 0) {
            changes.add((stats[id] ?? id) +
                ': ' + (amount > 0 ? '+' : '') + amount.toString());
          }
        }
        final learned = (after.knowledge['player'] ?? <String>{})
            .difference(before.knowledge['player'] ?? <String>{})
            .toList()..sort();
        for (final id in learned) {
          changes.add('Узнано: ' + (facts[id] ?? id));
        }
      }
      journal.add(WorldEventView(
        sequence: event.sequence,
        sceneId: event.sceneId,
        choiceLabel: RichNpcDialogueResponses.replyFor(
                presentation, event.sceneId, event.choiceId) == null
            ? choice.label
            : 'Игрок: «' +
                RichNpcDialogueResponses.replyFor(
                    presentation, event.sceneId, event.choiceId)! + '»',
        sceneTitle: scenes[event.sceneId],
        changes: List.unmodifiable(changes),
      ));
    }
    if (playback != null && playback.state.stateHash != state.stateHash) {
      throw const FormatException('История изменений не совпадает с героем');
    }

    return WorldGameView(
      campaignId: record.metadata.id,
      worldTitle: blueprint.title,
      sceneId: current.id,
      // When dialogue has per-NPC facts, do not pass its raw signed prose
      // to a UI fallback, history widget or local position cache.
      sceneText: hasReviewedNpcTurns
          ? 'Разговор с проверяемыми репликами.' : current.text,
      revision: state.revision,
      tick: state.tick,
      isTerminal: coordinator.isTerminal,
      stats: Map.unmodifiable(state.stats),
      inventory: List.unmodifiable(state.inventory.toList()..sort()),
      flags: Map.unmodifiable(state.flags),
      knownFacts: List.unmodifiable(
        (state.knowledge['player'] ?? <String>{}).toList()..sort(),
      ),
      choices: List.unmodifiable(coordinator.choices.map(
        (choice) => WorldChoiceView.fromVerifiedRules(
          signedChoice: current.choices.singleWhere(
              (signed) => signed.id == choice.id),
          lockReason: choice.lockReason,
          verifiedKnowledge: state.knowledge,
          reviewedSpokenReply: RichNpcDialogueResponses.replyFor(
              presentation, current.id, choice.id),
        ),
      )),
      journal: List.unmodifiable(journal),
      heroName: heroName,
      heroDescription: heroDescription,
      itemNames: items,
      itemDescriptions: itemDescriptions,
      statNames: stats,
      factNames: facts,
      sceneNames: scenes,
      sceneDialogueTurns: signedTurns,
      sceneSpeakerIdentityReviewed: hasReviewedNpcTurns,
      visibleSpeakerActorIds: visibleSpeakerActorIds,
      // Public reader projections must not contain future NPC spoilers at
      // all, even for a new caller that forgets to filter its own widgets.
      // The authoritative social state remains untouched in story_core.
      npcItemOwners: Map.unmodifiable({
        if (social != null)
          for (final item in blueprint.items)
            if (social.itemOwner(item) != null &&
                social.itemOwner(item) != 'player' &&
                npcRelations.any((npc) =>
                    npc.actorId == social.itemOwner(item)))
              item: social.itemOwner(item)!,
      }),
      npcDisplayNames: Map.unmodifiable({
        for (final npc in npcRelations) npc.actorId: npc.displayName,
        for (final actor in visibleSpeakers)
          if (npcDisplayNames.containsKey(actor))
            actor: npcDisplayNames[actor]!,
      }),
      npcRelations: List.unmodifiable(npcRelations),
      npcLifeStates: Map.unmodifiable({
        if (social != null && socialRules != null)
          for (final npc in npcRelations)
            if (socialRules.lifeTransitions.any((transition) =>
                transition.actorId == npc.actorId))
              npc.actorId: social.lifeState(npc.actorId).name,
      }),
    );
  }

  /// Headless engine entrypoint using the caller's own private SQLite store.
  /// The caller owns the store lifetime. No Flutter, preferences or cloud.
  List<WorldLibraryItem> worlds() =>
      List.unmodifiable(_store.installedWorlds().map(_world));

  WorldLibraryItem install(Uint8List archive) =>
      _world(_store.installBookworld(archive));

  List<WorldCampaignItem> campaigns({String? worldHash}) =>
      List.unmodifiable(_store.campaigns()
          .where((entry) => worldHash == null || entry.worldHash == worldHash)
          .map(_campaign));

  String start(String worldHash, {String? parentCampaignId}) =>
      _store.createCampaign(
          worldHash, parentCampaignId: parentCampaignId);

  /// Only replay-verified signed events, never source prose alone, reveal NPC
  /// knowledge, relationships, actor IDs, personal items or journal facts.
  WorldGameView load(String campaignId) {
    final record = _store.loadCampaign(campaignId);
    final rich = _verifiedRichContent(_store, record.metadata.worldHash);
    return _view(record, presentation: rich.presentation,
        socialRules: rich.social);
  }

  /// Atomic commit through the ONE authoritative story runtime and SQLite.
  /// An invalid/stale choice never changes the persistent campaign head.
  WorldChoiceResult choose(String campaignId, {
    required String actionId, required String choiceId,
    required int expectedRevision,
  }) {
    final result = _store.commitChoice(campaignId,
        actionId: actionId, choiceId: choiceId,
        expectedRevision: expectedRevision);
    final current = load(campaignId);
    return WorldChoiceResult(applied: result.applied,
        duplicate: result.status.name == 'duplicate',
        reason: result.reason, view: current);
  }

  String exportSave(String campaignId) =>
      _store.exportPortable(campaignId);

  void deleteCampaign(String campaignId, {required int expectedRevision}) =>
      _store.deleteCampaign(campaignId, expectedRevision: expectedRevision);

  Uint8List exportWorld(String worldHash) =>
      _store.exportBookworld(worldHash);

  void deleteWorld(String worldHash) =>
      _store.deleteBookworld(worldHash);

  WorldSavePreview previewSave(String text, {
    required String expectedWorldHash,
  }) {
    final verified = _store.previewPortable(text);
    if (verified.worldHash != expectedWorldHash) {
      throw const FormatException('Сохранение относится к другому игровому миру');
    }
    return WorldSavePreview(sourceCampaignId: verified.sourceCampaignId,
        worldHash: verified.worldHash, revision: verified.revision,
        stateHash: verified.stateHash, isTerminal: verified.isTerminal);
  }

  String importSave(String text, {required String expectedWorldHash}) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Сохранение превышает 2 МБ');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Некорректный JSON сохранения');
    }
    if (decoded is! Map || decoded['world_sha256'] != expectedWorldHash) {
      throw const FormatException('Сохранение относится к другому игровому миру');
    }
    return _store.importPortable(text);
  }
}

/// Preserves the existing asynchronous SQLite/isolate architecture.
/// Free-text cannot open its own DB, choose hidden actions, or write canon.
class FreeTextWorldGatewayPort {
  const FreeTextWorldGatewayPort(this.gateway);
  final WorldLibraryGateway gateway;

  static FreeTextCampaignHead headFromView(WorldGameView view) =>
      FreeTextCampaignHead(
        campaignId: view.campaignId,
        sceneId: view.sceneId,
        revision: view.revision,
        isTerminal: view.isTerminal,
        choices: [
          for (final choice in view.choices)
            FreeTextChoice(
              id: choice.id, label: choice.label,
              lockReason: choice.lockReason,
            ),
        ],
      );

  Future<FreeTextPreview> preview(String campaignId, String input) async {
    final current = await gateway.load(campaignId);
    return FreeTextActionGate.preview(headFromView(current), input);
  }

  /// Checks a fresh database snapshot *before* the existing transactional
  /// gateway.choose. The gateway itself rejects concurrent stale revisions.
  /// An exception/timeout never means we may assume a turn committed.
  Future<WorldChoiceResult> confirm({
    required FreeTextProposal proposal,
    required String actionId,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw const FormatException('Игрок не подтвердил действие.');
    }
    final fresh = await gateway.load(proposal.campaignId);
    FreeTextActionGate.validate(
      current: headFromView(fresh), proposal: proposal,
      actionId: actionId, userConfirmed: true,
    );
    return gateway.choose(proposal.campaignId,
      choiceId: proposal.choiceId,
      expectedRevision: proposal.expectedRevision,
      actionId: actionId,
    );
  }
}
