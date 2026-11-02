import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAppearance { system, light, dark }

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController._();
  static final instance = AppAppearanceController._();

  // Retain the historical light default for an unconfigured installation.
  // The explicit system option follows Android/Windows once selected.
  AppAppearance _value = AppAppearance.light;
  AppAppearance get value => _value;

  static const _modeKey = 'ai_story_app_appearance_v2';
  static const _legacyDarkKey = 'ai_story_app_dark_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey);
    _value = switch (raw) {
      'system' => AppAppearance.system,
      'light' => AppAppearance.light,
      'dark' => AppAppearance.dark,
      _ => prefs.getBool(_legacyDarkKey) == true
          ? AppAppearance.dark : AppAppearance.light,
    };
    // App appearance and reading palette are independent settings:
    // opening Settings must never silently overwrite a manually chosen
    // sepia/OLED palette or its older saved value.
    notifyListeners();
  }

  Future<void> change(AppAppearance next) async {
    _value = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, next.name);
    // Keep legacy app theme selection readable by previous installations,
    // but do NOT modify ai_story_reading_v1_palette.
    if (next != AppAppearance.system) {
      await prefs.setBool(_legacyDarkKey, next == AppAppearance.dark);
    }
  }
}

class AppTheme {
  static ThemeData light() => _make(
    Brightness.light,
    const Color(0xFFF6F2E9),
    const Color(0xFF765B42),
    const Color(0xFFE8DFCF),
  );

  static ThemeData dark() => _make(
    Brightness.dark,
    const Color(0xFF1D1F23),
    const Color(0xFFA58B70),
    const Color(0xFF30343B),
  );

  static ThemeData _make(Brightness brightness, Color background,
      Color primary, Color card) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: background,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
