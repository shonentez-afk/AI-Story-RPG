import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAppearance { light, dark }

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController._();
  static final instance = AppAppearanceController._();

  AppAppearance _value = AppAppearance.light;
  AppAppearance get value => _value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _value = prefs.getBool('ai_story_app_dark_v1') == true
        ? AppAppearance.dark : AppAppearance.light;
    notifyListeners();
  }

  Future<void> change(AppAppearance next) async {
    _value = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_story_app_dark_v1', next == AppAppearance.dark);
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
