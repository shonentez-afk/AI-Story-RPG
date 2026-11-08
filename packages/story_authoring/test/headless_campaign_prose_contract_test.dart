import 'dart:convert';
import 'dart:io';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_campaign_prose_writer.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

String narration(String id) =>
    'Ветер приносил запах моря, и свет старого маяка становился '
    'всё отчетливее. Герой оглядел дорогу и пытался понять, '
    'какой выбор ему предстоит. Никакое решение ещё не было принято. '
    'Описание сцены $id остаётся только проверочным.';

Map<String, Object?> row(String id) => {
  'scene_id': id, 'prose': narration(id),
  'uncertainty': 'Эти слова требуют отдельной литературной проверки.',
};

String answer(String batch, List<Map<String, Object?>> scenes,
    {String finish = 'stop'}) {
  final request = jsonDecode(batch) as Map<String, dynamic>;
  return jsonEncode({'choices': [{
    'finish_reason': finish,
    'message': {'content': jsonEncode({
      'batch_id': request['batch_id'], 'scenes': scenes,
    })},
  }]});
}

void main() {
  test('batch rejects foreign, duplicate and missing scene IDs or effects', () {
    const batch = '{"format":"ai_story_campaign_prose_request_v1",'
        '"batch_id":"b1","scenes":[{"scene_id":"entry"},'
        '{"scene_id":"canon_end"}]}';
    final valid = CampaignProseBatchVerifier.parse(batch,
        answer(batch, [row('entry'), row('canon_end')]));
    expect(valid.map((x) => x.sceneId).toList(), ['entry', 'canon_end']);
    expect(valid.every((x) => x.origin == 'ai_draft'), true);
    for (final wrong in <List<Map<String, Object?>>>[
      [row('entry')],
      [row('entry'), row('entry')],
      [row('entry'), row('other_scene')],
      [row('entry'), {...row('canon_end'), 'effects': []}],
      [row('entry'), {...row('canon_end'), 'prose': 'коротко'}],
    ]) {
      expect(() => CampaignProseBatchVerifier.parse(batch,
          answer(batch, wrong)), throwsFormatException);
    }
    expect(() => CampaignProseBatchVerifier.parse(batch,
        answer(batch, [row('entry'), row('canon_end')],
          finish: 'length')), throwsFormatException);
  });

  test('headless finalizer adds narration without changing choices', () {
    final source = jsonDecode(File(
        '../../shared_schemas/fixtures/private_classic_sample.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final blueprint = Map<String, dynamic>.from(source['blueprint'] as Map);
    final provenance = Map<String, dynamic>.from(source['provenance'] as Map);
    provenance['format'] = 'ai_story_private_provenance_v2';
    provenance['model_provenance'] = <String, dynamic>{
      'provider': 'none', 'model_id': null, 'model_id_status': 'not_applicable',
      'tool': 'none', 'method': 'local_fixture',
    };
    provenance['presentation'] = <String, dynamic>{
      'hero': {'name': 'Игрок', 'description': 'Частная игра'},
      'item_names': <String, String>{},
      'item_descriptions': <String, String>{},
      'stat_names': <String, String>{},
      'fact_names': <String, String>{},
      'scene_names': {
        for (final scene in blueprint['scenes'] as List)
          (scene as Map)['id'] as String: 'Проверенная сцена',
      },
    };
    final sourceIndex = Map<String, dynamic>.from(source['source_index'] as Map);
    final original = const RichPrivateBookworldWriter().build(
        blueprint: blueprint, provenance: provenance,
        sourceIndex: sourceIndex);
    final before = const RichPrivateBookworldImporter().inspect(original);
    final review = ReviewedCampaignProseWriter.review(
        archive: original,
        narration: {
          for (final id in before.blueprint.scenes.keys) id: narration(id),
        });
    final digest = ReviewedCampaignProseWriter.digest(review);
    final result = CampaignProseFinalizer.compile(
      verifiedArchive: original, sourceIndex: sourceIndex,
      reviewJson: review, approvedDigest: digest,
      fullTextReviewed: true, privateFictionConfirmed: true);
    final after = const RichPrivateBookworldImporter().inspect(result);
    expect(after.sourceFingerprint, before.sourceFingerprint);
    expect(after.blueprint.scenes.length, before.blueprint.scenes.length);
    expect(after.requiresNetwork, false);
    expect(after.canDistributePublicly, false);
    for (final scene in before.blueprint.scenes.entries) {
      final result = after.blueprint.scenes[scene.key]!;
      expect(result.text, startsWith(narration(scene.key)));
      expect(result.text, contains(scene.value.text));
      expect(result.choices.map((x) => x.id).toList(),
          scene.value.choices.map((x) => x.id).toList());
    }
    expect(() => CampaignProseFinalizer.compile(
      verifiedArchive: original, sourceIndex: sourceIndex,
      reviewJson: review, approvedDigest: 'f' * 64,
      fullTextReviewed: true, privateFictionConfirmed: true),
      throwsFormatException);
    expect(() => CampaignProseFinalizer.compile(
      verifiedArchive: original, sourceIndex: sourceIndex,
      reviewJson: review, approvedDigest: digest,
      fullTextReviewed: false, privateFictionConfirmed: true),
      throwsFormatException);
    expect(() => CampaignProseFinalizer.compile(
      verifiedArchive: original, sourceIndex: sourceIndex,
      reviewJson: review, approvedDigest: digest,
      fullTextReviewed: true, privateFictionConfirmed: false),
      throwsFormatException);
  });
}
