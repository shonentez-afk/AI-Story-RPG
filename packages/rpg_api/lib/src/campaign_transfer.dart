part of '../rpg_api.dart';

/// Self-contained, private campaign handoff for non-Flutter clients.
///
/// The original source-verified .bworld and its signed .bwsave travel together.
/// The transfer envelope makes NO claims of literary truth or publishability.
/// Gameplay, archive verification and replay remain owned by RpgGameApi.
final class RpgCampaignTransfer {
  const RpgCampaignTransfer._();

  static const format = 'ai_story_rpg_campaign_transfer_v1';
  static const maxWorldBytes = 12 * 1024 * 1024;
  static const maxSaveBytes = 2 * 1024 * 1024;
  static const maxBundleBytes = 20 * 1024 * 1024;

  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');

  static Map<String, Object?> _body({
    required String hash,
    required String archive,
    required String save,
    required String sourceCampaignId,
    required int revision,
    required String stateHash,
  }) => {
    'format': format,
    'world_hash': hash,
    'archive_base64': archive,
    'save_text': save,
    'source_campaign_id': sourceCampaignId,
    'revision': revision,
    'state_hash': stateHash,
    'scope': 'private_local_transfer',
  };

  static String _digest(Map<String, Object?> body) =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();

  static Map<String, Object?> create(
      RpgGameApi game, String campaignId) {
    final matched = game.campaigns()
        .where((campaign) => campaign.id == campaignId).toList();
    if (matched.length != 1) {
      throw const FormatException('Unknown campaign');
    }
    final campaign = matched.single;
    final archive = game.exportWorld(campaign.worldHash);
    if (archive.isEmpty || archive.length > maxWorldBytes) {
      throw const FormatException('Transfer archive exceeds limit');
    }
    final inspected = const LocalRpgWorldIntakeApi().inspect(archive);
    if (inspected.archiveHash != campaign.worldHash) {
      throw const FormatException('Installed world hash does not match');
    }
    final save = game.exportSave(campaign.id);
    if (utf8.encode(save).length > maxSaveBytes) {
      throw const FormatException('Portable save exceeds limit');
    }
    final preview = game.previewSave(save,
        expectedWorldHash: campaign.worldHash);
    if (preview.revision != campaign.revision ||
        preview.sourceCampaignId != campaign.id ||
        !_hash.hasMatch(preview.stateHash)) {
      throw const FormatException('Campaign changed during transfer');
    }
    final body = _body(
      hash: campaign.worldHash,
      archive: base64Encode(archive),
      save: save,
      sourceCampaignId: campaign.id,
      revision: preview.revision,
      stateHash: preview.stateHash,
    );
    final result = {...body, 'bundle_sha256': _digest(body)};
    if (utf8.encode(jsonEncode(result)).length > maxBundleBytes) {
      throw const FormatException('Transfer exceeds limit');
    }
    return result;
  }

  static ({
    String hash,
    Uint8List archive,
    String save,
    String sourceCampaignId,
    int revision,
    String stateHash,
  }) _verified(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.length != 9 ||
        !raw.keys.toSet().containsAll({
          'format', 'world_hash', 'archive_base64', 'save_text',
          'source_campaign_id', 'revision', 'state_hash', 'scope',
          'bundle_sha256',
        })) {
      throw const FormatException('Invalid private transfer envelope');
    }
    final hash = raw['world_hash'];
    final archiveText = raw['archive_base64'];
    final save = raw['save_text'];
    final sourceCampaignId = raw['source_campaign_id'];
    final revision = raw['revision'];
    final stateHash = raw['state_hash'];
    final checksum = raw['bundle_sha256'];
    if (raw['format'] != format || raw['scope'] != 'private_local_transfer' ||
        hash is! String || !_hash.hasMatch(hash) ||
        stateHash is! String || !_hash.hasMatch(stateHash) ||
        checksum is! String || !_hash.hasMatch(checksum) ||
        archiveText is! String || archiveText.isEmpty ||
        archiveText.length > (maxWorldBytes * 4 ~/ 3) + 16 ||
        save is! String || utf8.encode(save).length > maxSaveBytes ||
        sourceCampaignId is! String || sourceCampaignId.isEmpty ||
        sourceCampaignId.length > 128 ||
        revision is! int || revision < 0 || revision > 2000) {
      throw const FormatException('Invalid private transfer fields');
    }
    final body = _body(
      hash: hash,
      archive: archiveText,
      save: save,
      sourceCampaignId: sourceCampaignId,
      revision: revision,
      stateHash: stateHash,
    );
    if (_digest(body) != checksum) {
      throw const FormatException('Private transfer checksum mismatch');
    }
    final bytes = base64Decode(archiveText);
    if (bytes.isEmpty || bytes.length > maxWorldBytes) {
      throw const FormatException('Private archive exceeds limit');
    }
    final archive = Uint8List.fromList(bytes);
    final receipt = const LocalRpgWorldIntakeApi().inspect(archive);
    if (receipt.archiveHash != hash) {
      throw const FormatException('Transfer world hash mismatch');
    }
    final saveEnvelope = jsonDecode(save);
    if (saveEnvelope is! Map<String, dynamic> ||
        saveEnvelope['world_sha256'] != hash ||
        saveEnvelope['source_campaign_id'] != sourceCampaignId) {
      throw const FormatException('Portable save does not match transfer');
    }
    return (
      hash: hash, archive: archive, save: save,
      sourceCampaignId: sourceCampaignId,
      revision: revision, stateHash: stateHash,
    );
  }

  /// Read-only: can verify the archive and exact envelope checksum without
  /// installing anything. On a destination missing the world it CANNOT
  /// attest replay/stateHash yet; that requires native SQLite preview.
  static Map<String, Object?> inspect(
      RpgGameApi game, Object? bundle) {
    final verified = _verified(bundle);
    final installed = game.worlds().any(
        (world) => world.archiveHash == verified.hash);
    if (installed) {
      final preview = game.previewSave(verified.save,
          expectedWorldHash: verified.hash);
      if (preview.revision != verified.revision ||
          preview.stateHash != verified.stateHash ||
          preview.sourceCampaignId != verified.sourceCampaignId) {
        throw const FormatException('Save replay does not match transfer');
      }
    }
    return {
      'format': format,
      'world_hash': verified.hash,
      'source_campaign_id': verified.sourceCampaignId,
      'revision': verified.revision,
      'state_hash': verified.stateHash,
      'world_installed': installed,
      'archive_verified': true,
      'save_replay_verified': installed,
      'needs_explicit_confirmation': true,
      'literary_canon_verified': false,
    };
  }

  /// Never overwrite another campaign. Missing worlds are installed only
  /// after explicit consent. Failed replay/commit rolls back the newly
  /// installed world; all imported turns are committed by the original
  /// story_core/SQLite implementation, not by this transport.
  static String restore(RpgGameApi game, Object? bundle,
      {required bool confirmed}) {
    if (!confirmed) {
      throw const FormatException('Private import requires confirmation');
    }
    final verified = _verified(bundle);
    final alreadyInstalled = game.worlds().any(
        (world) => world.archiveHash == verified.hash);
    var addedWorld = false;
    String? importedId;
    try {
      if (!alreadyInstalled) {
        final world = game.install(verified.archive);
        if (world.archiveHash != verified.hash) {
          throw const FormatException('Installed world hash mismatch');
        }
        addedWorld = true;
      }
      final preview = game.previewSave(verified.save,
          expectedWorldHash: verified.hash);
      if (preview.revision != verified.revision ||
          preview.stateHash != verified.stateHash ||
          preview.sourceCampaignId != verified.sourceCampaignId) {
        throw const FormatException('Portable replay does not match transfer');
      }
      importedId = game.importSave(verified.save,
          expectedWorldHash: verified.hash);
      final verifiedImport = game.previewSave(game.exportSave(importedId),
          expectedWorldHash: verified.hash);
      if (verifiedImport.revision != verified.revision ||
          verifiedImport.stateHash != verified.stateHash) {
        throw const FormatException('Transferred replay was not preserved');
      }
      return importedId;
    } catch (_) {
      if (importedId != null) {
        game.deleteCampaign(importedId, expectedRevision: verified.revision);
      }
      if (addedWorld) {
        game.deleteWorld(verified.hash);
      }
      rethrow;
    }
  }
}
