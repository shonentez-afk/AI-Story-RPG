import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'zai_whole_book_event_outline.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// The first, deliberately modest one-screen mode. All source scenes contain
/// exact, locally verified book excerpts, not AI-asserted facts about the
/// story. Rich character choices/causal adaptations are a later stage.
enum QuickRpgMode { followBook, changeFate }

class QuickRpgAnchor {
  const QuickRpgAnchor({
    required this.chunkId,
    required this.chapterIndex,
    required this.startUtf16,
    required this.endUtf16,
    required this.quote,
  });
  final String chunkId;
  final int chapterIndex;
  final int startUtf16;
  final int endUtf16;
  final String quote;
}

class QuickRpgPlan {
  QuickRpgPlan._(this.index, this.mode, List<QuickRpgAnchor> anchors)
      : anchors = List.unmodifiable(anchors);
  final BookSourceIndex index;
  final QuickRpgMode mode;
  final List<QuickRpgAnchor> anchors;
  int get sourceScenes => anchors.length;
  int get endings => mode == QuickRpgMode.followBook ? 2 : anchors.length;
  bool get isCompleteRpgFromBook => false;
  bool get isCloudGenerated => false;
  bool get isSourceReviewed => false;
}

class QuickRpgCompilation {
  const QuickRpgCompilation({
    required this.archive,
    required this.sourceFingerprint,
    required this.bookworldId,
    required this.archiveSha256,
    required this.title,
    required this.sceneCount,
  });

  final Uint8List archive;
  final String sourceFingerprint;
  final String bookworldId;
  final String archiveSha256;
  final String title;
  final int sceneCount;
  bool get canDistributePublicly => false;
  bool get requiresCloud => false;
}

/// Quick RPG is a private *excerpt-based* playable starter, NOT a promise that
/// arbitrary novels have been understood or fully adapted. This keeps every
/// existing source/provenance/editorial/SQLite validation gate intact.
///
/// Confirmed assertions here state ONLY that these exact passages exist in
/// the imported book. They do not establish narrator reliability or NPC truth.
/// The user must inspect and explicitly accept ALL quoted passages and private
/// use before the compiler can mark them reviewed.
class QuickRpgBuilder {
  const QuickRpgBuilder._();

  static const maxAnchors = 8;
  static const quoteLimit = 140;
  static const maxTitle = 256;

  static bool _low(int code) => code >= 0xdc00 && code <= 0xdfff;
  static bool _high(int code) => code >= 0xd800 && code <= 0xdbff;

  static QuickRpgAnchor? _anchor(SourceChunk chunk, {int offset = 0}) {
    final text = chunk.text;
    if (offset < 0 || offset >= text.length) return null;
    final first = RegExp(r'\S').firstMatch(text.substring(offset));
    if (first == null) return null;
    final start = offset + first.start;
    var end = (start + quoteLimit).clamp(start + 1, text.length).toInt();
    if (end < text.length && _low(text.codeUnitAt(end))) end--;
    if (end > start && _high(text.codeUnitAt(end - 1))) end--;
    if (end - start < 28) return null;
    final quote = text.substring(start, end).trimRight();
    if (quote.runes.length < 22) return null;
    return QuickRpgAnchor(
      chunkId: chunk.id,
      chapterIndex: chunk.chapterIndex,
      startUtf16: chunk.startUtf16 + start,
      endUtf16: chunk.startUtf16 + start + quote.length,
      quote: quote,
    );
  }

  static QuickRpgPlan propose(BookSourceIndex index, {
    QuickRpgMode mode = QuickRpgMode.changeFate,
  }) {
    if (index.chapterCount == 0 ||
        index.indexedChapterCount != index.chapterCount ||
        index.totalTextUtf16 == 0 ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        index.title.trim().isEmpty ||
        index.title.length > maxTitle) {
      throw const FormatException(
          'Нужна полностью импортированная книга с корректным названием.');
    }
    final candidates = <QuickRpgAnchor>[
      for (final chunk in index.chunks)
        if (_anchor(chunk) case final value?) value,
    ];
    // Very short single-chunk books can still have two independent passages.
    if (candidates.length == 1) {
      final chunk = index.chunks.singleWhere(
          (value) => value.id == candidates.first.chunkId);
      final tailStart = chunk.text.length - quoteLimit;
      if (tailStart > quoteLimit + 15) {
        final tail = _anchor(chunk, offset: tailStart);
        if (tail != null &&
            tail.startUtf16 >= candidates.first.endUtf16 + 1) {
          candidates.add(tail);
        }
      }
    }
    if (candidates.length < 2) {
      throw const FormatException(
          'Слишком мало самостоятельных отрывков для игрового маршрута. '
          'Откройте расширенный редактор или выберите более длинную книгу.');
    }
    // Spread samples from beginning to end of the entire imported edition.
    // Never pretend that these samples cover every event of a long novel.
    final count = candidates.length < maxAnchors
        ? candidates.length : maxAnchors;
    final chosen = <QuickRpgAnchor>[];
    final selectedKeys = <String>{};
    for (var i = 0; i < count; i++) {
      final at = ((candidates.length - 1) * i / (count - 1)).round();
      final value = candidates[at];
      final key = '${value.chunkId}|${value.startUtf16}';
      if (selectedKeys.add(key)) chosen.add(value);
    }
    if (chosen.length < 2) {
      throw const FormatException('Не удалось получить две разные сцены.');
    }
    return QuickRpgPlan._(index, mode, chosen);
  }

  /// After a COMPLETE Z.ai book scan, prefer the exact passages at which
  /// the model suggested meaningful EVENTS rather than arbitrary text
  /// samples. This is still an excerpt-based, short starter, NOT a claim
  /// that the model understood all causality or verified world truth.
  ///
  /// Calling this does NOT mark AI candidate meanings as canon. The same
  /// visible quote confirmation, M2c editorial passage-provenance checks,
  /// private compiler and game state preflight remain mandatory.
  static QuickRpgPlan proposeFromEventOutline(
    BookSourceIndex index,
    ZaiWholeBookEventOutline outline, {
    QuickRpgMode mode = QuickRpgMode.changeFate,
  }) {
    if (outline.sourceFingerprint != index.sourceFingerprint ||
        outline.totalChapters != index.chapterCount ||
        !outline.analysisComplete ||
        outline.events.length < 2) {
      throw const FormatException(
          'Нужен завершённый анализ именно этой книги с '
          'как минимум двумя проверяемыми цитатами событий.');
    }
    final byId = {for (final chunk in index.chunks) chunk.id: chunk};
    final candidates = <QuickRpgAnchor>[];
    final seen = <String>{};
    for (final item in outline.events) {
      final chunk = byId[item.chunkId];
      if (chunk == null || chunk.chapterIndex != item.chapterIndex ||
          item.quote.length > 180 ||
          item.startUtf16 < chunk.startUtf16 ||
          item.startUtf16 + item.quote.length > chunk.endUtf16 ||
          chunk.text.substring(item.startUtf16 - chunk.startUtf16,
                  item.startUtf16 - chunk.startUtf16 + item.quote.length) !=
              item.quote) {
        throw const FormatException(
            'Событие ИИ не соответствует точному месту исходной книги.');
      }
      final key = '${item.chunkId}|${item.startUtf16}';
      if (!seen.add(key)) continue;
      candidates.add(QuickRpgAnchor(
        chunkId: chunk.id,
        chapterIndex: chunk.chapterIndex,
        startUtf16: item.startUtf16,
        endUtf16: item.startUtf16 + item.quote.length,
        quote: item.quote,
      ));
    }
    if (candidates.length < 2) {
      throw const FormatException(
          'В анализе слишком мало разных событий для игровой истории.');
    }
    final count = mathMin(candidates.length, maxAnchors);
    final selected = <QuickRpgAnchor>[];
    for (var i = 0; i < count; i++) {
      final at = ((candidates.length - 1) * i / (count - 1)).round();
      selected.add(candidates[at]);
    }
    return QuickRpgPlan._(index, mode, selected);
  }

  static int mathMin(int first, int second) =>
      first <= second ? first : second;

  static String _sceneText(QuickRpgAnchor anchor, int number) =>
      'Эпизод $number · глава ${anchor.chapterIndex + 1}\n\n'
      'Из книги:\n«${anchor.quote}»\n\n'
      'Выберите дальнейший путь. Это упрощённый игровой маршрут '
      'по подлинным отрывкам, а не полная литературная адаптация.';

  static String _branchText(QuickRpgAnchor anchor) =>
      'Вы решили отойти от событий книги после отрывка:\n'
      '«${anchor.quote}»\n\n'
      'Это отдельная игровая альтернатива, созданная приложением, '
      'а не продолжение, написанное автором. Путь здесь заканчивается.';

  /// This never installs, changes a campaign, or sends book text to the AI.
  /// A separate explicit user action in the UI installs/starts the world.
  static Future<QuickRpgCompilation> compile({
    required QuickRpgPlan plan,
    required bool allQuotesReviewedByUser,
    required bool privateUseConfirmed,
  }) async {
    if (!allQuotesReviewedByUser || !privateUseConfirmed) {
      throw const FormatException(
          'Сначала проверьте отрывки и подтвердите личное использование.');
    }
    final index = plan.index;
    final original = <SourceEvidence>[];
    for (final anchor in plan.anchors) {
      // Re-run independent exact offset/hash verification.
      original.add(SourceEvidence.propose(
        index,
        chunkId: anchor.chunkId,
        kind: EvidenceKind.fact,
        startUtf16: anchor.startUtf16,
        endUtf16: anchor.endUtf16,
      ));
      if (original.last.label != anchor.quote ||
          original.last.chapterIndex != anchor.chapterIndex) {
        throw const FormatException('Исходные цитаты изменились.');
      }
    }
    var evidence = SourceEvidenceGraph.empty(index).addAll(index, original);
    for (final quote in original) {
      evidence = evidence.review(index, quote.id, EvidenceStatus.confirmed);
    }
    final assertions = <SourceSemanticAssertion>[];
    for (var i = 0; i < original.length; i++) {
      assertions.add(SourceSemanticAssertion.propose(
        index, evidence,
        kind: SemanticAssertionKind.fact,
        evidenceIds: [original[i].id],
        subject: 'Текст книги',
        predicate: 'содержит отрывок',
        object: 'Эпизод ${i + 1}',
        voice: AssertionVoice.narratorCandidate,
        polarity: AssertionPolarity.affirmative,
        time: AssertionTime.textOrderOnly,
        uncertainty: 'Подтверждено только присутствие цитаты, '
            'не достоверность описанного события.',
      ));
    }
    final catalog = SourceSemanticCatalog.checked(index, evidence, assertions);
    var editorial = SemanticEditorialReviewSession.create(index, catalog);
    for (final assertion in assertions) {
      editorial = editorial.decide(
          catalog, assertion.id, SemanticEditorialVerdict.canonCandidate);
    }

    final scenes = <DraftScene>[];
    for (var i = 0; i < plan.anchors.length; i++) {
      final last = i == plan.anchors.length - 1;
      final alternate = plan.mode == QuickRpgMode.changeFate ||
          i == plan.anchors.length - 2;
      scenes.add(DraftScene(
        id: 'episode_${i + 1}',
        chapterIndex: plan.anchors[i].chapterIndex,
        text: _sceneText(plan.anchors[i], i + 1),
        origin: DraftSceneOrigin.sourcePassage,
        assertionIds: [assertions[i].id],
        terminal: last,
        choices: last ? const [] : [
          DraftChoice(
            id: 'continue_${i + 1}',
            label: 'Следовать книге',
            nextSceneId: 'episode_${i + 2}',
          ),
          if (alternate)
            DraftChoice(
              id: 'alternative_${i + 1}',
              label: plan.mode == QuickRpgMode.followBook
                  ? 'Завершить этот маршрут'
                  : 'Изменить судьбу',
              nextSceneId: 'alternative_end_${i + 1}',
            ),
        ],
      ));
      if (!last && alternate) {
        scenes.add(DraftScene(
          id: 'alternative_end_${i + 1}',
          chapterIndex: plan.anchors[i].chapterIndex,
          text: plan.mode == QuickRpgMode.followBook
              ? 'Вы завершили ознакомительный маршрут раньше конца '
                  'книги. Исходный текст остался неизменным.'
              : _branchText(plan.anchors[i]),
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [],
          terminal: true,
          choices: const [],
        ));
      }
    }
    final draft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      entrySceneId: 'episode_1',
      rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [],
      scenes: scenes,
    );
    // The existing M2c semantic, causal, source-offset, copyright and
    // independent ZIP/SQLite checks remain mandatory.
    final archive = await compileReviewedPrivateBookworldInWorker(
        index, evidence, catalog, editorial, draft);
    final inspected = const PrivateBookworldImporter().inspect(archive);
    if (inspected.sourceFingerprint != index.sourceFingerprint ||
        inspected.canDistributePublicly || inspected.requiresNetwork ||
        inspected.blueprint.scenes.length != scenes.length) {
      throw const FormatException('Проверка частного игрового мира не пройдена.');
    }
    return QuickRpgCompilation(
      archive: Uint8List.fromList(archive),
      sourceFingerprint: inspected.sourceFingerprint,
      bookworldId: inspected.bookworldId,
      archiveSha256: inspected.archiveSha256,
      title: inspected.blueprint.title,
      sceneCount: scenes.length,
    );
  }
}
