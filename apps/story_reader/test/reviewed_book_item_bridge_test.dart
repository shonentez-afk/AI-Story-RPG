import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/reviewed_book_item_bridge.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _npc = 'npc_cccccccccccccccccccccccccccccccc';
const _path = '../../shared_schemas/fixtures/private_classic_sample.json';

Map<String, dynamic> _fixture() {
  final raw = jsonDecode(File(_path).readAsStringSync())
      as Map<String, dynamic>;
  final bp = raw['blueprint'] as Map<String, dynamic>;
  final prov = raw['provenance'] as Map<String, dynamic>;
  (bp['actors'] as List).add(_npc);
  (bp['initial_state'] as Map)['knowledge'][_npc] = <String>[];
  final scene = (bp['scenes'] as List).first as Map<String, dynamic>;
  (scene['choices'] as List).addAll([
    {
      'id': 'give_map', 'label': 'Передать карту Марии',
      'next_scene_id': 'entry', 'conditions': <Object>[],
      'effects': <Object>[],
    },
    {
      'id': 'return_map', 'label': 'Получить карту у Марии',
      'next_scene_id': 'entry', 'conditions': <Object>[],
      'effects': <Object>[],
    },
  ]);
  expect(prov['scene_origins'], isNotEmpty);
  return raw;
}

List<Map<String, dynamic>> _review(Map<String, dynamic> fixture) {
  final origin = ((fixture['provenance'] as Map)['scene_origins'] as List)
      .first as Map;
  final quote = (origin['source_refs'] as List)
      .first['quote_sha256'] as String;
  return [
    {
      'item_name': 'Карта двора',
      'item_description': 'Карта, передаваемая персонажу',
      'actor_id': _npc,
      'acquire_choice_id': 'wait',
      'acquire_quote_sha256': quote,
      'give_choice_id': 'give_map',
      'give_quote_sha256': quote,
      'return_choice_id': 'return_map',
      'return_quote_sha256': quote,
      'personally_witnessed': true,
    },
  ];
}

void main() {
  test('reviewed book item flows through actual game choices and NPC custody',
      () {
    final fixture = _fixture();
    final bp = fixture['blueprint'] as Map<String, dynamic>;
    final prov = fixture['provenance'] as Map<String, dynamic>;
    final beforeId = bp['book_id'];
    final compiled = ReviewedBookItemBridge.apply(
      blueprint: bp, provenance: prov,
      npcSocial: null, reviewedItems: _review(fixture),
    );
    expect(bp['book_id'], isNot(beforeId));
    expect(prov['bookworld_id'], bp['book_id']);
    final itemId = (bp['items'] as List).single as String;
    expect(compiled.names[itemId], 'Карта двора');
    expect(compiled.descriptions[itemId], contains('передаваемая'));
    expect(compiled.social!['format'],
        RichNpcSocialContract.authoredItemFormat);
    final blueprint = StoryBlueprint.fromJson(bp);
    final signed = RichNpcSocialContract.inspect(
        {...prov, 'npc_social': compiled.social},
        {'npc_social_format': RichNpcSocialContract.authoredItemFormat},
        blueprint)!;
    expect(signed.itemTransfers, hasLength(2));
    final world = StoryWorld(blueprint, socialRulebook: signed);
    expect(world.apply(actionId: 'phantom', choiceId: 'return_map').applied,
        false);
    expect(world.apply(actionId: 'get', choiceId: 'wait').applied, true);
    expect(world.apply(actionId: 'give', choiceId: 'give_map').applied, true);
    expect(NpcSocialLedger.inspect(world, signed).itemOwner(itemId), _npc);
    expect(world.state.inventory, isNot(contains(itemId)));
    expect(world.apply(actionId: 'dup', choiceId: 'wait').applied, false);
    expect(world.apply(actionId: 'return', choiceId: 'return_map').applied,
        true);
    final replay = StoryWorld.replay(
      blueprint, world.events.map((event) => event.toJson()),
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
      socialRulebook: signed,
    );
    expect(NpcSocialLedger.inspect(replay, signed).itemOwner(itemId),
        'player');

    final second = _fixture();
    final copy = ReviewedBookItemBridge.apply(
      blueprint: second['blueprint'] as Map<String, dynamic>,
      provenance: second['provenance'] as Map<String, dynamic>,
      npcSocial: null, reviewedItems: _review(second),
    );
    expect((second['blueprint'] as Map)['book_id'], bp['book_id']);
    expect(copy.names.keys.single, itemId);
  });

  test('unconfirmed item or altered quote cannot mint an RPG object', () {
    for (final mutation in [
      'not_witnessed', 'wrong_actor', 'unknown_choice', 'unknown_quote',
      'duplicate_choice', 'wrong_chapter', 'same_transfer', 'duplicate_item',
    ]) {
      final fixture = _fixture();
      final review = _review(fixture);
      final first = review.single;
      switch (mutation) {
        case 'not_witnessed':
          first['personally_witnessed'] = false;
        case 'wrong_actor':
          first['actor_id'] = 'npc_' + 'a' * 32;
        case 'unknown_choice':
          first['acquire_choice_id'] = 'not_in_book';
        case 'unknown_quote':
          first['give_quote_sha256'] = 'f' * 64;
        case 'duplicate_choice':
          first['give_choice_id'] = 'wait';
        case 'wrong_chapter':
          first['return_quote_sha256'] = 'f' * 64;
        case 'same_transfer':
          first['return_choice_id'] = 'give_map';
        case 'duplicate_item':
          review.add(Map<String, dynamic>.from(first));
      }
      expect(() => ReviewedBookItemBridge.apply(
        blueprint: fixture['blueprint'] as Map<String, dynamic>,
        provenance: fixture['provenance'] as Map<String, dynamic>,
        npcSocial: null, reviewedItems: review,
      ), throwsFormatException, reason: mutation);
    }
  });

  test('no book-item selection leaves old worlds unchanged', () {
    final fixture = _fixture();
    final bp = fixture['blueprint'] as Map<String, dynamic>;
    final oldBookId = bp['book_id'];
    final result = ReviewedBookItemBridge.apply(
      blueprint: bp, provenance: fixture['provenance'] as Map<String, dynamic>,
      npcSocial: null, reviewedItems: const [],
    );
    expect(bp['book_id'], oldBookId);
    expect(bp['items'], isEmpty);
    expect(result.social, isNull);
  });
}
