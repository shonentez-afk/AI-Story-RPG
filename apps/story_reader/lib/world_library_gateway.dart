import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rpg_api/rpg_api.dart';

export 'package:rpg_api/rpg_api.dart' show
    WorldLibraryItem, WorldCampaignItem, WorldSavePreview,
    WorldChoiceView, WorldEventView, NpcRelationView, WorldGameView,
    WorldSceneSourceView,
    WorldChoiceResult, WorldLibraryGateway,
    WorldDynamicActionGateway, FreeformActionPreview;

/// Platform transport only. It owns application storage path and isolate
/// scheduling; game/NPC/journal/save rules belong to the independent API.
/// The same headless RpgGameplayEngine powers tests, CLI and Flutter.
class DeviceWorldLibraryGateway implements WorldLibraryGateway,
    WorldDynamicActionGateway {
  const DeviceWorldLibraryGateway({this.background = true});

  /// Production uses independent worker isolates. Host widget tests may
  /// explicitly use the same real SQLite store inline.
  final bool background;

  Future<T> _execute<T>(T Function(RpgGameApi engine) action) async {
    final support = await getApplicationSupportDirectory();
    final privateDirectory =
        support.path + Platform.pathSeparator + 'ai_story_bookworld';
    T runEngine() {
      final store = BookworldCampaignStore.openPrivateDirectory(
          privateDirectory);
      try {
        return action(LocalRpgGameApi(store));
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
  Future<FreeformActionPreview> previewDynamic(
      String campaignId, FreeformActionDraft draft, {
      required int expectedRevision}) =>
      _execute((game) => (game as RpgDynamicGameApi)
          .previewFreeform(campaignId, draft,
              expectedRevision: expectedRevision));

  @override
  Future<WorldChoiceResult> commitDynamic(String campaignId, {
    required String actionId,
    required FreeformActionDraft draft,
    required int expectedRevision,
    required String approvalDigest,
    required bool userConfirmed,
  }) => _execute((game) => (game as RpgDynamicGameApi)
      .commitFreeform(campaignId,
          actionId: actionId, draft: draft,
          expectedRevision: expectedRevision,
          approvalDigest: approvalDigest,
          userConfirmed: userConfirmed));

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
