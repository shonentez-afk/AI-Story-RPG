import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, user-selected PNG portrait bound to one exact campaign/speaker.
/// No network, BookWorld mutations, source claims, or cloud API requests.
///
/// This is OPTIONAL UI personalization. Structured, verified portraits
/// included in a future BookWorld version require their own importer contract.
class LocalDialoguePortraitStore {
  const LocalDialoguePortraitStore({this.root});

  final Directory? root;
  static const maxBytes = 2 * 1024 * 1024;
  static const maxSide = 2048;
  static const _prefix = 'ai_story_portrait_v1_';
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static const _magic = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  static String _digest(List<int> bytes) =>
      sha256.convert(bytes).toString();

  String _key(String campaignId, String speaker) {
    final who = speaker.trim().toLowerCase();
    if (campaignId.isEmpty || campaignId.length > 256 ||
        who.isEmpty || who.length > 120) {
      throw const FormatException('Некорректное имя персонажа.');
    }
    return _prefix + _digest(utf8.encode(
      jsonEncode([campaignId, who])));
  }

  Future<Directory> _directory() async {
    final home = root ?? await getApplicationSupportDirectory();
    final dir = Directory(home.path + Platform.pathSeparator +
        'ai_story_private_portraits');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static void validatePng(Uint8List bytes) {
    if (bytes.length < 45 || bytes.length > maxBytes ||
        !List.generate(_magic.length, (i) => bytes[i] == _magic[i])
            .every((match) => match) ||
        bytes[8] != 0 || bytes[9] != 0 ||
        bytes[10] != 0 || bytes[11] != 13 ||
        bytes[12] != 73 || bytes[13] != 72 ||
        bytes[14] != 68 || bytes[15] != 82) {
      throw const FormatException(
          'Для портрета нужен корректный PNG размером не более 2 МБ.');
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    if (width == 0 || height == 0 ||
        width > maxSide || height > maxSide) {
      throw const FormatException(
          'Размеры портрета не должны превышать 2048 × 2048.');
    }
  }

  /// Save bytes first, then publish a local SHA binding only on success.
  /// A cancelled pick or a validation failure never replaces an old portrait.
  Future<void> save({
    required String campaignId,
    required String speaker,
    required Uint8List png,
  }) async {
    validatePng(png);
    final id = _key(campaignId, speaker);
    final hash = _digest(png);
    final dir = await _directory();
    final destination = File(dir.path + Platform.pathSeparator + '$hash.png');
    if (!await destination.exists()) {
      final temporary = File(dir.path + Platform.pathSeparator +
          '$hash.incomplete');
      try {
        await temporary.writeAsBytes(png, flush: true);
        await temporary.rename(destination.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(id, hash)) {
      throw const FileSystemException('Не удалось сохранить портрет.');
    }
  }

  /// A corrupted, unknown or deleted local image is displayed as a silhouette.
  Future<Uint8List?> read({
    required String campaignId,
    required String speaker,
  }) async {
    final id = _key(campaignId, speaker);
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString(id);
      if (hash == null || !_sha.hasMatch(hash)) return null;
      final dir = await _directory();
      final path = File(dir.path + Platform.pathSeparator + '$hash.png');
      if (!await path.exists() || await path.length() > maxBytes) return null;
      final bytes = await path.readAsBytes();
      validatePng(bytes);
      if (_digest(bytes) != hash) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear({
    required String campaignId,
    required String speaker,
  }) async {
    final id = _key(campaignId, speaker);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(id);
    // Content-addressed PNG files may also be used by other speakers.
    // Cleanup is a separate bounded maintenance task.
  }
}
