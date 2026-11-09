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
    CrossActSourceEvidencePacket, PreparationReadinessReport,
    NpcDialogueDraftContext, NpcDialogueCloudDraft,
    SourceLockedProseContext, SourceLockedProseDraft,
    SourceLockedGameplayContext, GameplayCandidateDraft,
    SourceLockedProseAuditContext, AiProseFindingKind,
    AiProseFindingSeverity, AiProseAuditVerdict,
    AiProseAuditFinding, AiProseAuditReport,
    WholeBookNpcSourcePlan, CampaignProseManifest, CampaignProseEntry,
    CampaignProseSession, CampaignProseRequest, campaignProseHash,
    ReviewedHeroRole, NpcCampaignConsequencePreview,
    WholePlanGameplayBatchManifest, NpcCampaignDialogueDraft,
    ReviewedBookwideNpcCampaign, ReviewedCampaignStage,
    ReviewedCampaignState;
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

/// Validates consent-bound AI proposals without owning any model transport.
abstract interface class RpgProposalReviewApi {
  NpcDialogueCloudDraft reviewNpcDialogue(
      NpcDialogueDraftContext context, String responseBody);
  SourceLockedProseDraft reviewSceneProse(
      SourceLockedProseContext context, String responseBody);
  GameplayCandidateDraft reviewGameplaySuggestions(
      SourceLockedGameplayContext context, String responseBody);
  AiProseAuditReport reviewLiteraryCritique(
      SourceLockedProseAuditContext context, String responseBody);
}

/// All clients apply the SAME pure source-bound checks and prompts.
final class LocalRpgProposalReviewApi implements RpgProposalReviewApi {
  const LocalRpgProposalReviewApi();

  static const npcSystemPrompt = NpcDialogueCloudVerifier.systemPrompt;
  static const proseSystemPrompt = SourceLockedProseResponseVerifier.systemPrompt;
  static const gameplaySystemPrompt = GameplayCandidateProposalVerifier.systemPrompt;
  static const auditSystemPrompt = AiProseAuditVerifier.systemPrompt;

  @override
  NpcDialogueCloudDraft reviewNpcDialogue(
          NpcDialogueDraftContext context, String responseBody) =>
      NpcDialogueCloudVerifier.parseForTest(context, responseBody);

  @override
  SourceLockedProseDraft reviewSceneProse(
          SourceLockedProseContext context, String responseBody) =>
      SourceLockedProseResponseVerifier.parse(context, responseBody);

  @override
  GameplayCandidateDraft reviewGameplaySuggestions(
          SourceLockedGameplayContext context, String responseBody) =>
      GameplayCandidateProposalVerifier.parse(context, responseBody);

  @override
  AiProseAuditReport reviewLiteraryCritique(
          SourceLockedProseAuditContext context, String responseBody) =>
      AiProseAuditVerifier.parse(context, responseBody);
}


/// Standalone complete-campaign narration contract, including checkpoint
/// integrity, untrusted batch responses and text-only BookWorld finalization.
abstract interface class RpgCampaignProseApi {
  Future<CampaignProseManifest> prepare({
    required WholeBookNpcSourcePlan source,
    required Uint8List finalArchive,
    required Future<void> Function() verifyCurrent,
  });
  CampaignProseSession decodeCheckpoint(
      CampaignProseManifest manifest, String? checkpoint);
  String encodeCheckpoint({
    required CampaignProseManifest manifest,
    required int revision,
    required Iterable<CampaignProseEntry> entries,
  });
  CampaignProseRequest request(
      CampaignProseManifest manifest, CampaignProseSession session);
  List<CampaignProseEntry> parseBatch(String batch, String responseBody);
  String review(
      CampaignProseManifest manifest, CampaignProseSession session);
  Uint8List compileReviewed({
    required Uint8List verifiedArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool fullTextReviewed,
    required bool privateFictionConfirmed,
  });
}

final class LocalRpgCampaignProseApi implements RpgCampaignProseApi {
  const LocalRpgCampaignProseApi();
  static const systemPrompt = CampaignProseBatchVerifier.systemPrompt;

  @override
  Future<CampaignProseManifest> prepare({
    required WholeBookNpcSourcePlan source,
    required Uint8List finalArchive,
    required Future<void> Function() verifyCurrent,
  }) => const BookToRpgWorkflow().prepareCampaignNarration(
      source: source, finalArchive: finalArchive,
      verifyCurrent: verifyCurrent);

  @override
  CampaignProseSession decodeCheckpoint(
          CampaignProseManifest manifest, String? checkpoint) =>
      CampaignProseCheckpointCodec.decode(manifest, checkpoint);

  @override
  String encodeCheckpoint({
    required CampaignProseManifest manifest,
    required int revision,
    required Iterable<CampaignProseEntry> entries,
  }) => CampaignProseCheckpointCodec.encode(
      manifest: manifest, revision: revision, entries: entries);

  @override
  CampaignProseRequest request(
          CampaignProseManifest manifest, CampaignProseSession session) =>
      CampaignProseRequest.prepare(manifest, session);

  @override
  List<CampaignProseEntry> parseBatch(String batch, String responseBody) =>
      CampaignProseBatchVerifier.parse(batch, responseBody);

  @override
  String review(CampaignProseManifest manifest, CampaignProseSession session) =>
      CampaignProseFinalizer.review(manifest, session);

  @override
  Uint8List compileReviewed({
    required Uint8List verifiedArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool fullTextReviewed,
    required bool privateFictionConfirmed,
  }) => CampaignProseFinalizer.compile(
      verifiedArchive: verifiedArchive,
      sourceIndex: sourceIndex,
      reviewJson: reviewJson,
      approvedDigest: approvedDigest,
      fullTextReviewed: fullTextReviewed,
      privateFictionConfirmed: privateFictionConfirmed);
}


/// One source-locked, stage-gated, provider-independent authoring interface.
/// All gameplay, NPC and narration rules delegate to story_authoring.
abstract interface class RpgCampaignWorkflowApi {
  Future<ReviewedCampaignState> compileBase({
    required WholeBookNpcSourcePlan source,
    required List<ReviewedHeroRole> reviewedRoles,
    required String approvedPlanDigest,
    required String approvedHeroDigest,
    required bool allShownQuotesReviewed,
    required bool privateFictionConfirmed,
  });
  NpcCampaignConsequencePreview previewEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> proposals,
    required Map<String, String> reviewNotes,
  });
  Future<ReviewedCampaignState> acceptEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required NpcCampaignConsequencePreview review,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  });
  Future<ReviewedCampaignState> skipEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyConfirmedNoEffects,
  });
  ReviewedBookwideNpcCampaign reviewNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required List<NpcCampaignDialogueDraft> drafts,
  });
  Future<ReviewedCampaignState> acceptNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required ReviewedBookwideNpcCampaign review,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  });
  Future<ReviewedCampaignState> skipNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyConfirmedNoNpcDialogues,
  });
  Future<CampaignProseManifest> prepareNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required Future<void> Function() verifyCurrent,
  });
  Future<ReviewedCampaignState> completeWithoutNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyAcceptedExistingSceneText,
  });
  Future<ReviewedCampaignState> completeWithNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required CampaignProseManifest manifest,
    required CampaignProseSession session,
    required Future<CampaignProseSession> Function() readLatest,
    required String approvedDigest,
    required bool fullTextReviewed,
    required bool privateFictionConfirmed,
  });
}

/// Flutter, CLI and any future HTTP bridge use the same pure Dart flow.
final class LocalRpgCampaignWorkflowApi extends ReviewedCampaignWorkflow
    implements RpgCampaignWorkflowApi {
  const LocalRpgCampaignWorkflowApi();
}
