import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'multi_act_trial_editor.dart' as existing;
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'whole_book_npc_campaign_page.dart';
import 'world_library_gateway.dart';

/// Keeps the accepted single-campaign editor and its saved consent behavior
/// intact. The campaign-wide source/NPC workflow is one additional action,
/// not another library, engine, or replacement for existing saved games.
class MultiActTrialPage extends StatelessWidget {
  const MultiActTrialPage({
    super.key,
    required this.index,
    required this.book,
    required this.bookMap,
    required this.draft,
    required this.gateway,
    this.heroRoleCatalog,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final WorldLibraryGateway gateway;
  final ReviewedHeroRoleCatalog? heroRoleCatalog;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      existing.MultiActTrialPage(
        index: index, book: book, bookMap: bookMap, draft: draft,
        gateway: gateway, heroRoleCatalog: heroRoleCatalog,
      ),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 4,
        right: 8,
        child: Material(
          type: MaterialType.transparency,
          child: IconButton.filledTonal(
            key: const Key('multiact-open-whole-npc-campaign'),
            tooltip: 'События книги и несколько NPC',
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => WholeBookNpcCampaignPage(
                index: index, book: book, bookMap: bookMap, draft: draft,
                gateway: gateway, roleCatalog: heroRoleCatalog,
              )),
            ),
          ),
        ),
      ),
    ],
  );
}
