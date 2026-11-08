// Headless role-playing application client (no Flutter, AI, app imports).
// From packages/rpg_gameplay:
//   dart run example/standalone_gameplay.dart \
//     ../../artifacts/bookworld/book_private_rich_items_python.bworld
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart';

void must(bool condition, String why) {
  if (!condition) throw StateError(why);
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run example/standalone_gameplay.dart <source-reviewed.bworld>');
    exitCode = 64;
    return;
  }
  final raw = Uint8List.fromList(File(args.single).readAsBytesSync());
  final dir = Directory.systemTemp.createTempSync('ai_story_headless_');
  BookworldCampaignStore? store;
  try {
    store = BookworldCampaignStore.openPrivateDirectory(dir.path);
    var game = RpgGameplayEngine(store);
    final installed = game.install(raw);
    final campaignId = game.start(installed.archiveHash);
    final start = game.load(campaignId);
    must(start.revision == 0 && start.journal.isEmpty,
        'Initial headless RPG state missing');

    final proposal = FreeTextActionGate.previewAiChoice(
        FreeTextWorldGatewayPort.headFromView(start),
        'Жду у ворот', 'wait').offers.single;
    FreeTextActionGate.validate(
        current: FreeTextWorldGatewayPort.headFromView(start),
        proposal: proposal, actionId: 'headless_turn_1',
        userConfirmed: true);
    must(game.choose(campaignId, actionId: 'headless_turn_1',
        choiceId: 'wait', expectedRevision: 0).applied,
        'Could not commit signed NPC social event');
    must(game.choose(campaignId, actionId: 'headless_turn_2',
        choiceId: 'give_map', expectedRevision: 1).applied,
        'Could not transfer the owned item');

    final committed = game.load(campaignId);
    must(committed.npcRelations.isNotEmpty &&
        committed.npcItemOwners['map'] != null &&
        committed.journal.length == 2 &&
        !committed.inventory.contains('map'),
        'RPG mechanics did not project from SQLite');
    final portable = game.exportSave(campaignId);
    store.close();
    store = null;

    store = BookworldCampaignStore.openPrivateDirectory(dir.path);
    game = RpgGameplayEngine(store);
    must(game.load(campaignId).revision == 2,
        'SQLite restart did not recover the campaign');
    final imported = game.importSave(portable,
        expectedWorldHash: installed.archiveHash);
    final replayed = game.load(imported);
    must(replayed.journal.length == 2 &&
        replayed.npcItemOwners['map'] ==
            committed.npcItemOwners['map'],
        'Portable campaign diverged from original');
    stdout.writeln(jsonEncode({
      'engine': 'rpg_gameplay + story_core + campaign_manager',
      'npc_count': replayed.npcRelations.length,
      'revision': replayed.revision,
      'item_custody': replayed.npcItemOwners,
      'journal_entries': replayed.journal.length,
      'portable_save_verified': true,
      'sqlite_restart_verified': true,
      'flutter_required': false,
      'cloud_ai_required': false,
    }));
  } finally {
    store?.close();
    dir.deleteSync(recursive: true);
  }
}
