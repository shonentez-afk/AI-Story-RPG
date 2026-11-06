import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

/// A *presentation-only* turn extracted from the exact signed scene text.
/// It cannot grant items, knowledge, permissions or literary CANON.
class RichDialogueTurn {
  const RichDialogueTurn({required this.text, this.speaker});

  final String text;
  final String? speaker;

  bool get isNarration => speaker == null;

  Map<String, Object?> toJson() => {
    'speaker': speaker,
    'text': text,
  };
}

/// One deterministic parser shared between rich-v3 writer, importer and the
/// Flutter dialogue UI. No NPC identity is guessed from unattributed dashes,
/// dialogue in quotation marks, or the prose around a quote.
///
/// The optional v3 presentation projection MUST exactly match this parser
/// applied to the signed scene body. The importer does not trust a separate
/// AI-authored list of speakers or lines.
class RichSceneDialogue {
  const RichSceneDialogue._();

  static const maxTurns = 64;
  static const maxSceneTextLength = 50000;

  static final RegExp _named = RegExp(
    r'^([А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}):[ \t]*(«[^»\n]{1,1200}»|"[^"\n]{1,1200}"|—[ \t]*[^\n]{1,1200})[.!?]?$',
    unicode: true,
  );

  static List<RichDialogueTurn>? parse(String sceneText) {
    if (sceneText.trim().isEmpty ||
        sceneText.length > maxSceneTextLength) {
      return null;
    }
    final lines = sceneText.replaceAll('\r\n', '\n').split('\n');
    final turns = <RichDialogueTurn>[];
    final speakers = <String>{};
    var spoken = 0;
    for (final source in lines) {
      final line = source.trim();
      if (line.isEmpty) continue;
      final match = _named.firstMatch(line);
      if (match == null) {
        if (line.length > 5000) return null;
        turns.add(RichDialogueTurn(text: line));
      } else {
        final speaker = match.group(1)!.trim();
        var speech = match.group(2)!.trim();
        if (speaker.isEmpty) return null;
        if ((speech.startsWith('«') && speech.endsWith('»')) ||
            (speech.startsWith('"') && speech.endsWith('"'))) {
          speech = speech.substring(1, speech.length - 1).trim();
        } else if (speech.startsWith('—')) {
          speech = speech.substring(1).trim();
        }
        if (speech.isEmpty) return null;
        turns.add(RichDialogueTurn(speaker: speaker, text: speech));
        speakers.add(speaker);
        spoken++;
      }
      if (turns.length > maxTurns) return null;
    }
    // A one-character shout or a quotation is not a two-person dialogue.
    if (spoken < 2 || speakers.length < 2) return null;
    return List.unmodifiable(turns);
  }

  /// A signed-v3 optional presentation field. No new ZIP member, no schema
  /// for gameplay and no changes to the current story_core/SQLite engine.
  static Map<String, Object?>? presentationFor(String sceneText) {
    final turns = parse(sceneText);
    if (turns == null) return null;
    return {
      'scene_text_sha256':
          sha256.convert(utf8.encode(sceneText)).toString(),
      'turns': [for (final turn in turns) turn.toJson()],
    };
  }

  /// Fail closed if a speaker, word, ordering, narrator beat, scene SHA or
  /// unknown field has been tampered with, even if the ZIP hash is rebuilt.
  static List<RichDialogueTurn> verify(
      Object? signedProjection, String signedSceneText) {
    final expected = presentationFor(signedSceneText);
    if (expected == null ||
        signedProjection is! Map<String, dynamic> ||
        canonicalJson(expected) != canonicalJson(signedProjection)) {
      throw const FormatException(
          'Подмена имени, реплики или порядка диалога в RPG v3.');
    }
    return parse(signedSceneText)!;
  }
}
