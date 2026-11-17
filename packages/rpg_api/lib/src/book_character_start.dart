part of '../rpg_api.dart';

/// Book-character gameplay authoring, not a second StoryWorld or a CANON flag.
/// The v4 archive already contains a selected, source-reviewed permanent
/// player identity. This API binds human-reviewed chapter-zero evidence to
/// actual starting inventory/knowledge and to executable choice conditions.
abstract interface class RpgBookCharacterStartApi {
  Map<String, Object?> inspect(Uint8List archive);
  Uint8List compile({
    required Uint8List verifiedBaseArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  });
  Uint8List compileWithReviewedRole({
    required Uint8List verifiedBaseArchive,
    required BookSourceIndex index,
    required ReviewedHeroRole reviewedRole,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  });
}

final class LocalRpgBookCharacterStartApi
    implements RpgBookCharacterStartApi {
  const LocalRpgBookCharacterStartApi();

  static final RegExp _role = RegExp(r'^player_is_(npc_[a-f0-9]{32})$');

  @override
  Map<String, Object?> inspect(Uint8List archive) {
    final checked = const RichPrivateBookworldImporter().inspect(archive);
    final selected = checked.blueprint.initial.flags.entries.where(
        (entry) => _role.hasMatch(entry.key) && entry.value).toList();
    final playerFacts = checked.blueprint.initial.knowledge['player'] ??
        const <String>{};
    final withStart = checked.blueprint.initial.inventory.isNotEmpty ||
        playerFacts.isNotEmpty;
    if (selected.length > 1) {
      // No alternative book hero may inherit another's property or facts.
      throw const FormatException('Ambiguous source-reviewed book hero');
    }
    final characterId = selected.isEmpty
        ? null : _role.firstMatch(selected.single.key)!.group(1);
    return {
      'world_hash': checked.archiveSha256,
      'bookworld_id': checked.bookworldId,
      'format_version': checked.formatVersion,
      'source_fingerprint': checked.sourceFingerprint,
      'reviewed_source_character_id': characterId,
      'starting_inventory_ids': [...checked.blueprint.initial.inventory]..sort(),
      'starting_player_fact_ids': [...playerFacts]..sort(),
      'source_reviewed_start': characterId != null && withStart &&
          checked.formatVersion == 4,
      'is_playable_without_ai': !checked.requiresNetwork,
      'literary_canon_verified': false,
      'may_publish': false,
      'needs_explicit_human_review': true,
    };
  }

  @override
  Uint8List compile({
    required Uint8List verifiedBaseArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    final base = inspect(verifiedBaseArchive);
    if (base['format_version'] != 4 ||
        base['reviewed_source_character_id'] == null ||
        base['source_reviewed_start'] == true) {
      throw const FormatException('Cannot rewrite an unreviewed game identity');
    }
    final compiled = const ReviewedBookCharacterStartWriter().build(
      verifiedBaseArchive: verifiedBaseArchive,
      sourceIndex: sourceIndex, reviewJson: reviewJson,
      approvedDigest: approvedDigest, userConfirmed: userConfirmed,
    );
    final result = inspect(compiled);
    if (result['reviewed_source_character_id'] !=
            base['reviewed_source_character_id'] ||
        result['source_reviewed_start'] != true ||
        result['source_fingerprint'] != base['source_fingerprint'] ||
        result['world_hash'] == base['world_hash']) {
      throw const FormatException('Hero start is not verified by the RPG API');
    }
    return compiled;
  }

  /// Typed Flutter/Dart authoring adds the independent reviewed-dossier
  /// proof. External languages still must pass the same exact opening
  /// citation, consent and archive-derived permanent role through compile().
  @override
  Uint8List compileWithReviewedRole({
    required Uint8List verifiedBaseArchive,
    required BookSourceIndex index,
    required ReviewedHeroRole reviewedRole,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (reviewedRole.sourceFingerprint != index.sourceFingerprint ||
        reviewedRole.firstSourceChapter != 0) {
      throw const FormatException('Book character is not source-known at start');
    }
    final raw = jsonDecode(reviewJson);
    if (raw is! Map<String, dynamic> ||
        raw['character_id'] != reviewedRole.characterId ||
        raw['character_group_digest'] != reviewedRole.groupDigest ||
        raw['source_fingerprint'] != index.sourceFingerprint ||
        raw['hero_mention'] is! Map<String, dynamic>) {
      throw const FormatException('Player role was not editorially confirmed');
    }
    final mention = raw['hero_mention'] as Map<String, dynamic>;
    var confirmed = false;
    for (final source in reviewedRole.confirmedMentions) {
      source.validate(index);
      if (source.status == EvidenceStatus.confirmed &&
          source.kind == EvidenceKind.character &&
          source.visibleAfterChapter == 0 &&
          source.chapterIndex == 0 &&
          source.id == mention['evidence_id'] &&
          source.chunkId == mention['chunk_id'] &&
          source.startUtf16 == mention['start_utf16'] &&
          source.endUtf16 == mention['end_utf16'] &&
          source.evidenceSha256 == mention['evidence_sha256']) {
        confirmed = true;
      }
    }
    if (!confirmed) {
      throw const FormatException('Hero first-chapter evidence was not reviewed');
    }
    return compile(
      verifiedBaseArchive: verifiedBaseArchive,
      sourceIndex: index.toJson(),
      reviewJson: reviewJson, approvedDigest: approvedDigest,
      userConfirmed: userConfirmed,
    );
  }
}
