import 'free_text_action_gate.dart';
import 'world_library_gateway.dart';

/// Preserves the existing asynchronous SQLite/isolate architecture.
/// Free-text cannot open its own DB, choose hidden actions, or write canon.
class FreeTextWorldGatewayPort {
  const FreeTextWorldGatewayPort(this.gateway);
  final WorldLibraryGateway gateway;

  static FreeTextCampaignHead headFromView(WorldGameView view) =>
      FreeTextCampaignHead(
        campaignId: view.campaignId,
        sceneId: view.sceneId,
        revision: view.revision,
        isTerminal: view.isTerminal,
        choices: [
          for (final choice in view.choices)
            FreeTextChoice(
              id: choice.id, label: choice.label,
              lockReason: choice.lockReason,
            ),
        ],
      );

  Future<FreeTextPreview> preview(String campaignId, String input) async {
    final current = await gateway.load(campaignId);
    return FreeTextActionGate.preview(headFromView(current), input);
  }

  /// Checks a fresh database snapshot *before* the existing transactional
  /// gateway.choose. The gateway itself rejects concurrent stale revisions.
  /// An exception/timeout never means we may assume a turn committed.
  Future<WorldChoiceResult> confirm({
    required FreeTextProposal proposal,
    required String actionId,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw const FormatException('Игрок не подтвердил действие.');
    }
    final fresh = await gateway.load(proposal.campaignId);
    FreeTextActionGate.validate(
      current: headFromView(fresh), proposal: proposal,
      actionId: actionId, userConfirmed: true,
    );
    return gateway.choose(proposal.campaignId,
      choiceId: proposal.choiceId,
      expectedRevision: proposal.expectedRevision,
      actionId: actionId,
    );
  }
}
