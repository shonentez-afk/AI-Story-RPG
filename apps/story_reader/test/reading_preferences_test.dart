import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/reading_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all reader palettes exceed WCAG 7:1 text contrast', () {
    for (final palette in ReadingPalette.values) {
      final colors = ReadingPreferences(palette: palette);
      final fg = colors.foreground.computeLuminance();
      final bg = colors.background.computeLuminance();
      final maxL = fg > bg ? fg : bg;
      final minL = fg > bg ? bg : fg;
      final ratio = (maxL + 0.05) / (minL + 0.05);
      expect(ratio, greaterThanOrEqualTo(7.0), reason: palette.name);
    }
  });

  test('reading palette, font, spacing and margins persist', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReadingSettingsStore();
    final original = (await store.load()).copyWith(
      palette: ReadingPalette.oled,
      fontSize: 25,
      lineHeight: 1.9,
      horizontalPadding: 36,
    );
    await store.save(original);
    final restored = await ReadingSettingsStore().load();
    expect(restored.palette, ReadingPalette.oled);
    expect(restored.fontSize, 25);
    expect(restored.lineHeight, 1.9);
    expect(restored.horizontalPadding, 36);
  });

  test('rapid reading-style changes persist the last complete state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReadingSettingsStore();
    final first = store.save(const ReadingPreferences(
      palette: ReadingPalette.dark, fontSize: 20,
    ));
    final second = store.save(const ReadingPreferences(
      palette: ReadingPalette.oled, fontSize: 27,
      lineHeight: 1.95, horizontalPadding: 34,
    ));
    await Future.wait([first, second]);
    final restored = await ReadingSettingsStore().load();
    expect(restored.palette, ReadingPalette.oled);
    expect(restored.fontSize, 27);
    expect(restored.lineHeight, 1.95);
    expect(restored.horizontalPadding, 34);
  });

  test('invalid saved preferences fall back to safe values', () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_reading_v1_palette': 999,
      'ai_story_reading_v1_font': 999.0,
      'ai_story_reading_v1_line': 0.1,
      'ai_story_reading_v1_padding': -10.0,
    });
    final restored = await ReadingSettingsStore().load();
    expect(restored.palette, ReadingPalette.sepia);
    expect(restored.fontSize, 32);
    expect(restored.lineHeight, 1.2);
    expect(restored.horizontalPadding, 12);
  });
}
