import 'book_source_index.dart';
import 'narrative_book_model.dart';

/// Source position is always known. In-world order may remain UNKNOWN,
/// particularly for flashbacks, testimony and unreliable narration.
enum GameWorldTimeRelation {
  unknown,
  firstBeforeSecond,
  secondBeforeFirst,
  simultaneous,
}

class SourceWorldTimeLink {
  const SourceWorldTimeLink({
    required this.id,
    required this.sourceFingerprint,
    required this.fromEventId,
    required this.toEventId,
    required this.relation,
    this.reviewedAsGameFiction = false,
  });

  final String id, sourceFingerprint, fromEventId, toEventId;
  final GameWorldTimeRelation relation;
  final bool reviewedAsGameFiction;
}

class SourceWorldTimeReport {
  const SourceWorldTimeReport({
    required this.unknownWorldOrderLinks,
    required this.explicitFictionalOrderLinks,
    required this.reversedTextOrderLinks,
  });

  final int unknownWorldOrderLinks;
  final int explicitFictionalOrderLinks;
  final int reversedTextOrderLinks;

  /// A consistent author-supplied order for PRIVATE gameplay is not proof of
  /// the chronology of the original literary work.
  bool get establishesBookWorldChronology => false;
  bool get establishesNarratorReliability => false;
  bool get canonicalRpgReady => false;

  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_world_time_m2h7b_v1',
    'status': 'GAME_FICTION_OR_UNKNOWN_ONLY',
    'world_time_unknown': unknownWorldOrderLinks,
    'reviewed_game_fiction': explicitFictionalOrderLinks,
    'reversed_in_source_text': reversedTextOrderLinks,
    'book_world_time_proven': false,
    'canonical_rpg_ready': false,
  };
}

/// Cycle detection applies ONLY to explicitly authored game-time rules.
/// Never promote page order to world time; unknown remains unknown.
class SourceWorldTimeAuditor {
  const SourceWorldTimeAuditor._();
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  static SourceWorldTimeReport audit({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required List<SourceWorldTimeLink> links,
  }) {
    if (!book.analysisComplete ||
        book.sourceFingerprint != index.sourceFingerprint ||
        book.title != index.title ||
        links.isEmpty || links.length > 128) {
      throw const FormatException('Непроверенная временная модель книги.');
    }
    final events = {for (final event in book.events) event.id: event};
    for (final event in events.values) {
      event.source.validate(index);
    }
    final ids = <String>{};
    final parents = <String, String>{
      for (final event in events.values) event.id: event.id,
    };
    String root(String eventId) {
      var id = eventId;
      while (parents[id] != id) {
        id = parents[id]!;
      }
      return id;
    }

    var unknown = 0, explicit = 0, reversed = 0;
    for (final link in links) {
      final from = events[link.fromEventId];
      final to = events[link.toEventId];
      if (!_id.hasMatch(link.id) || !ids.add(link.id) ||
          link.sourceFingerprint != index.sourceFingerprint ||
          from == null || to == null ||
          link.fromEventId == link.toEventId ||
          (link.relation != GameWorldTimeRelation.unknown &&
              !link.reviewedAsGameFiction)) {
        throw const FormatException('Подменённый или неразрешённый '
            'порядок времени событий.');
      }
      // Merely report reversal in narrative order, never treat it as
      // an objective error or a temporal claim.
      if (from.narrativePosition > to.narrativePosition) reversed++;
      if (link.relation == GameWorldTimeRelation.unknown) {
        unknown++;
      } else {
        explicit++;
        if (link.relation == GameWorldTimeRelation.simultaneous) {
          parents[root(from.id)] = root(to.id);
        }
      }
    }
    final edges = <String, Set<String>>{};
    for (final link in links) {
      String? before, after;
      switch (link.relation) {
        case GameWorldTimeRelation.unknown:
        case GameWorldTimeRelation.simultaneous:
          continue;
        case GameWorldTimeRelation.firstBeforeSecond:
          before = link.fromEventId;
          after = link.toEventId;
        case GameWorldTimeRelation.secondBeforeFirst:
          before = link.toEventId;
          after = link.fromEventId;
      }
      final from = root(before);
      final to = root(after);
      if (from == to) {
        throw const FormatException('Противоречие времён одного события.');
      }
      edges.putIfAbsent(from, () => <String>{}).add(to);
    }
    final color = <String, int>{};
    void visit(String node) {
      final state = color[node] ?? 0;
      if (state == 1) {
        throw const FormatException('Циклическая игровая хронология.');
      }
      if (state == 2) return;
      color[node] = 1;
      for (final next in edges[node] ?? <String>{}) {
        visit(next);
      }
      color[node] = 2;
    }
    for (final event in events.values) {
      visit(root(event.id));
    }
    return SourceWorldTimeReport(
      unknownWorldOrderLinks: unknown,
      explicitFictionalOrderLinks: explicit,
      reversedTextOrderLinks: reversed,
    );
  }
}
