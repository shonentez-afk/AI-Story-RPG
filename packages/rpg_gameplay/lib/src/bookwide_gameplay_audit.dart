import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';

/// Bounded, true StoryWorld execution, never the generator's untrusted prose.
enum BookGameplayAuditStatus { playable, blocked, inconclusive }

final class RpgBookGameplayAudit {
  const RpgBookGameplayAudit({
    required this.archiveHash, required this.status,
    required this.exploredStates, required this.exhaustive,
    required this.reachedEndingCount, required this.totalEndingCount,
    required this.trapCount, required this.cycleCount,
  });

  final String archiveHash;
  final BookGameplayAuditStatus status;
  final int exploredStates, reachedEndingCount, totalEndingCount;
  final int trapCount, cycleCount;
  final bool exhaustive;
  bool get provenAllEndings => status == BookGameplayAuditStatus.playable &&
      exhaustive && reachedEndingCount == totalEndingCount &&
      reachedEndingCount >= 2;
  bool get sourceLiteraryCanonVerified => false;
  bool get exactGeneratorRoutesReplayed => false;
}

abstract interface class RpgBookGameplayAuditApi {
  RpgBookGameplayAudit inspect(Uint8List archive, {
    int maxStates = 4096, int maxMoves = 512,
  });
}

/// Optional native multi-act preflight. Every actual causal edge is applied
/// by the shared StoryWorld, including NPC memory/trust/item custody.
/// Inconclusive from search limits is never represented as a passed audit.
final class LocalRpgBookGameplayAuditApi implements RpgBookGameplayAuditApi {
  const LocalRpgBookGameplayAuditApi();

  @override
  RpgBookGameplayAudit inspect(Uint8List archive, {
    int maxStates = 4096, int maxMoves = 512,
  }) {
    final imported = const RichPrivateBookworldImporter().inspect(archive);
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: imported.blueprint,
      socialRulebook: imported.npcSocialRulebook,
      requireAllTerminals: true,
      maxStates: maxStates, maxMoves: maxMoves,
      projectDormantFlags: imported.formatVersion == 4,
    );
    final count = imported.blueprint.scenes.values
        .where((scene) => scene.terminal).length;
    return RpgBookGameplayAudit(
      archiveHash: imported.archiveSha256,
      status: switch (report.status) {
        CampaignCausalStatus.playable => BookGameplayAuditStatus.playable,
        CampaignCausalStatus.blocked => BookGameplayAuditStatus.blocked,
        CampaignCausalStatus.inconclusive =>
          BookGameplayAuditStatus.inconclusive,
      },
      exploredStates: report.exploredStates,
      exhaustive: report.exhaustive,
      reachedEndingCount: report.terminalWitnesses.length,
      totalEndingCount: count,
      trapCount: report.trapCount, cycleCount: report.cycleCount,
    );
  }
}
