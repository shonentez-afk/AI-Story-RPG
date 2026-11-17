import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _role = 'npc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _copy(Object? row) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(row)) as Map);

({Uint8List archive, Map<String, dynamic> index, String quote,
  Map<String, dynamic> mention}) _base() {
  final fixture = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final bp = _copy(fixture['blueprint']);
  final provenance = _copy(fixture['provenance']);
  final index = _copy(fixture['source_index']);
  (bp['initial_state'] as Map)['flags'] = {
    'helped': false, 'player_is_$_role': true,
  };
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = {
    'provider': 'none', 'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  provenance['presentation'] = {
    'hero': {
      'name': 'Подтверждённый герой',
      'description': 'Книжный персонаж в частной адаптации',
    },
    'item_names': <String, String>{},
    'item_descriptions': <String, String>{},
    'fact_names': <String, String>{},
    'stat_names': <String, String>{},
    'scene_names': {
      for (final raw in bp['scenes'] as List)
        (raw as Map)['id'] as String: 'Сцена ' + (raw['id'] as String),
    },
  };
  final origin = (provenance['scene_origins'] as List).first as Map;
  final sourceRef = (origin['source_refs'] as List).first as Map;
  final chunk = (index['chunks'] as List).singleWhere(
      (c) => (c as Map)['id'] == sourceRef['chunk_id']) as Map;
  final begin = sourceRef['start_utf16'] as int;
  final end = begin + 4;
  final snippet = (chunk['text'] as String).substring(
      begin - (chunk['start_utf16'] as int),
      end - (chunk['start_utf16'] as int));
  final mention = <String, dynamic>{
    'evidence_id': '1' * 32,
    'chunk_id': sourceRef['chunk_id'],
    'start_utf16': begin,
    'end_utf16': end,
    'evidence_sha256': sha256.convert(utf8.encode(snippet)).toString(),
  };
  return (
    archive: const RichPrivateBookworldWriter().build(
        blueprint: bp, provenance: provenance, sourceIndex: index,
        expanded: true),
    index: index, quote: sourceRef['quote_sha256'] as String,
    mention: mention,
  );
}

Map<String, dynamic> _review(
    ({Uint8List archive, Map<String, dynamic> index, String quote,
      Map<String, dynamic> mention}) base) {
  final checked = const RichPrivateBookworldImporter().inspect(base.archive);
  return {
    'format': ReviewedBookCharacterStartWriter.reviewFormat,
    'scope': ReviewedBookCharacterStartWriter.scope,
    'source_fingerprint': checked.sourceFingerprint,
    'base_archive_sha256': checked.archiveSha256,
    'character_id': _role,
    'character_group_digest': 'a' * 64,
    'hero_quote_sha256': base.quote,
    'hero_mention': base.mention,
    'literary_canon_verified': false,
    'initial_items': [{
      'item_id': 'hero_letter',
      'name': 'Письмо героя',
      'description': 'Письмо, полученное в начале истории',
      'source_quote_sha256': base.quote,
    }],
    'initial_facts': [{
      'fact_id': 'hero_opening_clue',
      'name': 'Известное герою обстоятельство',
      'source_quote_sha256': base.quote,
    }],
    'choice_gates': [{
      'scene_id': 'entry',
      'choice_id': 'help',
      'source_quote_sha256': base.quote,
      'requires_items': ['hero_letter'],
      'requires_facts': ['hero_opening_clue'],
    }],
  };
}

void main() {
  test('source reviewed character starts with actual item/fact gates and '
      'original SQLite replay with no Flutter or a model', () async {
    final base = _base();
    final review = canonicalJson(_review(base));
    final verified = const LocalRpgBookCharacterStartApi().compile(
      verifiedBaseArchive: base.archive,
      sourceIndex: base.index,
      reviewJson: review,
      approvedDigest: ReviewedBookCharacterStartWriter.digest(review),
      userConfirmed: true,
    );
    final checked = const RichPrivateBookworldImporter().inspect(verified);
    expect(checked.formatVersion, 4);
    expect(checked.blueprint.initial.flags['player_is_$_role'], true);
    expect(checked.blueprint.initial.inventory, contains('hero_letter'));
    expect(checked.blueprint.initial.knowledge['player'],
        contains('hero_opening_clue'));
    expect(checked.presentation['fact_names']['hero_opening_clue'],
        'Известное герою обстоятельство');
    final help = checked.blueprint.scenes['entry']!.choices
        .singleWhere((c) => c.id == 'help');
    expect(help.conditions.map((x) => x.op),
        containsAll(['has_item', 'knows_fact']));
    expect(checked.requiresNetwork, false);
    expect(checked.canDistributePublicly, false);

    final receipt = const LocalRpgBookCharacterStartApi().inspect(verified);
    expect(receipt['reviewed_source_character_id'], _role);
    expect(receipt['source_reviewed_start'], true);
    expect(receipt['literary_canon_verified'], false);
    final before = const LocalRpgBookCharacterStartApi()
        .inspect(base.archive);
    expect(before['source_reviewed_start'], false);
    expect(before['reviewed_source_character_id'], _role);

    final dir = await Directory.systemTemp.createTemp('hero_v4_play_');
    BookworldCampaignStore? store;
    try {
      store = BookworldCampaignStore.openPrivateDirectory(dir.path);
      final game = LocalRpgGameApi(store);
      final protocol = RpgClientProtocol(game);
      Future<Map<String, Object?>> invoke(String op,
          Map<String, Object?> args) => protocol.handle({
        'version': RpgClientProtocol.version, 'op': op, 'args': args,
      });
      final capabilities = (await invoke('capabilities', {}))['result'] as Map;
      expect(capabilities['reviewed_book_character_start'], true);
      final preview = (await invoke('inspect_character_start', {
        'archive_base64': base64Encode(base.archive),
      }))['result'] as Map;
      expect(preview['reviewed_source_character_id'], _role);
      expect(preview['source_reviewed_start'], false);
      final protocolReview = await invoke('compile_character_start', {
        'archive_base64': base64Encode(base.archive),
        'source_index': base.index,
        'review_json': review,
        'approved_digest': ReviewedBookCharacterStartWriter.digest(review),
        'user_confirmed': true,
      });
      expect(protocolReview['ok'], true);
      final protocolResult = protocolReview['result'] as Map;
      expect(protocolResult['literary_canon_verified'], false);
      expect((protocolResult['character'] as Map)['source_reviewed_start'],
          true);
      expect(base64Decode(protocolResult['archive_base64'] as String),
          verified);
      final item = game.install(verified);
      final started = game.start(item.archiveHash);
      final view = game.load(started);
      expect(view.heroSourceCharacterId, _role);
      expect(view.sourceReviewedHeroStart, true);
      expect(RpgClientProtocol.projectView(view)['hero_source_character_id'], _role);
      expect(RpgClientProtocol.projectView(view)['source_reviewed_hero_start'], true);
      expect(view.sourceReviewedHeroStart, true);
      expect(view.inventory, contains('hero_letter'));
      expect(view.knownFacts, contains('hero_opening_clue'));
      final advance = game.choose(started,
          actionId: 'confirmed_hero_choice', choiceId: 'help',
          expectedRevision: 0);
      expect(advance.applied, true);
      expect(advance.view.sourceReviewedHeroStart, true);
      final save = game.exportSave(started);
      final restored = game.importSave(save,
          expectedWorldHash: item.archiveHash);
      final replayed = game.load(restored);
      expect(replayed.stateHash, advance.view.stateHash);
      expect(replayed.inventory, contains('hero_letter'));
      expect(replayed.knownFacts, contains('hero_opening_clue'));
      expect(replayed.heroSourceCharacterId, _role);
    } finally {
      store?.close();
      await dir.delete(recursive: true);
    }
  });

  test('chapter spoilers, mismatched identity and stale approvals '
      'cannot create hero possessions or knowledge', () {
    final base = _base();
    final reviewed = _review(base);
    final writer = const LocalRpgBookCharacterStartApi();
    Uint8List compile(Map<String, dynamic> draft, {
        bool confirmed = true, String? digest}) {
      final json = canonicalJson(draft);
      return writer.compile(
          verifiedBaseArchive: base.archive,
          sourceIndex: base.index,
          reviewJson: json,
          approvedDigest: digest ??
              ReviewedBookCharacterStartWriter.digest(json),
          userConfirmed: confirmed);
    }
    expect(() => compile(reviewed, confirmed: false), throwsFormatException);
    expect(() => compile(reviewed, digest: '0' * 64), throwsFormatException);
    for (final edit in [
      {...reviewed, 'character_id': 'npc_' + 'b' * 32},
      {...reviewed, 'hero_quote_sha256': '0' * 64},
      {...reviewed, 'hero_mention': {
        ...base.mention, 'evidence_sha256': '0' * 64,
      }},
      {...reviewed, 'hero_mention': {
        ...base.mention, 'start_utf16': 9999,
      }},
      {...reviewed, 'literary_canon_verified': true},
      {...reviewed, 'initial_facts': [{
        'fact_id': 'hero_opening_clue',
        'name': 'Неизвестный секрет',
        'source_quote_sha256': '0' * 64,
      }]},
      {...reviewed, 'choice_gates': [{
        'scene_id': 'alternate_end',
        'choice_id': 'help',
        'source_quote_sha256': base.quote,
        'requires_items': ['hero_letter'],
        'requires_facts': [],
      }]},
    ]) {
      expect(() => compile(edit), throwsFormatException,
          reason: edit.toString().substring(0, 65));
    }
    // The native generic v4 initial state is NOT a fake BOOK_CHARACTER role.
    final other = File(
        '../../artifacts/bookworld/book_private_extended_dart.bworld');
    if (other.existsSync()) {
      final preview = writer.inspect(
          Uint8List.fromList(other.readAsBytesSync()));
      expect(preview['reviewed_source_character_id'], isNull);
      expect(preview['source_reviewed_start'], false);
    }
  });
}
