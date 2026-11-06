import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _fixturePath =
    '../../shared_schemas/fixtures/private_classic_sample.json';
const _npc = 'npc_cccccccccccccccccccccccccccccccc';
const _fact = 'npc_secret';
const _memory = 'npc_heard_promise';

Map<String, dynamic> _richNpcSocialFixture() {
  final fixture = jsonDecode(File(_fixturePath).readAsStringSync())
      as Map<String, dynamic>;
  final blueprint = fixture['blueprint'] as Map<String, dynamic>;
  final provenance = fixture['provenance'] as Map<String, dynamic>;
  (blueprint['actors'] as List).add(_npc);
  (blueprint['facts'] as List).add(_fact);
  (blueprint['items'] as List).add('map');
  final initial = blueprint['initial_state'] as Map<String, dynamic>;
  (initial['knowledge'] as Map<String, dynamic>)[_npc] = <String>[];
  final entry = (blueprint['scenes'] as List).first as Map<String, dynamic>;
  entry['text'] = 'Встреча у ворот.\n'
      'Мария: «Я помню обещание!»\n'
      'Игрок: «Помню».';
  final choices = (entry['choices'] as List).cast<Map<String, dynamic>>();
  (choices.firstWhere((e) => e['id'] == 'wait')['effects'] as List).addAll([
    {'op': 'learn_fact', 'id': _fact, 'actor': _npc},
    {'op': 'grant_item', 'id': 'map'},
  ]);
  choices.addAll([
    {
      'id': 'give_map', 'label': 'Передать карту Марии',
      'next_scene_id': 'entry',
      'conditions': [{'op': 'has_item', 'id': 'map'}],
      'effects': [{'op': 'consume_item', 'id': 'map'}],
    },
    {
      'id': 'return_map', 'label': 'Получить карту обратно',
      'next_scene_id': 'entry',
      'conditions': <Object>[],
      'effects': [{'op': 'grant_item', 'id': 'map'}],
    },
  ]);
  // This path is deliberately NOT guarded by the old fact predicate.
  // Only the independently verified social rule may lock this decision.
  final origin = (provenance['scene_origins'] as List).first as Map;
  final quote = (origin['source_refs'] as List).first['quote_sha256'] as String;
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = {
    'provider': 'none', 'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  provenance['presentation'] = {
    'hero': {'name': 'Игрок', 'description': 'Частная синтетическая проверка'},
    'item_names': {'map': 'Карта'},
    'item_descriptions': {'map': 'Подтверждённый предмет'},
    'stat_names': <String, String>{},
    'fact_names': {_fact: 'Секрет'},
    'scene_names': {
      'entry': 'Двор', 'canon_end': 'Помощь', 'alternate_end': 'Отказ',
    },
    'scene_dialogues': {
      'entry': RichSceneDialogue.presentationFor(entry['text'] as String),
    },
    'scene_dialogue_knowledge': {
      'entry': [
        {
          'turn_index': 1, 'speaker': 'Мария', 'actor_id': _npc,
          'required_fact_ids': [_fact],
          'required_social_memory_id': _memory,
          'minimum_trust_to_player': 7,
        },
        {
          'turn_index': 2, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
      ],
    },
  };
  provenance['npc_knowledge'] = {
    'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': blueprint['source_fingerprint'],
    'user_confirmed': true, 'literary_canon_verified': false,
    'grants': [
      {
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': _npc, 'fact_id': _fact,
        'source_quote_sha256': quote,
      },
    ],
  };
  provenance['npc_social'] = {
    'format': RichNpcSocialContract.itemTransferFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': blueprint['source_fingerprint'],
    'user_confirmed': true, 'literary_canon_verified': false,
    'witnesses': [
      {
        'scene_id': 'entry', 'actor_id': _npc,
        'mode': 'present', 'source_quote_sha256': quote,
      },
    ],
    'rules': [
      {
        'memory_id': _memory,
        'scene_id': 'entry', 'choice_id': 'wait',
        'observer_id': _npc,
        'kind': 'promiseReceived', 'related_actor_id': 'player',
        'relationship_delta': 7, 'max_triggers': 1,
        'source_quote_sha256': quote,
      },
    ],
    'choice_gates': [
      {
        'scene_id': 'entry', 'choice_id': 'help', 'actor_id': _npc,
        'required_memory_id': _memory,
        'minimum_trust_to_player': 7,
        'source_quote_sha256': quote,
      },
    ],
    'item_transfers': [
      {
        'scene_id': 'entry', 'choice_id': 'give_map',
        'item_id': 'map', 'from_actor_id': 'player',
        'to_actor_id': _npc, 'source_quote_sha256': quote,
      },
      {
        'scene_id': 'entry', 'choice_id': 'return_map',
        'item_id': 'map', 'from_actor_id': _npc,
        'to_actor_id': 'player', 'source_quote_sha256': quote,
      },
    ],
  };
  return fixture;
}

NpcSocialSnapshot _social(CampaignRecord campaign,
    VerifiedRichPrivateBookworld rich) {
  final engine = campaign.coordinator;
  final world = StoryWorld.replay(
    rich.blueprint, engine.events.map((event) => event.toJson()),
    expectedSequence: engine.state.revision,
    expectedStateHash: engine.state.stateHash,
    socialRulebook: rich.npcSocialRulebook,
  );
  return NpcSocialLedger.inspect(world, rich.npcSocialRulebook!);
}

void main() {
  test('social signed NPC dialogue remains gated after SQLite restart/fork',
      () {
    final root = Directory.systemTemp.createTempSync('npc_social_save_');
    BookworldCampaignStore? store;
    try {
      final data = _richNpcSocialFixture();
      final archive = const RichPrivateBookworldWriter().build(
        blueprint: data['blueprint'] as Map<String, dynamic>,
        provenance: data['provenance'] as Map<String, dynamic>,
        sourceIndex: data['source_index'] as Map<String, dynamic>,
      );
      final rich = const RichPrivateBookworldImporter().inspect(archive);
      final spoken = RichSceneDialogue.verify(
        (rich.presentation['scene_dialogues'] as Map)['entry'],
        rich.blueprint.scenes['entry']!.text,
      );
      final reviews = (rich.presentation['scene_dialogue_knowledge']
          as Map)['entry'] as List;
      final original = BookworldCampaignStore.openPrivateDirectory(root.path);
      store = original;
      final installed = original.installBookworld(archive);
      final campaignId = original.createCampaign(installed.archiveHash);
      final alternateId = original.createCampaign(installed.archiveHash);
      final empty = original.loadCampaign(campaignId);
      final emptySocial = _social(empty, rich);
      expect(emptySocial.memoriesFor(_npc), isEmpty);
      expect(emptySocial.directedScore(_npc, 'player'), 0);
      expect(RichNpcDialogueKnowledge.redact(
        spoken, reviews, empty.coordinator.state.knowledge,
        social: emptySocial,
      )[1].text, RichNpcDialogueKnowledge.unavailableLine);

      final cannotSkip = original.commitChoice(
        campaignId, actionId: 'too_early', choiceId: 'help',
        expectedRevision: 0,
      );
      expect(cannotSkip.applied, false);
      expect(cannotSkip.reason, 'condition_not_met:npc_memory');
      expect(original.loadCampaign(campaignId).metadata.revision, 0);

      final alternative = original.commitChoice(
        alternateId, actionId: 'left', choiceId: 'leave',
        expectedRevision: 0,
      );
      expect(alternative.applied, true);
      expect(_social(original.loadCampaign(alternateId), rich)
          .memoriesFor(_npc), isEmpty);

      final taught = original.commitChoice(
        campaignId, actionId: 'promise_confirmed', choiceId: 'wait',
        expectedRevision: 0,
      );
      expect(taught.applied, true);
      final after = original.loadCampaign(campaignId);
      final social = _social(after, rich);
      expect(after.coordinator.state.knowledge[_npc], contains(_fact));
      expect(after.coordinator.state.knowledge['player'], isEmpty);
      expect(social.memoriesFor(_npc).single.event.actionId,
          'promise_confirmed');
      expect(social.directedScore(_npc, 'player'), 7);
      expect(social.directedScore('player', _npc), 0);
      expect(social.itemOwner('map'), 'player');
      expect(after.coordinator.choices
          .singleWhere((choice) => choice.id == 'help').enabled, true);
      expect(RichNpcDialogueKnowledge.redact(
        spoken, reviews, after.coordinator.state.knowledge,
        social: social,
      )[1].text, 'Я помню обещание!');
      final gifted = original.commitChoice(
        campaignId, actionId: 'give_map_to_npc', choiceId: 'give_map',
        expectedRevision: 1,
      );
      expect(gifted.applied, true);
      final afterGift = original.loadCampaign(campaignId);
      final custody = _social(afterGift, rich);
      expect(custody.itemOwner('map'), _npc);
      expect(custody.itemsHeldBy(_npc), ['map']);
      expect(afterGift.coordinator.state.inventory, isNot(contains('map')));
      final socialHash = custody.snapshotHash;
      final stateHash = afterGift.metadata.stateHash;
      final portable = original.exportPortable(campaignId);
      expect(portable, isNot(contains('Я помню обещание')));
      original.close();
      store = null;

      final reopened = BookworldCampaignStore.openPrivateDirectory(root.path);
      store = reopened;
      final recovered = reopened.loadCampaign(campaignId);
      final socialAfterReopen = _social(recovered, rich);
      expect(recovered.metadata.stateHash, stateHash);
      expect(socialAfterReopen.snapshotHash, socialHash);
      expect(socialAfterReopen.directedScore(_npc, 'player'), 7);
      expect(socialAfterReopen.itemOwner('map'), _npc);
      expect(reopened.commitChoice(campaignId,
        actionId: 'counterfeit', choiceId: 'wait',
        expectedRevision: 2).reason, 'condition_not_met:npc_item_custody');
      expect(reopened.commitChoice(campaignId,
        actionId: 'double_gift', choiceId: 'give_map',
        expectedRevision: 2).applied, false);
      expect(RichNpcDialogueKnowledge.redact(
        spoken, reviews, recovered.coordinator.state.knowledge,
        social: socialAfterReopen,
      )[1].text, 'Я помню обещание!');

      expect(reopened.commitChoice(campaignId,
        actionId: 'return_gift', choiceId: 'return_map',
        expectedRevision: 2).applied, true);
      final back = _social(reopened.loadCampaign(campaignId), rich);
      expect(back.itemOwner('map'), 'player');
      expect(back.itemsHeldBy(_npc), isEmpty);
      // A second identical choice cannot farm trust even after the gift
      // returns. The existing item remains unique in the hero inventory.
      expect(reopened.commitChoice(campaignId,
        actionId: 'again', choiceId: 'wait',
        expectedRevision: 3).applied, true);
      final repeated = _social(reopened.loadCampaign(campaignId), rich);
      expect(repeated.memoriesFor(_npc), hasLength(1));
      expect(repeated.directedScore(_npc, 'player'), 7);
      expect(repeated.itemOwner('map'), 'player');
      expect(reopened.commitChoice(campaignId,
        actionId: 'help_later', choiceId: 'help',
        expectedRevision: 4).applied, true);
      expect(reopened.loadCampaign(campaignId).coordinator.isTerminal, true);
      expect(_social(reopened.loadCampaign(alternateId), rich)
          .memoriesFor(_npc), isEmpty);
    } finally {
      store?.close();
      root.deleteSync(recursive: true);
    }
  });
}
