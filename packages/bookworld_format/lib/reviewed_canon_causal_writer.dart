import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'private_bookworld_writer.dart';
import 'private_rich_bookworld.dart';
import 'src/zip_v1.dart';

/// Adds human-approved, exact-source NPC witnesses and future causal
/// obligations to an existing, verified literal CANON v5 archive.
/// No chapter is replaced. No model response alone is an NPC source proof.
/// Result is a NEW private BookWorld v5 with a distinct ID/source certificate.
final class ReviewedCanonCausalBookworldWriter {
  const ReviewedCanonCausalBookworldWriter();
  static const reviewFormat = 'ai_story_source_causal_review_v1';
  static const graphReviewFormat = 'ai_story_source_causal_review_v2';

  static String digest(String reviewJson) =>
      sha256.convert(utf8.encode(
          'source-causal-review-v1\n' + reviewJson)).toString();

  Uint8List compile({
    required Uint8List verifiedLiteralCanon,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (!userConfirmed || reviewJson.length > 4194304 ||
        approvedDigest != digest(reviewJson)) {
      throw const FormatException('Source causal approval was not confirmed');
    }
    final parsed = jsonDecode(reviewJson);
    final graphReview = parsed is Map<String, dynamic> &&
        parsed['format'] == graphReviewFormat;
    if (parsed is! Map<String, dynamic> ||
        canonicalJson(parsed) != reviewJson ||
        parsed.keys.toSet().length != (graphReview ? 9 : 8) ||
        !parsed.keys.toSet().containsAll({
          'format', 'review_scope', 'source_fingerprint',
          'base_archive_sha256', 'user_confirmed',
          'semantic_canon_automatically_verified',
          'witnesses', 'invariants',
          if (graphReview) 'event_graph',
        })) {
      throw const FormatException('Noncanonical source causal review');
    }
    final base = const RichPrivateBookworldImporter()
        .inspect(verifiedLiteralCanon);
    if (base.formatVersion != 5 ||
        !base.sourceLiteralCanonVerified ||
        base.npcSocialRulebook != null ||
        base.blueprint.actors.length != 1 ||
        !{reviewFormat, graphReviewFormat}.contains(parsed['format']) ||
        parsed['base_archive_sha256'] != base.archiveSha256 ||
        parsed['source_fingerprint'] != base.sourceFingerprint ||
        parsed['user_confirmed'] != true ||
        parsed['semantic_canon_automatically_verified'] != false ||
        sourceIndex['source_fingerprint'] != base.sourceFingerprint ||
        sourceIndex['chapter_count'] != base.sourceChaptersTotal ||
        sourceIndex['indexed_chapter_count'] != base.sourceChaptersTotal) {
      throw const FormatException('Causal review belongs to another book edition');
    }
    final witnesses = parsed['witnesses'];
    final invariants = parsed['invariants'];
    if (witnesses is! List || witnesses.isEmpty ||
        witnesses.length > 128 || invariants is! List ||
        invariants.isEmpty || invariants.length > 256) {
      throw const FormatException('Missing reviewed causal characters/events');
    }
    final npcIds = <String>{};
    for (final raw in witnesses) {
      if (raw is! Map<String, dynamic> ||
          raw['actor_id'] is! String ||
          !CharacterId.isValidNpc(raw['actor_id'] as String)) {
        throw const FormatException('Unreviewed permanent NPC actor');
      }
      npcIds.add(raw['actor_id'] as String);
    }
    if (npcIds.isEmpty || npcIds.length > 15) {
      throw const FormatException('Too many unreviewed NPC identities');
    }
    final files = BworldZipV1.readPrivate(verifiedLiteralCanon);
    final bp = jsonDecode(utf8.decode(
        files['scenario/blueprint.json']!)) as Map<String, dynamic>;
    final origin = jsonDecode(utf8.decode(
        files['source/provenance.json']!)) as Map<String, dynamic>;
    if (origin.containsKey('canon_causality') ||
        origin.containsKey('npc_social') ||
        origin.containsKey('npc_knowledge')) {
      throw const FormatException('Source NPC review is already sealed');
    }
    final id = 'canon_' + base.sourceFingerprint.substring(0, 12) +
        '_causal_' + digest(reviewJson).substring(0, 12);
    bp['book_id'] = id;
    (bp['actors'] as List).addAll(npcIds.toList()..sort());
    final initial = bp['initial_state'] as Map<String, dynamic>;
    final knowledge = initial['knowledge'] as Map<String, dynamic>;
    for (final actor in npcIds) knowledge[actor] = <String>[];
    origin['bookworld_id'] = id;
    origin['canon_causality'] = parsed;
    final result = const RichPrivateBookworldWriter().build(
      blueprint: bp, provenance: origin,
      sourceIndex: sourceIndex, expanded: true, literalCanon: true,
    );
    final verified = const RichPrivateBookworldImporter().inspect(result);
    if (verified.formatVersion != 5 ||
        verified.npcSocialRulebook?.dynamicInteractionsEnabled != true ||
        verified.blueprint.actors.difference({'player'}).length != npcIds.length ||
        verified.blueprint.scenes.length != base.blueprint.scenes.length ||
        verified.sourceFingerprint != base.sourceFingerprint ||
        verified.requiresNetwork || verified.canDistributePublicly) {
      throw const FormatException('Reviewed CANON NPC route failed import');
    }
    for (final entry in base.blueprint.scenes.entries) {
      if (verified.blueprint.scenes[entry.key]?.text != entry.value.text) {
        throw const FormatException('Causal extension changed a book passage');
      }
    }
    return result;
  }
}
