import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart' show canonicalJson;

import 'npc_campaign_consequences.dart';
import 'npc_campaign_writing_session.dart';
import 'reviewed_gameplay_compiler.dart';
import 'reviewed_hero_role.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'whole_book_npc_campaign.dart';
import 'whole_plan_gameplay_candidate_batch.dart';
import 'zai_source_locked_gameplay_candidates.dart';

/// A saved selection is an editable draft, NEVER a restored permission.
/// The preview is reconstructed from the CURRENT source and strict compiler.
class NpcConsequenceDraft {
  const NpcConsequenceDraft._(this.storageKey, this.revision,
      this.recordHash, this.preview);
  final String storageKey;
  final int revision;
  final String? recordHash;
  final NpcCampaignConsequencePreview? preview;
  int get effectCount => preview?.effectCount ?? 0;
  bool get cloudConsent => false;
  bool get installConsent => false;
  bool get effectsAccepted => false;
}

/// Private authoring storage in the existing repository. No archive, book
/// passages, API key, cloud consent or executable approval is persisted.
/// Process-local serialization + exact-record comparison protects concurrent
/// editors in this app. The repository provides atomic file replacement.
class NpcCampaignConsequenceStore {
  NpcCampaignConsequenceStore({required this.repository});
  final SourceAnalysisCheckpointRepository repository;
  static const format = 'ai_story_npc_consequence_draft_v1';
  static const maxBytes = 64 * 1024;
  static final _queues = <String, Future<void>>{};
  static final _random = Random.secure();

  static String storageKey(WholeBookNpcSourcePlan source) => npcWritingHash({
    'scope': format, 'source': source.index.sourceFingerprint,
    'plan': source.planDigest, 'hero': source.heroReviewDigest,
  });
  static String? _token(String? raw) => raw == null ? null : npcWritingHash(raw);
  static String _archiveHash(Uint8List archive) => sha256.convert(archive).toString();
  static void _keys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
      throw const FormatException('Неизвестные поля сохранённых последствий.');
    }
  }

  Future<T> _locked<T>(String key, Future<T> Function() operation) async {
    final previous = _queues[key] ?? Future<void>.value();
    final release = Completer<void>();
    _queues[key] = release.future;
    await previous;
    try { return await operation(); }
    finally {
      release.complete();
      if (identical(_queues[key], release.future)) _queues.remove(key);
    }
  }

  static Map<String, dynamic> _candidate(GameplayCandidate c) => {
    'kind': c.kind, 'id': c.id, 'label': c.label, 'op': c.op,
    'scene_id': c.sceneId, 'choice_id': c.choiceId,
    'source_event_id': c.sourceEventId, 'uncertainty': c.uncertainty,
  };

  static GameplayCandidate _parseCandidate(Object? value) {
    final raw = value as Map<String, dynamic>;
    _keys(raw, {'kind', 'id', 'label', 'op', 'scene_id', 'choice_id',
      'source_event_id', 'uncertainty'});
    if (raw.values.any((v) => v is! String || v.length > 350 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(v))) {
      throw const FormatException('Некорректные поля игрового эффекта.');
    }
    return GameplayCandidate(kind: raw['kind'] as String,
      id: raw['id'] as String, label: raw['label'] as String,
      op: raw['op'] as String, sceneId: raw['scene_id'] as String,
      choiceId: raw['choice_id'] as String,
      sourceEventId: raw['source_event_id'] as String,
      uncertainty: raw['uncertainty'] as String);
  }

  NpcConsequenceDraft _decode(String? raw, WholeBookNpcSourcePlan source,
      Uint8List originalArchive, List<ReviewedHeroRole> roles) {
    source.verifyCurrentHero(roles);
    source.verifyArchiveHero(const RichPrivateBookworldImporter().inspect(originalArchive));
    final key = storageKey(source);
    if (raw == null) return NpcConsequenceDraft._(key, 0, null, null);
    try {
      if (utf8.encode(raw).length > maxBytes) throw const FormatException();
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      _keys(envelope, {'payload', 'sha256'});
      final p = envelope['payload'] as Map<String, dynamic>;
      _keys(p, {'format', 'source', 'plan', 'hero', 'base', 'revision',
        'write_id', 'selection'});
      if (p['format'] != format || p['source'] != source.index.sourceFingerprint ||
          p['plan'] != source.planDigest || p['hero'] != source.heroReviewDigest ||
          p['base'] != _archiveHash(originalArchive) || p['revision'] is! int ||
          (p['revision'] as int) < 1 || p['write_id'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(p['write_id'] as String) ||
          envelope['sha256'] != npcWritingHash(p)) throw const FormatException();
      NpcCampaignConsequencePreview? preview;
      if (p['selection'] != null) {
        final selected = p['selection'] as Map<String, dynamic>;
        _keys(selected, {'manifest', 'max_new_requests', 'batches', 'notes'});
        final manifest = WholePlanGameplayBatchManifest.fromPlan(
          index: source.index, book: source.book, plan: source.plan,
          maxNewRequestsPerRun: selected['max_new_requests'] as int);
        final batches = selected['batches'] as List;
        final notes = Map<String, String>.from(selected['notes'] as Map);
        if (manifest.approvalDigest != selected['manifest'] ||
            batches.length != manifest.totalBatches || notes.isEmpty || notes.length > 6) {
          throw const FormatException();
        }
        final proposals = <GameplayCandidateDraft>[];
        var count = 0;
        for (var i = 0; i < batches.length; i++) {
          final row = batches[i] as Map<String, dynamic>;
          _keys(row, {'context', 'candidates'});
          final ctx = manifest.contexts[i];
          final values = row['candidates'] as List;
          count += values.length;
          if (row['context'] != ctx.approvalDigest || count > 6) {
            throw const FormatException();
          }
          proposals.add(GameplayCandidateDraft(sourceFingerprint: ctx.sourceFingerprint,
            approvalDigest: ctx.approvalDigest,
            candidates: List.unmodifiable(values.map(_parseCandidate))));
        }
        if (count != notes.length) throw const FormatException();
        // This rechecks literal item labels, source/event/choice bindings,
        // cross-batch names and every reachable inventory/knowledge route.
        // A recomputed checksum is not sufficient to authorize a forged rule.
        preview = NpcCampaignConsequences.preview(source: source,
          originalArchive: originalArchive, currentReviewedRoles: roles,
          manifest: manifest, proposals: proposals, selectedUserReviewNotes: notes);
      }
      return NpcConsequenceDraft._(key, p['revision'] as int, _token(raw), preview);
    } catch (_) {
      throw const FormatException('Сохранённые последствия повреждены или относятся '
          'к другой редакции. Файл не перезаписан; реплики и игры сохранены.');
    }
  }

  Future<NpcConsequenceDraft> load({required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive, required List<ReviewedHeroRole> roles}) async =>
      _decode(await repository.read(storageKey(source)), source, originalArchive, roles);

  Future<String?> recordHash(WholeBookNpcSourcePlan source) async =>
      _token(await repository.read(storageKey(source)));

  Future<void> assertUnchanged(WholeBookNpcSourcePlan source,
      NpcConsequenceDraft expected) async {
    if (expected.storageKey != storageKey(source) ||
        await recordHash(source) != expected.recordHash) {
      throw const FormatException('Последствия изменены в другом окне. '
          'Восстановите редактор перед продолжением.');
    }
  }

  String _encode(WholeBookNpcSourcePlan source, Uint8List archive,
      int revision, Object? selection) {
    final payload = {
      'format': format, 'source': source.index.sourceFingerprint,
      'plan': source.planDigest, 'hero': source.heroReviewDigest,
      'base': _archiveHash(archive), 'revision': revision,
      // A tombstone/reset can never recreate an older editor's CAS token.
      'write_id': List.generate(16, (_) => _random.nextInt(256)
          .toRadixString(16).padLeft(2, '0')).join(),
      'selection': selection,
    };
    final raw = canonicalJson({'payload': payload, 'sha256': npcWritingHash(payload)});
    if (utf8.encode(raw).length > maxBytes) throw const FormatException('Слишком большой черновик последствий.');
    return raw;
  }

  Future<NpcConsequenceDraft> save({required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive, required List<ReviewedHeroRole> roles,
    required NpcConsequenceDraft expected,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> proposals,
    required Map<String, String> selectedUserReviewNotes}) {
    // Validate before cropping: an unknown selection, duplicate candidate or
    // foreign packet is rejected rather than silently discarded.
    NpcCampaignConsequences.preview(source: source, originalArchive: originalArchive,
      currentReviewedRoles: roles, manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: selectedUserReviewNotes);
    final selection = {
      'manifest': manifest.approvalDigest,
      'max_new_requests': manifest.maxNewRequestsPerRun,
      'batches': [for (var i = 0; i < proposals.length; i++) {
        'context': manifest.contexts[i].approvalDigest,
        'candidates': [for (final c in proposals[i].candidates)
          if (selectedUserReviewNotes.containsKey(ReviewedGameplayCompiler.signature(c))) _candidate(c)],
      }],
      'notes': Map<String, String>.of(selectedUserReviewNotes),
    };
    return _write(source, originalArchive, roles, expected, selection);
  }

  Future<NpcConsequenceDraft> clear({required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive, required List<ReviewedHeroRole> roles,
    required NpcConsequenceDraft expected, required bool confirmed}) {
    if (!confirmed) throw const FormatException('Удаление последствий не подтверждено.');
    return _write(source, originalArchive, roles, expected, null);
  }

  Future<NpcConsequenceDraft> _write(WholeBookNpcSourcePlan source, Uint8List archive,
      List<ReviewedHeroRole> roles, NpcConsequenceDraft expected, Object? selection) {
    // Freeze and validate all input before the first asynchronous operation.
    final raw = _encode(source, archive, expected.revision + 1, selection);
    final result = _decode(raw, source, archive, roles);
    return _locked(storageKey(source), () async {
      await assertUnchanged(source, expected);
      await repository.write(storageKey(source), raw);
      return result; // Never publish success before the atomic write succeeds.
    });
  }

  /// Deliberately discard only THIS corrupt/stale effect record after showing
  /// a confirmation. Other heroes, NPC writings, book files and saves survive.
  Future<NpcConsequenceDraft> discard({required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive, required List<ReviewedHeroRole> roles,
    required String? expectedRecordHash, required bool confirmed}) {
    if (!confirmed) throw const FormatException('Сброс последствий не подтверждён.');
    final raw = _encode(source, originalArchive, 1, null);
    final result = _decode(raw, source, originalArchive, roles);
    return _locked(storageKey(source), () async {
      if (await recordHash(source) != expectedRecordHash) {
        throw const FormatException('Файл изменился после запроса сброса.');
      }
      await repository.write(storageKey(source), raw);
      return result;
    });
  }
}
