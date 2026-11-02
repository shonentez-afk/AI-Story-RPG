import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingPalette { light, sepia, dark, oled }

class ReadingPreferences {
  const ReadingPreferences({
    this.palette = ReadingPalette.sepia,
    this.fontSize = 18,
    this.lineHeight = 1.65,
    this.horizontalPadding = 24,
  });

  final ReadingPalette palette;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;

  Color get background => switch (palette) {
    ReadingPalette.light => const Color(0xFFFFFFFF),
    ReadingPalette.sepia => const Color(0xFFF4ECDD),
    ReadingPalette.dark => const Color(0xFF272727),
    ReadingPalette.oled => const Color(0xFF000000),
  };
  Color get foreground => switch (palette) {
    ReadingPalette.light => const Color(0xFF202020),
    ReadingPalette.sepia => const Color(0xFF3A332B),
    ReadingPalette.dark => const Color(0xFFF0F0F0),
    ReadingPalette.oled => const Color(0xFFFFFFFF),
  };

  ReadingPreferences copyWith({
    ReadingPalette? palette,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
  }) => ReadingPreferences(
        palette: palette ?? this.palette,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      );
}

class ReadingSettingsStore {
  static const _prefix = 'ai_story_reading_v1_';

  // Repeated slider changes and navigation used to cause overlapping
  // preference writes. All callers share one ordered queue.
  static Future<void> _writeFence = Future<void>.value();
  static ReadingPreferences? _queuedView;

  Future<ReadingPreferences> load() async {
    // Reading settings in a freshly opened page should not be blocked by
    // outstanding slider writes. Present the last explicitly chosen style
    // until its ordered persistence finishes.
    final queued = _queuedView;
    if (queued != null) return queued;
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getInt('${_prefix}palette') ?? 1;
    final palette = theme >= 0 && theme < ReadingPalette.values.length
        ? ReadingPalette.values[theme]
        : ReadingPalette.sepia;
    final font = (prefs.getDouble('${_prefix}font') ?? 18).clamp(12.0, 32.0).toDouble();
    final height = (prefs.getDouble('${_prefix}line') ?? 1.65).clamp(1.2, 2.2).toDouble();
    final padding = (prefs.getDouble('${_prefix}padding') ?? 24).clamp(12.0, 48.0).toDouble();
    return ReadingPreferences(
      palette: palette, fontSize: font, lineHeight: height, horizontalPadding: padding,
    );
  }

  Future<void> save(ReadingPreferences settings) {
    _queuedView = settings;
    final previous = _writeFence;
    final operation = previous.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_prefix}palette', settings.palette.index);
      await prefs.setDouble('${_prefix}font', settings.fontSize);
      await prefs.setDouble('${_prefix}line', settings.lineHeight);
      await prefs.setDouble('${_prefix}padding', settings.horizontalPadding);
    });
    _writeFence = operation;
    operation.then((_) {
      if (identical(_queuedView, settings)) _queuedView = null;
    }, onError: (Object _) {
      if (identical(_queuedView, settings)) _queuedView = null;
    });
    return operation;
  }

  /// Wait until all issued appearance writes have committed. Useful before
  /// closing an editing session and for exact persistence regressions.
  Future<void> flush() => _writeFence;

  Future<void> reset() => save(const ReadingPreferences());
}
