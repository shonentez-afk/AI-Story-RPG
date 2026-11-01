import 'package:shared_preferences/shared_preferences.dart';

/// M1 single-slot persistence. The final .bwsave storage API will replace this.
class SaveStore {
  static const key = 'ai_story_m1_snapshot_v1';

  Future<void> write(String snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, snapshot);
    if (!ok) throw StateError('Could not persist game snapshot');
  }

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}
