// Private route discovery + whole-book *PLAYABLE CHAPTER* proof.
//
// Uses ONLY the same LocalRpgGameApi/SQLite implementation used by Flutter.
// No Python game state simulation. An optional source map, derived from the
// signed native BookWorld provenance, asks the Dart engine to prove that at
// least one ORIGINAL scene in EVERY chapter is reachable through real choices.
// The chapter proof is an existential UNION across playable branches; it does
// NOT certify that one route reads the entire book or that prose is canonical.
// No private text, dialogue or saves are printed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['format'] != 'rpg_author_native_route_discovery_v1' ||
      input['archive_b64'] is! String) {
    throw const FormatException('Invalid native route discovery request');
  }

  final strictCoverage = input.containsKey('source_chapters_total');
  final byScene = <String, int>{};
  var totalChapters = 0;
  if (strictCoverage) {
    final count = input['source_chapters_total'];
    final rows = input['source_passages'];
    if (count is! int || count < 1 || count > 10000 ||
        rows is! List || rows.isEmpty || rows.length > 10000) {
      throw const FormatException('Invalid checked chapter source map');
    }
    totalChapters = count;
    final represented = <int>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row.keys.toSet().difference({'scene_id', 'chapter_index'}).isNotEmpty ||
          row.length != 2 ||
          row['scene_id'] is! String || row['chapter_index'] is! int) {
        throw const FormatException('Invalid original source scene proof');
      }
      final scene = row['scene_id'] as String;
      final chapter = row['chapter_index'] as int;
      if (scene.isEmpty || chapter < 0 || chapter >= count ||
          byScene.containsKey(scene)) {
        throw const FormatException('Duplicate or incorrect original source scene');
      }
      byScene[scene] = chapter;
      represented.add(chapter);
    }
    if (represented.length != count) {
      throw const FormatException('Native source map omits original book chapters');
    }
  }

  final world = Uint8List.fromList(base64Decode(input['archive_b64'] as String));
  final temp = Directory.systemTemp.createTempSync('rpg_discover_private_');
  BookworldCampaignStore? store;
  try {
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    final RpgGameApi api = LocalRpgGameApi(store);
    final installed = api.install(world);
    // Native start(parentCampaignId:) clones the exact verified campaign head.
    // Old discovery started a fresh game and replayed the ENTIRE path for
    // every BFS state: quadratic replay amplified by long books. Never
    // simulate a rule or invent a state hash here; fork the REAL SQLite
    // campaign through LocalRpgGameApi and choose one enabled action.
    final rootCampaign = api.start(installed.archiveHash);
    // A native depth-first frontier reaches a complete long-book route
    // before expanding every alternate choice at each of 200+ chapters.
    // Every transition STILL goes through LocalRpgGameApi and SQLite.
    // Choose() returns the checked view: do not replay it redundantly.
    final frontier = <({
      String campaignId, List<String> path, WorldGameView view
    })>[
      (campaignId: rootCampaign, path: <String>[],
       view: api.load(rootCampaign)),
    ];
    var cursor = 0;
    final endings = <String>{};
    final found = <Map<String, Object?>>[];
    final explored = <String>{};
    final reachedChapters = <int>{};
    final reachedOriginalScenes = <String>{};
    const maxNodes = 3000;
    const maxSteps = 512;

    while (frontier.isNotEmpty && cursor < maxNodes &&
           (found.length < 2 ||
            (strictCoverage && reachedChapters.length < totalChapters))) {
      final current = frontier.removeLast();
      cursor++;
      final path = current.path;
      final campaign = current.campaignId;
      final state = current.view;

      if (strictCoverage) {
        final chapter = byScene[state.sceneId];
        if (chapter != null) {
          reachedChapters.add(chapter);
          reachedOriginalScenes.add(state.sceneId);
        }
      }
      if (state.isTerminal) {
        if (endings.add(state.sceneId) && path.isNotEmpty &&
            found.length < 2) {
          found.add({
            'id': 'route_' + (found.length + 1).toString(),
            'choice_ids': path,
            'expected_ending_scene_id': state.sceneId,
          });
        }
        continue;
      }
      if (path.length >= maxSteps) continue;
      final enabled = state.choices.where((c) => c.enabled).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      // Use the genuine *native* state hash only when states may fork or
      // converge. A forced single-choice corridor cannot produce another
      // distinct local outcome; skipping its redundant SQLite load is safe.
      // If a loop exists, the strict 512-step/3000-node limits still fail
      // closed rather than incorrectly claiming complete chapter coverage.
      if (enabled.length != 1) {
        final hash = store.loadCampaign(campaign).metadata.stateHash;
        if (!explored.add(hash)) continue;
      }
      // Reverse the stable sort when pushing a LIFO frontier so the first
      // lexical choice is explored FIRST. This finds full playable endings
      // without an exponential breadth-wise explosion in a long corridor.
      for (final choice in enabled.reversed) {
        if (cursor + frontier.length >= maxNodes) break;
        // A deterministic one-choice corridor needs no clone: this BFS
        // node has exactly one successor and will never be reused. Mutating
        // its own native campaign is safe and avoids O(n^2) SQLite history
        // copying along 200+ chapter novels. Fork ONLY genuine branches.
        final forked = enabled.length == 1
            ? campaign
            : api.start(installed.archiveHash,
                parentCampaignId: campaign);
        final outcome = api.choose(forked,
            actionId: 'discover_' + state.revision.toString(),
            choiceId: choice.id, expectedRevision: state.revision);
        if (!outcome.applied) {
          throw const FormatException('Native fork refused enabled decision');
        }
        frontier.add((campaignId: forked,
                      path: [...path, choice.id], view: outcome.view));
      }
    }
    if (found.length != 2) {
      // Source-safe failure metadata is essential for distinguishing a
      // real unplayable branch from an exhausted bounded exploration.
      // Only numeric counters and opaque game scene IDs; no book prose,
      // NPC secrets or portable saves are printed.
      final sortedChapters = reachedChapters.toList()..sort();
      final lastChapter = sortedChapters.isEmpty ? -1 : sortedChapters.last;
      final verifiedEndings = endings.toList()..sort();
      throw FormatException(
          'Two distinct reachable native endings were not found in budget'
          ' explored=$cursor/$maxNodes frontier=${frontier.length}'
          ' terminals=$verifiedEndings'
          ' reachable_chapters=${reachedChapters.length}/$totalChapters'
          ' last_reached_chapter=$lastChapter');
    }
    if (strictCoverage && reachedChapters.length != totalChapters) {
      final missing = [
        for (var chapter = 0; chapter < totalChapters; chapter++)
          if (!reachedChapters.contains(chapter)) chapter,
      ];
      throw FormatException(
          'Source chapters not playable via native RPG API: $missing '
          '(bounded native search; cannot certify completeness)');
    }
    stdout.write(jsonEncode({
      'format': 'rpg_author_native_two_discovered_routes_v1',
      'archive_sha256': installed.archiveHash,
      'routes': found,
      'explored_states': cursor,
      'deduplicated_branch_states': explored.length,
      'true_rpg_api': true,
      'native_world_readonly': true,
      'native_source_chapter_coverage': strictCoverage,
      'source_chapters_total': strictCoverage ? totalChapters : 0,
      'reachable_source_chapters':
          (reachedChapters.toList()..sort()),
      'reachable_original_scene_count': reachedOriginalScenes.length,
      'source_passage_scene_count': byScene.length,
    }));
  } finally {
    store?.close();
    temp.deleteSync(recursive: true);
  }
}
