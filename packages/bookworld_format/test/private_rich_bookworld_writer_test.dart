import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _fixture = '../../shared_schemas/fixtures/private_classic_sample.json';
const _output = '../../artifacts/bookworld/book_private_rich_dart.bworld';

Map<String, dynamic> _asObject(Object? value) =>
    Map<String, dynamic>.from(value as Map);

Map<String, dynamic> _richSample() {
  final input = _asObject(jsonDecode(File(_fixture).readAsStringSync()));
  final blueprint = _asObject(input['blueprint']);
  final provenance = _asObject(input['provenance']);
  // The original synthetic story requires only narrative flags.
  // No invented equipment, stats or player knowledge is inserted.
  expect(blueprint['items'], isEmpty);
  expect(blueprint['facts'], isEmpty);
  expect(_asObject(_asObject(blueprint['initial_state'])['stats']), isEmpty);
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = <String, dynamic>{
    'provider': 'none',
    'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none',
    'method': 'local_fixture',
  };
  provenance['presentation'] = <String, dynamic>{
    'hero': <String, String>{
      'name': 'Игрок',
      'description': 'Герой синтетической проверки решения.',
    },
    'item_names': <String, String>{},
    'item_descriptions': <String, String>{},
    'stat_names': <String, String>{},
    'fact_names': <String, String>{},
    'scene_names': <String, String>{
      'entry': 'Начало пути',
      'canon_end': 'Помощь оказана',
      'alternate_end': 'Герой ушёл',
    },
  };
  input['provenance'] = provenance;
  return input;
}

Map<String, dynamic> _npcRichSample() {
  final data = _richSample();
  final blueprint = _asObject(data['blueprint']);
  final provenance = _asObject(data['provenance']);
  final npcId = 'npc_' + List.filled(32, 'c').join();
  const factId = 'npc_secret';
  (blueprint['actors'] as List).add(npcId);
  (blueprint['facts'] as List).add(factId);
  final initial = _asObject(blueprint['initial_state']);
  (initial['knowledge'] as Map<String, dynamic>)[npcId] = <String>[];
  final entry = (blueprint['scenes'] as List).first as Map<String, dynamic>;
  final wait = (entry['choices'] as List)[0] as Map<String, dynamic>;
  final help = (entry['choices'] as List)[1] as Map<String, dynamic>;
  (wait['effects'] as List).add({
    'op': 'learn_fact', 'id': factId, 'actor': npcId,
  });
  (help['conditions'] as List).add({
    'op': 'knows_fact', 'id': factId, 'actor': npcId,
  });
  final origin = (provenance['scene_origins'] as List).first as Map;
  final source = (origin['source_refs'] as List).first as Map;
  final presentation = _asObject(provenance['presentation']);
  presentation['fact_names'] = {factId: 'Секрет, переданный NPC'};
  provenance['presentation'] = presentation;
  provenance['npc_knowledge'] = {
    'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': blueprint['source_fingerprint'],
    'user_confirmed': true,
    'literary_canon_verified': false,
    'grants': [
      {
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': npcId, 'fact_id': factId,
        'source_quote_sha256': source['quote_sha256'],
      },
    ],
  };
  blueprint['initial_state'] = initial;
  data['blueprint'] = blueprint;
  data['provenance'] = provenance;
  return data;
}

void main() {
  const writer = RichPrivateBookworldWriter();
  const importer = RichPrivateBookworldImporter();


  test('source-reviewed spoken answers cause distinct NPC social replay', () {
    final input = _npcRichSample();
    final bp = _asObject(input['blueprint']);
    final prov = _asObject(input['provenance']);
    final actor = 'npc_' + List.filled(32, 'c').join();
    final entry = (bp['scenes'] as List).first as Map<String, dynamic>;
    entry['text'] = 'Мария: «Я услышала о твоём решении.»\n'
        'Игрок: «Я готов объяснить свой выбор.»';
    final origin = (prov['scene_origins'] as List).first as Map;
    final quote = (origin['source_refs'] as List).first['quote_sha256'] as String;
    final turns = RichSceneDialogue.presentationFor(entry['text'] as String)!;
    final dialogues = <String, dynamic>{'entry': turns};
    final speakers = <String, dynamic>{
      'entry': [
        {
          'turn_index': 0, 'speaker': 'Мария', 'actor_id': actor,
          'required_fact_ids': <String>[],
        },
        {
          'turn_index': 1, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
      ],
    };
    prov['npc_social'] = {
      'format': RichNpcSocialContract.format,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': bp['source_fingerprint'],
      'user_confirmed': true,
      'literary_canon_verified': false,
      'witnesses': [
        {
          'scene_id': 'entry', 'actor_id': actor,
          'mode': 'present', 'source_quote_sha256': quote,
        },
      ],
      'rules': [
        for (final row in [
          ('wait', 'npc_listened', 'promiseReceived', 10),
          ('help', 'npc_helped', 'helped', 10),
          ('leave', 'npc_refused', 'betrayed', -10),
        ])
          {
            'memory_id': row.$2,
            'scene_id': 'entry',
            'choice_id': row.$1,
            'observer_id': actor,
            'kind': row.$3,
            'related_actor_id': 'player',
            'relationship_delta': row.$4,
            'max_triggers': 1,
            'source_quote_sha256': quote,
          },
      ],
    };
    final source = RichNpcSocialContract.inspect(
      prov,
      {'npc_social_format': RichNpcSocialContract.format},
      StoryBlueprint.fromJson(bp),
    )!;
    final origins = <String, dynamic>{
      for (final raw in prov['scene_origins'] as List)
        (raw as Map)['scene_id'] as String: raw,
    };
    final blueprint = StoryBlueprint.fromJson(bp);
    final options = {
      'entry': {
        'wait': 'Сначала расскажу тебе всю правду.',
        'help': 'Да, я помогу тебе войти.',
        'leave': 'Нет, я ухожу без обещаний.',
      },
    };
    final proposal = RichNpcDialogueResponses.propose(
      blueprint: blueprint, sceneOrigins: origins,
      signedDialogues: dialogues, reviewedSpeakerTurns: speakers,
      playerLinesByScene: options,
      interlocutorByScene: {'entry': actor},
      sourceQuoteByScene: {'entry': quote},
      wholeDialogueReviewed: true, privateFictionAcknowledged: true,
      socialRules: source,
    );
    expect(proposal.isLiteraryCanon, isFalse);
    expect(proposal.canModifyCampaign, isFalse);
    expect(proposal.needsFinalApproval, isTrue);
    final reviewed = RichNpcDialogueResponses.accept(
      proposal: proposal, blueprint: blueprint,
      approvedDigest: proposal.approvalDigest,
      userConfirmed: true, socialRules: source,
    );
    expect(RichNpcDialogueResponses.replyFor(
      {'scene_dialogue_responses': reviewed}, 'entry', 'help'),
      'Да, я помогу тебе войти.');
    expect(() => RichNpcDialogueResponses.accept(
      proposal: proposal, blueprint: blueprint,
      approvedDigest: List.filled(64, '0').join(),
      userConfirmed: true, socialRules: source), throwsFormatException);
    expect(() => RichNpcDialogueResponses.accept(
      proposal: proposal, blueprint: blueprint,
      approvedDigest: proposal.approvalDigest,
      userConfirmed: false, socialRules: source), throwsFormatException);
    final presentation = _asObject(prov['presentation']);
    presentation['scene_dialogues'] = dialogues;
    presentation['scene_dialogue_knowledge'] = speakers;
    presentation['scene_dialogue_responses'] = reviewed;
    prov['presentation'] = presentation;
    final archive = writer.build(
      blueprint: bp, provenance: prov,
      sourceIndex: _asObject(input['source_index']),
    );
    final verified = importer.inspect(archive);
    expect(verified.requiresNetwork, isFalse);
    expect(verified.presentation['scene_dialogue_responses'], isNotNull);
    final rules = verified.npcSocialRulebook!;
    final positive = StoryWorld(verified.blueprint, socialRulebook: rules);
    expect(positive.apply(actionId: 'hear', choiceId: 'wait').applied, true);
    expect(positive.apply(actionId: 'help_her', choiceId: 'help').applied,
        true);
    final liked = NpcSocialLedger.inspect(positive, rules);
    expect(liked.directedScore(actor, 'player'), 20);
    expect(liked.hasMemory(actor, 'npc_helped'), true);
    expect(positive.state.knowledge[actor], contains('npc_secret'));
    final negative = StoryWorld(verified.blueprint, socialRulebook: rules);
    expect(negative.apply(actionId: 'refuse', choiceId: 'leave').applied,
        true);
    final refused = NpcSocialLedger.inspect(negative, rules);
    expect(refused.directedScore(actor, 'player'), -10);
    expect(refused.hasMemory(actor, 'npc_refused'), true);
    expect(negative.state.knowledge[actor], isEmpty);
    expect(negative.state.sceneId, isNot(positive.state.sceneId));
    for (final played in [positive, negative]) {
      final restored = StoryWorld.replay(
        verified.blueprint, played.events.map((event) => event.toJson()),
        expectedSequence: played.state.revision,
        expectedStateHash: played.state.stateHash,
        socialRulebook: rules,
      );
      expect(restored.state.stateHash, played.state.stateHash);
      expect(NpcSocialLedger.inspect(restored, rules).snapshotHash,
          NpcSocialLedger.inspect(played, rules).snapshotHash);
    }

    Map<String, dynamic> changed() =>
        jsonDecode(jsonEncode(prov)) as Map<String, dynamic>;
    void forged(String key, Object? value) {
      final copy = changed();
      (((copy['presentation'] as Map)['scene_dialogue_responses'] as Map)
          ['entry'] as List).first[key] = value;
      expect(() => writer.build(
        blueprint: bp, provenance: copy,
        sourceIndex: _asObject(input['source_index']),
      ), throwsFormatException);
    }
    forged('choice_id', 'other_unreviewed_choice');
    forged('interlocutor_id', 'player');
    forged('source_quote_sha256', List.filled(64, '0').join());
    forged('private_fiction_confirmed', false);
    forged('player_line', 'Мария: «Я сама подделаю эту реплику»');
    final missing = changed();
    (((missing['presentation'] as Map)['scene_dialogue_responses'] as Map)
        ['entry'] as List).removeLast();
    expect(() => writer.build(
      blueprint: bp, provenance: missing,
      sourceIndex: _asObject(input['source_index']),
    ), throwsFormatException);
    expect(() => RichNpcDialogueResponses.propose(
      blueprint: blueprint, sceneOrigins: origins,
      signedDialogues: dialogues, reviewedSpeakerTurns: speakers,
      playerLinesByScene: options, interlocutorByScene: {'entry': actor},
      sourceQuoteByScene: {'entry': quote},
      wholeDialogueReviewed: false, privateFictionAcknowledged: true,
      socialRules: source,
    ), throwsFormatException);

    final out = File('../../artifacts/bookworld/'
        'book_private_rich_npc_responses_dart.bworld');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(archive, flush: true);
  });

  test('source-reviewed v5 NPC lifecycle is portable and event-replayed', () {
    final data = _npcRichSample();
    final bp = _asObject(data['blueprint']);
    final prov = _asObject(data['provenance']);
    final npc = 'npc_' + List.filled(32, 'c').join();
    final origin = (prov['scene_origins'] as List).first as Map;
    final quote = (origin['source_refs'] as List).first['quote_sha256'];
    prov['npc_social'] = {
      'format': RichNpcSocialContract.lifeEventFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': bp['source_fingerprint'],
      'user_confirmed': true,
      'literary_canon_verified': false,
      'witnesses': <Map<String, Object?>>[],
      'rules': <Map<String, Object?>>[],
      'choice_gates': <Map<String, Object?>>[],
      'item_transfers': <Map<String, Object?>>[],
      'item_grants': <Map<String, Object?>>[],
      'life_transitions': [{
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': npc, 'next_state': 'absent',
        'source_quote_sha256': quote,
      }],
    };
    data['provenance'] = prov;
    Uint8List build() => writer.build(
      blueprint: _asObject(data['blueprint']),
      provenance: _asObject(data['provenance']),
      sourceIndex: _asObject(data['source_index']),
    );
    final bytes = build();
    expect(build(), bytes);
    final worldData = importer.inspect(bytes);
    final rules = worldData.npcSocialRulebook!;
    expect(rules.lifeTransitions.single.nextState, NpcLifeState.absent);
    final world = StoryWorld(worldData.blueprint, socialRulebook: rules);
    expect(NpcSocialLedger.inspect(world, rules).lifeState(npc),
        NpcLifeState.present);
    expect(world.apply(actionId: 'depart', choiceId: 'wait').applied, isTrue);
    final gone = NpcSocialLedger.inspect(world, rules);
    expect(gone.lifeState(npc), NpcLifeState.absent);
    final spoken = <RichDialogueTurn>[
      const RichDialogueTurn(speaker: 'Мария', text: 'Секретная реплика'),
    ];
    final reviewed = <Map<String, dynamic>>[{
      'turn_index': 0, 'speaker': 'Мария', 'actor_id': npc,
      'required_fact_ids': <String>[],
    }];
    expect(RichNpcDialogueKnowledge.redact(
        spoken, reviewed, world.state.knowledge, social: gone).single.text,
        RichNpcDialogueKnowledge.unavailableLine);
    expect(world.choiceLockReason('wait'),
        'condition_not_met:npc_life_transition');
    final reopened = StoryWorld.replay(worldData.blueprint,
        world.events.map((event) => event.toJson()),
        socialRulebook: rules, expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash);
    expect(NpcSocialLedger.inspect(reopened, rules).snapshotHash,
        NpcSocialLedger.inspect(world, rules).snapshotHash);
    final forged = jsonDecode(jsonEncode(prov)) as Map<String, dynamic>;
    ((forged['npc_social'] as Map)['life_transitions'] as List).first
        ['next_state'] = 'resurrected';
    expect(() => writer.build(blueprint: bp, provenance: forged,
        sourceIndex: _asObject(data['source_index'])),
        throwsFormatException);
  });

  test('private social memories require source-locked NPC witnesses and replay',
      () {
    final data = _npcRichSample();
    final provenance = _asObject(data['provenance']);
    final first = (provenance['scene_origins'] as List).first as Map;
    final quote = (first['source_refs'] as List).first['quote_sha256'] as String;
    final npc = 'npc_' + List.filled(32, 'c').join();
    final rawBlueprint = _asObject(data['blueprint']);
    final sourceScene =
        (rawBlueprint['scenes'] as List).first as Map<String, dynamic>;
    sourceScene['text'] = 'Встреча у ворот.\n'
        'Мария: «Я услышала обещание!»\n'
        'Игрок: «Обещаю».';
    final presentation = _asObject(provenance['presentation']);
    presentation['scene_dialogues'] = {
      'entry': RichSceneDialogue.presentationFor(
          sourceScene['text'] as String),
    };
    presentation['scene_dialogue_knowledge'] = {
      'entry': [
        {
          'turn_index': 1, 'speaker': 'Мария', 'actor_id': npc,
          'required_fact_ids': <String>[],
          'required_social_memory_id': 'npc_heard_promise',
          'minimum_trust_to_player': 7,
        },
        {
          'turn_index': 2, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
      ],
    };
    provenance['presentation'] = presentation;
    // Only social memory (not an ordinary knows_fact) unlocks this decision.
    final gatedHelp = ((rawBlueprint['scenes'] as List).first
        as Map<String, dynamic>)['choices'] as List;
    ((gatedHelp[1] as Map)['conditions'] as List).clear();
    provenance['npc_social'] = {
      'format': RichNpcSocialContract.choiceGateFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': _asObject(data['blueprint'])['source_fingerprint'],
      'user_confirmed': true,
      'literary_canon_verified': false,
      'witnesses': [
        {
          'scene_id': 'entry', 'actor_id': npc,
          'mode': 'present', 'source_quote_sha256': quote,
        },
      ],
      'rules': [
        {
          'memory_id': 'npc_heard_promise',
          'scene_id': 'entry', 'choice_id': 'wait',
          'observer_id': npc, 'kind': 'promiseReceived',
          'related_actor_id': 'player',
          'relationship_delta': 7, 'max_triggers': 1,
          'source_quote_sha256': quote,
        },
      ],
      'choice_gates': [
        {
          'scene_id': 'entry', 'choice_id': 'help', 'actor_id': npc,
          'required_memory_id': 'npc_heard_promise',
          'minimum_trust_to_player': 7,
          'source_quote_sha256': quote,
        },
      ],
    };
    data['provenance'] = provenance;
    Uint8List build() => writer.build(
      blueprint: _asObject(data['blueprint']),
      provenance: _asObject(data['provenance']),
      sourceIndex: _asObject(data['source_index']),
    );
    final archive = build();
    expect(build(), archive);
    final verified = importer.inspect(archive);
    final rules = verified.npcSocialRulebook!;
    expect(rules.requireReviewedWitnesses, isTrue);
    final world = StoryWorld(verified.blueprint, socialRulebook: rules);
    expect(world.choiceLockReason('help'), 'condition_not_met:npc_memory');
    final signed = RichSceneDialogue.verify(
      (verified.presentation['scene_dialogues'] as Map)['entry'],
      verified.blueprint.scenes['entry']!.text,
    );
    final reviews =
        (verified.presentation['scene_dialogue_knowledge'] as Map)['entry']
            as List;
    final initial = NpcSocialLedger.inspect(world, rules);
    expect(initial.memoriesFor(npc), isEmpty);
    expect(RichNpcDialogueKnowledge.redact(
        signed, reviews, world.state.knowledge, social: initial)[1].text,
        RichNpcDialogueKnowledge.unavailableLine);
    expect(world.apply(actionId: 'got_it', choiceId: 'wait').applied, isTrue);
    final social = NpcSocialLedger.inspect(world, rules);
    expect(social.memoriesFor(npc), hasLength(1));
    expect(social.memoriesFor(npc).single.witnessMode, NpcWitnessMode.present);
    expect(social.directedScore(npc, 'player'), 7);
    expect(social.directedScore('player', npc), 0);
    expect(world.choiceLockReason('help'), isNull);
    expect(RichNpcDialogueKnowledge.redact(
        signed, reviews, world.state.knowledge, social: social)[1].text,
        'Я услышала обещание!');
    final overThreshold = jsonDecode(jsonEncode(reviews)) as List;
    (overThreshold.first as Map)['minimum_trust_to_player'] = 8;
    expect(RichNpcDialogueKnowledge.redact(
        signed, overThreshold, world.state.knowledge, social: social)[1].text,
        RichNpcDialogueKnowledge.unavailableLine);
    final replay = StoryWorld.replay(
        verified.blueprint, world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
        socialRulebook: rules);
    expect(NpcSocialLedger.inspect(replay, rules).snapshotHash,
        social.snapshotHash);
    // The exact Dart archive, not a recreated Python fixture, must pass
    // the independent source-bound Python social review in CI.
    final socialFile = File(
        '../../artifacts/bookworld/book_private_rich_social_dart.bworld');
    socialFile.parent.createSync(recursive: true);
    socialFile.writeAsBytesSync(archive, flush: true);

    void rejects(void Function(Map<String, dynamic>) mutate) {
      final changed = _npcRichSample();
      final prov = _asObject(changed['provenance']);
      prov['npc_social'] =
          jsonDecode(jsonEncode(provenance['npc_social']));
      changed['provenance'] = prov;
      mutate(changed);
      expect(() => writer.build(
        blueprint: _asObject(changed['blueprint']),
        provenance: _asObject(changed['provenance']),
        sourceIndex: _asObject(changed['source_index']),
      ), throwsFormatException);
    }
    rejects((changed) {
      final social = _asObject(
          _asObject(changed['provenance'])['npc_social']);
      (social['witnesses'] as List).clear();
    });
    rejects((changed) {
      final social = _asObject(
          _asObject(changed['provenance'])['npc_social']);
      (social['witnesses'] as List).first['mode'] = 'reported';
    });
    rejects((changed) {
      final social = _asObject(
          _asObject(changed['provenance'])['npc_social']);
      (social['rules'] as List).first['source_quote_sha256'] =
          List.filled(64, 'f').join();
    });
  });

  test('reviewed NPC item ownership is portable and replay protected', () {
    for (final authored in [false, true]) {
    final data = _npcRichSample();
    final bp = _asObject(data['blueprint']);
    (bp['items'] as List).add('map');
    final entry = (bp['scenes'] as List).first as Map<String, dynamic>;
    final options = (entry['choices'] as List).cast<Map<String, dynamic>>();
    (options.singleWhere((c) => c['id'] == 'wait')['effects'] as List)
        .add({'op': 'grant_item', 'id': 'map'});
    options.addAll([
      {
        'id': 'give_map', 'label': 'Передать карту персонажу',
        'next_scene_id': 'entry',
        'conditions': [
          {'op': 'has_item', 'id': 'map'},
        ],
        'effects': [
          {'op': 'consume_item', 'id': 'map'},
        ],
      },
      {
        'id': 'return_map', 'label': 'Получить карту обратно',
        'next_scene_id': 'entry',
        'conditions': <Object>[],
        'effects': [
          {'op': 'grant_item', 'id': 'map'},
        ],
      },
    ]);
    final prov = _asObject(data['provenance']);
    final pres = _asObject(prov['presentation']);
    (pres['item_names'] as Map<String, dynamic>)['map'] = 'Карта';
    (pres['item_descriptions'] as Map<String, dynamic>)['map'] =
        'Подтверждённый игровой предмет';
    prov['presentation'] = pres;
    final npc = 'npc_' + List.filled(32, 'c').join();
    final origin = (prov['scene_origins'] as List).first as Map;
    final quote = (origin['source_refs'] as List).first['quote_sha256'] as String;
    prov['npc_social'] = {
      'format': authored
          ? RichNpcSocialContract.authoredItemFormat
          : RichNpcSocialContract.itemTransferFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': bp['source_fingerprint'],
      'user_confirmed': true,
      'literary_canon_verified': false,
      'witnesses': [
        {
          'scene_id': 'entry', 'actor_id': npc,
          'mode': 'present', 'source_quote_sha256': quote,
        },
      ],
      'rules': [
        {
          'memory_id': 'npc_remembers_pledge', 'scene_id': 'entry',
          'choice_id': 'wait', 'observer_id': npc,
          'kind': 'promiseReceived', 'related_actor_id': 'player',
          'relationship_delta': 7, 'max_triggers': 1,
          'source_quote_sha256': quote,
        },
      ],
      'choice_gates': <Map<String, Object?>>[],
      if (authored)
        'item_grants': [
          {
            'scene_id': 'entry', 'choice_id': 'wait',
            'item_id': 'map', 'source_quote_sha256': quote,
          },
        ],
      'item_transfers': [
        {
          'scene_id': 'entry', 'choice_id': 'give_map',
          'item_id': 'map', 'from_actor_id': 'player',
          'to_actor_id': npc, 'source_quote_sha256': quote,
        },
        {
          'scene_id': 'entry', 'choice_id': 'return_map',
          'item_id': 'map', 'from_actor_id': npc,
          'to_actor_id': 'player', 'source_quote_sha256': quote,
        },
      ],
    };
    data['provenance'] = prov;
    final archive = writer.build(
      blueprint: bp, provenance: prov,
      sourceIndex: _asObject(data['source_index']),
    );
    final inspected = importer.inspect(archive);
    final rules = inspected.npcSocialRulebook!;
    expect(rules.itemTransfers, hasLength(2));
    final world = StoryWorld(inspected.blueprint, socialRulebook: rules);
    expect(world.apply(actionId: 'phantom_return', choiceId: 'return_map')
        .reason, 'condition_not_met:npc_item_owner');
    expect(world.apply(actionId: 'gift_before_ownership',
        choiceId: 'give_map').applied, false);
    expect(world.apply(actionId: 'acquired', choiceId: 'wait').applied, true);
    expect(NpcSocialLedger.inspect(world, rules).itemOwner('map'), 'player');
    expect(world.apply(actionId: 'given', choiceId: 'give_map').applied, true);
    final held = NpcSocialLedger.inspect(world, rules);
    expect(held.itemOwner('map'), npc);
    expect(held.itemsHeldBy(npc), ['map']);
    expect(world.state.inventory, isNot(contains('map')));
    expect(world.apply(actionId: 'counterfeit', choiceId: 'wait').reason,
        'condition_not_met:npc_item_custody');
    expect(world.apply(actionId: 'returned', choiceId: 'return_map')
        .applied, true);
    expect(NpcSocialLedger.inspect(world, rules).itemOwner('map'), 'player');
    final replayed = StoryWorld.replay(
      inspected.blueprint, world.events.map((event) => event.toJson()),
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
      socialRulebook: rules,
    );
    expect(NpcSocialLedger.inspect(replayed, rules).snapshotHash,
        NpcSocialLedger.inspect(world, rules).snapshotHash);
    final output = File(authored
        ? '../../artifacts/bookworld/book_private_rich_items_authored_dart.bworld'
        : '../../artifacts/bookworld/book_private_rich_items_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(archive, flush: true);
    }
  });



  test('source-reviewed NPC dialogue plan builds playable offline branches',
      () {
    final data = _npcRichSample();
    final bp = _asObject(data['blueprint']);
    final entry = (bp['scenes'] as List).first as Map<String, dynamic>;
    // The two routes enter the same conversation, but only an explicit
    // source event taught the permanent NPC the selected secret.
    (((entry['choices'] as List)[1] as Map)['conditions'] as List).clear();
    final meeting = (bp['scenes'] as List)[1] as Map<String, dynamic>;
    meeting['text'] = 'Мария: «Теперь я знаю тайну.»\n'
        'Игрок: «Что произошло?»\n'
        'Мария: «Поговорим о дороге.»';
    final proven = _asObject(data['provenance']);
    final origins = {
      for (final value in proven['scene_origins'] as List)
        (value as Map)['scene_id'] as String: value,
    };
    final permanent = 'npc_' + List.filled(32, 'c').join();
    final playerAndNpc = {'Мария': permanent, 'Игрок': 'player'};
    final boundGrants = [
      for (final row in ((proven['npc_knowledge'] as Map)['grants'] as List))
        Map<String, String>.from(row as Map),
    ];
    final world = StoryBlueprint.fromJson(bp);
    final proposal = RichNpcDialogueAuthoring.propose(
      blueprint: world,
      sceneOrigins: origins,
      reviewedSpeakerActorIds: playerAndNpc,
      verifiedNpcFactGrants: boundGrants,
      reviewedNpcFactByTurn: const {
        'canon_end': {0: 'npc_secret'},
      },
      reviewedSafeNpcTurns: const {
        'canon_end': {2},
      },
      wholeDialogueTextReviewed: true,
      privateFictionAcknowledged: true,
    );
    expect(proposal.isLiteraryCanon, isFalse);
    expect(proposal.needsFinalApproval, isTrue);
    expect(proposal.requiresNetwork, isFalse);
    expect(proposal.npcLineCount, 2);
    expect(proposal.causallyGuardedLineCount, 1);
    final gatedTurn = proposal.reviewedTurns['canon_end']!.first;
    expect(gatedTurn['actor_id'], permanent);
    expect(gatedTurn['required_fact_ids'], ['npc_secret']);
    expect(gatedTurn['required_prior_choice_id'], 'wait');
    expect(gatedTurn['source_quote_sha256'],
        ((origins['entry'] as Map)['source_refs'] as List).first['quote_sha256']);
    final review = RichNpcDialogueAuthoring.accept(
      proposal: proposal,
      blueprint: world,
      reviewedSpeakerActorIds: playerAndNpc,
      approvedDigest: proposal.approvalDigest,
      userConfirmed: true,
    );
    // Double consent: a stable preview digest must be accepted for the
    // exact blueprint and signed actor bindings. Nothing writes a save.
    expect(() => RichNpcDialogueAuthoring.accept(
        proposal: proposal, blueprint: world,
        reviewedSpeakerActorIds: playerAndNpc,
        approvedDigest: proposal.approvalDigest, userConfirmed: false),
        throwsFormatException);
    expect(() => RichNpcDialogueAuthoring.accept(
        proposal: proposal, blueprint: world,
        reviewedSpeakerActorIds: playerAndNpc,
        approvedDigest: List.filled(64, '0').join(), userConfirmed: true),
        throwsFormatException);
    expect(() => RichNpcDialogueAuthoring.accept(
        proposal: proposal, blueprint: world,
        reviewedSpeakerActorIds: {'Мария': 'player', 'Игрок': 'player'},
        approvedDigest: proposal.approvalDigest, userConfirmed: true),
        throwsFormatException);
    Map<String, dynamic> projection() => _asObject(proven['presentation']);
    final presentation = projection();
    presentation['scene_dialogues'] = {
      'canon_end':
          RichSceneDialogue.presentationFor(meeting['text'] as String),
    };
    presentation['scene_dialogue_knowledge'] = review;
    proven['presentation'] = presentation;
    final archive = writer.build(
      blueprint: bp, provenance: proven,
      sourceIndex: _asObject(data['source_index']),
    );
    expect(archive, writer.build(
      blueprint: bp, provenance: proven,
      sourceIndex: _asObject(data['source_index']),
    ));
    final installed = importer.inspect(archive);
    expect(installed.requiresNetwork, isFalse);
    final signed = RichSceneDialogue.verify(
      (installed.presentation['scene_dialogues'] as Map)['canon_end'],
      installed.blueprint.scenes['canon_end']!.text,
    );
    final signedReviews =
        (installed.presentation['scene_dialogue_knowledge'] as Map)
            ['canon_end'] as List;

    final direct = StoryWorld(installed.blueprint);
    expect(direct.apply(actionId: 'direct', choiceId: 'help').applied, true);
    final before = RichNpcDialogueKnowledge.redact(
        signed, signedReviews, direct.state.knowledge,
        committedEvents: direct.events, sceneId: direct.state.sceneId);
    expect(before[0].text, RichNpcDialogueKnowledge.unavailableLine);
    expect(before[1].text, 'Что произошло?');
    expect(before[2].text, 'Поговорим о дороге.');

    final learned = StoryWorld(installed.blueprint);
    expect(learned.apply(actionId: 'read', choiceId: 'wait').applied, true);
    expect(learned.apply(actionId: 'talk', choiceId: 'help').applied, true);
    final after = RichNpcDialogueKnowledge.redact(
        signed, signedReviews, learned.state.knowledge,
        committedEvents: learned.events, sceneId: learned.state.sceneId);
    expect(after[0].text, 'Теперь я знаю тайну.');
    final restored = StoryWorld.replay(installed.blueprint,
        learned.events.map((event) => event.toJson()),
        expectedSequence: learned.state.revision,
        expectedStateHash: learned.state.stateHash);
    expect(RichNpcDialogueKnowledge.redact(
        signed, signedReviews, restored.state.knowledge,
        committedEvents: restored.events, sceneId: restored.state.sceneId)[0]
        .text, 'Теперь я знаю тайну.');

    void wrongProposal({
      Map<String, String>? speakers,
      List<Map<String, String>>? grants,
      Map<String, Map<int, String>> facts = const {
        'canon_end': {0: 'npc_secret'},
      },
      Map<String, Set<int>> safe = const {
        'canon_end': {2},
      },
      bool confirmed = true,
    }) {
      expect(() => RichNpcDialogueAuthoring.propose(
        blueprint: world, sceneOrigins: origins,
        reviewedSpeakerActorIds: speakers ?? playerAndNpc,
        verifiedNpcFactGrants: grants ?? boundGrants,
        reviewedNpcFactByTurn: facts,
        reviewedSafeNpcTurns: safe,
        wholeDialogueTextReviewed: true,
        privateFictionAcknowledged: confirmed,
      ), throwsFormatException);
    }
    wrongProposal(speakers: const {'Игрок': 'player'}); // no invented actor
    wrongProposal(grants: const []); // no invented learning
    wrongProposal(grants: [...boundGrants, ...boundGrants]); // ambiguous
    wrongProposal(facts: const {'canon_end': {0: 'wrong_fact'}});
    wrongProposal(safe: const {});
    wrongProposal(safe: const {'canon_end': {1, 2}});
    wrongProposal(confirmed: false);

    // The existing importer and deterministic engine, not a new runtime,
    // execute the accepted dialogue contract. No private source text or
    // model-generated literary claims were added by the planner.
    final path = File('../../artifacts/bookworld/'
        'book_private_rich_dialogue_plan_dart.bworld');
    path.parent.createSync(recursive: true);
    path.writeAsBytesSync(archive, flush: true);
  });

  test('P0: causal NPC reply needs committed source action on this route', () {
    final data = _npcRichSample();
    final bp = _asObject(data['blueprint']);
    final entry = (bp['scenes'] as List).first as Map<String, dynamic>;
    // Same destination, two real routes: direct talk never teaches a secret.
    (((entry['choices'] as List)[1] as Map)['conditions'] as List).clear();
    final meeting = (bp['scenes'] as List)[1] as Map<String, dynamic>;
    meeting['text'] = 'Мария: «Теперь я знаю тайну.»\n'
        'Игрок: «Расскажи мне.»';
    final prov = _asObject(data['provenance']);
    final source = (prov['scene_origins'] as List).first as Map;
    final quote = ((source['source_refs'] as List).first
        as Map)['quote_sha256'] as String;
    final npc = 'npc_' + List.filled(32, 'c').join();
    final presentation = _asObject(prov['presentation']);
    presentation['scene_dialogues'] = {
      'canon_end': RichSceneDialogue.presentationFor(
          meeting['text'] as String),
    };
    presentation['scene_dialogue_knowledge'] = {
      'canon_end': [
        {
          'turn_index': 0, 'speaker': 'Мария', 'actor_id': npc,
          'required_fact_ids': ['npc_secret'],
          'required_prior_choice_id': 'wait',
          'source_quote_sha256': quote,
          'private_fiction_confirmed': true,
        },
        {
          'turn_index': 1, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
      ],
    };
    prov['presentation'] = presentation;
    final sourceIndex = _asObject(data['source_index']);
    final archive = writer.build(
        blueprint: bp, provenance: prov, sourceIndex: sourceIndex);
    final verified = importer.inspect(archive);
    final turns = RichSceneDialogue.verify(
      (verified.presentation['scene_dialogues'] as Map)['canon_end'],
      verified.blueprint.scenes['canon_end']!.text,
    );
    final reviews = (verified.presentation['scene_dialogue_knowledge']
        as Map)['canon_end'] as List;

    // Route B: going directly to the dialogue cannot reveal NPC knowledge.
    final without = StoryWorld(verified.blueprint);
    expect(without.apply(actionId: 'go_direct', choiceId: 'help').applied,
        isTrue);
    final blocked = RichNpcDialogueKnowledge.redact(
      turns, reviews, without.state.knowledge,
      committedEvents: without.events, sceneId: without.state.sceneId);
    expect(blocked[0].text, RichNpcDialogueKnowledge.unavailableLine);
    expect(blocked[1].text, 'Расскажи мне.');

    // Route A: the earlier source-bound action explicitly teaches the
    // permanent NPC actor, then the scene becomes eligible.
    final withLearning = StoryWorld(verified.blueprint);
    expect(withLearning.apply(actionId: 'observe', choiceId: 'wait').applied,
        isTrue);
    expect(withLearning.apply(actionId: 'go_after', choiceId: 'help').applied,
        isTrue);
    final spoken = RichNpcDialogueKnowledge.redact(
      turns, reviews, withLearning.state.knowledge,
      committedEvents: withLearning.events, sceneId: withLearning.state.sceneId);
    expect(spoken[0].text, 'Теперь я знаю тайну.');
    expect(spoken[1].text, 'Расскажи мне.');
    // Deliberately omit the event journal: a world-state fact alone is
    // insufficient proof of the causal prerequisite.
    expect(RichNpcDialogueKnowledge.redact(
        turns, reviews, withLearning.state.knowledge)[0].text,
        RichNpcDialogueKnowledge.unavailableLine);
    final replayed = StoryWorld.replay(
      verified.blueprint, withLearning.events.map((e) => e.toJson()),
      expectedSequence: withLearning.state.revision,
      expectedStateHash: withLearning.state.stateHash);
    expect(RichNpcDialogueKnowledge.redact(
      turns, reviews, replayed.state.knowledge,
      committedEvents: replayed.events, sceneId: replayed.state.sceneId,
    )[0].text, spoken[0].text);
    expect(replayed.state.stateHash, withLearning.state.stateHash);

    Map<String, dynamic> cloneSource() =>
        jsonDecode(jsonEncode(prov)) as Map<String, dynamic>;
    void changeLine(Map<String, dynamic> origin, String key, Object? value) {
      final row = (((origin['presentation'] as Map)
          ['scene_dialogue_knowledge'] as Map)
          ['canon_end'] as List).first as Map;
      if (value == null) {
        row.remove(key);
      } else {
        row[key] = value;
      }
    }
    void rejects(String key, Object? value) {
      final tampered = cloneSource();
      changeLine(tampered, key, value);
      expect(() => writer.build(
          blueprint: bp, provenance: tampered, sourceIndex: sourceIndex),
          throwsFormatException);
    }
    rejects('source_quote_sha256', List.filled(64, '0').join());
    rejects('required_prior_choice_id', 'leave'); // wrong destination
    rejects('required_prior_choice_id', 'help'); // never teaches the NPC
    rejects('private_fiction_confirmed', false);
    rejects('private_fiction_confirmed', null);

    // The ordinary CI independently verifies these EXACT Dart bytes in
    // Python (not only a recreated Python fixture).
    final output = File(
        '../../artifacts/bookworld/book_private_rich_dialogue_causal_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(archive, flush: true);
  });

  test('explicit private NPC v3 roundtrip uses source-reviewed fact grants', () {
    final data = _npcRichSample();
    final rawBlueprint = _asObject(data['blueprint']);
    final first = (rawBlueprint['scenes'] as List).first as Map<String, dynamic>;
    first['text'] = 'Встреча у ворот.\n'
        'Мария: «Мне известен секрет!»\n'
        'Игрок: «Я слушаю».';
    final provenance = _asObject(data['provenance']);
    final presentation = _asObject(provenance['presentation']);
    presentation['scene_dialogues'] = {
      'entry': RichSceneDialogue.presentationFor(first['text'] as String),
    };
    final npcId = 'npc_' + List.filled(32, 'c').join();
    presentation['scene_dialogue_knowledge'] = {
      'entry': [
        {
          'turn_index': 1, 'speaker': 'Мария', 'actor_id': npcId,
          'required_fact_ids': ['npc_secret'],
        },
        {
          'turn_index': 2, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
      ],
    };
    provenance['presentation'] = presentation;
    data['provenance'] = provenance;
    final archive = writer.build(
      blueprint: _asObject(data['blueprint']),
      provenance: _asObject(data['provenance']),
      sourceIndex: _asObject(data['source_index']),
    );
    final inspected = importer.inspect(archive);
    expect(inspected.blueprint.actors, contains(npcId));
    final world = StoryWorld(inspected.blueprint);
    final signed = RichSceneDialogue.verify(
      (inspected.presentation['scene_dialogues'] as Map)['entry'],
      inspected.blueprint.scenes['entry']!.text,
    );
    final reviewed = (inspected.presentation['scene_dialogue_knowledge']
        as Map)['entry'] as List;
    final blockedWords = RichNpcDialogueKnowledge.redact(
        signed, reviewed, world.state.knowledge);
    expect(blockedWords[1].text, RichNpcDialogueKnowledge.unavailableLine);
    expect(blockedWords[1].speaker, isNull,
        reason: 'Future NPC identity must not leak with gated words');
    expect(blockedWords[2].text, 'Я слушаю');
    final denied = world.apply(actionId: 'too_soon', choiceId: 'help');
    expect(denied.applied, isFalse);
    expect(denied.reason, 'condition_not_met:knows_fact');
    expect(world.actorKnowsFact(npcId, 'npc_secret'), isFalse);
    expect(world.apply(actionId: 'talk', choiceId: 'wait').applied, isTrue);
    expect(world.actorKnowsFact(npcId, 'npc_secret'), isTrue);
    final afterLearning = RichNpcDialogueKnowledge.redact(
        signed, reviewed, world.state.knowledge);
    expect(afterLearning[1].text, 'Мне известен секрет!');
    expect(afterLearning[1].speaker, signed[1].speaker,
        reason: 'Verified event restores the exact signed speaker');
    expect(world.actorKnowsFact('player', 'npc_secret'), isFalse);
    expect(world.factLearningEvents(npcId, 'npc_secret').single.actionId,
        'talk');
    expect(world.apply(actionId: 'help_later', choiceId: 'help').applied, isTrue);
    final restored = StoryWorld.replay(inspected.blueprint,
        world.events.map((e) => e.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash);
    expect(restored.state.knowledge[npcId], {'npc_secret'});
    expect(restored.state.stateHash, world.state.stateHash);

    // CI verifies these exact Dart-produced bytes independently in Python.
    final output = File(
      '../../artifacts/bookworld/book_private_rich_npc_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(archive, flush: true);
  });

  test('versioned NPC grant review rejects tampered identity and quote', () {
    void rejects(void Function(Map<String, dynamic>) mutate) {
      final data = _npcRichSample();
      mutate(data);
      expect(() => writer.build(
        blueprint: _asObject(data['blueprint']),
        provenance: _asObject(data['provenance']),
        sourceIndex: _asObject(data['source_index']),
      ), throwsFormatException);
    }
    rejects((data) =>
        (data['provenance'] as Map).remove('npc_knowledge'));
    rejects((data) {
      final provenance = _asObject(data['provenance']);
      final review = _asObject(provenance['npc_knowledge']);
      ((review['grants'] as List).first as Map)['source_quote_sha256'] =
          List.filled(64, 'f').join();
    });
    rejects((data) {
      final provenance = _asObject(data['provenance']);
      final review = _asObject(provenance['npc_knowledge']);
      ((review['grants'] as List).first as Map)['actor_id'] = 'player';
    });
    rejects((data) {
      final blueprint = _asObject(data['blueprint']);
      (blueprint['actors'] as List)[1] = 'npc_unstable_alias';
    });
    rejects((data) {
      final blueprint = _asObject(data['blueprint']);
      final first = (blueprint['scenes'] as List).first as Map;
      first['text'] = 'Мария: «Я всё знаю».\nИгрок: «Верно».';
      // A named scene with NPC actors cannot fall back to raw text
      // by deleting both exact dialogue and knowledge projections.
    });
    rejects((data) {
      final blueprint = _asObject(data['blueprint']);
      final initial = _asObject(blueprint['initial_state']);
      final npcId = 'npc_' + List.filled(32, 'c').join();
      (initial['knowledge'] as Map)[npcId] = ['npc_secret'];
    });
  });

  test('native rich v3 writes deterministic offline package with real hero and honest empty catalogs', () {
    final input = _richSample();
    final bytes = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final inspected = importer.inspect(bytes);
    expect(inspected.bookworldId, 'book_private_sample');
    expect(inspected.sourceFingerprint, 'a' * 64);
    expect(inspected.presentation['hero'], containsPair('name', 'Игрок'));
    expect(inspected.presentation['item_names'], isEmpty);
    expect(inspected.presentation['stat_names'], isEmpty);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.requiresNetwork, false);
    expect(inspected.blueprint.initial.stats, isEmpty);
    expect(inspected.blueprint.items, isEmpty);
    expect(inspected.blueprint.facts, isEmpty);
    final second = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    expect(second, orderedEquals(bytes));
    expect(() => const PrivateBookworldImporter().inspect(bytes), throwsFormatException);
    final output = File(_output);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes, flush: true);
  });

  test('new private v3 carries exact signed two-speaker turns, '
      'including narrator beats, without altering choices or source', () {
    final fixture = _asObject(
        jsonDecode(File(_fixture).readAsStringSync()));
    final originalBp = _asObject(fixture['blueprint']);
    final scenes = originalBp['scenes'] as List;
    final first = scenes.first as Map;
    final originalText = first['text'] as String;
    first['text'] = originalText + '\n' +
        'Мария: «Ты видел дверь?»\n' +
        'Иван: «Да, но я ничего не обещал»\n' +
        'Рассказчик ничего не утверждает о чужих мыслях.';
    final original = const PrivateBookworldWriter().build(
      blueprint: originalBp,
      provenance: _asObject(fixture['provenance']),
      sourceIndex: _asObject(fixture['source_index']),
    );
    final rich = writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(fixture['source_index']),
    );
    // Used by the independent Python package verifier in the same CI run.
    final output = File(
        '../../artifacts/bookworld/book_private_rich_dialogue_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(rich, flush: true);
    final inspected = importer.inspect(rich);
    final transcripts = _asObject(
        inspected.presentation['scene_dialogues']);
    expect(transcripts.keys, contains('entry'));
    expect(transcripts.length, 1);
    final signed = _asObject(transcripts['entry']);
    final turns = signed['turns'] as List;
    expect(turns, hasLength(4));
    expect(_asObject(turns[0])['speaker'], isNull);
    expect(_asObject(turns[1])['speaker'], 'Мария');
    expect(_asObject(turns[1])['text'], 'Ты видел дверь?');
    expect(_asObject(turns[2])['speaker'], 'Иван');
    expect(_asObject(turns[3])['speaker'], isNull);
    final canonical = RichSceneDialogue.verify(
        signed, inspected.blueprint.scenes['entry']!.text);
    expect(canonical.map((line) => line.text).toList(), [
      originalText, 'Ты видел дверь?',
      'Да, но я ничего не обещал',
      'Рассказчик ничего не утверждает о чужих мыслях.',
    ]);
    expect(inspected.blueprint.scenes['entry']!.choices.length,
        ((scenes.first as Map)['choices'] as List).length);

    // Even a separately recomputed ZIP SHA must not authorize a fabricated
    // attribution or a partial transcript.
    final corrupt = _richSample();
    final corruptBp = _asObject(corrupt['blueprint']);
    (corruptBp['scenes'] as List).first['text'] = first['text'];
    final provenance = _asObject(corrupt['provenance']);
    final presentation = _asObject(provenance['presentation']);
    final altered = _asObject(
        RichSceneDialogue.presentationFor(first['text'] as String));
    final alteredTurns = (altered['turns'] as List)
        .map((line) => Map<String, dynamic>.from(line as Map)).toList();
    alteredTurns[1]['speaker'] = 'Чужой говорящий';
    altered['turns'] = alteredTurns;
    presentation['scene_dialogues'] = {'entry': altered};
    provenance['presentation'] = presentation;
    expect(() => writer.build(
      blueprint: corruptBp, provenance: provenance,
      sourceIndex: _asObject(corrupt['source_index']),
    ), throwsFormatException);
    final truncated = _richSample();
    final truncatedBp = _asObject(truncated['blueprint']);
    (truncatedBp['scenes'] as List).first['text'] = first['text'];
    final tprovenance = _asObject(truncated['provenance']);
    final tp = _asObject(tprovenance['presentation']);
    tp['scene_dialogues'] = <String, Object?>{};
    tprovenance['presentation'] = tp;
    expect(() => writer.build(
      blueprint: truncatedBp, provenance: tprovenance,
      sourceIndex: _asObject(truncated['source_index']),
    ), throwsFormatException);
  });

  test('native v3 records configured Z.ai model request, without claiming literary truth', () {
    final input = _richSample();
    final provenance = _asObject(input['provenance']);
    provenance['model_provenance'] = {
      'provider': 'zai',
      'model_id': 'glm-4.7-flash',
      'model_id_status': 'requested',
      'tool': 'AI Story RPG',
      'method': 'built_in',
    };
    final package = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: provenance,
      sourceIndex: _asObject(input['source_index']),
    );
    final imported = importer.inspect(package);
    expect(imported.presentation['hero'], containsPair('name', 'Игрок'));
    expect(imported.sourceFingerprint, 'a' * 64);
    final wrong = _asObject(provenance['model_provenance']);
    wrong['model_id'] = 'different_model';
    provenance['model_provenance'] = wrong;
    expect(() => writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: provenance,
      sourceIndex: _asObject(input['source_index']),
    ), throwsFormatException);
  });

  test('native v3 replays two real flag-based endings without fake inventory', () {
    final input = _richSample();
    final raw = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final verified = importer.inspect(raw);
    for (final target in ['help', 'leave']) {
      final world = StoryWorld(verified.blueprint);
      final result = world.apply(
        actionId: 'native_rich_$target',
        choiceId: target,
        expectedRevision: 0,
      );
      expect(result.status, DecisionStatus.applied);
      expect(world.isTerminal, true);
      expect(world.events.single.choiceId, target);
      expect(world.state.stats, isEmpty);
      expect(world.state.inventory, isEmpty);
      expect(world.state.knowledge['player'], isEmpty);
      final restored = StoryWorld.replay(
        verified.blueprint,
        world.events.map((event) => event.toJson()),
        expectedSequence: world.state.revision,
        expectedStateHash: world.state.stateHash,
      );
      expect(restored.state.stateHash, world.state.stateHash);
    }
  });

  test('native v3 blocks wrong book, invented item, dishonest model and fake citation', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (input) => (input['source_index'] as Map)['source_fingerprint'] = 'f' * 64,
      (input) => (input['blueprint'] as Map)['items'] = ['ghost'],
      (input) => (input['provenance'] as Map)['model_provenance'] = {
        'provider': 'openai',
        'model_id': 'made_up_model',
        'model_id_status': 'user_declared',
        'tool': 'ChatGPT', 'method': 'external',
      },
      (input) {
        final origins = _asObject(input['provenance'])['scene_origins'] as List;
        final refs = (origins.first as Map)['source_refs'] as List;
        (refs.first as Map)['quote_sha256'] = 'f' * 64;
      },
    ]) {
      final input = _richSample();
      mutate(input);
      expect(() => writer.build(
        blueprint: _asObject(input['blueprint']),
        provenance: _asObject(input['provenance']),
        sourceIndex: _asObject(input['source_index']),
      ), throwsFormatException);
    }
  });

  test('reviewed v2 scenario promotes automatically to real rich v3 hero and journal', () {
    final input = _asObject(jsonDecode(File(_fixture).readAsStringSync()));
    final original = const PrivateBookworldWriter().build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final upgraded = writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: 'Путник',
      sceneTitles: {'entry': 'Путник решает', 'canon_end': 'Помощь',
                    'alternate_end': 'Отказ'},
    );
    final rich = importer.inspect(upgraded);
    // The separate CI Python verifier must accept the exact Dart-produced
    // upgrade bytes, not a Python-generated approximation.
    final output = File(
        '../../artifacts/bookworld/book_private_rich_upgraded_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(upgraded, flush: true);
    expect(rich.bookworldId, isNot('book_private_sample'));
    expect(rich.presentation['hero'], containsPair('name', 'Путник'));
    expect(rich.presentation['scene_names'],
        containsPair('entry', 'Путник решает'));
    expect(rich.presentation['item_names'], isEmpty);
    expect(rich.blueprint.initial.stats, isEmpty);
    expect(rich.blueprint.items, isEmpty);
    expect(rich.blueprint.facts, isEmpty);
    expect(rich.sourceFingerprint, 'a' * 64);
    expect(rich.canDistributePublicly, false);
    final again = writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: 'Путник',
      sceneTitles: {'entry': 'Путник решает', 'canon_end': 'Помощь',
                    'alternate_end': 'Отказ'},
    );
    expect(again, orderedEquals(upgraded));
    expect(() => const PrivateBookworldImporter().inspect(upgraded),
        throwsFormatException);
    for (final action in ['help', 'leave']) {
      final world = StoryWorld(rich.blueprint);
      expect(world.apply(actionId: 'rich_' + action, choiceId: action,
          expectedRevision: 0).status, DecisionStatus.applied);
      expect(world.isTerminal, true);
      expect(world.events.single.choiceId, action);
      expect(world.state.inventory, isEmpty);
      expect(world.state.stats, isEmpty);
    }

    final corruptIndex = _asObject(input['source_index']);
    corruptIndex['source_fingerprint'] = 'f' * 64;
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: corruptIndex,
    ), throwsFormatException);
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      heroName: '',
    ), throwsFormatException);
    expect(() => writer.upgradeReviewedV2(
      verifiedPrivateV2Archive: original,
      sourceIndex: _asObject(input['source_index']),
      sceneTitles: {'another_book_scene': 'Подмена'},
    ), throwsFormatException);
  });

  test('user-reviewed book item and fact become actual source-bound v3 runtime state',
      () {
    final input = _richSample();
    final index = _asObject(input['source_index']);
    final chunks = index['chunks'] as List;
    final first = chunks.first as Map<String, dynamic>;
    const excerpt = 'Ключ лежал у двери. Мария решала, кому помочь.';
    first['text'] = excerpt;
    first['end_utf16'] = excerpt.length;
    first['sha256_text'] = sha256.convert(utf8.encode(excerpt)).toString();
    final total = chunks.fold<int>(
        0, (count, c) => count + ((c as Map)['text'] as String).length);
    index['text_total_utf16'] = total;
    index['text_indexed_utf16'] = total;
    final quoteSha = sha256.convert(
        utf8.encode(excerpt.substring(0, 16))).toString();
    final origins = _asObject(input['provenance'])['scene_origins'] as List;
    final refs = (origins.first as Map)['source_refs'] as List;
    (refs.first as Map)['quote_sha256'] = quoteSha;

    final original = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: index,
    );
    final review = <String, dynamic>{
      'format': 'ai_story_private_gameplay_review_m2h8e1_v1',
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': 'a' * 64,
      'base_archive_sha256': sha256.convert(original).toString(),
      'source_payload_digest': 'e' * 64,
      'user_confirmed': true,
      'literary_canon_verified': false,
      'effects': <Map<String, dynamic>>[
        {
          'scene_id': 'entry', 'choice_id': 'help',
          'op': 'grant_item', 'kind': 'item',
          'id': 'old_key', 'label': 'Ключ',
          'source_quote_sha256': quoteSha,
          'review_note': 'Читатель разрешил только вымышленную находку ключа.',
        },
        {
          'scene_id': 'entry', 'choice_id': 'help',
          'op': 'learn_fact', 'kind': 'fact',
          'id': 'opened_door', 'label': 'Открытая дверь',
          'source_quote_sha256': quoteSha,
          'review_note': 'Читатель одобрил игровое знание, не вывод о каноне.',
        },
      ],
    };
    const reviewedWriter = ReviewedGameplayBookworldWriter();
    final reviewed = reviewedWriter.build(
      verifiedBaseArchive: original, sourceIndex: index, userReview: review);
    final again = reviewedWriter.build(
      verifiedBaseArchive: original, sourceIndex: index, userReview: review);
    expect(reviewed, orderedEquals(again));
    final compiled = importer.inspect(reviewed);
    expect(compiled.bookworldId, isNot('book_private_sample'));
    expect(compiled.presentation['item_names'],
        containsPair('old_key', 'Ключ'));
    expect(compiled.presentation['fact_names'],
        containsPair('opened_door', 'Открытая дверь'));
    expect(compiled.canDistributePublicly, false);
    expect(compiled.requiresNetwork, false);
    final helping = StoryWorld(compiled.blueprint);
    expect(helping.apply(actionId: 'pick_up_key', choiceId: 'help',
        expectedRevision: 0).status, DecisionStatus.applied);
    expect(helping.state.inventory, contains('old_key'));
    expect(helping.state.knowledge['player'], contains('opened_door'));
    expect(helping.events.single.choiceId, 'help');
    expect(helping.isTerminal, true);
    final originalRoute = StoryWorld(compiled.blueprint);
    expect(originalRoute.apply(actionId: 'reject_key', choiceId: 'leave',
        expectedRevision: 0).status, DecisionStatus.applied);
    expect(originalRoute.state.inventory, isEmpty);
    expect(originalRoute.state.knowledge['player'], isEmpty);
    expect(originalRoute.isTerminal, true);
    final restored = StoryWorld.replay(
      compiled.blueprint,
      helping.events.map((e) => e.toJson()),
      expectedSequence: helping.state.revision,
      expectedStateHash: helping.state.stateHash,
    );
    expect(restored.state.stateHash, helping.state.stateHash);
    final output = File(
        '../../artifacts/bookworld/book_private_reviewed_dart.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(reviewed, flush: true);

    final badConsent = Map<String, dynamic>.from(review)
      ..['user_confirmed'] = false;
    expect(() => reviewedWriter.build(
      verifiedBaseArchive: original,
      sourceIndex: index, userReview: badConsent,
    ), throwsFormatException);
    final falseCanon = Map<String, dynamic>.from(review)
      ..['literary_canon_verified'] = true;
    expect(() => reviewedWriter.build(
      verifiedBaseArchive: original,
      sourceIndex: index, userReview: falseCanon,
    ), throwsFormatException);
    final foreignQuote = jsonDecode(jsonEncode(review)) as Map<String, dynamic>;
    (foreignQuote['effects'] as List).first['source_quote_sha256'] = 'f' * 64;
    expect(() => reviewedWriter.build(
      verifiedBaseArchive: original,
      sourceIndex: index, userReview: foreignQuote,
    ), throwsFormatException);
    final consumedOnRefusal =
        jsonDecode(jsonEncode(review)) as Map<String, dynamic>;
    final second = (consumedOnRefusal['effects'] as List)[1] as Map;
    second['choice_id'] = 'leave';
    second['op'] = 'consume_item';
    second['kind'] = 'item';
    second['id'] = 'old_key';
    second['label'] = 'Ключ';
    expect(() => reviewedWriter.build(
      verifiedBaseArchive: original,
      sourceIndex: index, userReview: consumedOnRefusal,
    ), throwsFormatException);
    expect(() => reviewedWriter.build(
      verifiedBaseArchive: reviewed,
      sourceIndex: index, userReview: review,
    ), throwsFormatException);
  });

  test('rich v3 rejects damaged ZIP without adopting it as an older format', () {
    final input = _richSample();
    final data = writer.build(
      blueprint: _asObject(input['blueprint']),
      provenance: _asObject(input['provenance']),
      sourceIndex: _asObject(input['source_index']),
    );
    final modified = Uint8List.fromList(data);
    modified[110] ^= 0xff;
    expect(() => importer.inspect(modified), throwsFormatException);
  });
}
