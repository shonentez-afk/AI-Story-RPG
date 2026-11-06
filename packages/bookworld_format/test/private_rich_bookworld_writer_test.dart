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
    expect(blockedWords[2].text, 'Я слушаю');
    final denied = world.apply(actionId: 'too_soon', choiceId: 'help');
    expect(denied.applied, isFalse);
    expect(denied.reason, 'condition_not_met:knows_fact');
    expect(world.actorKnowsFact(npcId, 'npc_secret'), isFalse);
    expect(world.apply(actionId: 'talk', choiceId: 'wait').applied, isTrue);
    expect(world.actorKnowsFact(npcId, 'npc_secret'), isTrue);
    expect(RichNpcDialogueKnowledge.redact(
        signed, reviewed, world.state.knowledge)[1].text,
        'Мне известен секрет!');
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
      first['text'] = 'Мария: «Я всё знаю».\\nИгрок: «Верно».';
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
