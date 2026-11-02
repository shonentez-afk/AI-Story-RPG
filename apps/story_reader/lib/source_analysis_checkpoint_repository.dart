import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'book_source_analysis.dart';

/// Only checkpoints, IDs, hashes and evidence offsets are written.
/// Full TXT/FB2 text stays in the existing private library.
abstract class SourceAnalysisCheckpointRepository {
  Future<String?> read(String sourceFingerprint);
  Future<void> write(String sourceFingerprint, String checkpoint);
  Future<void> delete(String sourceFingerprint);
}

/// Private app-support storage shared by Android and Windows.
/// The temporary file is flushed and renamed on the SAME filesystem; an
/// interrupted write cannot turn the previous checkpoint into a partial JSON.
/// This is not an OS power-loss/real-device durability certification.
class FileSourceAnalysisCheckpointRepository
    implements SourceAnalysisCheckpointRepository {
  const FileSourceAnalysisCheckpointRepository({this.rootDirectory});

  /// Injected only in unit tests; production uses application support.
  final Future<Directory> Function()? rootDirectory;

  static final RegExp _validFingerprint = RegExp(r'^[a-f0-9]{64}$');
  static const _folderName = 'ai_story_source_analysis_v1';

  static void _checkFingerprint(String fingerprint) {
    if (!_validFingerprint.hasMatch(fingerprint)) {
      throw const FormatException('Недопустимый отпечаток книги');
    }
  }

  Future<Directory> _folder() async {
    final base = await (rootDirectory?.call() ??
        getApplicationSupportDirectory());
    final folder = Directory('${base.path}/$_folderName');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<File> _file(String fingerprint) async {
    _checkFingerprint(fingerprint);
    final folder = await _folder();
    return File('${folder.path}/$fingerprint.json');
  }

  @override
  Future<String?> read(String sourceFingerprint) async {
    final file = await _file(sourceFingerprint);
    if (!await file.exists()) return null;
    if (await file.length() > SourceAnalysisSession.maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой сохранённый анализ');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > SourceAnalysisSession.maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой сохранённый анализ');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }

  @override
  Future<void> write(String sourceFingerprint, String checkpoint) async {
    final bytes = utf8.encode(checkpoint);
    if (bytes.length > SourceAnalysisSession.maxCheckpointUtf8Bytes) {
      throw const FormatException('Слишком большой checkpoint анализа');
    }
    final target = await _file(sourceFingerprint);
    final suffix = '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 32)}';
    final temp = File('${target.path}.$suffix.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> delete(String sourceFingerprint) async {
    final target = await _file(sourceFingerprint);
    if (await target.exists()) await target.delete();
  }
}

/// Deterministic test double. Never used for persistent app data.
class MemorySourceAnalysisCheckpointRepository
    implements SourceAnalysisCheckpointRepository {
  final Map<String, String> _items = {};
  bool failNextWrite = false;

  @override
  Future<String?> read(String sourceFingerprint) async =>
      _items[sourceFingerprint];

  @override
  Future<void> write(String sourceFingerprint, String checkpoint) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Simulation: write failed');
    }
    _items[sourceFingerprint] = checkpoint;
  }

  @override
  Future<void> delete(String sourceFingerprint) async {
    _items.remove(sourceFingerprint);
  }
}
