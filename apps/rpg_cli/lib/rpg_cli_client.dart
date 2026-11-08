/// Second standalone client of the public RPG API. Never import game rules.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';

class RpgCliClient {
  const RpgCliClient();
  static const maxInputBytes = 64 * 1024 * 1024;

  static Uint8List _read(String path) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() <= 0 ||
        file.lengthSync() > maxInputBytes) {
      throw const FormatException('Input missing or oversized');
    }
    return file.readAsBytesSync();
  }

  static Map<String, Object?> _view(WorldGameView view) => {
    'campaign_id': view.campaignId,
    'world_title': view.worldTitle,
    'hero_name': view.heroName,
    'scene_id': view.sceneId,
    'scene_text': view.sceneText,
    'revision': view.revision,
    'tick': view.tick,
    'terminal': view.isTerminal,
    'inventory': view.inventory,
    'known_facts': view.knownFacts,
    'npc_encountered': [
      for (final npc in view.npcRelations) {
        'actor_id': npc.actorId,
        'display_name': npc.displayName,
        'memory_count': npc.memoryCount,
        'life_state': npc.lifeState,
      }
    ],
    'journal': [
      for (final event in view.journal) {
        'sequence': event.sequence,
        'scene_id': event.sceneId,
        'choice': event.choiceLabel,
        'changes': event.changes,
      }
    ],
    'choices': [
      for (final choice in view.choices) {
        'id': choice.id,
        'label': choice.label,
        'enabled': choice.enabled,
        'lock_reason': choice.lockReason,
      }
    ],
  };

  Future<Map<String, Object?>> execute(List<String> argv) async {
    if (argv.isEmpty) throw const FormatException('Command is required');
    final command = argv.first;
    final args = _Options(argv.skip(1).toList());
    if (command == 'prepare') {
      final path = args.take('book');
      final chapter = args.positive('chapter');
      args.done();
      const RpgAuthoringApi api = LocalRpgAuthoringApi();
      final source = api.openSource(File(path).uri.pathSegments.last,
          _read(path), selectedChapter: chapter);
      return (await api.prepareBook(source)).status;
    }
    // CLI owns the directory and lifecycle; no gameplay rules live here.
    final storeDir = args.take('store');
    final store = BookworldCampaignStore.openPrivateDirectory(storeDir);
    try {
      final RpgGameApi api = LocalRpgGameApi(store);
      if (command == 'install') {
        final path = args.take('world');
        args.done();
        final world = api.install(_read(path));
        return {'status': 'installed', 'world_hash': world.archiveHash,
          'bookworld_id': world.bookworldId, 'title': world.title};
      }
      if (command == 'worlds') {
        args.done();
        return {'worlds': [
          for (final world in api.worlds())
            {'world_hash': world.archiveHash,
              'bookworld_id': world.bookworldId, 'title': world.title}
        ]};
      }
      if (command == 'campaigns') {
        final hash = args.optional('world-hash');
        args.done();
        return {'campaigns': [
          for (final campaign in api.campaigns(worldHash: hash))
            {'campaign_id': campaign.id, 'world_hash': campaign.worldHash,
              'revision': campaign.revision, 'parent_id': campaign.parentId}
        ]};
      }
      if (command == 'start') {
        final hash = args.take('world-hash');
        final parent = args.optional('parent');
        args.done();
        final id = api.start(hash, parentCampaignId: parent);
        return {'status': 'started', ..._view(api.load(id))};
      }
      if (command == 'view') {
        final id = args.take('campaign');
        args.done();
        return _view(api.load(id));
      }
      if (command == 'choose') {
        final id = args.take('campaign');
        final choice = args.take('choice');
        final action = args.take('action');
        final revision = args.nonnegative('revision');
        args.done();
        final result = api.choose(id, actionId: action, choiceId: choice,
            expectedRevision: revision);
        return {'applied': result.applied, 'duplicate': result.duplicate,
          'reason': result.reason, ..._view(result.view)};
      }
      if (command == 'export-save') {
        final id = args.take('campaign');
        final path = args.take('output');
        args.done();
        final data = api.exportSave(id);
        final file = File(path);
        file.createSync(exclusive: true);
        try {
          file.writeAsStringSync(data, flush: true);
        } catch (_) {
          if (file.existsSync()) file.deleteSync();
          rethrow;
        }
        return {'status': 'exported', 'output': path};
      }
      if (command == 'import-save') {
        final hash = args.take('world-hash');
        final path = args.take('input');
        args.done();
        final data = utf8.decode(_read(path));
        api.previewSave(data, expectedWorldHash: hash);
        final id = api.importSave(data, expectedWorldHash: hash);
        return {'status': 'imported', ..._view(api.load(id))};
      }
      throw const FormatException('Unknown command');
    } finally {
      store.close();
    }
  }
}

class _Options {
  _Options(List<String> tokens) {
    if (tokens.length.isOdd) {
      throw const FormatException('Options require values');
    }
    for (var i = 0; i < tokens.length; i += 2) {
      final key = tokens[i];
      if (!key.startsWith('--') || key.length <= 2 ||
          tokens[i + 1].isEmpty || _values.containsKey(key.substring(2))) {
        throw const FormatException('Malformed or repeated option');
      }
      _values[key.substring(2)] = tokens[i + 1];
    }
  }

  final Map<String, String> _values = {};
  String take(String key) {
    final value = _values.remove(key);
    if (value == null || value.isEmpty) {
      throw FormatException('Missing --$key');
    }
    return value;
  }
  String? optional(String key) => _values.remove(key);
  int? positive(String key) {
    final text = optional(key);
    if (text == null) return null;
    final value = int.tryParse(text);
    if (value == null || value < 1) throw FormatException('Invalid --$key');
    return value;
  }
  int nonnegative(String key) {
    final value = int.tryParse(take(key));
    if (value == null || value < 0) throw FormatException('Invalid --$key');
    return value;
  }
  void done() {
    if (_values.isNotEmpty) throw const FormatException('Unknown option');
  }
}
