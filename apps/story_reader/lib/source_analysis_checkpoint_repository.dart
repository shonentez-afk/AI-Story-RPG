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

/// Two isolated folders. Existing M2b1 files keep their original path.
enum SourceCheckpointScope {
  mentions,
  narrativeEvidence,
  identityRelations,
  semanticProposals,
  semanticCatalog,
  semanticEditorial,
  intermediateDraft,
  multiSceneDraft,
  npcEditorial,
  npcKnowledgeRules,
  zaiWindowReview,
  zaiCrossWindowLinks,
  zaiEditorialConsistency,
  zaiSceneDraft,
}

/// Private app-support storage shared by Android and Windows.
/// The temporary file is flushed and renamed on the SAME filesystem; an
/// interrupted write cannot turn the previous checkpoint into a partial JSON.
/// This is not an OS power-loss/real-device durability certification.
class FileSourceAnalysisCheckpointRepository
    implements SourceAnalysisCheckpointRepository {
  const FileSourceAnalysisCheckpointRepository({
    this.rootDirectory,
    this.scope = SourceCheckpointScope.mentions,
  });

  /// Injected only in unit tests; production uses application support.
  final Future<Directory> Function()? rootDirectory;
  final SourceCheckpointScope scope;

  static final RegExp _validFingerprint = RegExp(r'^[a-f0-9]{64}$');
  static const _mentionsFolder = 'ai_story_source_analysis_v1';
  static const _evidenceFolder = 'ai_story_evidence_review_v1';
  static const _relationsFolder = 'ai_story_relation_review_v1';
  static const _semanticFolder = 'ai_story_semantic_review_m2b4a_v1';
  static const _catalogFolder = 'ai_story_semantic_catalog_m2b4b_v1';
  static const _editorialFolder = 'ai_story_semantic_editorial_m2c_v1';
  static const _draftFolder = 'ai_story_intermediate_draft_m2c_v1';
  static const _multiSceneFolder = 'ai_story_multiscene_draft_m2e5a_v1';
  static const _npcFolder = 'ai_story_npc_editorial_m2e5b2_v1';
  static const _knowledgeFolder = 'ai_story_npc_knowledge_rules_m2e5b3b1_v1';
  static const _zaiReviewFolder = 'ai_story_zai_private_window_review_m2f3a_v1';
  static const _zaiLinksFolder = 'ai_story_zai_private_links_m2f3b_v1';
  static const _zaiConsistencyFolder = 'ai_story_zai_private_editorial_consistency_m2f3c_v1';
  static const _zaiSceneFolder = 'ai_story_zai_private_source_scene_draft_m2f3d_v1';

  static void _checkFingerprint(String fingerprint) {
    if (!_validFingerprint.hasMatch(fingerprint)) {
      throw const FormatException('Недопустимый отпечаток книги');
    }
  }

  Future<Directory> _folder() async {
    final base = await (rootDirectory?.call() ??
        getApplicationSupportDirectory());
    final name = switch (scope) {
      SourceCheckpointScope.mentions => _mentionsFolder,
      SourceCheckpointScope.narrativeEvidence => _evidenceFolder,
      SourceCheckpointScope.identityRelations => _relationsFolder,
      SourceCheckpointScope.semanticProposals => _semanticFolder,
      SourceCheckpointScope.semanticCatalog => _catalogFolder,
      SourceCheckpointScope.semanticEditorial => _editorialFolder,
      SourceCheckpointScope.intermediateDraft => _draftFolder,
      SourceCheckpointScope.multiSceneDraft => _multiSceneFolder,
      SourceCheckpointScope.npcEditorial => _npcFolder,
      SourceCheckpointScope.npcKnowledgeRules => _knowledgeFolder,
      SourceCheckpointScope.zaiWindowReview => _zaiReviewFolder,
      SourceCheckpointScope.zaiCrossWindowLinks => _zaiLinksFolder,
      SourceCheckpointScope.zaiEditorialConsistency => _zaiConsistencyFolder,
      SourceCheckpointScope.zaiSceneDraft => _zaiSceneFolder,
    };
    final folder = Directory('${base.path}/$name');
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
