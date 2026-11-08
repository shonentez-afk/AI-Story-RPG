/// Public, Flutter-independent API boundary for AI Story RPG.
///
/// Flutter, a Dart CLI, a future native frontend or a network adapter are
/// clients of these interfaces. This package does not own game rules,
/// persist platform paths, talk to a model or invent literary canon.
library;

import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart';
import 'package:story_authoring/story_authoring.dart';

export 'package:rpg_gameplay/rpg_gameplay.dart' show
    WorldLibraryItem, WorldCampaignItem, WorldSavePreview,
    WorldChoiceView, WorldEventView, NpcRelationView, WorldGameView,
    WorldChoiceResult, WorldLibraryGateway;
export 'package:story_authoring/story_authoring.dart' show
    ImportedBook, BookSourceIndex, SourceLockedBook,
    OfflineSourceReview, OfflineScanCheckpoint,
    BookPreparationSnapshot, BookToRpgWorkflow,
    NpcContinuityAudit, DraftSceneGraphOverview,
    CrossActSourceEvidencePacket, PreparationReadinessReport;
export 'package:bookworld_format/bookworld_format.dart' show
    VerifiedRichPrivateBookworld;

/// Contract version, not a promise that all planned game modes exist.
abstract final class RpgApiContract {
  static const version = '0.1.0';
  static const offlinePlay = true;
  static const verifiedPrivateCompilation = true;
  static const arbitraryBookCanon = false;
  static const dynamicAiGameMaster = false;
}

/// Synchronous game port. The client provides a private, already-open store.
///
/// No widget, Dart isolate, file picker, cloud transport or API key is used
/// here. A frontend is free to execute these operations in its own isolate.
/// The caller owns closing the supplied SQLite store.
abstract interface class RpgGameApi {
  List<WorldLibraryItem> worlds();
  WorldLibraryItem install(Uint8List archive);
  List<WorldCampaignItem> campaigns({String? worldHash});
  String start(String worldHash, {String? parentCampaignId});
  WorldGameView load(String campaignId);
  WorldChoiceResult choose(String campaignId, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  });
  String exportSave(String campaignId);
  WorldSavePreview previewSave(String text, {
    required String expectedWorldHash,
  });
  void deleteCampaign(String campaignId, {required int expectedRevision});
  Uint8List exportWorld(String worldHash);
  void deleteWorld(String worldHash);
  String importSave(String text, {required String expectedWorldHash});
}

/// The ONLY local game implementation delegates to the already-tested engine.
/// Never duplicate choice, knowledge, NPC, inventory or replay semantics.
final class LocalRpgGameApi implements RpgGameApi {
  LocalRpgGameApi(BookworldCampaignStore store)
      : _engine = RpgGameplayEngine(store);

  final RpgGameplayEngine _engine;

  @override
  List<WorldLibraryItem> worlds() => _engine.worlds();

  @override
  WorldLibraryItem install(Uint8List archive) => _engine.install(archive);

  @override
  List<WorldCampaignItem> campaigns({String? worldHash}) =>
      _engine.campaigns(worldHash: worldHash);

  @override
  String start(String worldHash, {String? parentCampaignId}) =>
      _engine.start(worldHash, parentCampaignId: parentCampaignId);

  @override
  WorldGameView load(String campaignId) => _engine.load(campaignId);

  @override
  WorldChoiceResult choose(String campaignId, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  }) => _engine.choose(campaignId,
      actionId: actionId, choiceId: choiceId,
      expectedRevision: expectedRevision);

  @override
  String exportSave(String campaignId) => _engine.exportSave(campaignId);

  @override
  WorldSavePreview previewSave(String text, {
    required String expectedWorldHash,
  }) => _engine.previewSave(text, expectedWorldHash: expectedWorldHash);

  @override
  void deleteCampaign(String campaignId, {required int expectedRevision}) =>
      _engine.deleteCampaign(campaignId, expectedRevision: expectedRevision);

  @override
  Uint8List exportWorld(String worldHash) => _engine.exportWorld(worldHash);

  @override
  void deleteWorld(String worldHash) => _engine.deleteWorld(worldHash);

  @override
  String importSave(String text, {required String expectedWorldHash}) =>
      _engine.importSave(text, expectedWorldHash: expectedWorldHash);
}

/// Independent book-authoring API. Input is bytes or a reviewed record, not
/// a widget or a network request. AI suggestions remain UNTRUSTED until a
/// separately reviewed source-bound compiler accepts them.
abstract interface class RpgAuthoringApi {
  ImportedBook parseBook(String filename, Uint8List bytes);
  SourceLockedBook openSource(String filename, Uint8List bytes,
      {int? selectedChapter});
  Future<BookPreparationSnapshot> prepareBook(SourceLockedBook source, {
    OfflineScanCheckpoint? resume,
    void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
    bool Function()? shouldStop,
  });
  BookSourceIndex indexBook(ImportedBook book);
  SourceLockedBook inspectSource(String filename, Uint8List bytes);
  Future<OfflineSourceReview> scanSource(SourceLockedBook source, {
    OfflineScanCheckpoint? resume,
    void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
    bool Function()? shouldStop,
  });
  Uint8List buildReviewedWorld({
    required SourceLockedBook source,
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    bool expanded = false,
  });
  Future<Uint8List> buildReviewedDraft({
    required SourceLockedBook source,
    required Map<String, dynamic> review,
    bool expanded = false,
  });
  VerifiedRichPrivateBookworld inspectPrivateWorld(Uint8List bytes);
}

/// Reuses the SAME source importer, analyzer and strict private compiler
/// already used by the Flutter app and standalone Dart CLI.
final class LocalRpgAuthoringApi implements RpgAuthoringApi {
  const LocalRpgAuthoringApi();

  static const _author = BookAuthoringEngine();

  @override
  ImportedBook parseBook(String filename, Uint8List bytes) =>
      BookImporter.parse(filename, bytes);

  @override
  SourceLockedBook openSource(String filename, Uint8List bytes,
      {int? selectedChapter}) =>
      const BookToRpgWorkflow().openSource(
          filename, bytes, selectedChapter: selectedChapter);

  @override
  Future<BookPreparationSnapshot> prepareBook(SourceLockedBook source, {
    OfflineScanCheckpoint? resume,
    void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
    bool Function()? shouldStop,
  }) => const BookToRpgWorkflow().prepare(source,
      resume: resume, onCheckpoint: onCheckpoint,
      shouldStop: shouldStop);

  @override
  BookSourceIndex indexBook(ImportedBook book) =>
      _author.indexImported(book).index;

  @override
  SourceLockedBook inspectSource(String filename, Uint8List bytes) =>
      _author.parseAndIndex(filename, bytes);

  @override
  Future<OfflineSourceReview> scanSource(SourceLockedBook source, {
    OfflineScanCheckpoint? resume,
    void Function(OfflineScanCheckpoint checkpoint)? onCheckpoint,
    bool Function()? shouldStop,
  }) => const OfflineBookAnalyzer().scan(source,
      resume: resume, onCheckpoint: onCheckpoint,
      shouldStop: shouldStop);

  @override
  Uint8List buildReviewedWorld({
    required SourceLockedBook source,
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    bool expanded = false,
  }) => _author.buildReviewedPrivateWorld(
      source: source, blueprint: blueprint,
      provenance: provenance, expanded: expanded);

  @override
  Future<Uint8List> buildReviewedDraft({
    required SourceLockedBook source,
    required Map<String, dynamic> review,
    bool expanded = false,
  }) => const PortableReviewedDraftCompiler().build(
      source: source, review: review, expanded: expanded);

  @override
  VerifiedRichPrivateBookworld inspectPrivateWorld(Uint8List bytes) =>
      _author.inspectPrivateWorld(bytes);
}
