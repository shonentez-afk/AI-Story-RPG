import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

/// A pure-Dart library-visibility test: these must remain accessible from
/// the standalone package without importing Flutter, Z.ai or the app.
void main() {
  test('all core authoring gateways are available outside Flutter', () {
    expect(StoryPlanTrialCompiler.compile, isNotNull);
    expect(MultiActTrialCompiler.compile, isNotNull);
    expect(BookwideNpcCampaignAuthoring.compile, isNotNull);
    expect(BookwideNpcCampaignAuthoring.discover, isNotNull);
    expect(WholeStoryLiteraryReviewManifest.fromEvidence, isNotNull);
    expect(WholeStoryLiteraryReviewReport.fromJson, isNotNull);
    expect(ReviewedProseSceneOverlay.validate, isNotNull);
    expect(SourceLockedProseContext.forSituation, isNotNull);
    expect(ReviewedHeroRole.fromReviewedSources, isNotNull);
    expect(ReviewedStoryNarrative, isNotNull);
    expect(LiteraryReviewWireContract.modelId, 'glm-4.7-flash');
    expect(LiteraryReviewWireContract.maxAttempts, 3);
  });
}
