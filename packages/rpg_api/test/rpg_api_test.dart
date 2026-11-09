import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:story_authoring/story_authoring.dart' show BookImporter, BookSourceIndexer;
import 'package:test/test.dart';

Uint8List _bytes(String source) =>
    Uint8List.fromList(utf8.encode(source));

void main() {
  test('generator v4 acceptance report is SHA-bound; import stays engine-owned',
      () {
    const RpgWorldIntakeApi api = LocalRpgWorldIntakeApi();
    final richV3 = Uint8List.fromList(File(
      '../../artifacts/bookworld/book_private_rich_items_python.bworld')
        .readAsBytesSync());
    final v3 = api.inspect(richV3);
    expect(v3.formatVersion, 3);
    expect(v3.isPrivate, true);
    expect(v3.generatorReportAttached, false);
    expect(v3.literaryCanonProven, false);
    final bytes = Uint8List.fromList(File(
      '../../artifacts/bookworld/book_private_extended_dart.bworld')
        .readAsBytesSync());
    final v4 = api.inspect(bytes);
    expect(v4.formatVersion, 4);
    expect(v4.sceneCount, greaterThanOrEqualTo(3));
    expect(v4.endingCount, greaterThanOrEqualTo(2));
    expect(v4.sourceFingerprint, isNotNull);
    final world = const LocalRpgAuthoringApi().inspectPrivateWorld(bytes);
    final terminals = world.blueprint.scenes.entries
        .where((entry) => entry.value.terminal)
        .map((entry) => entry.key).toList();
    expect(terminals, hasLength(greaterThanOrEqualTo(2)));
    final routes = [
      for (var i = 0; i < 2; i++) {
        'route_id': 'route_${i+1}',
        'ending_scene_id': terminals[i],
        'replayed_choices': 2,
        'portable_save_verified': true,
        'native_state_sha256': i == 0 ? 'a' * 64 : 'b' * 64,
      },
    ];
    final source = {
      'verified_scene_review_records': v4.sceneCount,
      'source_evidence_binds_exact_revision': true,
      'review_report_complete': true,
      'literary_truth_attested': false,
      'reviewed_full_routes': 2,
      'reviewed_distinct_ending_scenes': 2,
      'reviewed_book_chapters': 3,
      'source_chapters_with_gameplay': 3,
    };
    Map<String, dynamic> report() => {
      'format': 'rpg_author_complete_native_campaign_acceptance_v1',
      'status': 'native_multi_act_campaign_mechanically_verified',
      'format_version': 4,
      'archive_sha256': v4.archiveHash,
      'source_fingerprint': v4.sourceFingerprint,
      'private_only': true,
      'literary_truth_attested': false,
      'automatic_ai_book_canon_verified': false,
      'user_ready': false,
      'source_review': source,
      'reviewed_extension': {
        'act_count': 2, 'chapters_without_source_scenes': [],
      },
      'native_routes': {
        'status': 'two_complete_routes_native_rpg_api_and_sqlite_verified',
        'archive_sha256': v4.archiveHash,
        'route_count': 2, 'endings_verified': 2,
        'native_game_rules_reused': true,
        'python_game_rule_fork_used': false,
        'routes': routes,
      },
    };
    final attached = api.inspect(bytes, readinessJson: jsonEncode(report()));
    expect(attached.generatorReportAttached, true);
    expect(attached.producerClaimsTwoReplayedRoutes, true);
    expect(attached.literaryCanonProven, false);
    for (final invalid in [
      {...report(), 'archive_sha256': '0' * 64},
      {...report(), 'source_fingerprint': '0' * 64},
      {...report(), 'user_ready': true},
      {...report(), 'format_version': 3},
      {...report(), 'source_review': {...source,
          'verified_scene_review_records': v4.sceneCount - 1}},
      {...report(), 'native_routes': {
          ...(report()['native_routes'] as Map<String, dynamic>),
          'routes': [routes.first, routes.first],
      }},
      {...report(), 'native_routes': {
          ...(report()['native_routes'] as Map<String, dynamic>),
          'routes': [{...routes.first, 'ending_scene_id': 'forged'},
                     routes.last],
      }},
    ]) {
      expect(() => api.inspect(bytes, readinessJson: jsonEncode(invalid)),
          throwsFormatException);
    }
    expect(() => api.inspect(richV3, readinessJson: jsonEncode(report())),
        throwsFormatException);
    expect(() => api.inspect(Uint8List.fromList(List.filled(40, 1))),
        throwsFormatException);
    // Same native game API as the generator's Dart probe and Flutter.
    final temp = Directory.systemTemp.createTempSync('rpg_generator_intake_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      final RpgGameApi game = LocalRpgGameApi(store);
      final installed = game.install(bytes);
      expect(installed.archiveHash, attached.archiveHash);
      final id = game.start(installed.archiveHash);
      final initial = game.load(id);
      expect(initial.revision, 0);
      expect(initial.worldTitle, attached.title);
    } finally {
      store?.close();
      temp.deleteSync(recursive: true);
    }
  });

  test('public authoring API indexes and scans without Flutter or cloud',
      () async {
    const RpgAuthoringApi api = LocalRpgAuthoringApi();
    final input = _bytes('Мария открыла дверь. Иван ждал у ворот.');
    final book = api.parseBook('story.txt', input);
    final index = api.indexBook(book);
    final source = api.inspectSource('story.txt', input);
    expect(source.index.sourceFingerprint, index.sourceFingerprint);
    expect(source.hasCompleteText, isTrue);

    OfflineScanCheckpoint? saved;
    final scan = await api.scanSource(source,
        onCheckpoint: (checkpoint) => saved = checkpoint);
    expect(scan.summary['is_playable_rpg'], false);
    expect(scan.summary['is_literary_canon'], false);
    expect(saved, isNotNull);
    final replay = await api.scanSource(source, resume: saved);
    expect(replay.summary, scan.summary);
    final prepared = await api.prepareBook(source);
    expect(prepared.status['is_playable_rpg'], false);
    expect(prepared.status['requires_cloud'], false);
    expect(prepared.readiness.canStartPlayableBook, isFalse);
    expect(prepared.sourceFingerprint, index.sourceFingerprint);
    expect(RpgApiContract.arbitraryBookCanon, isFalse);
    expect(RpgApiContract.dynamicAiGameMaster, isFalse);
  });

  test('one-book/one-tale API scopes source without changing library book',
      () async {
    const RpgAuthoringApi api = LocalRpgAuthoringApi();
    final fb2 = _bytes('<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Сказки</book-title>'
        '</title-info></description><body>'
        '<section><p>Первая история.</p></section>'
        '<section><p>Вторая история.</p></section>'
        '</body></FictionBook>');
    final complete = api.openSource('tales.fb2', fb2);
    final scoped = api.openSource('tales.fb2', fb2, selectedChapter: 1);
    expect(complete.index.chapterCount, 2);
    expect(scoped.index.chapterCount, 1);
    expect(scoped.sourceFingerprint, isNot(complete.sourceFingerprint));
    OfflineScanCheckpoint? cp;
    final prepared = await api.prepareBook(scoped,
        onCheckpoint: (value) => cp = value);
    expect(prepared.status['stage'], 'BOOK_SOURCE_PREPARED_NEEDS_REVIEW');
    expect(cp, isNotNull);
    final repeat = await api.prepareBook(scoped, resume: cp);
    expect(repeat.status, prepared.status);
    await expectLater(api.prepareBook(complete, resume: cp),
        throwsFormatException);
  });

  test('one creation contract refuses fake CANON/freeform and preserves real short modes',
      () async {
    const RpgCreationApi api = LocalRpgCreationApi();
    const follow = RpgCreationIntent.quickFollow();
    const alter = RpgCreationIntent.quickAlterFate();
    expect(RpgCreationIntent.fromJson(
      Map<String, dynamic>.from(follow.toJson())).plot,
        RpgCreationPlot.sourceExcerptRoute);
    expect(api.inspect(follow).supported, isTrue);
    expect(api.inspect(alter).supported, isTrue);
    expect(api.inspect(follow).isFullLiteraryCanon, isFalse);
    for (final denied in [
      const RpgCreationIntent(
          route: RpgCreationRoute.shortOffline,
          plot: RpgCreationPlot.canon),
      const RpgCreationIntent(
          route: RpgCreationRoute.reviewedBookwide,
          plot: RpgCreationPlot.canon),
      const RpgCreationIntent(
          route: RpgCreationRoute.reviewedBookwide,
          plot: RpgCreationPlot.freeWorld),
      const RpgCreationIntent(
          route: RpgCreationRoute.reviewedBookwide,
          plot: RpgCreationPlot.alterFate,
          interaction: RpgCreationInteraction.aiFreeform),
      const RpgCreationIntent(
          route: RpgCreationRoute.shortOffline,
          plot: RpgCreationPlot.alterFate,
          hero: RpgCreationHero.reviewedCharacterIdentity),
    ]) {
      expect(api.inspect(denied).supported, isFalse);
      expect(() => api.inspect(denied).requireSupported(),
          throwsFormatException);
    }
    expect(() => RpgCreationIntent.fromJson({
      ...follow.toJson(), 'plot': 'UNKNOWN_MODE',
    }), throwsFormatException);
    final input = _bytes(List.filled(8,
        'Герой прошёл по лесу и встретил старого друга у озера. '
        'Друг рассказал о дальнейшей дороге и решении. ').join('\n'));
    final book = BookImporter.parse('story.txt', input);
    final index = BookSourceIndexer.index(book);
    final plan = api.previewShort(index: index, intent: follow);
    expect(plan.mode, QuickRpgMode.followBook);
    await expectLater(api.compileShort(
      plan: plan, intent: alter,
      allQuotesReviewedByUser: true, privateUseConfirmed: true),
        throwsFormatException);
    await expectLater(api.compileShort(
      plan: plan, intent: follow,
      allQuotesReviewedByUser: false, privateUseConfirmed: true),
        throwsFormatException);
    final built = await api.compileShort(
      plan: plan, intent: follow,
      allQuotesReviewedByUser: true, privateUseConfirmed: true);
    expect(built.sourceFingerprint, index.sourceFingerprint);
    expect(built.archive, isNotEmpty);
    expect(built.requiresCloud, false);
    expect(built.canDistributePublicly, false);
    final another = api.previewShort(index: index, intent: alter);
    expect(another.mode, QuickRpgMode.changeFate);
  });

  test('public game API keeps signed choices, SQLite replay and portable saves',
      () {
    final archive = Uint8List.fromList(File(
        '../../artifacts/bookworld/book_private_rich_items_python.bworld')
        .readAsBytesSync());
    final directory = Directory.systemTemp.createTempSync('rpg_api_client_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(directory.path);
      RpgGameApi game = LocalRpgGameApi(store);
      final world = game.install(archive);
      final id = game.start(world.archiveHash);
      expect(game.load(id).revision, 0);
      expect(game.load(id).inventory, isNot(contains('map')));
      final denied = game.choose(id,
          actionId: 'api_denied', choiceId: 'help',
          expectedRevision: 0);
      expect(denied.applied, isFalse);
      expect(game.load(id).revision, 0);
      expect(game.choose(id, actionId: 'api_wait',
          choiceId: 'wait', expectedRevision: 0).applied, isTrue);
      expect(game.choose(id, actionId: 'api_transfer',
          choiceId: 'give_map', expectedRevision: 1).applied, isTrue);
      final committed = game.load(id);
      expect(committed.journal, hasLength(2));
      expect(committed.npcItemOwners['map'], isNotNull);
      final portable = game.exportSave(id);
      expect(game.previewSave(portable,
          expectedWorldHash: world.archiveHash).revision, 2);
      store.close();
      store = null;

      store = BookworldCampaignStore.openPrivateDirectory(directory.path);
      game = LocalRpgGameApi(store);
      expect(game.load(id).revision, 2);
      final imported = game.importSave(portable,
          expectedWorldHash: world.archiveHash);
      final recovered = game.load(imported);
      expect(recovered.sceneId, committed.sceneId);
      expect(recovered.npcItemOwners, committed.npcItemOwners);
      expect(recovered.journal.map((e) => e.choiceLabel).toList(),
          committed.journal.map((e) => e.choiceLabel).toList());
    } finally {
      store?.close();
      directory.deleteSync(recursive: true);
    }
  });
  test('complete-campaign narration API is usable without Flutter', () {
    const RpgCampaignProseApi api = LocalRpgCampaignProseApi();
    const request = '{"format":"ai_story_campaign_prose_request_v1",'
        '"batch_id":"source_scope","scenes":[{"scene_id":"entry"}]}';
    const prose = 'Старый маяк возник впереди, и его свет постепенно '
        'становился заметнее. Путник молча оценивал дорогу и ещё '
        'не принимал никакого решения, наблюдая за тихим морем.';
    final answer = jsonEncode({
      'choices': [{
        'finish_reason': 'stop',
        'message': {
          'content': jsonEncode({
            'batch_id': 'source_scope',
            'scenes': [{
              'scene_id': 'entry',
              'prose': prose,
              'uncertainty': 'Литературный смысл требует отдельной проверки.',
            }],
          }),
        },
      }],
    });
    final proposal = api.parseBatch(request, answer);
    expect(proposal.single.origin, 'ai_draft');
    expect(proposal.single.sceneId, 'entry');
    expect(() => api.parseBatch(request, answer.replaceFirst(
        'source_scope', 'forged_scope')), throwsFormatException);
    expect(LocalRpgCampaignProseApi.systemPrompt,
        contains('Никаких effects'));
  });

  test('legacy multi-act compiler is exposed via independent client API', () {
    const RpgMultiActTrialApi api = LocalRpgMultiActTrialApi();
    final archive = Uint8List.fromList(File(
        '../../artifacts/bookworld/book_private_rich_items_python.bworld')
        .readAsBytesSync());
    final expected = const LocalRpgAuthoringApi().inspectPrivateWorld(archive);
    final inspected = api.verifyPrivateWorld(archive,
        expectedSourceFingerprint: expected.sourceFingerprint);
    expect(inspected.archiveSha256, expected.archiveSha256);
    expect(inspected.sourceFingerprint, expected.sourceFingerprint);
    expect(inspected.requiresNetwork, isFalse);
    expect(inspected.canDistributePublicly, isFalse);
    expect(() => api.verifyPrivateWorld(archive,
        expectedSourceFingerprint: 'forged-foreign-book'),
        throwsFormatException);
    expect(api.compileTrial, isNotNull);
    expect(api.composePreviewPlan, isNotNull);
    expect(api.previewOneGameplay, isNotNull);
    expect(api.previewWholeGameplay, isNotNull);
    expect(api.acceptGameplay, isNotNull);
  });

  test('public workflow API exposes the same pure Dart stage coordinator', () {
    const RpgCampaignWorkflowApi flow = LocalRpgCampaignWorkflowApi();
    expect(flow, isA<ReviewedCampaignWorkflow>());
    expect(ReviewedCampaignStage.values.length, 4);
    expect(ReviewedCampaignStage.complete.name, 'complete');
  });

}
