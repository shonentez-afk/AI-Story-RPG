import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:path_provider/path_provider.dart';

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
    this.npcItemOwners = const {},
    this.npcDisplayNames = const {},
    this.npcLifeStates = const {},
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
  /// Item -> NPC character_id, derived only from verified committed events.
  final Map<String, String> npcItemOwners;
  /// Source-reviewed signed speakers where available; not guessed from names.
  final Map<String, String> npcDisplayNames;
  /// Event-replayed NPC life states only for worlds with v5 annotations.
  final Map<String, String> npcLifeStates;
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

/// No Python, network or arbitrary user-provided paths at runtime.
/// Each request is a short independent isolate with its own DB connection;
/// previous M1.6 SharedPreferences are never opened or migrated.
class DeviceWorldLibraryGateway implements WorldLibraryGateway {
  const DeviceWorldLibraryGateway({this.background = true});

  /// Production uses worker isolates. Host-based widget tests may explicitly
  /// run the same real SQLite store inline to avoid fakeAsync deadlock.
  final bool background;

  Future<T> _execute<T>(T Function(BookworldCampaignStore store) action) async {
    final support = await getApplicationSupportDirectory();
    final privateDirectory =
        support.path + Platform.pathSeparator + 'ai_story_bookworld';
    T runStore() {
      final store = BookworldCampaignStore.openPrivateDirectory(
        privateDirectory,
      );
      try {
        return action(store);
      } finally {
        store.close();
      }
    }

    if (!background) return runStore();
    return Isolate.run(runStore);
  }

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
          social: social);
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
        choiceLabel: choice.label,
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
        (choice) => WorldChoiceView(
          id: choice.id, label: choice.label,
          lockReason: choice.lockReason,
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
      npcItemOwners: Map.unmodifiable({
        if (social != null)
          for (final item in blueprint.items)
            if (social.itemOwner(item) != null &&
                social.itemOwner(item) != 'player')
              item: social.itemOwner(item)!,
      }),
      npcDisplayNames: Map.unmodifiable(npcDisplayNames),
      npcLifeStates: Map.unmodifiable({
        if (social != null && socialRules != null)
          for (final actor in socialRules.lifeTransitions
              .map((event) => event.actorId).toSet())
            actor: social.lifeState(actor).name,
      }),
    );
  }

  @override
  Future<List<WorldLibraryItem>> worlds() => _execute(
    (store) => List.unmodifiable(store.installedWorlds().map(_world)),
  );

  @override
  Future<WorldLibraryItem> install(Uint8List archive) => _execute(
    (store) => _world(store.installBookworld(archive)),
  );

  @override
  Future<List<WorldCampaignItem>> campaigns({String? worldHash}) => _execute(
    (store) => List.unmodifiable(store.campaigns()
        .where((entry) => worldHash == null || entry.worldHash == worldHash)
        .map(_campaign)),
  );

  @override
  Future<String> start(String worldHash, {String? parentCampaignId}) =>
      _execute((store) => store.createCampaign(
        worldHash, parentCampaignId: parentCampaignId,
      ));

  @override
  Future<WorldGameView> load(String campaignId) =>
      _execute((store) {
        final record = store.loadCampaign(campaignId);
        final rich = _verifiedRichContent(
          store, record.metadata.worldHash);
        return _view(record, presentation: rich.presentation,
            socialRules: rich.social);
      });

  @override
  Future<WorldChoiceResult> choose(String campaignId, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  }) => _execute((store) {
    final result = store.commitChoice(
      campaignId,
      actionId: actionId,
      choiceId: choiceId,
      expectedRevision: expectedRevision,
    );
    // A complete view is read only after the SQLite transaction returned.
    final record = store.loadCampaign(campaignId);
    final rich = _verifiedRichContent(
      store, record.metadata.worldHash);
    final view = _view(record, presentation: rich.presentation,
        socialRules: rich.social);
    return WorldChoiceResult(
      applied: result.applied,
      duplicate: result.status.name == 'duplicate',
      reason: result.reason,
      view: view,
    );
  });

  @override
  Future<String> exportSave(String campaignId) =>
      _execute((store) => store.exportPortable(campaignId));

  @override
  Future<void> deleteCampaign(String campaignId, {
    required int expectedRevision,
  }) => _execute<void>((store) => store.deleteCampaign(
    campaignId, expectedRevision: expectedRevision,
  ));

  @override
  Future<Uint8List> exportWorld(String worldHash) =>
      _execute((store) => store.exportBookworld(worldHash));

  @override
  Future<void> deleteWorld(String worldHash) =>
      _execute<void>((store) => store.deleteBookworld(worldHash));

  @override
  Future<WorldSavePreview> previewSave(String text, {
    required String expectedWorldHash,
  }) => _execute((store) {
    final verified = store.previewPortable(text);
    if (verified.worldHash != expectedWorldHash) {
      throw const FormatException(
        'Сохранение относится к другому игровому миру',
      );
    }
    return WorldSavePreview(
      sourceCampaignId: verified.sourceCampaignId,
      worldHash: verified.worldHash,
      revision: verified.revision,
      stateHash: verified.stateHash,
      isTerminal: verified.isTerminal,
    );
  });

  @override
  Future<String> importSave(String text, {
    required String expectedWorldHash,
  }) => _execute((store) {
    // This is an additional UI-level world boundary; the store verifies
    // the entire envelope and all events before committing a new campaign.
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
      throw const FormatException(
        'Сохранение относится к другому игровому миру',
      );
    }
    return store.importPortable(text);
  });
}
