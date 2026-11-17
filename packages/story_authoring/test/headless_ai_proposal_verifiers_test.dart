import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

Map<String, dynamic> _obj(Object? value) =>
    Map<String, dynamic>.from(value as Map);

(NpcDialogueDraftContext, VerifiedRichPrivateBookworld) _context() {
  final sample = _obj(jsonDecode(
      File('../../shared_schemas/fixtures/private_classic_sample.json')
          .readAsStringSync()));
  final bp = _obj(sample['blueprint']);
  final provenance = _obj(sample['provenance']);
  final npc = 'npc_' + List.filled(32, 'c').join();
  (bp['actors'] as List).add(npc);
  (bp['facts'] as List).add('npc_secret');
  final initial = _obj(bp['initial_state']);
  (initial['knowledge'] as Map)[npc] = <String>[];
  bp['initial_state'] = initial;
  final entry = (bp['scenes'] as List).first as Map;
  final learning = (entry['choices'] as List).first as Map;
  (learning['effects'] as List).add({
    'op': 'learn_fact', 'id': 'npc_secret', 'actor': npc,
  });
  final encounter = (bp['scenes'] as List)[1] as Map;
  encounter['text'] = 'Мария: «Теперь я слышала историю.»\n'
      'Игрок: «Расскажи подробнее.»\n'
      'Мария: «Ты можешь выбрать свой путь.»';
  final source = (provenance['scene_origins'] as List).first as Map;
  final quote = (source['source_refs'] as List).first['quote_sha256'];
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = <String, dynamic>{
    'provider': 'none', 'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  provenance['presentation'] = <String, dynamic>{
    'hero': {'name': 'Игрок', 'description': 'Частный герой'},
    'item_names': <String, String>{},
    'item_descriptions': <String, String>{},
    'stat_names': <String, String>{},
    'fact_names': {'npc_secret': 'Проверенный факт NPC'},
    'scene_names': {
      'entry': 'Начало', 'canon_end': 'Разговор',
      'alternate_end': 'Другой исход',
    },
    'scene_dialogues': {
      'canon_end':
          RichSceneDialogue.presentationFor(encounter['text'] as String),
    },
    'scene_dialogue_knowledge': {
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
        {
          'turn_index': 2, 'speaker': 'Мария', 'actor_id': npc,
          'required_fact_ids': <String>[],
        },
      ],
    },
  };
  provenance['npc_knowledge'] = {
    'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': bp['source_fingerprint'],
    'user_confirmed': true,
    'literary_canon_verified': false,
    'grants': [
      {
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': npc, 'fact_id': 'npc_secret',
        'source_quote_sha256': quote,
      },
    ],
  };
  final bytes = const RichPrivateBookworldWriter().build(
    blueprint: bp, provenance: provenance,
    sourceIndex: _obj(sample['source_index']),
  );
  final verified = const RichPrivateBookworldImporter().inspect(bytes);
  final origins = <String, dynamic>{
    for (final raw in provenance['scene_origins'] as List)
      (raw as Map)['scene_id'] as String: raw,
  };
  return (NpcDialogueDraftContext.fromVerifiedWorld(
    world: verified, sceneId: 'canon_end', sceneOrigins: origins,
    approvedMotivations: {
      npc: 'Пытается осторожно предупредить игрока о выборе.',
    },
    approvedFactDescriptions: {
      'npc_secret': 'Ранее услышанное сообщение о событиях.',
    },
  ), verified);
}


class _CitedEvent implements BookEventProposal {
  const _CitedEvent(this.id, this.chapterIndex, this.blockIndex,
      this.chunkId, this.startUtf16, this.quote);
  @override final String id;
  @override final int chapterIndex, blockIndex, startUtf16;
  @override final String chunkId, quote;
  @override String get label => quote;
}

class _SourceOutline implements BookEventOutline {
  const _SourceOutline(this.sourceFingerprint, this.events);
  @override final String sourceFingerprint;
  @override final List<BookEventProposal> events;
  @override int get totalChapters => 1;
  @override int get chaptersWithEventProposals => 1;
  @override bool get analysisComplete => true;
}

(BookSourceIndex, NarrativeBookModel, StoryPlan) _scenario() {
  const first = 'Мария открыла ворота';
  const second = 'Иван вошёл в город';
  const text = '$first. $second.';
  final index = const BookAuthoringEngine().parseAndIndex(
      'book.txt', Uint8List.fromList(utf8.encode(text))).index;
  final chunk = index.chunks.single;
  final book = NarrativeBookModel.fromExisting(
    index: index,
    outline: _SourceOutline(index.sourceFingerprint, [
      _CitedEvent('event_open', chunk.chapterIndex, chunk.blockIndex,
          chunk.id, chunk.startUtf16 + text.indexOf(first), first),
      _CitedEvent('event_enter', chunk.chapterIndex, chunk.blockIndex,
          chunk.id, chunk.startUtf16 + text.indexOf(second), second),
    ]),
  );
  final proposal = StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: 'event_open',
    outcomeEventId: 'event_enter',
    kind: StoryDilemmaKind.agreement,
    dilemma: 'Попросить ли Ивана помочь открыть ворота?',
    acceptIntent: 'Согласиться помочь Ивану открыть ворота.',
    refuseIntent: 'Отказаться от помощи и искать другой путь.',
    followupGoal: 'Открыть ворота вместе с Иваном.',
    finishOriginalIntent: 'Подтвердить помощь и войти во двор.',
    originalEnding: 'Герой получает помощь и проходит через ворота.',
    alternativeSearchGoal: 'Исследовать окрестности в поисках обхода.',
    searchIntent: 'Осмотреть старую тропинку вокруг ворот.',
    alternativeDiscovery: 'На тропе находится проход между деревьями.',
    useDiscoveryIntent: 'Использовать найденную тропинку для обхода.',
    alternativeEnding: 'Герой обходит ворота и уходит своей дорогой.',
  );
  final plan = StoryPlanDilemmaGenerator.propose(book, proposal);
  if (!plan.validate(book).isStructurallySound) {
    throw StateError('Invalid fixture');
  }
  return (index, book, plan);
}

String _envelope(Map<String, Object?> payload, {
  String? finishReason = 'stop',
}) => jsonEncode({
  'choices': [
    {
      'finish_reason': finishReason,
      'message': {'content': jsonEncode(payload)},
    }
  ],
});

const _prose = 'Путник остановился у старых ворот, прислушиваясь к '
    'словам своего спутника. Он не давал обещаний и только '
    'обдумывал возможности. Решение ещё не было принято.';

void main() {
  test('source-bound NPC dialogue can be validated by standalone Dart', () {
    final (context, _) = _context();
    final reply = _envelope({
      'scene_id': context.sceneId,
      'turns': [
        {'turn_index': 0, 'speaker': 'Мария',
         'text': 'Я помню тот рассказ и могу ответить.'},
        {'turn_index': 1, 'speaker': 'Игрок',
         'text': 'Тогда скажи мне, что случилось.'},
        {'turn_index': 2, 'speaker': 'Мария',
         'text': 'Решение остаётся только за тобой.'},
      ],
      'uncertainty': 'Характер героев требует дальнейшей проверки.',
    });
    final draft = NpcDialogueCloudVerifier.parseForTest(context, reply);
    expect(draft.sceneId, context.sceneId);
    expect(draft.sceneText, contains('Мария: «'));
    expect(draft.canInstallDirectly, isFalse);
    expect(draft.canModifyCampaign, isFalse);
    final spoof = jsonDecode(reply) as Map<String, dynamic>;
    final forged = jsonDecode(
        (spoof['choices'][0]['message'] as Map)['content'] as String)
        as Map<String, dynamic>;
    (forged['turns'][0] as Map)['speaker'] = 'Неизвестный король';
    spoof['choices'][0]['message']['content'] = jsonEncode(forged);
    expect(() => NpcDialogueCloudVerifier.parseForTest(
        context, jsonEncode(spoof)), throwsFormatException);
    final extra = Map<String, Object?>.from(forged)
      ..['turns'] = [
        {'turn_index': 0, 'speaker': 'Мария',
         'text': 'Я помню тот рассказ и могу ответить.'},
        {'turn_index': 1, 'speaker': 'Игрок',
         'text': 'Тогда скажи мне, что случилось.'},
        {'turn_index': 2, 'speaker': 'Мария',
         'text': 'Решение остаётся только за тобой.'},
      ]
      ..['canon_confirmed'] = true;
    expect(() => NpcDialogueCloudVerifier.parseForTest(context,
        _envelope(extra)), throwsFormatException);
  });

  test('one-scene prose cannot promote claims or change a scene id', () {
    final (index, book, plan) = _scenario();
    final context = SourceLockedProseContext.forSituation(
        index: index, book: book, plan: plan,
        situationId: plan.situations.first.id);
    final accepted = SourceLockedProseResponseVerifier.parse(context,
        _envelope({
          'scene_id': context.situation.id,
          'prose': _prose,
          'uncertainty': 'Причинность сцены требует отдельной проверки.',
        }));
    expect(accepted.approvalDigest, context.approvalDigest);
    expect(accepted.canInstallDirectly, isFalse);
    expect(accepted.canMutateCampaign, isFalse);
    expect(() => SourceLockedProseResponseVerifier.parse(context,
        _envelope({
          'scene_id': 'foreign_scene',
          'prose': _prose,
          'uncertainty': 'Причинность сцены требует отдельной проверки.',
        })), throwsFormatException);
    expect(() => SourceLockedProseResponseVerifier.parse(context,
        _envelope({
          'scene_id': context.situation.id,
          'prose': _prose,
          'uncertainty': 'Причинность сцены требует отдельной проверки.',
          'rights_status': 'public',
        })), throwsFormatException);
  });

  test('item and knowledge proposals stay source/decision-locked', () {
    final (index, book, plan) = _scenario();
    final context = SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: [for (final e in book.events) e.id],
    );
    final anchor = context.choices.firstWhere(
        (c) => c.sourceEventId == 'event_open');
    Map<String, Object?> candidate({String op = 'grant_item',
        String name = 'ворота'}) => {
      'kind': 'item', 'id': 'book_gate', 'label': name,
      'op': op, 'scene_id': anchor.sceneId,
      'choice_id': anchor.choiceId,
      'source_event_id': anchor.sourceEventId,
      'uncertainty': 'В тексте предмет упомянут, но владение не доказано.',
    };
    final draft = GameplayCandidateProposalVerifier.parse(context,
        _envelope({'proposals': [candidate()]}, finishReason: null));
    expect(draft.hasCandidate, true);
    expect(draft.mayChangeGameState, isFalse);
    expect(draft.isAcceptedIntoGame, isFalse);
    for (final bad in [
      candidate(op: 'set_npc_knowledge'),
      candidate(name: 'несуществующая вещь'),
      {...candidate(), 'scene_id': 'forged_scene'},
      {...candidate(), 'can_mutate_game': true},
    ]) {
      expect(() => GameplayCandidateProposalVerifier.parse(context,
          _envelope({'proposals': [bad]}, finishReason: null)),
          throwsFormatException);
    }
  });

  test('literary critique is untrusted and rejects invented quotations', () {
    final (index, book, plan) = _scenario();
    final scene = SourceLockedProseContext.forSituation(
        index: index, book: book, plan: plan,
        situationId: plan.situations.first.id);
    final draft = SourceLockedProseDraft(
        sourceFingerprint: index.sourceFingerprint,
        situationId: scene.situation.id,
        approvalDigest: scene.approvalDigest,
        text: _prose,
        uncertainty: 'Причинность не проверена по всей книге.',
        route: scene.situation.route);
    final context = SourceLockedProseAuditContext.forDraft(
        index: index, book: book, plan: plan, draft: draft);
    final result = AiProseAuditVerifier.parse(context,
        _envelope({
          'scene_id': scene.situation.id,
          'verdict': 'needsRevision',
          'findings': [],
          'uncertainty': 'Неизвестны события, произошедшие в других главах.',
        }));
    expect(result.literaryCanonConfirmed, isFalse);
    expect(result.mayEditGameRules, isFalse);
    expect(result.mayAutoApprove, isFalse);
    expect(result.contextDigest, context.approvalDigest);
    expect(() => AiProseAuditVerifier.parse(context,
        _envelope({
          'scene_id': scene.situation.id,
          'verdict': 'possibleConsistency',
          'findings': [
            {
              'kind': 'worldTime', 'severity': 'low',
              'problem': 'Возможно нарушена хронология книги.',
              'evidence_quote': 'Выдуманная цитата',
            },
          ],
          'uncertainty': 'Неизвестны события, произошедшие в других главах.',
        })), throwsFormatException);
  });
}
