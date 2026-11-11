import 'package:bookworld_format/bookworld_format.dart';

/// The FIRST dialogue UI contract is intentionally presentation-only.
///
/// A line is dialogue only when the authored scene explicitly names the
/// speaker and quotes their words. Bare em dashes, unattributed quotations
/// and prose must NEVER be assigned to an invented character.
class SceneDialogueTurn {
  const SceneDialogueTurn({required this.text, this.speaker});
  final String text;
  final String? speaker;
  bool get isNarration => speaker == null;
}

class SceneDialogueScript {
  SceneDialogueScript._(List<SceneDialogueTurn> turns)
      : turns = List.unmodifiable(turns);

  final List<SceneDialogueTurn> turns;

  // One shared deterministic algorithm (and exact same speaker rules)
  // powers the v3 writer, independent importer and this legacy Flutter UI.
  // Older v1/v2 worlds still get the existing dialogue presentation.
  static SceneDialogueScript? fromSceneText(String text) {
    final turns = RichSceneDialogue.parse(text);
    return turns == null ? null : fromSignedTurns(turns);
  }

  static SceneDialogueScript fromSignedTurns(List<RichDialogueTurn> turns) {
    if (turns.isEmpty) {
      throw const FormatException('Пустой подписанный диалог .bworld');
    }
    return SceneDialogueScript._([
      for (final turn in turns)
        SceneDialogueTurn(text: turn.text, speaker: turn.speaker),
    ]);
  }
}

