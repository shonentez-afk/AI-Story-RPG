import 'dart:convert';
import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const _actor = 'npc_cccccccccccccccccccccccccccccccc';

({StoryBlueprint blueprint, Map<String, dynamic> origins, String quote})
    _sample({bool lockedGrant = false}) {
  final doc = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final blueprint = doc['blueprint'] as Map<String, dynamic>;
  (blueprint['actors'] as List).add(_actor);
  (blueprint['facts'] as List).add('npc_secret');
  final initial = blueprint['initial_state'] as Map<String, dynamic>;
  (initial['knowledge'] as Map<String, dynamic>)[_actor] = <String>[];
  final entry = (blueprint['scenes'] as List).first as Map<String, dynamic>;
  final wait = (entry['choices'] as List)[0] as Map<String, dynamic>;
  (wait['effects'] as List).add({
    'op': 'learn_fact', 'id': 'npc_secret', 'actor': _actor,
  });
  if (lockedGrant) {
    // A graph-only audit sees this self-loop, but no player can make it
    // true. The only choice setting "helped" true is itself locked.
    (wait['conditions'] as List).add({
      'op': 'flag_is', 'id': 'helped', 'value': true,
    });
    ((entry['choices'] as List)[1] as Map)['conditions'] = [
      {'op': 'knows_fact', 'actor': _actor, 'id': 'npc_secret'},
    ];
  }
  final end = (blueprint['scenes'] as List)[1] as Map<String, dynamic>;
  end['text'] = 'Мария: «Теперь я знаю твой секрет.»\n'
      'Игрок: «Мы можем говорить.»';
  final prov = doc['provenance'] as Map<String, dynamic>;
  final origins = <String, dynamic>{
    for (final item in prov['scene_origins'] as List)
      (item as Map)['scene_id'] as String: item,
  };
  final source = (origins['entry']['source_refs'] as List).first as Map;
  return (
    blueprint: StoryBlueprint.fromJson(blueprint),
    origins: origins,
    quote: source['quote_sha256'] as String,
  );
}

void main() {
  test('source-reviewed NPC line gains real replayable causal witness', () {
    final source = _sample();
    final proposal = RichNpcDialogueAuthoring.propose(
      blueprint: source.blueprint,
      sceneOrigins: source.origins,
      reviewedSpeakerActorIds: {'Мария': _actor, 'Игрок': 'player'},
      verifiedNpcFactGrants: [{
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': _actor, 'fact_id': 'npc_secret',
        'source_quote_sha256': source.quote,
      }],
      reviewedNpcFactByTurn: {'canon_end': {0: 'npc_secret'}},
      reviewedSafeNpcTurns: const {},
      wholeDialogueTextReviewed: true,
      privateFictionAcknowledged: true,
    );
    expect(proposal.causallyGuardedLineCount, 1);
    expect(proposal.approvalDigest, hasLength(64));
    final accepted = RichNpcDialogueAuthoring.accept(
      proposal: proposal,
      blueprint: source.blueprint,
      reviewedSpeakerActorIds: {'Мария': _actor, 'Игрок': 'player'},
      approvedDigest: proposal.approvalDigest, userConfirmed: true,
    );
    expect(accepted['canon_end']![0]['required_prior_choice_id'], 'wait');
    final report = StoryCausalRouteAudit.find(
      blueprint: source.blueprint,
      targetSceneId: 'canon_end',
      requiredPriorChoiceId: 'wait',
      actorId: _actor, requiredFactIds: const ['npc_secret'],
    );
    expect(report.proven, true);
    final events = report.events.map((e) => e.toJson());
    expect(StoryWorld.replay(source.blueprint, events,
        expectedSequence: 2,
        expectedStateHash: report.resultStateHash)
        .actorKnowsFact(_actor, 'npc_secret'), true);
  });

  test('structurally connected but impossible author dialogue is rejected', () {
    final source = _sample(lockedGrant: true);
    expect(() => RichNpcDialogueAuthoring.propose(
      blueprint: source.blueprint,
      sceneOrigins: source.origins,
      reviewedSpeakerActorIds: {'Мария': _actor, 'Игрок': 'player'},
      verifiedNpcFactGrants: [{
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': _actor, 'fact_id': 'npc_secret',
        'source_quote_sha256': source.quote,
      }],
      reviewedNpcFactByTurn: {'canon_end': {0: 'npc_secret'}},
      reviewedSafeNpcTurns: const {},
      wholeDialogueTextReviewed: true,
      privateFictionAcknowledged: true,
    ), throwsFormatException);
  });

  test('social memory and directed trust need an executable action', () {
    final source = _sample();
    final reviews = <String, dynamic>{
      'canon_end': [
        {
          'turn_index': 0, 'actor_id': _actor, 'speaker': 'Мария',
          'required_fact_ids': <String>[],
          'required_social_memory_id': 'npc_promise',
          'minimum_trust_to_player': 10,
        },
        {
          'turn_index': 1, 'actor_id': 'player', 'speaker': 'Игрок',
          'required_fact_ids': <String>[],
        },
      ],
    };
    final rules = NpcSocialRulebook(
      blueprintHash: source.blueprint.blueprintHash,
      rules: const [
        NpcSocialRule(
          memoryId: 'npc_promise', sceneId: 'entry',
          choiceId: 'wait', observerId: _actor,
          kind: NpcMemoryKind.promiseReceived,
          relatedActorId: 'player', relationshipDelta: 10,
        ),
      ],
    );
    // Full authoring preflight checks the real visited route rather than
    // treating a future rule definition as an event that already happened.
    RichNpcDialogueKnowledge.auditExecutableRoutes(
      reviews, source.blueprint, socialRules: rules,
    );
    final impossible = _sample(lockedGrant: true);
    final locked = NpcSocialRulebook(
      blueprintHash: impossible.blueprint.blueprintHash,
      rules: const [
        NpcSocialRule(
          memoryId: 'npc_promise', sceneId: 'entry',
          choiceId: 'wait', observerId: _actor,
          kind: NpcMemoryKind.promiseReceived,
          relatedActorId: 'player', relationshipDelta: 10,
        ),
      ],
    );
    expect(() => RichNpcDialogueKnowledge.auditExecutableRoutes(
      reviews, impossible.blueprint, socialRules: locked,
    ), throwsFormatException);
  });

  test('bounded author preflight cannot claim that partial search proved it', () {
    final source = _sample();
    final reviews = <String, dynamic>{
      'canon_end': [
        {
          'turn_index': 0, 'actor_id': _actor, 'speaker': 'Мария',
          'required_fact_ids': ['npc_secret'],
          'required_prior_choice_id': 'wait',
        },
      ],
    };
    expect(() => RichNpcDialogueKnowledge.auditExecutableRoutes(
      reviews, source.blueprint, maxMoves: 1,
    ), throwsFormatException);
  });
}
