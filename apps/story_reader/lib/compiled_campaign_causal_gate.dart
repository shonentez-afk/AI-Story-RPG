import 'package:story_core/story_core.dart';

/// Final pre-install check for a PRIVATE game that has already passed the
/// regular strict BookWorld importer. It does not read prose, call AI, change
/// authored choices, or simulate a second state machine.
///
/// A graph-reachable ending is not enough: every promised ending must be
/// reachable via successful StoryWorld.apply calls. Every explored
/// nonterminal state must offer at least one executable choice. A bounded
/// search result is REVIEW REQUIRED, never misrepresented as a PASS.
class CompiledCampaignCausalGate {
  const CompiledCampaignCausalGate._();

  static CampaignCausalReport verify({
    required StoryBlueprint blueprint,
    NpcSocialRulebook? socialRules,
    Iterable<String> requiredChoiceIds = const [],
    int maxStates = 8192,
    int maxMoves = 256,
  }) {
    final report = StoryCampaignCausalAudit.inspect(
      blueprint: blueprint,
      socialRulebook: socialRules,
      requiredChoiceIds: requiredChoiceIds,
      maxStates: maxStates,
      maxMoves: maxMoves,
    );
    if (report.status == CampaignCausalStatus.playable) return report;
    if (report.traps.isNotEmpty) {
      final trap = report.traps.first;
      throw FormatException(
        'Игра приводит в тупик: сцена ' + trap.sceneId +
        ', после решений ' + trap.choiceIds.join(' → ') +
        '. Нет доступных действий: ' +
        trap.choiceLockReasons.keys.join(', ') + '.',
      );
    }
    if (report.status == CampaignCausalStatus.inconclusive) {
      throw FormatException(
        'Не удалось проверить все причинные ветви в установленном '
        'лимите (' + report.exploredStates.toString() +
        ' состояний). Нужен отдельный проход с большими пределами '
        'или сокращение несущественных повторов.',
      );
    }
    throw FormatException(
      'Сценарий содержит недостижимые игровые исходы или '
      'обязательные решения. Не подтверждены концовки: ' +
      report.unprovenTerminalIds.join(', ') +
      '; решения: ' + report.unprovenRequiredChoiceIds.join(', ') + '.',
    );
  }
}
