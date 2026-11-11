import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_analysis.dart';
import 'book_source_index.dart';

/// M2b4a: strictly untrusted semantic proposals. No model, network, runtime,
/// save store or BookWorld dependency may be introduced through this contract.
enum SemanticCategory { character, alias, location, event, fact, state, dependency }
enum SemanticProviderMode { offlineRules, localModel, cloud }

String _semanticHash(String value) =>
    sha256.convert(utf8.encode(value)).toString();

class SemanticExtractionRequest {
  SemanticExtractionRequest({
    required this.index,
    required List<SourceChunk> chunks,
    required Set<SemanticCategory> categories,
    this.languageHint = 'und',
  }) : chunks = List.unmodifiable(chunks),
       categories = Set.unmodifiable(categories) {
    validate();
  }

  static const maxChunksPerRequest = 12;
  static const maxInputUtf8Bytes = 64 * 1024;

  final BookSourceIndex index;
  final List<SourceChunk> chunks;
  final Set<SemanticCategory> categories;
  final String languageHint;

  void validate() {
    if (chunks.isEmpty || chunks.length > maxChunksPerRequest ||
        categories.isEmpty || languageHint.isEmpty ||
        languageHint.length > 32 || index.sourceFingerprint.length != 64) {
      throw const FormatException('Недопустимый запрос семантического анализа');
    }
    final originals = {for (final c in index.chunks) c.id: c};
    final ids = <String>{};
    var bytes = 0;
    for (final c in chunks) {
      final original = originals[c.id];
      if (!ids.add(c.id) || original == null ||
          original.chapterIndex != c.chapterIndex ||
          original.chapterId != c.chapterId ||
          original.blockIndex != c.blockIndex ||
          original.startUtf16 != c.startUtf16 ||
          original.endUtf16 != c.endUtf16 ||
          original.text != c.text ||
          original.sha256Text != c.sha256Text ||
          _semanticHash(c.text) != c.sha256Text) {
        throw const FormatException('Фрагмент не совпадает с исходным индексом');
      }
      bytes += utf8.encode(c.text).length;
      if (bytes > maxInputUtf8Bytes) {
        throw const FormatException('Превышен предел исходного текста');
      }
    }
  }
}

/// Even a correctly quoted fragment is a PROPOSAL, never an accepted fact.
class SemanticCandidate {
  const SemanticCandidate({
    required this.id,
    required this.category,
    required this.sourceFingerprint,
    required this.chunkId,
    required this.startUtf16,
    required this.endUtf16,
    required this.quote,
    required this.quoteSha256,
    required this.label,
    required this.uncertainty,
    this.status = 'INFERRED',
    this.spoilerGate = 'CHAPTER',
    required this.visibleAfterChapter,
  });

  final String id;
  final SemanticCategory category;
  final String sourceFingerprint;
  final String chunkId;
  final int startUtf16;
  final int endUtf16;
  final String quote;
  final String quoteSha256;
  final String label;
  final String uncertainty;
  final String status;
  final String spoilerGate;
  final int visibleAfterChapter;

  static String identity(String fingerprint, String chunkId,
      SemanticCategory category, int start, int end,
      String quoteHash, String label) =>
      _semanticHash(fingerprint + '|' + chunkId + '|' + category.name +
          '|' + start.toString() + '|' + end.toString() +
          '|' + quoteHash + '|' + label).substring(0, 32);

  factory SemanticCandidate.propose(BookSourceIndex index, SourceChunk chunk, {
    required SemanticCategory category,
    required int startUtf16,
    required int endUtf16,
    required String label,
    required String uncertainty,
  }) {
    if (startUtf16 < chunk.startUtf16 || endUtf16 > chunk.endUtf16 ||
        startUtf16 >= endUtf16) {
      throw const FormatException('Недопустимый диапазон цитаты');
    }
    final quote = chunk.text.substring(
        startUtf16 - chunk.startUtf16, endUtf16 - chunk.startUtf16);
    final hash = _semanticHash(quote);
    return SemanticCandidate(
      id: identity(index.sourceFingerprint, chunk.id, category,
          startUtf16, endUtf16, hash, label),
      category: category,
      sourceFingerprint: index.sourceFingerprint,
      chunkId: chunk.id,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      quote: quote,
      quoteSha256: hash,
      label: label,
      uncertainty: uncertainty,
      visibleAfterChapter: chunk.chapterIndex,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'category': category.name.toUpperCase(),
    'source_fingerprint': sourceFingerprint,
    'chunk_id': chunkId,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'quote': quote,
    'quote_sha256': quoteSha256,
    'label': label,
    'uncertainty': uncertainty,
    'status': status,
    'spoiler_gate': spoilerGate,
    'visible_after_chapter': visibleAfterChapter,
  };

  static const _fields = {
    'id', 'category', 'source_fingerprint', 'chunk_id',
    'start_utf16', 'end_utf16', 'quote', 'quote_sha256', 'label',
    'uncertainty', 'status', 'spoiler_gate', 'visible_after_chapter',
  };

  factory SemanticCandidate.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference(_fields).isNotEmpty ||
        json.length != _fields.length) {
      throw const FormatException('Неизвестные поля semantic-кандидата');
    }
    try {
      return SemanticCandidate(
        id: json['id'] as String,
        category: SemanticCategory.values.byName(
            (json['category'] as String).toLowerCase()),
        sourceFingerprint: json['source_fingerprint'] as String,
        chunkId: json['chunk_id'] as String,
        startUtf16: json['start_utf16'] as int,
        endUtf16: json['end_utf16'] as int,
        quote: json['quote'] as String,
        quoteSha256: json['quote_sha256'] as String,
        label: json['label'] as String,
        uncertainty: json['uncertainty'] as String,
        status: json['status'] as String,
        spoilerGate: json['spoiler_gate'] as String,
        visibleAfterChapter: json['visible_after_chapter'] as int,
      );
    } catch (_) {
      throw const FormatException('Неизвестный тип semantic-кандидата');
    }
  }
}

class SemanticCandidateBatch {
  SemanticCandidateBatch({
    required this.providerId,
    required this.providerVersion,
    required this.sourceFingerprint,
    required List<String> chunkIds,
    required List<SemanticCandidate> candidates,
    this.gameplayCoverage = 0,
    this.canPublishBookworld = false,
  }) : chunkIds = List.unmodifiable(chunkIds),
       candidates = List.unmodifiable(candidates);

  final String providerId;
  final String providerVersion;
  final String sourceFingerprint;
  final List<String> chunkIds;
  final List<SemanticCandidate> candidates;
  final double gameplayCoverage;
  final bool canPublishBookworld;

  Map<String, Object> toJson() => {
    'provider_id': providerId,
    'provider_version': providerVersion,
    'source_fingerprint': sourceFingerprint,
    'chunk_ids': chunkIds,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    'gameplay_coverage': gameplayCoverage,
    'can_publish_bookworld': canPublishBookworld,
  };
}

abstract class SourceSemanticProvider {
  String get id;
  String get version;
  SemanticProviderMode get mode;
  bool get isAvailable;

  Future<SemanticCandidateBatch> extract(SemanticExtractionRequest request);
}

/// The sole active provider in M2b4a. Reuses the M2b1 deterministic scanner.
class OfflineRuleProvider implements SourceSemanticProvider {
  const OfflineRuleProvider();

  @override
  String get id => 'offline-rules';
  @override
  String get version => 'm2b4a-v1';
  @override
  SemanticProviderMode get mode => SemanticProviderMode.offlineRules;
  @override
  bool get isAvailable => true;

  @override
  Future<SemanticCandidateBatch> extract(
      SemanticExtractionRequest request) async {
    request.validate();
    final found = <SemanticCandidate>[];
    for (final chunk in request.chunks) {
      for (final mention in SourceAnalysisSession.scanChunk(chunk)) {
        final category = switch (mention.kind) {
          'CHARACTER_NAME' => SemanticCategory.character,
          'LOCATION_NAME' => SemanticCategory.location,
          _ => throw const FormatException('Недопустимый тип локального шаблона'),
        };
        if (!request.categories.contains(category)) continue;
        found.add(SemanticCandidate.propose(
          request.index, chunk,
          category: category,
          startUtf16: mention.startUtf16,
          endUtf16: mention.endUtf16,
          label: mention.label,
          uncertainty: 'Шаблонное упоминание; личность и факт не подтверждены',
        ));
      }
    }
    return SemanticCandidateBatch(
      providerId: id,
      providerVersion: version,
      sourceFingerprint: request.index.sourceFingerprint,
      chunkIds: [for (final c in request.chunks) c.id],
      candidates: found,
    );
  }
}

/// Explicitly unavailable: no hidden download, fake model or network fallback.
class UnconfiguredLocalModelProvider implements SourceSemanticProvider {
  const UnconfiguredLocalModelProvider();

  @override
  String get id => 'local-model-unconfigured';
  @override
  String get version => 'not-installed';
  @override
  SemanticProviderMode get mode => SemanticProviderMode.localModel;
  @override
  bool get isAvailable => false;

  @override
  Future<SemanticCandidateBatch> extract(
      SemanticExtractionRequest request) async =>
      throw StateError('Локальная модель не установлена');
}

class DisabledCloudSemanticProvider implements SourceSemanticProvider {
  const DisabledCloudSemanticProvider();

  @override
  String get id => 'cloud-disabled';
  @override
  String get version => 'not-configured';
  @override
  SemanticProviderMode get mode => SemanticProviderMode.cloud;
  @override
  bool get isAvailable => false;

  @override
  Future<SemanticCandidateBatch> extract(
      SemanticExtractionRequest request) async =>
      throw StateError('Облачный анализ не подключён');
}

/// M2b4a does not expose cloud opt-in yet: deny *all* cloud implementations,
/// including injected test providers, before their extract() could run.
class SemanticProviderGate {
  const SemanticProviderGate._();

  static Future<SemanticCandidateBatch> run(
      SourceSemanticProvider provider, SemanticExtractionRequest request) async {
    request.validate();
    if (provider.mode == SemanticProviderMode.cloud) {
      throw StateError('Передача текста в облако недоступна до отдельного согласия');
    }
    if (provider.mode != SemanticProviderMode.offlineRules ||
        !provider.isAvailable) {
      throw StateError('Подключённая локальная модель отсутствует');
    }
    final response = await provider.extract(request);
    SemanticCandidateValidator.validateBatch(
        request, response, providerId: provider.id,
        providerVersion: provider.version);
    return response;
  }
}

class SemanticCandidateValidator {
  const SemanticCandidateValidator._();

  static const maxCandidatesPerBatch = 360;
  static const maxResponseUtf8Bytes = 256 * 1024;

  static bool _lowSurrogate(int code) => code >= 0xDC00 && code <= 0xDFFF;

  static void validateCandidate(
      BookSourceIndex index, SemanticCandidate item, {
      required Set<String> allowedChunkIds,
      required Set<SemanticCategory> categories,
      SourceChunk? sourceChunk,
  }) {
    final chunk = sourceChunk ??
        ({for (final c in index.chunks) c.id: c})[item.chunkId];
    if (chunk == null || chunk.id != item.chunkId ||
        !allowedChunkIds.contains(item.chunkId) ||
        item.sourceFingerprint != index.sourceFingerprint ||
        !categories.contains(item.category) ||
        item.status != 'INFERRED' || item.spoilerGate != 'CHAPTER' ||
        item.visibleAfterChapter != chunk.chapterIndex ||
        item.startUtf16 < chunk.startUtf16 ||
        item.endUtf16 > chunk.endUtf16 ||
        item.endUtf16 <= item.startUtf16 ||
        item.endUtf16 - item.startUtf16 > 180 ||
        item.label.trim().isEmpty || item.label.length > 180 ||
        item.uncertainty.trim().isEmpty || item.uncertainty.length > 240) {
      throw const FormatException('Неподтверждённое или небезопасное утверждение');
    }
    final start = item.startUtf16 - chunk.startUtf16;
    final end = item.endUtf16 - chunk.startUtf16;
    if ((start > 0 && _lowSurrogate(chunk.text.codeUnitAt(start))) ||
        (end < chunk.text.length && _lowSurrogate(chunk.text.codeUnitAt(end)))) {
      throw const FormatException('Цитата разрывает символ Unicode');
    }
    final actualQuote = chunk.text.substring(start, end);
    if (actualQuote.trim().isEmpty || item.quote != actualQuote ||
        item.quoteSha256 != _semanticHash(actualQuote) ||
        item.id != SemanticCandidate.identity(
            index.sourceFingerprint, chunk.id, item.category,
            item.startUtf16, item.endUtf16,
            item.quoteSha256, item.label)) {
      throw const FormatException('Цитата не соответствует исходному тексту');
    }
  }

  static void validateBatch(
      SemanticExtractionRequest request, SemanticCandidateBatch batch, {
      required String providerId,
      required String providerVersion,
  }) {
    request.validate();
    if (batch.providerId != providerId ||
        batch.providerVersion != providerVersion ||
        batch.sourceFingerprint != request.index.sourceFingerprint ||
        batch.gameplayCoverage != 0 || batch.canPublishBookworld ||
        batch.chunkIds.length != request.chunks.length ||
        batch.candidates.length > maxCandidatesPerBatch ||
        utf8.encode(jsonEncode(batch.toJson())).length > maxResponseUtf8Bytes) {
      throw const FormatException('Провайдер вернул небезопасный ответ');
    }
    for (var i = 0; i < batch.chunkIds.length; i++) {
      if (batch.chunkIds[i] != request.chunks[i].id) {
        throw const FormatException('Неверный набор фрагментов источника');
      }
    }
    final ids = <String>{};
    final allowed = batch.chunkIds.toSet();
    final sourceChunks = {for (final c in request.chunks) c.id: c};
    for (final item in batch.candidates) {
      if (!ids.add(item.id)) {
        throw const FormatException('Дублирующийся semantic-кандидат');
      }
      validateCandidate(request.index, item,
          allowedChunkIds: allowed, categories: request.categories,
          sourceChunk: sourceChunks[item.chunkId]);
    }
  }
}
