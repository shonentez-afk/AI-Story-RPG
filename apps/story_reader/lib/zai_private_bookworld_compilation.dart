import 'package:story_authoring/zai_private_bookworld_compilation.dart'
    as headless;
import 'package:story_authoring/story_authoring.dart'
    show ZaiWindowReviewQueue, ZaiCausalChoiceNotebook,
        ZaiEditorialConsistencyNotebook, SourceEvidenceGraph,
        SourceSemanticCatalog, SemanticEditorialReviewSession;
import 'package:bookworld_format/bookworld_format.dart';
import 'world_library_gateway.dart';

export 'package:story_authoring/zai_private_bookworld_compilation.dart'
    show ZaiCompiledPrivateWorld;

/// Platform adapter: exactly the same source-reviewed compiler runs in
/// ordinary Dart, installation uses the existing local library gateway.
class ZaiPrivateBookworldCompilation {
  const ZaiPrivateBookworldCompilation._();

  static Future<headless.ZaiCompiledPrivateWorld> compile({
    required ZaiWindowReviewQueue queue,
    required ZaiCausalChoiceNotebook notebook,
    required ZaiEditorialConsistencyNotebook consistency,
    required SourceEvidenceGraph evidence,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required Set<String> sourceSceneIds,
    required Map<String, String> eventAssertionIds,
    required Map<String, String> authoredSceneTexts,
    required bool consentForPrivateCompilation,
  }) => headless.ZaiPrivateBookworldCompilation.compile(
    queue: queue,
    notebook: notebook,
    consistency: consistency,
    evidence: evidence,
    catalog: catalog,
    editorial: editorial,
    sourceSceneIds: sourceSceneIds,
    eventAssertionIds: eventAssertionIds,
    authoredSceneTexts: authoredSceneTexts,
    consentForPrivateCompilation: consentForPrivateCompilation,
  );

  /// An explicit second confirmation is essential: compile is a preview;
  /// install mutates only the private BookWorld catalog, never existing saves.
  static Future<WorldLibraryItem> installConfirmed({
    required headless.ZaiCompiledPrivateWorld compiled,
    required WorldLibraryGateway gateway,
    required bool userConfirmedInstall,
  }) async {
    if (!userConfirmedInstall) {
      throw const FormatException(
          'Установка игрового мира требует отдельного подтверждения.');
    }
    final checked = const PrivateBookworldImporter().inspect(compiled.archive);
    if (checked.archiveSha256 != compiled.archiveSha256 ||
        checked.sourceFingerprint != compiled.sourceFingerprint ||
        checked.bookworldId != compiled.bookworldId ||
        checked.canDistributePublicly || checked.requiresNetwork) {
      throw const FormatException('Пакет изменён после проверки.');
    }
    final result = await gateway.install(compiled.archive);
    if (result.archiveHash != compiled.archiveSha256 ||
        result.bookworldId != compiled.bookworldId ||
        result.title != compiled.title) {
      throw const FormatException(
          'Установленный мир не совпадает с проверенным пакетом.');
    }
    return result;
  }
}
