import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart';

export 'package:rpg_gameplay/rpg_gameplay.dart' show
    WorldLibraryItem, WorldCampaignItem, WorldSavePreview,
    WorldChoiceView, WorldEventView, NpcRelationView, WorldGameView,
    WorldChoiceResult, WorldLibraryGateway;

/// Platform transport only. It owns application storage path and isolate
/// scheduling; ALL game, NPC, journal and save logic is in rpg_gameplay.
/// The same headless RpgGameplayEngine powers tests, CLI and Flutter.
class DeviceWorldLibraryGateway implements WorldLibraryGateway {
  const DeviceWorldLibraryGateway({this.background = true});

  /// Production uses independent worker isolates. Host widget tests may
  /// explicitly use the same real SQLite store inline.
  final bool background;

  Future<T> _execute<T>(T Function(RpgGameplayEngine engine) action) async {
    final support = await getApplicationSupportDirectory();
    final privateDirectory =
        support.path + Platform.pathSeparator + 'ai_story_bookworld';
    T runEngine() {
      final store = BookworldCampaignStore.openPrivateDirectory(
          privateDirectory);
      try {
        return action(RpgGameplayEngine(store));
      } finally {
        store.close();
      }
    }
    if (!background) return runEngine();
    return Isolate.run(runEngine);
  }

  @override
  Future<List<WorldLibraryItem>> worlds() =>
      _execute((engine) => engine.worlds());

  @override
  Future<WorldLibraryItem> install(Uint8List archive) =>
      _execute((engine) => engine.install(archive));

  @override
  Future<List<WorldCampaignItem>> campaigns({String? worldHash}) =>
      _execute((engine) => engine.campaigns(worldHash: worldHash));

  @override
  Future<String> start(String worldHash, {String? parentCampaignId}) =>
      _execute((engine) => engine.start(
          worldHash, parentCampaignId: parentCampaignId));

  @override
  Future<WorldGameView> load(String campaignId) =>
      _execute((engine) => engine.load(campaignId));

  @override
  Future<WorldChoiceResult> choose(String campaignId, {
    required String actionId, required String choiceId,
    required int expectedRevision,
  }) => _execute((engine) => engine.choose(campaignId,
      actionId: actionId, choiceId: choiceId,
      expectedRevision: expectedRevision));

  @override
  Future<String> exportSave(String campaignId) =>
      _execute((engine) => engine.exportSave(campaignId));

  @override
  Future<WorldSavePreview> previewSave(String text, {
    required String expectedWorldHash,
  }) => _execute((engine) => engine.previewSave(
      text, expectedWorldHash: expectedWorldHash));

  @override
  Future<void> deleteCampaign(String campaignId, {
    required int expectedRevision,
  }) => _execute<void>((engine) => engine.deleteCampaign(
      campaignId, expectedRevision: expectedRevision));

  @override
  Future<Uint8List> exportWorld(String worldHash) =>
      _execute((engine) => engine.exportWorld(worldHash));

  @override
  Future<void> deleteWorld(String worldHash) =>
      _execute<void>((engine) => engine.deleteWorld(worldHash));

  @override
  Future<String> importSave(String text, {
    required String expectedWorldHash,
  }) => _execute((engine) => engine.importSave(
      text, expectedWorldHash: expectedWorldHash));
}
