import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'npc_editorial_notebook.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_plan.dart';

/// A PRIVATE selectable protagonist bound to an EXISTING permanent NPC ID.
///
/// The runtime actor remains 'player' in all supported .bworld versions.
/// Its selected book character identity is persisted as an initial, immutable
/// story_core flag. This does not import inferred facts, secrets or NPC
/// knowledge into the player, and is never a claim of literary CANON.
class ReviewedHeroRole {
  const ReviewedHeroRole._({
    required this.sourceFingerprint,
    required this.characterId,
    required this.displayName,
    required this.dossierId,
    required this.groupDigest,
    required this.firstSourceChapter,
    required this.confirmedMentions,
  });

  final String sourceFingerprint, characterId, displayName;
  final String dossierId, groupDigest;
  final int firstSourceChapter;
  /// Literal source spans, explicitly confirmed in the original NPC editor.
  /// Text is never shipped to a public archive or inferred from a name.
  final List<SourceEvidence> confirmedMentions;

  String get playerIdentityFlag => 'player_is_' + characterId;

  /// The current verified snapshot is authoritative; author-entered names
  /// never create or resolve a permanent identity.
  static List<ReviewedHeroRole> fromReviewedSources({
    required BookSourceIndex index,
    required SourceCharacterDossierIndex dossiers,
    required SourceEvidenceGraph graph,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required NpcEditorialNotebook notebook,
  }) {
    notebook.validate(index, dossiers, graph, catalog, editorial);
    final groups = {for (final d in dossiers.dossiers) d.id: d};
    final result = <ReviewedHeroRole>[];
    final usedIds = <String>{};
    for (final profile in notebook.profiles) {
      final id = profile.characterId;
      final dossier = groups[profile.dossierId];
      if (id == null || dossier == null) continue; // Legacy draft, not role.
      profile.card!.validate();
      if (!usedIds.add(id) ||
          !NpcEditorialNotebook.isConfirmedDossier(dossier) ||
          NpcEditorialNotebook.mentionIds(dossier)
                  .join('|') != profile.mentionIds.join('|')) {
        throw const FormatException(
            'Выбранная личность героя не подтверждена источником');
      }
      result.add(ReviewedHeroRole._(
        sourceFingerprint: index.sourceFingerprint,
        characterId: id,
        displayName: profile.displayName,
        dossierId: dossier.id,
        groupDigest: NpcEditorialNotebook.groupDigest(dossier),
        firstSourceChapter: dossier.firstChapter,
        confirmedMentions: List.unmodifiable(dossier.mentions
            .where((m) => m.kind == EvidenceKind.character &&
                m.status == EvidenceStatus.confirmed)),
      ));
    }
    result.sort((a, b) {
      final c = a.firstSourceChapter.compareTo(b.firstSourceChapter);
      return c != 0 ? c : a.characterId.compareTo(b.characterId);
    });
    return List.unmodifiable(result);
  }

  /// Bind to actual engine state. An id cannot be silently swapped when
  /// a user changes a displayed label. The game starts without any
  /// artificially inferred facts from the original NPC.
  StoryPlan bindTo(StoryPlan plan, NarrativeBookModel book) {
    if (sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != book.sourceFingerprint ||
        displayName.trim().isEmpty ||
        plan.flags.any((f) => f.startsWith('player_is_npc_'))) {
      throw const FormatException(
          'Постоянная роль героя относится к другому сценарию.');
    }
    final next = StoryPlan(
      sourceFingerprint: plan.sourceFingerprint,
      title: plan.title,
      entrySituationId: plan.entrySituationId,
      flags: [...plan.flags, playerIdentityFlag],
      initialFlags: [...plan.initialFlags, playerIdentityFlag],
      situations: plan.situations,
    );
    final audit = next.validate(book);
    if (!audit.isStructurallySound ||
        audit.terminalSituations < 2 ||
        !audit.branchChangesState) {
      throw const FormatException(
          'Выбор героя нарушил проверенный игровой маршрут.');
    }
    return next;
  }
}

