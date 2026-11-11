import 'source_semantic_provider.dart';

/// Immutable, provider-validated preview payload shared by the app and
/// standalone source-locked authoring. Neither event meanings nor NPC facts
/// become canon by merely appearing in this result.
class SemanticPreviewWireContract {
  const SemanticPreviewWireContract._();
  static const providerId = 'zai-glm47flash-preview';
  static const providerVersion = 'm2f2d-v1';
  static const maxProposals = 8;
  static const maxAttempts = 3;
  static const categories = <SemanticCategory>{
    SemanticCategory.character, SemanticCategory.location,
    SemanticCategory.event, SemanticCategory.fact, SemanticCategory.state,
  };
}

class ZaiSemanticPreviewResult {
  const ZaiSemanticPreviewResult({
    required this.batch,
    required this.rejectedCount,
    required this.rejectedNonRussian,
    this.rejectionReasons = const [],
    required this.totalSuggestions,
  });

  final SemanticCandidateBatch batch;
  final int rejectedCount;
  final int rejectedNonRussian;
  final List<String> rejectionReasons;
  final int totalSuggestions;
}

