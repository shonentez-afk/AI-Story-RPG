import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
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
    required this.choiceLabel,
  });

  final int sequence;
  final String sceneId;
  final String choiceLabel;
}

class WorldGameView {
  const WorldGameView({
    required this.campaignId, required this.worldTitle,
    required this.sceneId, required this.sceneText,
    required this.revision, required this.tick, required this.isTerminal,
    required this.stats, required this.inventory,
    required this.flags, required this.knownFacts,
    required this.choices, required this.journal,
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

  static WorldGameView _view(CampaignRecord record) {
    final coordinator = record.coordinator;
    final blueprint = coordinator.blueprint;
    final state = coordinator.state;
    final current = blueprint.scenes[coordinator.sceneId]!;
    final journal = [
      for (final event in coordinator.events)
        WorldEventView(
          sequence: event.sequence,
          sceneId: event.sceneId,
          choiceLabel: blueprint.scenes[event.sceneId]!.choices
              .firstWhere((choice) => choice.id == event.choiceId).label,
        ),
    ];
    return WorldGameView(
      campaignId: record.metadata.id,
      worldTitle: blueprint.title,
      sceneId: current.id,
      sceneText: current.text,
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
      _execute((store) => _view(store.loadCampaign(campaignId)));

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
    final view = _view(store.loadCampaign(campaignId));
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
