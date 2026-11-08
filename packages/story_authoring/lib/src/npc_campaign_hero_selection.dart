import 'reviewed_hero_role.dart';
import 'whole_book_npc_campaign.dart';

/// A remembered editing preference, never permission to upload or install.
class NpcCampaignHeroSelection {
  const NpcCampaignHeroSelection(this.role, this.sourceAction, this.revision);
  final ReviewedHeroRole? role;
  final bool sourceAction;
  final int revision;
  bool get cloudConsent => false;
  bool get installConsent => false;

  WholeBookNpcSourcePlan bind(WholeBookNpcSourcePlan source) =>
      WholeBookNpcSourcePlan.fromBook(
        index: source.index, book: source.book, bookMap: source.bookMap,
        draft: source.draft, selectedHeroRole: role,
        reviewedHeroSourceAction: sourceAction,
      );
}

