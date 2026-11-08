import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'private_bookworld_writer.dart';
import 'private_rich_bookworld.dart';
import 'rich_scene_dialogue.dart';
import 'src/zip_v1.dart';

/// Text-only authoring over an already compiled campaign. A narration can
/// never supply choices, effects, facts, actors, provenance or permission.
/// Original quotations and signed dialogue remain verbatim after the new
/// opening paragraph. Only presentation turn indexes are shifted by one.
class ReviewedCampaignProseWriter {
  const ReviewedCampaignProseWriter();
  static const format = 'ai_story_complete_campaign_narration_v1';
  static const maxScenes = 192;
  static const maxReviewBytes = 2 * 1024 * 1024;

  static String digest(String reviewJson) => sha256.convert(
      utf8.encode('$format\n$reviewJson')).toString();

  static void validateNarration(Object? value) {
    // Exactly one narrator paragraph, never an additional attributed speech
    // turn. Existing knowledge-gated dialogue must not be re-authored here.
    if (value is! String || value.trim() != value ||
        value.length < 80 || value.length > 1800 ||
        !RegExp(r'[А-Яа-яЁё]').hasMatch(value) ||
        RegExp(r'[\x00-\x1f\x7f:«»"]').hasMatch(value)) {
      throw const FormatException('Нужен русский абзац повествования 80–1800 '
          'символов, без реплик, двоеточий, кавычек и переносов строк.');
    }
  }

  static String review({required Uint8List archive,
    required Map<String, String> narration}) {
    final original = const RichPrivateBookworldImporter().inspect(archive);
    _validateCoverage(original, narration);
    return canonicalJson({
      'format': format,
      'source_fingerprint': original.sourceFingerprint,
      'base_archive_sha256': original.archiveSha256,
      'base_blueprint_sha256': original.blueprint.blueprintHash,
      'scenes': narration,
    });
  }

  static void _validateCoverage(VerifiedRichPrivateBookworld original,
      Map<String, String> narration) {
    final ids = original.blueprint.scenes.keys.toSet();
    if (ids.isEmpty || ids.length > maxScenes || narration.length != ids.length ||
        !narration.keys.toSet().containsAll(ids)) {
      throw const FormatException('Нужен текст каждой сцены, включая обе '
          'развязки. Неполный или чужой набор не применяется.');
    }
    for (final text in narration.values) { validateNarration(text); }
  }

  /// Stable proof that the variant cannot change any gameplay field. Only
  /// book_id and scene text are excluded; initial state and ALL rules remain.
  static String mechanics(Map<String, dynamic> blueprint) {
    final copy = jsonDecode(jsonEncode(blueprint)) as Map<String, dynamic>;
    copy.remove('book_id');
    for (final scene in copy['scenes'] as List) { (scene as Map).remove('text'); }
    return canonicalJson(copy);
  }

  Uint8List build({required Uint8List verifiedArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson, required String approvedDigest,
    required bool fullTextReviewed, required bool privateFictionConfirmed}) {
    if (!fullTextReviewed || !privateFictionConfirmed ||
        approvedDigest != digest(reviewJson) ||
        utf8.encode(reviewJson).length > maxReviewBytes) {
      throw const FormatException('Нет нового согласия на полный текст этой игры.');
    }
    final original = const RichPrivateBookworldImporter().inspect(verifiedArchive);
    final raw = jsonDecode(reviewJson);
    const keys = {'format', 'source_fingerprint', 'base_archive_sha256',
      'base_blueprint_sha256', 'scenes'};
    if (raw is! Map<String, dynamic> || raw.length != keys.length ||
        !raw.keys.toSet().containsAll(keys) || raw['format'] != format ||
        raw['source_fingerprint'] != original.sourceFingerprint ||
        sourceIndex['source_fingerprint'] != original.sourceFingerprint ||
        raw['base_archive_sha256'] != original.archiveSha256 ||
        raw['base_blueprint_sha256'] != original.blueprint.blueprintHash ||
        raw['scenes'] is! Map) {
      throw const FormatException('Текст относится к другой редакции кампании.');
    }
    final narration = <String, String>{};
    for (final entry in (raw['scenes'] as Map).entries) {
      if (entry.key is! String) throw const FormatException('Неизвестная сцена.');
      validateNarration(entry.value);
      narration[entry.key as String] = entry.value as String;
    }
    _validateCoverage(original, narration);
    final files = BworldZipV1.readPrivate(verifiedArchive);
    final blueprint = jsonDecode(utf8.decode(files['scenario/blueprint.json']!))
        as Map<String, dynamic>;
    final provenance = jsonDecode(utf8.decode(files['source/provenance.json']!))
        as Map<String, dynamic>;
    final beforeMechanics = mechanics(blueprint);
    final presentation = provenance['presentation'] as Map<String, dynamic>;
    final dialogues = presentation['scene_dialogues'] as Map<String, dynamic>?;
    final reviews = presentation['scene_dialogue_knowledge'] as Map<String, dynamic>?;
    for (final rawScene in blueprint['scenes'] as List) {
      final scene = rawScene as Map<String, dynamic>;
      final id = scene['id'] as String, oldText = scene['text'] as String;
      final text = '${narration[id]}\n\n$oldText';
      if (text.length > RichSceneDialogue.maxSceneTextLength) {
        throw const FormatException('Итоговый текст сцены превышает лимит формата.');
      }
      final previousProjection = dialogues?[id];
      if (previousProjection != null) {
        final oldTurns = RichSceneDialogue.verify(previousProjection, oldText);
        final newTurns = RichSceneDialogue.parse(text);
        if (newTurns == null || newTurns.length != oldTurns.length + 1 ||
            newTurns.first.speaker != null || newTurns.first.text != narration[id]) {
          throw const FormatException('Повествование изменило структуру диалога.');
        }
        for (var i = 0; i < oldTurns.length; i++) {
          if (canonicalJson(oldTurns[i].toJson()) !=
              canonicalJson(newTurns[i + 1].toJson())) {
            throw const FormatException('Изменены слова или говорящий в принятом диалоге.');
          }
        }
        dialogues![id] = RichSceneDialogue.presentationFor(text);
        final oldReview = reviews?[id];
        if (oldReview != null) {
          if (oldReview is! List) throw const FormatException('Повреждено согласование реплик.');
          for (final row in oldReview) {
            if (row is! Map<String, dynamic> || row['turn_index'] is! int) {
              throw const FormatException('Повреждена позиция проверенной реплики.');
            }
            row['turn_index'] = (row['turn_index'] as int) + 1;
          }
        }
      } else if (RichSceneDialogue.presentationFor(text) != null) {
        throw const FormatException('Повествование не может создавать новый диалог.');
      }
      scene['text'] = text;
    }
    if (mechanics(blueprint) != beforeMechanics) {
      throw const FormatException('Художественный текст изменил игровые правила.');
    }
    final id = 'prose_${approvedDigest.substring(0, 32)}';
    blueprint['book_id'] = id; provenance['bookworld_id'] = id;
    // Source copies do not attest which model, if any, authored the prose.
    provenance['model_provenance'] = {
      'provider': 'unknown', 'model_id': null, 'model_id_status': 'not_attested',
      'tool': 'AI Story RPG', 'method': 'reviewed_local_compilation',
    };
    final result = const RichPrivateBookworldWriter().build(
        blueprint: blueprint, provenance: provenance, sourceIndex: sourceIndex);
    final verified = const RichPrivateBookworldImporter().inspect(result);
    if (verified.requiresNetwork || verified.canDistributePublicly ||
        verified.sourceFingerprint != original.sourceFingerprint) {
      throw const FormatException('Нарушен автономный частный формат игры.');
    }
    // Import independently validates the shifted dialogue knowledge guards.
    // The actual runtime still has to witness every original choice/ending.
    final proof = StoryCampaignCausalAudit.inspect(blueprint: verified.blueprint,
      socialRulebook: verified.npcSocialRulebook,
      requiredChoiceIds: [for (final scene in original.blueprint.scenes.values)
        for (final choice in scene.choices) choice.id]);
    if (!proof.playable || !proof.exhaustive) {
      throw const FormatException('Итоговая игра не прошла проверку прохождения.');
    }
    return result;
  }
}
