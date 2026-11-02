import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';

enum PreparationGateStatus { complete, needsReview, blocked }

class PreparationGate {
  const PreparationGate(this.id, this.label, this.status, this.explanation);
  final String id;
  final String label;
  final PreparationGateStatus status;
  final String explanation;
}

/// Read-only pre-AI readiness. No network, game saves, import/export or
/// asynchronous reprocessing. The UI can explain exactly WHY creation is
/// unavailable without claiming that text indexing equals gameplay coverage.
class PreparationReadinessReport {
  PreparationReadinessReport._(this.gates, this.indexedChapters,
      this.totalChapters, this.reviewedAssertions, this.totalAssertions);

  final List<PreparationGate> gates;
  final int indexedChapters;
  final int totalChapters;
  final int reviewedAssertions;
  final int totalAssertions;

  int get completedStages => gates.where(
      (gate) => gate.status == PreparationGateStatus.complete).length;
  bool get canStartPlayableBook => false;
  bool get mayAutomaticallySendBookToCloud => false;
  double get gameplayCoverage => 0;

  factory PreparationReadinessReport.assess(
    BookSourceIndex index, {
    SourceAnalysisSession? mentions,
    StoryEvidenceReviewSession? narrative,
    SourceEvidenceGraph? evidence,
    SourceSemanticCatalog? catalog,
    SemanticEditorialReviewSession? editorial,
    IntermediateStoryBlueprint? draft,
  }) {
    if (mentions != null && mentions.sourceFingerprint != index.sourceFingerprint ||
        narrative != null &&
            narrative.sourceFingerprint != index.sourceFingerprint ||
        evidence != null &&
            evidence.sourceFingerprint != index.sourceFingerprint ||
        catalog != null &&
            catalog.sourceFingerprint != index.sourceFingerprint ||
        editorial != null &&
            editorial.sourceFingerprint != index.sourceFingerprint ||
        draft != null &&
            draft.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Нельзя объединять разные редакции книги');
    }
    final gates = <PreparationGate>[];
    void add(String id, String label, PreparationGateStatus status,
        String explanation) => gates.add(
            PreparationGate(id, label, status, explanation));

    final indexComplete = index.indexedChapterCount == index.chapterCount &&
        index.textIndexCoverage == 1;
    add('source', 'Текст и границы глав', indexComplete
        ? PreparationGateStatus.complete : PreparationGateStatus.blocked,
        indexComplete ? 'Текст проиндексирован, но не интерпретирован'
            : 'Есть главы без извлекаемого текста');

    final mentionsDone = mentions != null &&
        mentions.pendingCount == 0 && mentions.failedCount == 0;
    add('mentions', 'Упоминания имён и мест',
        mentionsDone ? PreparationGateStatus.complete
            : PreparationGateStatus.needsReview,
        mentionsDone ? 'Поиск завершён; имена ещё не равны NPC'
            : 'Нужно завершить локальный поиск или обработать ошибки');

    final evidenceDone = narrative != null &&
        narrative.scannedChunks == index.chunks.length;
    add('citations', 'Цитаты событий и фактов',
        evidenceDone ? PreparationGateStatus.complete
            : PreparationGateStatus.needsReview,
        evidenceDone ? 'Найденные цитаты не доказывают истину событий'
            : 'Не закончено выделение событий и проверяемых цитат');

    final hasCatalog = catalog != null && catalog.assertions.isNotEmpty;
    add('semantics', 'Смысловые утверждения',
        hasCatalog ? PreparationGateStatus.needsReview
            : PreparationGateStatus.blocked,
        hasCatalog ? 'Есть локальные кандидаты; нет полной смысловой модели'
            : 'Нет структурированных проверяемых утверждений');

    final reviewed = editorial?.reviewedCount ?? 0;
    final allReviewed = catalog != null &&
        catalog.assertions.isNotEmpty && editorial != null &&
        editorial.matches(index, catalog) &&
        reviewed == catalog.assertions.length;
    add('editorial', 'Редакторская проверка канона',
        allReviewed ? PreparationGateStatus.needsReview
            : PreparationGateStatus.blocked,
        allReviewed ? 'Решения записаны; требуется проверка идентичности и времени'
            : 'Не проверены все события, слухи и связи');

    if (draft == null) {
      add('causality', 'Сцены и альтернативы',
          PreparationGateStatus.blocked,
          'Нет чернового сценария с проверенными развилками');
    } else if (evidence == null || catalog == null) {
      add('causality', 'Сцены и альтернативы',
          PreparationGateStatus.blocked,
          'Нельзя проверить сценарий без источника и каталога');
    } else {
      try {
        final result = draft.validate(index, evidence, catalog);
        add('causality', 'Сцены и альтернативы',
            result.isCausallyComplete ? PreparationGateStatus.complete
                : PreparationGateStatus.blocked,
            result.isCausallyComplete
                ? 'Причинные переходы и окончания проверены; это ещё не игра'
                : 'Не завершена проверка сценарных переходов');
      } on FormatException {
        add('causality', 'Сцены и альтернативы',
            PreparationGateStatus.blocked,
            'В сценарии ошибка причинности, источника или спойлеров');
      }
    }

    final rights = draft?.rights ?? PreparationRights.unknown;
    add('rights', 'Права на адаптацию',
        rights == PreparationRights.unknown
            ? PreparationGateStatus.blocked
            : PreparationGateStatus.needsReview,
        rights == PreparationRights.unknown
            ? 'Требуется самостоятельное указание прав'
            : 'Личное использование не даёт права на публичное распространение');

    add('compiler', 'Игровой .bworld из книги',
        PreparationGateStatus.blocked,
        'Компилятор есть, но нужен проверенный сценарий и успешная сборка пакета');

    add('ai', 'Подключённый ИИ',
        PreparationGateStatus.blocked,
        'Модель не настроена; отправка исходного текста запрещена');

    return PreparationReadinessReport._(
      List.unmodifiable(gates),
      index.indexedChapterCount,
      index.chapterCount,
      reviewed,
      catalog?.assertions.length ?? 0,
    );
  }
}
