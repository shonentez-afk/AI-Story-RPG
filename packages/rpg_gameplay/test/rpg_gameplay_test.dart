import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart';
import 'package:test/test.dart';

/// This runs on the SAME Python source-reviewed NPC/ownership fixture as the
/// Flutter E2E suite, but outside Flutter and without any app imports.
const _richFixture =
    '../../artifacts/bookworld/book_private_rich_items_python.bworld';

void main() {
  test('autonomous RPG engine applies signed NPC relationships, custody, '
      'journal, revision and portable SQLite save without Flutter or AI', () {
    final package = File(_richFixture).readAsBytesSync();
    final dir = Directory.systemTemp.createTempSync('rpg_gameplay_headless_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      var game = RpgGameplayEngine(store);
      final installed = game.install(Uint8List.fromList(package));
      final id = game.start(installed.archiveHash);
      final beginning = game.load(id);

      expect(beginning.campaignId, id);
      expect(beginning.sceneSource, isNotNull);
      expect(beginning.sceneSource!.chapterNumber, greaterThanOrEqualTo(1));
      expect(beginning.sceneSource!.chapterNumber,
          lessThanOrEqualTo(beginning.sceneSource!.chapterCount));
      expect(beginning.sceneSource!.sourceTitle, isNotEmpty);
      expect(beginning.revision, 0);
      expect(beginning.npcRelations, isEmpty);
      expect(beginning.npcDisplayNames, isEmpty);
      expect(beginning.npcItemOwners, isEmpty);
      expect(beginning.journal, isEmpty);
      // Source-reviewed map is granted by the first actual wait event.
      // It does NOT belong to a player at the start of the story.
      expect(beginning.inventory, isNot(contains('map')));
      expect(beginning.choices.any((choice) =>
          choice.id == 'help' && !choice.enabled), isTrue);

      // An LLM may not forge knowledge or force a locked choice.
      final prohibited = game.choose(id,
          actionId: 'headless_denied',
          choiceId: 'help', expectedRevision: 0);
      expect(prohibited.applied, isFalse);
      expect(game.load(id).revision, 0);

      final head = FreeTextWorldGatewayPort.headFromView(beginning);
      final proposed = FreeTextActionGate.previewAiChoice(
          head, 'Жду у ворот', 'wait');
      expect(proposed.canChoose, isTrue);
      final wait = proposed.offers.single;
      // No game execution until user explicitly confirms a known choice.
      expect(() => FreeTextActionGate.validate(
          current: head, proposal: wait,
          actionId: 'headless_wait',
          userConfirmed: false), throwsFormatException);
      FreeTextActionGate.validate(current: head, proposal: wait,
          actionId: 'headless_wait', userConfirmed: true);

      expect(game.choose(id,
          actionId: 'headless_wait', choiceId: 'wait',
          expectedRevision: 0).applied, isTrue);
      final met = game.load(id);
      expect(met.revision, 1);
      expect(met.inventory, contains('map'),
          reason: 'Only committed source-bound wait grants the map');
      expect(met.choices.firstWhere((choice) => choice.id == 'give_map')
          .requiredItemIds, contains('map'),
          reason: 'Only signed has_item may expose item-dependent actions');
      expect(met.npcRelations, isNotEmpty);
      expect(met.journal, hasLength(1));

      // A proposal from the previous SQLite revision cannot execute now.
      expect(() => FreeTextActionGate.validate(
          current: FreeTextWorldGatewayPort.headFromView(met),
          proposal: wait, actionId: 'headless_stale',
          userConfirmed: true), throwsFormatException);

      final transfer = game.choose(id,
          actionId: 'headless_transfer', choiceId: 'give_map',
          expectedRevision: 1);
      expect(transfer.applied, isTrue);
      final committed = game.load(id);
      expect(committed.revision, 2);
      expect(committed.npcItemOwners['map'], isNotNull);
      expect(committed.inventory, isNot(contains('map')));
      expect(committed.journal.last.changes,
          contains('Передано персонажу: Карта'));

      final portable = game.exportSave(id);
      final preview = game.previewSave(portable,
          expectedWorldHash: installed.archiveHash);
      expect(preview.revision, 2);
      expect(() => game.previewSave(portable,
          expectedWorldHash: '0' * 64), throwsFormatException);

      // Real SQLite restart, then a separately imported signed campaign.
      store.close();
      store = null;
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      game = RpgGameplayEngine(store);
      final reopened = game.load(id);
      expect(reopened.revision, 2);
      expect(reopened.npcItemOwners, committed.npcItemOwners);
      expect(
          jsonEncode(reopened.journal
              .map((entry) => entry.changes.toList()).toList()),
          jsonEncode(committed.journal
              .map((entry) => entry.changes.toList()).toList()),
          reason: 'Replayed journal must match exact event order and text');
      final imported = game.importSave(portable,
          expectedWorldHash: installed.archiveHash);
      expect(imported, isNot(id));
      final restored = game.load(imported);
      expect(restored.revision, reopened.revision);
      expect(restored.npcRelations.map((n) => n.actorId).toList(),
          reopened.npcRelations.map((n) => n.actorId).toList());
      expect(restored.npcItemOwners, reopened.npcItemOwners);
      expect(restored.journal.map((e) => e.choiceLabel).toList(),
          reopened.journal.map((e) => e.choiceLabel).toList());
      expect(restored.sceneId, reopened.sceneId);
      expect(restored.sceneSource?.chapterIndex,
          reopened.sceneSource?.chapterIndex);
      expect(restored.sceneSource?.isSourcePassage,
          reopened.sceneSource?.isSourcePassage);
    } finally {
      store?.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('headless story projection never assigns an ambiguous or hidden NPC '
      'portrait, without requiring Flutter widget state', () {
    const known = NpcRelationView(
      actorId: 'npc_aaaaaaaaaaaaaaaaaaaa',
      displayName: 'Мария', directedScore: 2,
      memoryCount: 1, memoryKinds: {'witnessed': 1},
    );
    const other = NpcRelationView(
      actorId: 'npc_bbbbbbbbbbbbbbbbbbbb',
      displayName: 'Мария', directedScore: 2,
      memoryCount: 1, memoryKinds: {'helped': 1},
    );
    WorldGameView view({
      bool reviewed = false, List<NpcRelationView> seen = const [],
      Map<String, String> visible = const {},
    }) => WorldGameView(
      campaignId: 'game', worldTitle: 'Book',
      sceneId: 'entry', sceneText: 'story', revision: 0,
      tick: 0, isTerminal: false, stats: const {},
      inventory: const [], flags: const {}, knownFacts: const [],
      choices: const [], journal: const [], npcRelations: seen,
      sceneSpeakerIdentityReviewed: reviewed,
      visibleSpeakerActorIds: visible,
    );
    expect(view(seen: [known, other])
        .portraitStorageKeyFor('Мария'), isNull);
    expect(view(reviewed: true, seen: [known])
        .portraitStorageKeyFor('Мария'), isNull);
    expect(view(reviewed: true, seen: [known],
        visible: {'Мария': known.actorId})
        .portraitStorageKeyFor('Мария'), known.actorId);
  });
}
