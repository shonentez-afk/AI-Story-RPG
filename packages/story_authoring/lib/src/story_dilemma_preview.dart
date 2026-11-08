import 'story_plan.dart';
import 'story_plan_dilemma_generator.dart';

/// A deliberately non-executable, source-reviewed candidate. The provider
/// that proposed it (Z.ai, manual editor, local model) is not an engine.
class ZaiStoryDilemmaPreview {
  const ZaiStoryDilemmaPreview({
    required this.proposal,
    required this.plan,
    required this.sampledEventCount,
  });

  final StoryDilemmaProposal? proposal;
  final StoryPlan? plan;
  final int sampledEventCount;
  bool get foundCandidate => proposal != null && plan != null;
  bool get hasVerifiedLiteraryMeaning => false;
  bool get isPlayableRpg => false;
}
