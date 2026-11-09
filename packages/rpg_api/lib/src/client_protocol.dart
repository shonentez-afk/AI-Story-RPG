part of '../rpg_api.dart';

/// Versioned, transport-independent client protocol. No IO, Flutter, model
/// connection or application state machine; all writes use RpgGameApi.
final class RpgClientProtocol {
  RpgClientProtocol(this.game, {RpgAuthoringApi? authoring})
      : _authoring = authoring ?? const LocalRpgAuthoringApi();

  static const version = 'ai_story_rpg_client_v1';
  static const maxArchiveBytes = 64 * 1024 * 1024;
  static const maxBookBytes = 16 * 1024 * 1024;
  static const maxSaveBytes = 2 * 1024 * 1024;

  final RpgGameApi game;
  final RpgAuthoringApi _authoring;

  static Map<String, Object?> _error(String code) => {
    'version': version,
    'ok': false,
    'error': {'code': code},
  };

  /// Opaque errors: never return source text, local paths, model contents,
  /// SQLite details or exception stack traces through a client transport.
  Future<Map<String, Object?>> handle(Object? request) async {
    try {
      if (request is! Map<String, dynamic>) {
        throw const FormatException('Malformed protocol message');
      }
      if (request['version'] != version) {
        return _error('unsupported_version');
      }
      if (request.keys.toSet().difference(
          {'version', 'op', 'args'}).isNotEmpty) {
        throw const FormatException('Unexpected message fields');
      }
      final op = request['op'];
      final rawArgs = request['args'] ?? <String, dynamic>{};
      if (op is! String || rawArgs is! Map<String, dynamic>) {
        throw const FormatException('Malformed operation');
      }
      final result = await _dispatch(op, rawArgs);
      return {'version': version, 'ok': true, 'result': result};
    } on FormatException {
      return _error('invalid_input');
    } on ArgumentError {
      return _error('invalid_input');
    } on StateError {
      return _error('invalid_state');
    } catch (_) {
      return _error('engine_error');
    }
  }

  static void _fields(Map<String, dynamic> args,
      {Set<String> must = const {}, Set<String> may = const {}}) {
    if (!args.keys.toSet().containsAll(must) ||
        args.keys.toSet().difference({...must, ...may}).isNotEmpty) {
      throw const FormatException('Unexpected operation arguments');
    }
  }

  static String _text(Map<String, dynamic> args, String key,
      {int maxLength = 512}) {
    final value = args[key];
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw const FormatException('Invalid text argument');
    }
    return value;
  }

  static String? _optional(Map<String, dynamic> args, String key) =>
      args.containsKey(key) ? _text(args, key) : null;

  static int _number(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! int || value < 0 || value > 2147483647) {
      throw const FormatException('Invalid revision or chapter');
    }
    return value;
  }

  static Uint8List _bytes(Map<String, dynamic> args, String key,
      int maxBytes) {
    final encoded = _text(args, key,
        maxLength: (maxBytes * 4 ~/ 3) + 16);
    final data = base64Decode(encoded);
    if (data.isEmpty || data.length > maxBytes) {
      throw const FormatException('Invalid binary input size');
    }
    return Uint8List.fromList(data);
  }

  static Map<String, Object?> _world(WorldLibraryItem item) => {
    'world_hash': item.archiveHash,
    'bookworld_id': item.bookworldId,
    'title': item.title,
  };

  static Map<String, Object?> _campaign(WorldCampaignItem item) => {
    'campaign_id': item.id,
    'world_hash': item.worldHash,
    'revision': item.revision,
    'saved_at': item.savedAt,
    'parent_id': item.parentId,
  };

  /// The SAME safe game projection is used by CLI and future hosts. Do not
  /// export hidden scene titles, unpublished NPC cards or future item lists.
  static Map<String, Object?> projectView(WorldGameView view) => {
    'campaign_id': view.campaignId,
    'world_title': view.worldTitle,
    'hero_name': view.heroName,
    'hero_description': view.heroDescription,
    'scene_id': view.sceneId,
    'scene_title': view.sceneNames[view.sceneId],
    'scene_text': view.sceneText,
    'scene_origin': view.sceneSource == null ? null : {
      'source_title': view.sceneSource!.sourceTitle,
      'chapter_index': view.sceneSource!.chapterIndex,
      'chapter_number': view.sceneSource!.chapterNumber,
      'chapter_count': view.sceneSource!.chapterCount,
      'is_source_passage': view.sceneSource!.isSourcePassage,
    },
    'revision': view.revision,
    'tick': view.tick,
    'terminal': view.isTerminal,
    'stats': view.stats,
    'inventory': view.inventory,
    'items': [
      for (final id in view.inventory) {
        'id': id,
        'name': view.itemNames[id] ?? id,
        'description': view.itemDescriptions[id],
      }
    ],
    'known_facts': view.knownFacts,
    'npc_encountered': [
      for (final npc in view.npcRelations) {
        'actor_id': npc.actorId,
        'display_name': npc.displayName,
        'directed_score': npc.directedScore,
        'memory_count': npc.memoryCount,
        'memory_kinds': npc.memoryKinds,
        'life_state': npc.lifeState,
      }
    ],
    'npc_item_owners': view.npcItemOwners,
    'dialogue': [
      for (final turn in view.sceneDialogueTurns ?? const []) {
        'speaker': turn.speaker,
        'text': turn.text,
        'actor_id': view.sceneSpeakerIdentityReviewed &&
                turn.speaker != null
            ? view.visibleSpeakerActorIds[turn.speaker]
            : null,
      }
    ],
    'journal': [
      for (final event in view.journal) {
        'sequence': event.sequence,
        'scene_id': event.sceneId,
        'scene_title': event.sceneTitle,
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

  Future<Map<String, Object?>> _dispatch(
      String op, Map<String, dynamic> args) async {
    switch (op) {
      case 'capabilities':
        _fields(args);
        return {
          'sdk_version': RpgApiContract.version,
          'protocol_version': version,
          'offline_play': RpgApiContract.offlinePlay,
          'verified_private_compilation':
              RpgApiContract.verifiedPrivateCompilation,
          'arbitrary_book_canon': RpgApiContract.arbitraryBookCanon,
          'dynamic_ai_game_master': RpgApiContract.dynamicAiGameMaster,
          'world_formats': [1, 2, 3, 4],
          'portable_save': true,
        };
      case 'worlds':
        _fields(args);
        return {'worlds': [for (final item in game.worlds()) _world(item)]};
      case 'inspect_world':
        _fields(args, must: {'archive_base64'}, may: {'readiness_json'});
        final receipt = const LocalRpgWorldIntakeApi().inspect(
          _bytes(args, 'archive_base64', maxArchiveBytes),
          readinessJson: args.containsKey('readiness_json')
              ? _text(args, 'readiness_json', maxLength: 1024 * 1024)
              : null,
        );
        return {
          'title': receipt.title,
          'world_hash': receipt.archiveHash,
          'bookworld_id': receipt.bookworldId,
          'format_version': receipt.formatVersion,
          'source_fingerprint': receipt.sourceFingerprint,
          'scene_count': receipt.sceneCount,
          'ending_count': receipt.endingCount,
          'npc_actor_count': receipt.npcActorCount,
          'item_count': receipt.itemCount,
          'is_private': receipt.isPrivate,
          'chapters_total': receipt.sourceChaptersTotal,
          'chapters_indexed': receipt.sourceChaptersIndexed,
          'chapters_with_gameplay': receipt.sourceChaptersWithGameplay,
          'all_source_chapters_covered': receipt.allSourceChaptersCovered,
          'generator_report_attached': receipt.generatorReportAttached,
          'producer_claims_two_replayed_routes':
              receipt.producerClaimsTwoReplayedRoutes,
          'literary_canon_proven': receipt.literaryCanonProven,
          'allowed_to_publish': receipt.allowedToPublish,
        };
      case 'audit_world':
        _fields(args, must: {'archive_base64'},
            may: {'max_states', 'max_moves'});
        final maxStates = args.containsKey('max_states')
            ? _number(args, 'max_states') : 4096;
        final maxMoves = args.containsKey('max_moves')
            ? _number(args, 'max_moves') : 512;
        if (maxStates < 1 || maxStates > 4096 ||
            maxMoves < 1 || maxMoves > 512) {
          throw const FormatException('Audit budget exceeded');
        }
        final audit = const LocalRpgBookGameplayAuditApi().inspect(
            _bytes(args, 'archive_base64', maxArchiveBytes),
            maxStates: maxStates, maxMoves: maxMoves);
        return {
          'world_hash': audit.archiveHash,
          'status': audit.status.name,
          'explored_states': audit.exploredStates,
          'exhaustive': audit.exhaustive,
          'reached_endings': audit.reachedEndingCount,
          'total_endings': audit.totalEndingCount,
          'trap_count': audit.trapCount,
          'cycle_count': audit.cycleCount,
          'proven_all_endings': audit.provenAllEndings,
          'literary_canon_verified': audit.sourceLiteraryCanonVerified,
          'exact_generator_routes_replayed':
              audit.exactGeneratorRoutesReplayed,
        };
      case 'suggest_action':
        _fields(args, must: {'campaign_id', 'text'});
        final view = game.load(_text(args, 'campaign_id'));
        final preview = FreeTextActionGate.preview(
            FreeTextWorldGatewayPort.headFromView(view),
            _text(args, 'text', maxLength: 1000));
        return {
          'error': preview.error,
          'offers': [
            for (final offer in preview.offers) {
              'choice_id': offer.choiceId,
              'label': offer.label,
              'score': offer.score,
              'scene_id': offer.sceneId,
              'expected_revision': offer.expectedRevision,
              'fingerprint': offer.fingerprint,
            }
          ],
          'dynamic_ai_game_master': false,
        };
      case 'install_world':
        _fields(args, must: {'archive_base64'});
        final item = game.install(_bytes(
            args, 'archive_base64', maxArchiveBytes));
        return {'status': 'installed', ..._world(item)};
      case 'export_world':
        _fields(args, must: {'world_hash'});
        return {'archive_base64': base64Encode(
            game.exportWorld(_text(args, 'world_hash')))};
      case 'delete_world':
        _fields(args, must: {'world_hash'});
        game.deleteWorld(_text(args, 'world_hash'));
        return {'status': 'deleted'};
      case 'campaigns':
        _fields(args, may: {'world_hash'});
        return {'campaigns': [
          for (final c in game.campaigns(worldHash: _optional(args, 'world_hash')))
            _campaign(c)
        ]};
      case 'start':
        _fields(args, must: {'world_hash'}, may: {'parent_id'});
        final id = game.start(_text(args, 'world_hash'),
            parentCampaignId: _optional(args, 'parent_id'));
        return {'status': 'started', ...projectView(game.load(id))};
      case 'view':
        _fields(args, must: {'campaign_id'});
        return projectView(game.load(_text(args, 'campaign_id')));
      case 'choose':
        _fields(args, must: {
          'campaign_id', 'action_id', 'choice_id', 'expected_revision'
        });
        final result = game.choose(_text(args, 'campaign_id'),
            actionId: _text(args, 'action_id'),
            choiceId: _text(args, 'choice_id'),
            expectedRevision: _number(args, 'expected_revision'));
        return {
          'applied': result.applied,
          'duplicate': result.duplicate,
          'reason': result.reason,
          ...projectView(result.view),
        };
      case 'delete_campaign':
        _fields(args, must: {'campaign_id', 'expected_revision'});
        game.deleteCampaign(_text(args, 'campaign_id'),
            expectedRevision: _number(args, 'expected_revision'));
        return {'status': 'deleted'};
      case 'export_save':
        _fields(args, must: {'campaign_id'});
        return {'save_text': game.exportSave(_text(args, 'campaign_id'))};
      case 'preview_save':
        _fields(args, must: {'world_hash', 'save_text'});
        final text = _text(args, 'save_text', maxLength: maxSaveBytes);
        if (utf8.encode(text).length > maxSaveBytes) {
          throw const FormatException('Oversized portable save');
        }
        final save = game.previewSave(text,
            expectedWorldHash: _text(args, 'world_hash'));
        return {
          'source_campaign_id': save.sourceCampaignId,
          'world_hash': save.worldHash,
          'revision': save.revision,
          'state_hash': save.stateHash,
          'terminal': save.isTerminal,
        };
      case 'import_save':
        _fields(args, must: {'world_hash', 'save_text'});
        final hash = _text(args, 'world_hash');
        final text = _text(args, 'save_text', maxLength: maxSaveBytes);
        if (utf8.encode(text).length > maxSaveBytes) {
          throw const FormatException('Oversized portable save');
        }
        game.previewSave(text, expectedWorldHash: hash);
        final id = game.importSave(text, expectedWorldHash: hash);
        return {'status': 'imported', ...projectView(game.load(id))};
      case 'prepare_book':
        _fields(args, must: {'filename', 'book_base64'},
            may: {'selected_chapter'});
        final chapter = args.containsKey('selected_chapter')
            ? _number(args, 'selected_chapter') : null;
        if (chapter == 0) throw const FormatException('Invalid chapter');
        final source = _authoring.openSource(_text(args, 'filename'),
            _bytes(args, 'book_base64', maxBookBytes),
            selectedChapter: chapter);
        final report = await _authoring.prepareBook(source);
        return {
          'source_fingerprint': source.sourceFingerprint,
          'status': report.status,
        };
      case 'inspect_creation':
        _fields(args, must: {'intent'}, may: {'source_fingerprint'});
        final raw = args['intent'];
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Invalid creation intent');
        }
        final decision = const LocalRpgCreationApi().inspect(
            RpgCreationIntent.fromJson(raw),
            sourceFingerprint: _optional(args, 'source_fingerprint'));
        return {
          'supported': decision.supported,
          'explanation': decision.explanation,
          'can_play_without_network': decision.canPlayWithoutNetwork,
          'is_full_literary_canon': decision.isFullLiteraryCanon,
          'is_dynamic_ai_master': decision.isDynamicAiMaster,
          'requires_further_review': decision.requiresFurtherReview,
        };
      default:
        throw const FormatException('Unknown operation');
    }
  }
}
