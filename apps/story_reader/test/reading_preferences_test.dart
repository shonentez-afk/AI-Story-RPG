import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/reading_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
