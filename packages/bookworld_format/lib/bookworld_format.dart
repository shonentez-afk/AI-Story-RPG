import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'src/sqlite_v1.dart';
import 'src/zip_v1.dart';

export 'private_bookworld.dart' show PrivateBookworldImporter, VerifiedPrivateBookworld;
export 'private_rich_bookworld.dart' show RichPrivateBookworldImporter, VerifiedRichPrivateBookworld;
export 'rich_scene_dialogue.dart' show RichSceneDialogue, RichDialogueTurn;
export 'npc_dialogue_knowledge.dart' show RichNpcDialogueKnowledge;
export 'npc_social_contract.dart' show RichNpcSocialContract;
export 'private_bookworld_writer.dart' show PrivateBookworldWriter, RichPrivateBookworldWriter;
export 'reviewed_gameplay_bookworld_writer.dart' show ReviewedGameplayBookworldWriter;

/// Validated compiled game rules (legacy demo or explicit private source v2),
/// not a game save, a reader book, or distribution permission.
class VerifiedBookworld {
  const VerifiedBookworld({
    required this.blueprint,
    required this.archiveHash,
    this.npcSocialRulebook,
  });
  final StoryBlueprint blueprint;
  final String archiveHash;
  /// Source-locked rulebook from a strictly verified rich-v3 archive only.
  final NpcSocialRulebook? npcSocialRulebook;
  String get bookworldId => blueprint.bookId;
}

/// Entirely offline, read-only import of the strict .bworld v1 subset.
/// Run this synchronous work in a background isolate when wiring Flutter.
class BookworldImporter {
  const BookworldImporter();

  VerifiedBookworld inspect(Uint8List rawArchive) {
    final files = BworldZipV1.read(rawArchive);
    final raw = _parse(files['scenario/blueprint.json']!, 'blueprint');
    final canonical = utf8.encode(canonicalJson(raw));
    if (!_equal(files['scenario/blueprint.json']!, canonical)) {
      throw const FormatException('Noncanonical blueprint JSON');
    }
    final blueprint = StoryBlueprint.fromJson(raw);
    final manifest = _parse(files['manifest.json']!, 'manifest');
    _validateManifest(manifest, blueprint, raw, files);
    BworldSqliteV1.inspect(files['world.sqlite']!, blueprint, raw);
    return VerifiedBookworld(
      blueprint: blueprint,
      archiveHash: sha256.convert(rawArchive).toString(),
    );
  }

  Map<String, dynamic> _parse(Uint8List bytes, String where) {
    final dynamic result;
    try {
      result = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException catch (error) {
      throw FormatException('Invalid $where JSON: $error');
    }
    if (result is! Map<String, dynamic>) {
      throw FormatException('Invalid $where object');
    }
    return result;
  }

  void _validateManifest(
    Map<String, dynamic> m,
    StoryBlueprint blueprint,
    Map<String, dynamic> raw,
    Map<String, Uint8List> files,
  ) {
    const keys = {
      'format', 'format_version', 'bookworld_id', 'source_fingerprint',
      'title', 'author', 'languages', 'engine_min_version',
      'scenario_format', 'scenario_format_version', 'content_capabilities',
      'build_status', 'hashes', 'sizes', 'build_tool', 'model_provenance',
      'rights_status', 'blueprint_sha256',
    };
    if (m.keys.toSet().length != keys.length ||
        !m.keys.toSet().containsAll(keys) ||
        m['format'] != 'ai_story_bookworld' ||
        m['format_version'] != 1 ||
        m['bookworld_id'] != blueprint.bookId ||
        m['title'] != blueprint.title ||
        m['source_fingerprint'] != null ||
        m['rights_status'] != 'original_demo' ||
        m['author'] != 'AI Story RPG' ||
        canonicalJson(m['languages']) != canonicalJson(['ru']) ||
        m['engine_min_version'] != '0.1.0' ||
        m['scenario_format'] != 'ai_story_blueprint_v1' ||
        m['scenario_format_version'] != 1 ||
        m['build_status'] != 'original_demo_verified' ||
        m['blueprint_sha256'] != blueprint.blueprintHash ||
        canonicalJson(m['content_capabilities']) !=
            canonicalJson(raw['supported_modes']) ||
        canonicalJson(m['build_tool']) != canonicalJson({
          'name': 'ai_story_offline_bookworld', 'version': '1.0',
        }) ||
        canonicalJson(m['model_provenance']) != canonicalJson({
          'provider': 'none', 'model_id': null,
        })) {
      throw const FormatException('Unsupported .bworld manifest');
    }
    final hashes = m['hashes'];
    final sizes = m['sizes'];
    const payload = {'scenario/blueprint.json', 'world.sqlite'};
    if (hashes is! Map<String, dynamic> ||
        sizes is! Map<String, dynamic> ||
        hashes.length != 2 || sizes.length != 2 ||
        !hashes.keys.toSet().containsAll(payload) ||
        !sizes.keys.toSet().containsAll(payload)) {
      throw const FormatException('Invalid .bworld manifest hashes/sizes');
    }
    for (final name in payload) {
      final entry = files[name]!;
      if (sizes[name] is! int || sizes[name] != entry.length ||
          hashes[name] != sha256.convert(entry).toString()) {
        throw FormatException('Checksum or size mismatch: $name');
      }
    }
  }

  bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; ++i) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
