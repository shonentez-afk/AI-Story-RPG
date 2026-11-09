import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';
import 'private_bookworld_writer.dart';

/// Builds a genuinely literal, FULL-SOURCE, linear CANON edition.
///
/// Every source-index chunk is reproduced verbatim in exactly one reachable
/// scene, in source order; nothing is generated, summarized or silently
/// skipped. An optional AI interlude may change only reserved GM fiction
/// state in a persistent event, NEVER this immutable sequence of book text.
/// This is textual CANON, not semantic proof of motives or invented episodes.
final class ReviewedLiteralCanonBookworldWriter {
  const ReviewedLiteralCanonBookworldWriter();
  static const reviewFormat = 'ai_story_literal_canon_review_v1';
  static const reviewScope = 'exact_complete_source_text';
  static final RegExp _safe = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static String _hash(Object? source) =>
      sha256.convert(utf8.encode(canonicalJson(source))).toString();
  static String _shaText(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String approvalDigest({
    required Map<String, dynamic> sourceIndex,
    required String title, required String author,
  }) => _hash({
    'format': reviewFormat, 'scope': reviewScope,
    'edition': sourceIndex['source_fingerprint'],
    'source_index_sha256': _hash(sourceIndex),
    'title': title, 'author': author,
  });

  Uint8List build({
    required Map<String, dynamic> sourceIndex,
    required String title,
    required String author,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (!userConfirmed || title.trim().isEmpty ||
        title != title.trim() || title.length > 256 ||
        author.length > 256 || _safe.hasMatch(title) ||
        _safe.hasMatch(author) ||
        approvedDigest != approvalDigest(
            sourceIndex: sourceIndex, title: title, author: author)) {
      throw const FormatException('Full-book CANON approval is absent or stale');
    }
    final fingerprint = sourceIndex['source_fingerprint'];
    final chapterCount = sourceIndex['chapter_count'];
    final chunks = sourceIndex['chunks'];
    final coverage = sourceIndex['text_total_utf16'];
    if (fingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        chapterCount is! int || chapterCount < 1 ||
        chapterCount > 10000 ||
        sourceIndex['indexed_chapter_count'] != chapterCount ||
        sourceIndex['text_indexed_utf16'] != coverage ||
        coverage is! int || coverage <= 0 ||
        sourceIndex['media_blocks_for_review'] != 0 ||
        chunks is! List || chunks.isEmpty || chunks.length > 5000) {
      throw const FormatException(
          'CANON requires all source chapters and 1..5000 text blocks with no unreviewed media');
    }
    final bpScenes = <Map<String, dynamic>>[];
    final origins = <Map<String, dynamic>>[];
    final route = <Map<String, dynamic>>[];
    final chapterHits = <int>{};
    var lastChapter = 0;
    for (var i = 0; i < chunks.length; i++) {
      final raw = chunks[i];
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid book text chunk');
      }
      final ch = raw['chapter_index'];
      final text = raw['text'];
      final start = raw['start_utf16'];
      final end = raw['end_utf16'];
      final chunkId = raw['id'];
      final chapterId = raw['chapter_id'];
      final block = raw['block_index'];
      if (ch is! int || ch < lastChapter || ch >= chapterCount ||
          text is! String || text.trim().isEmpty ||
          start is! int || end is! int || end - start != text.length ||
          chunkId is! String || chunkId.isEmpty ||
          chunkId.length > 120 ||
          chapterId is! String || chapterId.isEmpty ||
          chapterId.length > 120 ||
          block is! int || block < 0 ||
          raw['sha256_text'] != _shaText(text)) {
        throw const FormatException('CANON source text is incomplete or reordered');
      }
      lastChapter = ch;
      chapterHits.add(ch);
      final sceneId = 'canon_' + i.toString().padLeft(5, '0');
      final isLast = i + 1 == chunks.length;
      bpScenes.add({
        'id': sceneId,
        'text': text,
        'terminal': isLast,
        'choices': isLast ? <Map<String, dynamic>>[] : [{
          'id': 'canon_next_' + i.toString().padLeft(5, '0'),
          'label': 'Продолжить книгу',
          'next_scene_id': 'canon_' +
              (i + 1).toString().padLeft(5, '0'),
          'conditions': <Object>[], 'effects': <Object>[],
        }],
      });
      // A quote witness lies inside its exact own chunk. Source index
      // validation verifies ALL original bytes, even those not quoted here.
      final startRelative = text.indexOf(RegExp(r'\S', unicode: true));
      if (startRelative < 0) {
        throw const FormatException('Empty canonical source passage');
      }
      var endRelative = math.min(startRelative + 160, text.length);
      if (endRelative < text.length &&
          text.codeUnitAt(endRelative) >= 0xdc00 &&
          text.codeUnitAt(endRelative) <= 0xdfff) {
        endRelative--;
      }
      final sample = text.substring(startRelative, endRelative);
      final quoteId = _shaText(sceneId + '|' + chunkId + '|' +
          start.toString()).substring(0, 32);
      final assertion = _shaText('literal|' + quoteId).substring(0, 32);
      origins.add({
        'scene_id': sceneId,
        'chapter_index': ch,
        'origin': 'SOURCE_PASSAGE',
        'assertion_ids': [assertion],
        'source_refs': [{
          'id': quoteId,
          'chunk_id': chunkId,
          'chapter_id': chapterId,
          'chapter_index': ch,
          'block_index': block,
          'start_utf16': start + startRelative,
          'end_utf16': start + endRelative,
          'quote_sha256': _shaText(sample),
          'visible_after_chapter': ch,
        }],
      });
      route.add({
        'scene_id': sceneId,
        'chunk_id': chunkId,
        'chapter_index': ch,
        'start_utf16': start,
        'end_utf16': end,
        'source_sha256': _shaText(text),
      });
    }
    if (chapterHits.length != chapterCount ||
        chapterHits.any((ch) => ch < 0 || ch >= chapterCount) ||
        !chapterHits.containsAll(
            Iterable<int>.generate(chapterCount)) ||
        lastChapter != chapterCount - 1) {
      throw const FormatException('Canon cannot silently omit a book chapter');
    }
    final id = 'canon_' + fingerprint.substring(0, 12) +
        '_' + approvedDigest.substring(0, 12);
    final bp = <String, dynamic>{
      'format': 'ai_story_blueprint_v1',
      'schema_version': 1,
      'book_id': id,
      'title': title,
      'entry_scene_id': bpScenes.first['id'],
      'rights_status': 'private_adaptation',
      'source_fingerprint': fingerprint,
      'supported_modes': {
        'roles': ['PROTAGONIST'],
        'plots': ['CANON'],
        'interactions': ['AI_FREEFORM'],
      },
      'items': ['gm_keepsake'],
      'facts': ['gm_impression'],
      'actors': ['player'],
      'initial_state': {
        'scene_id': bpScenes.first['id'],
        'revision': 0,
        'tick': 0,
        'stats': {'gm_resolve': 50},
        'inventory': <String>[],
        'flags': {'gm_noted': false},
        'knowledge': {'player': <String>[]},
      },
      'scenes': bpScenes,
    };
    final canonical = <String, dynamic>{
      'format': reviewFormat,
      'scope': reviewScope,
      'source_fingerprint': fingerprint,
      'source_index_sha256': _hash(sourceIndex),
      'source_chapters_total': chapterCount,
      'source_chunks_total': chunks.length,
      'user_confirmed': true,
      'literary_truth_scope': 'verbatim_text_and_order_only',
      'route': route,
    };
    final provenance = <String, dynamic>{
      'format': 'ai_story_private_provenance_v2',
      'bookworld_id': id,
      'source_fingerprint': fingerprint,
      'source_title': title,
      'source_author': author,
      'source_chapters_total': chapterCount,
      'source_chapters_indexed': chapterCount,
      'semantic_catalog_sha256': _hash(sourceIndex),
      'intermediate_draft_sha256': approvedDigest,
      'rights_status': 'private_use_only',
      'publication_authorized': false,
      'model_provenance': {
        'provider': 'none', 'model_id': null,
        'model_id_status': 'not_applicable',
        'tool': 'AI Story RPG', 'method': 'source_literal_compilation',
      },
      'scene_origins': origins,
      'canon_review': canonical,
      'presentation': {
        'hero': {
          'name': 'Читатель',
          'description': 'Игрок в буквальном тексте книги. '
              'Свободные ИИ-вставки не являются событиями литературного канона.',
        },
        'item_names': {'gm_keepsake': 'Вымышленная находка'},
        'item_descriptions': {
          'gm_keepsake': 'Не является предметом из исходной книги',
        },
        'stat_names': {'gm_resolve': 'Решимость в игре'},
        'fact_names': {'gm_impression': 'Вымышленное наблюдение игрока'},
        'scene_names': {
          for (var i = 0; i < bpScenes.length; i++)
            bpScenes[i]['id'] as String:
                'Глава ' +
                ((route[i]['chapter_index'] as int) + 1).toString() +
                ' · фрагмент ' + (i + 1).toString(),
        },
      },
    };
    // The existing source audit verifies every indexed byte and every
    // literal quote. The new v5 importer independently verifies that the
    // compiled blueprint has NO non-source scenes or alternate ending.
    return const RichPrivateBookworldWriter().build(
      blueprint: bp, provenance: provenance,
      sourceIndex: sourceIndex,
      expanded: true,
      literalCanon: true,
    );
  }
}
