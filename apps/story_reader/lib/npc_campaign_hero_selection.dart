import 'dart:async';
import 'dart:convert';
import 'npc_campaign_writing_session.dart';
import 'reviewed_hero_role.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'whole_book_npc_campaign.dart';
import 'package:story_authoring/npc_campaign_hero_selection.dart'
    show NpcCampaignHeroSelection;

export 'package:story_authoring/npc_campaign_hero_selection.dart'
    show NpcCampaignHeroSelection;

/// Separate small record points to the chosen role. Actual dialogue drafts
/// retain their per-plan addresses, so switching heroes deletes no work.
class NpcCampaignHeroStore {
  NpcCampaignHeroStore({SourceAnalysisCheckpointRepository? repository})
      : repository = repository ?? NpcWritingStore().repository;
  final SourceAnalysisCheckpointRepository repository;
  static final _queues = <String, Future<void>>{};
  static const _format = 'ai_story_npc_protagonist_selection_v1';

  static String _draftDigest(WholeBookNpcSourcePlan source) => npcWritingHash(source.draft.plan.encode());
  static String storageKey(WholeBookNpcSourcePlan source) => npcWritingHash({
    'scope': _format, 'source': source.index.sourceFingerprint,
    'draft': _draftDigest(source),
  });

  Future<NpcCampaignHeroSelection> load(WholeBookNpcSourcePlan source,
      List<ReviewedHeroRole> currentRoles) async {
    final raw = await repository.read(storageKey(source));
    if (raw == null) return const NpcCampaignHeroSelection(null, false, 0);
    try {
      if (utf8.encode(raw).length > 8192) throw const FormatException();
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope.length != 2 || !envelope.keys.toSet().containsAll({'payload', 'sha256'})) {
        throw const FormatException();
      }
      final p = envelope['payload'] as Map<String, dynamic>;
      if (p.length != 7 || !p.keys.toSet().containsAll({
        'format', 'source', 'draft', 'character_id', 'role_digest', 'source_action', 'revision',
      }) || p['format'] != _format || p['source'] != source.index.sourceFingerprint ||
          p['draft'] != _draftDigest(source) || p['source_action'] is! bool ||
          p['revision'] is! int || (p['revision'] as int) < 1 ||
          envelope['sha256'] != npcWritingHash(p)) throw const FormatException();
      ReviewedHeroRole? role;
      if (p['character_id'] != null) {
        final matches = currentRoles.where((r) => r.characterId == p['character_id']).toList();
        if (matches.length != 1 ||
            WholeBookNpcSourcePlan.roleDigest(matches.single) != p['role_digest']) {
          throw const FormatException();
        }
        role = matches.single;
      } else if (p['role_digest'] != null || p['source_action'] != false) {
        throw const FormatException();
      }
      final selection = NpcCampaignHeroSelection(role, p['source_action'] as bool, p['revision'] as int);
      selection.bind(source).verifyCurrentHero(currentRoles);
      return selection;
    } catch (_) {
      throw const FormatException('Сохранённый выбор героя повреждён или карточка изменилась. '
          'Автоматическая замена запрещена. Черновики и игры сохранены.');
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

  Future<NpcCampaignHeroSelection> save(WholeBookNpcSourcePlan source, {
    required List<ReviewedHeroRole> currentRoles,
    required ReviewedHeroRole? role,
    required bool sourceAction,
    required int expectedRevision,
  }) {
    final candidate = NpcCampaignHeroSelection(role, sourceAction, expectedRevision + 1);
    candidate.bind(source).verifyCurrentHero(currentRoles);
    return _locked(storageKey(source), () async {
      final previous = await load(source, currentRoles);
      if (previous.revision != expectedRevision) throw const FormatException(
          'Герой выбран в другом окне. Перечитайте выбор, не перезаписывая его.');
      final payload = {
        'format': _format, 'source': source.index.sourceFingerprint,
        'draft': _draftDigest(source), 'character_id': role?.characterId,
        'role_digest': role == null ? null : WholeBookNpcSourcePlan.roleDigest(role),
        'source_action': sourceAction, 'revision': expectedRevision + 1,
      };
      await repository.write(storageKey(source),
          jsonEncode({'payload': payload, 'sha256': npcWritingHash(payload)}));
      return candidate;
    });
  }

  /// Reset affects only the remembered selection, never per-hero writings.
  Future<void> reset(WholeBookNpcSourcePlan source, {required bool confirmed}) {
    if (!confirmed) throw const FormatException('Сброс выбора героя не подтверждён.');
    return _locked(storageKey(source), () => repository.delete(storageKey(source)));
  }
}
