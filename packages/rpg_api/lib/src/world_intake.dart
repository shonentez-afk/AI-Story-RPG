import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';

/// An independent, read-only preflight for a game authored by any client.
/// It verifies the actual game ZIP through the same trusted importers as
/// LocalRpgGameApi, but does not install, publish or advance a campaign.
final class RpgWorldIntakePreview {
  const RpgWorldIntakePreview({
    required this.title, required this.bookworldId,
    required this.archiveHash, required this.formatVersion,
    required this.sourceFingerprint, required this.sceneCount,
    required this.endingCount, required this.npcActorCount,
    required this.itemCount, required this.isPrivate,
    this.sourceChaptersTotal = 0,
    this.sourceChaptersIndexed = 0,
    this.sourceChaptersWithGameplay = 0,
    this.generatorReportAttached = false,
    this.producerClaimsTwoReplayedRoutes = false,
    this.sourceLiteralCanonVerified = false,
    this.sourceCausalReviewVerified = false,
  });

  final String title, bookworldId, archiveHash;
  final int formatVersion, sceneCount, endingCount, npcActorCount, itemCount;
  final String? sourceFingerprint;
  final bool isPrivate;
  final bool sourceLiteralCanonVerified;
  /// True only when the exact v5 source-backed full event graph has
  /// passed the native importer; never derived from a producer label.
  final bool sourceCausalReviewVerified;
  /// Canonical BookWorld provenance, not an external JSON assertion.
  final int sourceChaptersTotal, sourceChaptersIndexed;
  final int sourceChaptersWithGameplay;
  bool get allSourceChaptersCovered => sourceChaptersTotal > 0 &&
      sourceChaptersIndexed == sourceChaptersTotal &&
      sourceChaptersWithGameplay == sourceChaptersTotal;

  /// A SHA-bound producer statement; not a signature or an independent replay.
  final bool generatorReportAttached, producerClaimsTwoReplayedRoutes;

  bool get verifiedByNativeImporter => true;
  bool get literaryCanonProven => false;
  bool get allowedToPublish => false;
  bool get requiresNetwork => false;

  RpgWorldIntakePreview _withGeneratorReport() => RpgWorldIntakePreview(
    title: title, bookworldId: bookworldId, archiveHash: archiveHash,
    formatVersion: formatVersion, sourceFingerprint: sourceFingerprint,
    sceneCount: sceneCount, endingCount: endingCount,
    npcActorCount: npcActorCount, itemCount: itemCount, isPrivate: isPrivate,
    sourceChaptersTotal: sourceChaptersTotal,
    sourceChaptersIndexed: sourceChaptersIndexed,
    sourceChaptersWithGameplay: sourceChaptersWithGameplay,
    generatorReportAttached: true, producerClaimsTwoReplayedRoutes: true,
    sourceLiteralCanonVerified: sourceLiteralCanonVerified,
    sourceCausalReviewVerified: sourceCausalReviewVerified,
  );
}

abstract interface class RpgWorldIntakeApi {
  RpgWorldIntakePreview inspect(Uint8List archive, {String? readinessJson});
}

/// No Flutter, cloud key, filesystem, or invented RPG mechanics.
/// Every accepted world passed the canonical BookWorld native importer.
/// Generator .readiness.json is optional and NEVER authorizes public release.
final class LocalRpgWorldIntakeApi implements RpgWorldIntakeApi {
  const LocalRpgWorldIntakeApi();
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  @override
  RpgWorldIntakePreview inspect(Uint8List archive, {String? readinessJson}) {
    if (archive.isEmpty || archive.length > 12 * 1024 * 1024) {
      throw const FormatException('Игровой архив пуст или превышает 12 МБ.');
    }
    late RpgWorldIntakePreview inspected;
    try {
      final world = const RichPrivateBookworldImporter().inspect(archive);
      final bp = world.blueprint;
      inspected = RpgWorldIntakePreview(
        title: bp.title, bookworldId: world.bookworldId,
        archiveHash: world.archiveSha256, formatVersion: world.formatVersion,
        sourceFingerprint: world.sourceFingerprint,
        sceneCount: bp.scenes.length,
        endingCount: bp.scenes.values.where((s) => s.terminal).length,
        npcActorCount: bp.actors.where((a) => a != 'player').length,
        itemCount: bp.items.length, isPrivate: true,
        sourceLiteralCanonVerified: world.sourceLiteralCanonVerified,
        sourceCausalReviewVerified:
            world.npcSocialRulebook?.bookCausality != null,
        sourceChaptersTotal: world.sourceChaptersTotal,
        sourceChaptersIndexed: world.sourceChaptersIndexed,
        sourceChaptersWithGameplay: world.sceneOrigins.values
            .where((origin) => origin.isSourcePassage)
            .map((origin) => origin.chapterIndex).toSet().length,
      );
    } on FormatException {
      try {
        final world = const PrivateBookworldImporter().inspect(archive);
        final bp = world.blueprint;
        inspected = RpgWorldIntakePreview(
          title: bp.title, bookworldId: world.bookworldId,
          archiveHash: world.archiveSha256, formatVersion: 2,
          sourceFingerprint: world.sourceFingerprint,
          sceneCount: bp.scenes.length,
          endingCount: bp.scenes.values.where((s) => s.terminal).length,
          npcActorCount: bp.actors.where((a) => a != 'player').length,
          itemCount: bp.items.length, isPrivate: true,
        );
      } on FormatException {
        final world = const BookworldImporter().inspect(archive);
        final bp = world.blueprint;
        inspected = RpgWorldIntakePreview(
          title: bp.title, bookworldId: world.bookworldId,
          archiveHash: world.archiveHash, formatVersion: 1,
          sourceFingerprint: bp.sourceFingerprint,
          sceneCount: bp.scenes.length,
          endingCount: bp.scenes.values.where((s) => s.terminal).length,
          npcActorCount: bp.actors.where((a) => a != 'player').length,
          itemCount: bp.items.length, isPrivate: false,
        );
      }
    }
    if (readinessJson == null) return inspected;
    _verifyGeneratorReport(inspected, archive, readinessJson);
    return inspected._withGeneratorReport();
  }

  static void _verifyGeneratorReport(
      RpgWorldIntakePreview game, Uint8List archive, String text) {
    if (game.formatVersion != 4 || !game.isPrivate ||
        text.length > 256 * 1024) {
      throw const FormatException(
          'Отчёт полного генератора применим только к приватному v4.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Не удалось прочитать отчёт генератора.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] !=
          'rpg_author_complete_native_campaign_acceptance_v1' ||
        decoded['status'] != 'native_multi_act_campaign_mechanically_verified' ||
        decoded['format_version'] != 4 ||
        decoded['archive_sha256'] != game.archiveHash ||
        decoded['source_fingerprint'] != game.sourceFingerprint ||
        decoded['private_only'] != true ||
        decoded['literary_truth_attested'] != false ||
        decoded['automatic_ai_book_canon_verified'] != false ||
        decoded['user_ready'] != false ||
        decoded['native_routes'] is! Map<String, dynamic> ||
        decoded['source_review'] is! Map<String, dynamic> ||
        decoded['reviewed_extension'] is! Map<String, dynamic>) {
      throw const FormatException(
          'Отчёт другой редакции или неподдерживаемые заявления о готовности.');
    }
    final routes = decoded['native_routes'] as Map<String, dynamic>;
    final source = decoded['source_review'] as Map<String, dynamic>;
    final extension = decoded['reviewed_extension'] as Map<String, dynamic>;
    if (routes['status'] !=
            'two_complete_routes_native_rpg_api_and_sqlite_verified' ||
        routes['archive_sha256'] != game.archiveHash ||
        routes['route_count'] != 2 || routes['endings_verified'] != 2 ||
        routes['native_game_rules_reused'] != true ||
        routes['python_game_rule_fork_used'] != false ||
        routes['routes'] is! List ||
        (routes['routes'] as List).length != 2 ||
        source['verified_scene_review_records'] != game.sceneCount ||
        source['source_evidence_binds_exact_revision'] != true ||
        source['review_report_complete'] != true ||
        source['literary_truth_attested'] != false ||
        source['reviewed_full_routes'] != 2 ||
        source['reviewed_distinct_ending_scenes'] != 2 ||
        source['reviewed_book_chapters'] is! int ||
        (source['reviewed_book_chapters'] as int) < 2 ||
        source['reviewed_book_chapters'] != game.sourceChaptersTotal ||
        source['source_chapters_with_gameplay'] !=
            game.sourceChaptersWithGameplay ||
        !game.allSourceChaptersCovered ||
        extension['act_count'] is! int ||
        (extension['act_count'] as int) < 2 ||
        extension['chapters_without_source_scenes'] is! List ||
        (extension['chapters_without_source_scenes'] as List).isNotEmpty) {
      throw const FormatException('Отчёт не подтверждает полный охват книги.');
    }
    // A report contains ENDINGS and signed hashes, not choice traces.
    // Never pretend this inspection repeated the producer's SQLite replays.
    final verified = const RichPrivateBookworldImporter().inspect(archive);
    final terminal = verified.blueprint.scenes.entries
        .where((entry) => entry.value.terminal)
        .map((entry) => entry.key).toSet();
    final seenRouteIds = <String>{}, seenEndings = <String>{};
    for (final value in routes['routes'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Некорректный маршрут в отчёте.');
      }
      final id = value['route_id'];
      final end = value['ending_scene_id'];
      final steps = value['replayed_choices'];
      final state = value['native_state_sha256'];
      if (id is! String || id.isEmpty || !seenRouteIds.add(id) ||
          end is! String || !terminal.contains(end) ||
          !seenEndings.add(end) || steps is! int ||
          steps < 2 || steps > 512 ||
          value['portable_save_verified'] != true ||
          state is! String || !_hash.hasMatch(state)) {
        throw const FormatException(
            'Отчёт заявляет непроверяемый или повторный финал.');
      }
    }
    if (seenEndings.length != 2) {
      throw const FormatException('Нужны две различные концовки.');
    }
  }
}
