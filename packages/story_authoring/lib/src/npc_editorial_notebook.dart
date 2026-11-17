import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'npc_character_card.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// Editorial annotations for a possible playable NPC. No fact in this
/// notebook is automatically a source truth or a story_core actor.
enum NpcDraftField { role, motivation, knowledge, secret, relationship }

class NpcDraftNote {
  const NpcDraftNote({
    required this.id,
    required this.field,
    required this.text,
    this.sourceAssertionId,
    this.targetDossierId,
    this.targetGroupDigest,
    this.targetCharacterId,
  });

  final String id;
  final NpcDraftField field;
  final String text;

  /// Null = explicitly authored alternate material. Non-null = a
  /// source-backed, human-reviewed *candidate*, never automatic canon.
  final String? sourceAssertionId;

  /// A relationship names one other current mention-group, not an NPC ID.
  final String? targetDossierId;
  /// Exact snapshot of the other name group's source spans, so SAME/DIFFERENT
  /// edits cannot silently redirect an authored relationship.
  final String? targetGroupDigest;
  /// Stable, opaque identity of the reviewed target NPC. A group/name is
  /// only a source witness, never a substitute for a permanent actor ID.
  /// Null is accepted for old editorial notes, but new UI links pin the ID.
  final String? targetCharacterId;

  bool get isAuthorial => sourceAssertionId == null;
  bool get isWorldCanon => false;

  Map<String, Object?> toJson() => {
    'id': id,
    'field': field.name.toUpperCase(),
    'text': text,
    'source_assertion_id': sourceAssertionId,
    'target_dossier_id': targetDossierId,
    'target_group_sha256': targetGroupDigest,
    if (targetCharacterId != null) 'target_character_id': targetCharacterId,
  };

  static NpcDraftNote fromJson(Map<String, dynamic> item) {
    const fields = {
      'id', 'field', 'text',
      'source_assertion_id', 'target_dossier_id', 'target_group_sha256',
    };
    final expected = {
      ...fields,
      if (item.containsKey('target_character_id')) 'target_character_id',
    };
    if (item.length != expected.length ||
        !item.keys.toSet().containsAll(expected)) {
      throw const FormatException('Неизвестные поля заметки NPC');
    }
    try {
      final kind = NpcDraftField.values.singleWhere(
          (v) => v.name.toUpperCase() == item['field']);
      return NpcDraftNote(
        id: item['id'] as String,
        field: kind,
        text: item['text'] as String,
        sourceAssertionId: item['source_assertion_id'] as String?,
        targetDossierId: item['target_dossier_id'] as String?,
        targetGroupDigest: item['target_group_sha256'] as String?,
        targetCharacterId: item['target_character_id'] as String?,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённая заметка NPC');
    }
  }
}

class NpcDraftProfile {
  NpcDraftProfile({
    required this.dossierId,
    required List<String> mentionIds,
    required this.displayName,
    required List<NpcDraftNote> notes,
    this.card,
  }) : mentionIds = List.unmodifiable(mentionIds),
       notes = List.unmodifiable(notes);

  /// Current source-only dossier representative; NOT a permanent actor id.
  final String dossierId;
  final List<String> mentionIds;
  final String displayName;
  final List<NpcDraftNote> notes;
  /// Null only for older editorial test/checkpoint formats that never had a
  /// stable character identity. All NEW user-created cards get this exactly
  /// once through freshProfile(), and it is immutable thereafter.
  final NpcCharacterCard? card;

  String? get characterId => card?.characterId;
  bool get hasPermanentIdentity => card != null;

  NpcDraftProfile copyWith({
    String? displayName,
    List<NpcDraftNote>? notes,
    NpcCharacterCard? card,
  }) => NpcDraftProfile(
    dossierId: dossierId,
    mentionIds: mentionIds,
    displayName: displayName ?? this.displayName,
    notes: notes ?? this.notes,
    card: card ?? this.card,
  );

  bool get canPublishToGame => false;

  Map<String, Object> toJson() => {
    'dossier_id': dossierId,
    'mention_ids': mentionIds,
    'display_name': displayName,
    'notes': [for (final n in notes) n.toJson()],
    if (card != null) 'character_card': card!.toJson(),
  };

  static NpcDraftProfile fromJson(Map<String, dynamic> item) {
    const keys = {'dossier_id', 'mention_ids', 'display_name', 'notes'};
    final expected = {
      ...keys,
      if (item.containsKey('character_card')) 'character_card',
    };
    if (item.length != expected.length ||
        !item.keys.toSet().containsAll(expected)) {
      throw const FormatException('Неизвестные поля карточки NPC');
    }
    try {
      return NpcDraftProfile(
        dossierId: item['dossier_id'] as String,
        mentionIds: [for (final id in item['mention_ids'] as List) id as String],
        displayName: item['display_name'] as String,
        notes: [
          for (final raw in item['notes'] as List)
            NpcDraftNote.fromJson(Map<String, dynamic>.from(raw as Map)),
        ],
        card: item.containsKey('character_card')
            ? NpcCharacterCard.fromJson(
                Map<String, dynamic>.from(item['character_card'] as Map))
            : null,
      );
    } catch (_) {
      throw const FormatException('Повреждённая карточка NPC');
    }
  }
}

/// Separate, private, bounded checkpoint. Do not migrate/modify previously
/// compiled BookWorld, story saves, short drafts or relation decisions.
class NpcEditorialNotebook {
  NpcEditorialNotebook._(this.sourceFingerprint, List<NpcDraftProfile> profiles)
      : profiles = List.unmodifiable(profiles);

  static const format = 'ai_story_npc_editorial_m2e5b2_v1';
  static const maxBytes = 2 * 1024 * 1024;
  static const maxProfiles = 256;
  static const maxNotesPerProfile = 48;
  static final RegExp _noteId = RegExp(r'^npc_note_[1-9][0-9]{0,6}$');
  static final RegExp _noControl =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', unicode: true);

  final String sourceFingerprint;
  final List<NpcDraftProfile> profiles;

  bool get canPublishBookworld => false;
  bool get isVerifiedWorldCanon => false;
  bool get isLlmPromptApproved => false;

  factory NpcEditorialNotebook.empty(BookSourceIndex index) =>
      NpcEditorialNotebook._(index.sourceFingerprint, const []);

  static String _sha(String raw) => sha256.convert(utf8.encode(raw)).toString();

  static String _normal(String raw) => raw.trim().toLowerCase()
      .replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ');

  static List<String> mentionIds(SourceCharacterDossier dossier) =>
      List.unmodifiable([for (final e in dossier.mentions) e.id]..sort());

  static String groupDigest(SourceCharacterDossier dossier) =>
      _sha(mentionIds(dossier).join('|'));

  /// Fail closed for unverified names or a changed identity group. Refuse to
  /// rebind the old profile to a different NPC merely because names match.
  static bool isConfirmedDossier(SourceCharacterDossier dossier) =>
      dossier.mentions.isNotEmpty &&
      dossier.mentions.every((e) =>
          e.kind == EvidenceKind.character &&
          e.status == EvidenceStatus.confirmed &&
          e.spoilerGate == EvidenceSpoilerGate.chapter &&
          e.visibleAfterChapter == e.chapterIndex);

  /// The name match is a search hint; no coreference is inferred.
  /// Only explicitly reviewed catalog candidates with all source spans
  /// confirmed and chapter-visible may be cited by authored annotations.
  static List<SourceSemanticAssertion> eligibleClaims(
    SourceCharacterDossier dossier,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
    SourceEvidenceGraph graph,
  ) {
    final mentions = {for (final e in dossier.mentions) e.id};
    final names = dossier.labels.map(_normal).toSet();
    final quotes = {for (final e in graph.records) e.id: e};
    final result = <SourceSemanticAssertion>[];
    for (final claim in catalog.assertions) {
      if (editorial.verdicts[claim.id] !=
          SemanticEditorialVerdict.canonCandidate) continue;
      if (!(claim.evidenceIds.any(mentions.contains) ||
          names.contains(_normal(claim.subject)) ||
          (claim.object.isNotEmpty &&
              names.contains(_normal(claim.object))))) continue;
      if (claim.evidenceIds.isEmpty || !claim.evidenceIds.every((id) {
        final quote = quotes[id];
        return quote != null &&
            quote.status == EvidenceStatus.confirmed &&
            quote.spoilerGate == EvidenceSpoilerGate.chapter &&
            quote.visibleAfterChapter == quote.chapterIndex;
      })) continue;
      result.add(claim);
    }
    return List.unmodifiable(result);
  }

  static void _text(String raw, int limit, String label) {
    if (raw.trim().isEmpty || raw.length > limit ||
        _noControl.hasMatch(raw)) {
      throw FormatException('Недопустимый текст: $label');
    }
  }

  /// Validation is mandatory before every write AND on every read.
  /// An updated SAME/DIFFERENT decision changes the group and explicitly
  /// blocks a stale notebook instead of silently migrating annotations.
  void validate(
    BookSourceIndex index,
    SourceCharacterDossierIndex dossiers,
    SourceEvidenceGraph graph,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
  ) {
    if (sourceFingerprint != index.sourceFingerprint ||
        dossiers.sourceFingerprint != sourceFingerprint ||
        graph.sourceFingerprint != sourceFingerprint ||
        catalog.sourceFingerprint != sourceFingerprint ||
        !editorial.matches(index, catalog) ||
        profiles.length > maxProfiles) {
      throw const FormatException('Чужая редакция или слишком много NPC');
    }
    final groupById = {for (final d in dossiers.dossiers) d.id: d};
    final profileByDossier = {for (final p in profiles) p.dossierId: p};
    final usedProfiles = <String>{};
    final usedCharacterIds = <String>{};
    final usedNotes = <String>{};
    for (final profile in profiles) {
      final dossier = groupById[profile.dossierId];
      if (dossier == null ||
          !usedProfiles.add(profile.dossierId) ||
          !isConfirmedDossier(dossier) ||
          profile.mentionIds.length != dossier.mentions.length ||
          profile.mentionIds.join('|') != mentionIds(dossier).join('|')) {
        throw const FormatException(
            'Изменились подтверждения или объединение имён NPC');
      }
      _text(profile.displayName, 96, 'имя NPC');
      profile.card?.validate();
      if (profile.characterId != null &&
          !usedCharacterIds.add(profile.characterId!)) {
        throw const FormatException('Один character_id назначен двум NPC');
      }
      if (profile.notes.length > maxNotesPerProfile) {
        throw const FormatException('Слишком много заметок у NPC');
      }
      final eligible = {
        for (final claim in eligibleClaims(
            dossier, catalog, editorial, graph)) claim.id,
      };
      for (final note in profile.notes) {
        if (!_noteId.hasMatch(note.id) || !usedNotes.add(note.id)) {
          throw const FormatException('Дубликат идентификатора заметки');
        }
        _text(note.text, 800, 'заметка персонажа');
        if (note.sourceAssertionId != null &&
            !eligible.contains(note.sourceAssertionId)) {
          throw const FormatException(
              'Отозвана цитата или редакторское решение по NPC');
        }
        if (note.field != NpcDraftField.relationship) {
          if (note.targetDossierId != null ||
              note.targetGroupDigest != null ||
              note.targetCharacterId != null) {
            throw const FormatException('Цель есть у нереляционной заметки');
          }
        } else {
          final target = groupById[note.targetDossierId];
          if (note.targetDossierId == null ||
              note.targetDossierId == profile.dossierId ||
              target == null || !isConfirmedDossier(target) ||
              note.targetGroupDigest != groupDigest(target)) {
            throw const FormatException(
                'Связь указывает на неподтверждённого персонажа');
          }
          // Only source-anchored OLD notes may omit the stable target ID.
          // Never silently resolve a stored ID by matching names/aliases:
          // a deleted, replaced or regrouped target must fail closed.
          if (note.targetCharacterId != null) {
            final pinnedTarget = profileByDossier[note.targetDossierId];
            if (profile.characterId == null ||
                pinnedTarget?.characterId != note.targetCharacterId ||
                profile.characterId == note.targetCharacterId) {
              throw const FormatException(
                  'Связь NPC потеряла подтверждённый character_id адресата');
            }
          }
        }
      }
    }
    if (utf8.encode(encode()).length > maxBytes) {
      throw const FormatException('Превышен размер заметок NPC');
    }
  }

  /// Once issued, the identity is never changed by editing name, prose,
  /// aliases, quotes, notes or source grouping. A raw stale profile may omit
  /// the card; in that case we retain the already persisted identity. A
  /// deliberate replacement with another ID is rejected rather than silently
  /// reassigning the actor and its existing game knowledge.
  NpcEditorialNotebook putProfile(NpcDraftProfile profile) {
    final previous = [
      for (final p in profiles)
        if (p.dossierId == profile.dossierId) p,
    ];
    if (previous.isNotEmpty) {
      final oldId = previous.single.characterId;
      final newId = profile.characterId;
      if (oldId != null && newId != null && oldId != newId) {
        throw const FormatException('Нельзя заменять постоянный character_id');
      }
      if (oldId != null && newId == null) {
        profile = profile.copyWith(card: previous.single.card);
      }
    }
    return NpcEditorialNotebook._(sourceFingerprint, [
      for (final p in profiles)
        if (p.dossierId != profile.dossierId) p,
      profile,
    ]);
  }

  NpcEditorialNotebook removeProfile(String dossierId) =>
      NpcEditorialNotebook._(sourceFingerprint, [
        for (final p in profiles) if (p.dossierId != dossierId) p,
      ]);

  static NpcDraftProfile freshProfile(SourceCharacterDossier dossier) {
    if (!isConfirmedDossier(dossier)) {
      throw const FormatException('Сначала подтвердите все цитаты имени');
    }
    return NpcDraftProfile(
      dossierId: dossier.id,
      mentionIds: mentionIds(dossier),
      displayName: dossier.labels.first,
      notes: const [],
      card: NpcCharacterCard.fresh(),
    );
  }

  String nextNoteId() {
    final used = {
      for (final profile in profiles)
        for (final note in profile.notes) note.id,
    };
    for (var n = 1; n <= 9999999; n++) {
      final next = 'npc_note_$n';
      if (!used.contains(next)) return next;
    }
    throw const FormatException('Исчерпаны номера заметок NPC');
  }

  String encode() {
    final payload = <String, Object>{
      'source_fingerprint': sourceFingerprint,
      'stage': 'PERSONAL_NPC_EDITORIAL_ONLY',
      'can_publish_bookworld': false,
      'is_verified_world_canon': false,
      'profiles': [for (final p in profiles) p.toJson()],
    };
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint NPC');
    }
    return raw;
  }

  static NpcEditorialNotebook decode(
    BookSourceIndex index,
    SourceCharacterDossierIndex dossiers,
    SourceEvidenceGraph graph,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
    String raw,
  ) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint NPC');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final payload = Map<String, dynamic>.from(root['payload'] as Map);
      const keys = {
        'source_fingerprint', 'stage', 'can_publish_bookworld',
        'is_verified_world_canon', 'profiles',
      };
      if (root.length != 3 ||
          !root.keys.toSet().containsAll({'format', 'payload', 'sha256'}) ||
          root['format'] != format ||
          payload.length != keys.length ||
          !payload.keys.toSet().containsAll(keys) ||
          payload['source_fingerprint'] != index.sourceFingerprint ||
          payload['stage'] != 'PERSONAL_NPC_EDITORIAL_ONLY' ||
          payload['can_publish_bookworld'] != false ||
          payload['is_verified_world_canon'] != false ||
          root['sha256'] != _sha(jsonEncode(payload))) {
        throw const FormatException('Повреждённый или чужой checkpoint NPC');
      }
      final items = payload['profiles'] as List;
      if (items.length > maxProfiles) {
        throw const FormatException('Слишком много карточек NPC');
      }
      final notebook = NpcEditorialNotebook._(
        index.sourceFingerprint,
        [
          for (final item in items)
            NpcDraftProfile.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
      );
      notebook.validate(index, dossiers, graph, catalog, editorial);
      if (notebook.encode() != raw) {
        throw const FormatException('Неканоническая запись NPC');
      }
      return notebook;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённые поля checkpoint NPC');
    }
  }
}
