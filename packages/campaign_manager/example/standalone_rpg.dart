// Standalone, ordinary Dart usage of the reusable RPG packages.
// No Flutter, AI service, app code, platform UI or application imports.
// Run from packages/campaign_manager:
//   dart run example/standalone_rpg.dart ../../artifacts/bookworld/manor_m17_original_demo.bworld
import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:story_core/story_core.dart';
import 'package:story_runtime_adapter/story_runtime_adapter.dart';

void requireState(bool value, String description) {
  if (!value) throw StateError(description);
}

DecisionResult play(BookworldCampaignStore store, String campaignId,
    String actionId, String choiceId) {
  final current = store.loadCampaign(campaignId);
  final StoryRuntimeAdapter runtime = current.coordinator;
  final matches = runtime.choices.where((choice) => choice.id == choiceId);
  requireState(matches.length == 1 && matches.single.enabled,
      'Choice not available: ' + choiceId);
  final accepted = store.commitChoice(campaignId,
      actionId: actionId, choiceId: choiceId,
      expectedRevision: runtime.state.revision);
  requireState(accepted.applied, 'Core rejected action: ' + choiceId);
  return accepted;
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run example/standalone_rpg.dart <verified_demo.bworld>');
    exitCode = 64;
    return;
  }
  // Explicit application-provided path: the packages do not read UI state.
  final bytes = File(args.single).readAsBytesSync();
  final verified = const BookworldImporter().inspect(bytes);
  requireState(verified.blueprint.entrySceneId == 'gate',
      'Expected the independent sample world, not a different book');

  final directory = Directory.systemTemp.createTempSync('dart_rpg_engine_');
  BookworldCampaignStore? store;
  try {
    store = BookworldCampaignStore.openPrivateDirectory(directory.path);
    final installed = store.installBookworld(bytes);
    requireState(installed.blueprintHash == verified.blueprint.blueprintHash,
        'Imported and installed verified blueprints disagree');
    final campaignId = store.createCampaign(installed.archiveHash);
    final start = store.loadCampaign(campaignId);
    final StoryRuntimeAdapter firstView = start.coordinator;
    requireState(firstView.sceneId == 'gate' && firstView.sceneText.isNotEmpty,
        'No scene presentation available');
    requireState(firstView.choices.any((choice) =>
        choice.id == 'enter_hall' && !choice.enabled),
        'Locked choice was exposed as playable');

    // The only writer of state is the existing verified story_core/adapter.
    for (var i = 0; i < 20; i++) {
      play(store, campaignId, 'inspect_' + i.toString(), 'inspect_gate');
    }
    play(store, campaignId, 'market_1', 'walk_market');
    play(store, campaignId, 'trust', 'ask_guard');
    play(store, campaignId, 'market_2', 'walk_market');
    play(store, campaignId, 'map', 'buy_map');
    play(store, campaignId, 'market_3', 'walk_market');
    play(store, campaignId, 'key', 'find_key');
    play(store, campaignId, 'hall', 'enter_hall');
    play(store, campaignId, 'secret', 'learn_from_guard');
    play(store, campaignId, 'note', 'write_note');
    play(store, campaignId, 'cellar', 'go_cellar');
    play(store, campaignId, 'vault', 'open_vault');

    final beforeRestart = store.loadCampaign(campaignId);
    final current = beforeRestart.coordinator;
    requireState(current.sceneId == 'archive', 'Story did not reach archive');
    requireState(current.state.inventory.contains('map') &&
        !current.state.inventory.contains('key'),
        'Verified inventory effects were not applied');
    requireState(current.state.knowledge['player']!.contains('archive_origin') &&
        current.state.flags['notes_ready'] == true,
        'Knowledge and journal flags did not survive choices');
    requireState(current.choices.any((choice) =>
        choice.id == 'publish_archive' && choice.enabled),
        'Newly unlocked choice is missing');
    final stateHash = beforeRestart.metadata.stateHash;
    final revision = beforeRestart.metadata.revision;
    final portable = store.exportPortable(campaignId);
    store.close();
    store = null;

    // Actual DB close/open and portable save import: no app-owned persistence.
    store = BookworldCampaignStore.openPrivateDirectory(directory.path);
    final resumed = store.loadCampaign(campaignId);
    requireState(resumed.metadata.stateHash == stateHash &&
        resumed.metadata.revision == revision &&
        resumed.coordinator.sceneText == current.sceneText,
        'Disk restart did not deterministically recover state and scene');
    final importedId = store.importPortable(portable);
    final imported = store.loadCampaign(importedId);
    requireState(imported.metadata.stateHash == stateHash &&
        imported.coordinator.state.stateHash == resumed.coordinator.state.stateHash,
        'Portable save replay differs from disk restart');

    final ended = play(store, campaignId, 'finish', 'publish_archive');
    final endedCopy = play(store, importedId, 'finish', 'publish_archive');
    requireState(ended.event!.hash == endedCopy.event!.hash,
        'Same confirmed input did not deterministically replay');
    final finalGame = store.loadCampaign(campaignId);
    requireState(finalGame.coordinator.isTerminal &&
        finalGame.coordinator.sceneId == 'end_reveal' &&
        finalGame.coordinator.state.flags['revealed'] == true,
        'Restored campaign did not finish correctly');
    requireState(store.loadCampaign(importedId).metadata.stateHash ==
        finalGame.metadata.stateHash,
        'Independent portable campaign ended in different state');

    stdout.writeln(jsonEncode({
      'demo': 'standalone_pure_dart_rpg',
      'verified_world': installed.bookworldId,
      'scenario_text': firstView.sceneText,
      'state_revision': finalGame.metadata.revision,
      'final_scene': finalGame.coordinator.sceneId,
      'final_hash': finalGame.metadata.stateHash,
      'portable_save_restored': true,
      'sqlite_restart_restored': true,
      'deterministic_replay': true,
      'flutter_required': false,
      'ai_required': false
    }));
  } finally {
    store?.close();
    directory.deleteSync(recursive: true);
  }
}
