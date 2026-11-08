import 'dart:convert';
import 'dart:io';

import 'package:story_authoring/story_authoring.dart';

/// Source + verified scenario -> native rich-v3 BookWorld, offline.
/// DOES NOT autonomously invent/approve literary meaning or grant copyright.
Future<void> main(List<String> args) async {
  const engine = BookAuthoringEngine();
  try {
    if (args.length == 2 && args[0] == 'inspect-source') {
      final source = engine.parseAndIndex(
          args[1], await File(args[1]).readAsBytes());
      stdout.writeln(jsonEncode(source.status));
    } else if ((args.length == 2 || args.length == 4) &&
        args[0] == 'scan-source' &&
        (args.length == 2 || args[2] == '--checkpoint')) {
      final source = engine.parseAndIndex(
          args[1], await File(args[1]).readAsBytes());
      final save = args.length == 4 ? File(args[3]) : null;
      OfflineScanCheckpoint? restored;
      if (save != null && await save.exists()) {
        final raw = jsonDecode(await save.readAsString());
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Неверный локальный checkpoint');
        }
        restored = OfflineScanCheckpoint.fromJson(source.index, raw);
      }
      final report = await const OfflineBookAnalyzer().scan(
        source, resume: restored,
        onCheckpoint: save == null ? null : (checkpoint) {
          // Atomically replace the file only with source-validated snapshots.
          // Contains source excerpts; store in a PRIVATE folder, never CI.
          final partial = File(save.path + '.pending');
          partial.writeAsStringSync(jsonEncode(checkpoint.toJson()),
              flush: true);
          partial.renameSync(save.path);
        },
      );
      stdout.writeln(jsonEncode(report.summary));
    } else if (args.length == 5 && args[0] == 'review-plan') {
      // The event outline is an UNTRUSTED model/editor result. It must name
      // every source chunk and contain only literal, source-bound quotes.
      final source = engine.parseAndIndex(
          args[1], await File(args[1]).readAsBytes());
      final candidateRaw = jsonDecode(await File(args[2]).readAsString());
      final responseRaw = jsonDecode(await File(args[3]).readAsString());
      if (candidateRaw is! Map<String, dynamic> ||
          responseRaw is! Map<String, dynamic>) {
        throw const FormatException('Нужны два JSON-объекта без команд модели');
      }
      final outline = SourceLockedEventOutline.fromJson(
          source.index, candidateRaw);
      final book = NarrativeBookModel.fromExisting(
          index: source.index, outline: outline);
      final selected = book.events.length <= 8
          ? book.events : [
              for (var i = 0; i < 8; i++)
                book.events[((book.events.length - 1) * i / 7).round()],
            ];
      final result = StoryProposalValidator.validate(
        book: book, allowedEvents: selected, proposedJson: responseRaw,
      );
      final artifact = <String, Object?>{
        'format': 'ai_story_untrusted_story_plan_review_v1',
        'source_fingerprint': source.index.sourceFingerprint,
        'model_provenance': 'not_attested',
        'is_literary_canon': false,
        'is_playable': false,
        'source_events': outline.events.length,
        'chapters_with_event_candidates':
            outline.chaptersWithEventProposals,
        'total_chapters': outline.totalChapters,
      };
      if (result.foundCandidate) {
        final quality = StoryPlanQualityGate.assess(
            book: book, preview: result);
        artifact['status'] = 'DRAFT_NEEDS_EDITORIAL_REVIEW';
        artifact['formal_readiness'] = quality.toReadinessJson();
        artifact['story_plan'] = jsonDecode(quality.plan.encode());
      } else {
        artifact['status'] = 'NO_APPLICABLE_PROPOSAL';
      }
      if (!args[4].toLowerCase().endsWith('.json')) {
        throw const FormatException('Промежуточный отчёт должен быть .json');
      }
      // Never overwrite the destination on a validation failure.
      final output = File(args[4]);
      final partial = File(output.path + '.pending');
      await partial.writeAsString(jsonEncode(artifact), flush: true);
      await partial.rename(output.path);
      stdout.writeln(jsonEncode({
        'status': artifact['status'],
        'source_fingerprint': source.index.sourceFingerprint,
        'events': outline.events.length,
        'is_playable': false,
      }));
    } else if (args.length == 4 && args[0] == 'build-draft') {
      // This portable bundle is exported from the SAME user-reviewed source,
      // semantic and NPC editors. It is not an LLM-generated shortcut.
      final source = engine.parseAndIndex(
          args[1], await File(args[1]).readAsBytes());
      final reviewFile = File(args[2]);
      if (await reviewFile.length() > 40 * 1024 * 1024) {
        throw const FormatException('Редакторские записи превышают лимит');
      }
      final raw = jsonDecode(await reviewFile.readAsString());
      if (raw is! Map<String, dynamic> ||
          !args[3].toLowerCase().endsWith('.bworld')) {
        throw const FormatException(
            'Нужен JSON проверок и выходной файл .bworld');
      }
      final archive = await const PortableReviewedDraftCompiler().build(
          source: source, review: raw);
      final inspected = engine.inspectPrivateWorld(archive);
      final out = File(args[3]);
      final partial = File(out.path + '.pending');
      await partial.writeAsBytes(archive, flush: true);
      await partial.rename(out.path);
      stdout.writeln(jsonEncode({
        'result': 'PRIVATE_RICH_V3_VERIFIED',
        'source_fingerprint': inspected.sourceFingerprint,
        'archive_sha256': inspected.archiveSha256,
        'scenes': inspected.blueprint.scenes.length,
        'requires_network': false,
        'can_distribute_publicly': false,
      }));
    } else if (args.length == 4 &&
        (args[0] == 'build-reviewed' || args[0] == 'build-extended')) {
      final source = engine.parseAndIndex(
          args[1], await File(args[1]).readAsBytes());
      final raw = jsonDecode(await File(args[2]).readAsString());
      if (raw is! Map<String, dynamic> ||
          raw.keys.toSet().difference({'blueprint', 'provenance'}).isNotEmpty ||
          raw.length != 2 ||
          raw['blueprint'] is! Map<String, dynamic> ||
          raw['provenance'] is! Map<String, dynamic>) {
        throw const FormatException(
            'Нужен подтверждённый blueprint и provenance JSON');
      }
      if (!args[3].toLowerCase().endsWith('.bworld')) {
        throw const FormatException('Результат должен иметь расширение .bworld');
      }
      final archive = engine.buildReviewedPrivateWorld(
        source: source,
        blueprint: Map<String, dynamic>.from(raw['blueprint'] as Map),
        provenance: Map<String, dynamic>.from(raw['provenance'] as Map),
        expanded: args[0] == 'build-extended',
      );
      final verified = engine.inspectPrivateWorld(archive);
      // Never touch the output before all source+runtime validation passes.
      await File(args[3]).writeAsBytes(archive, flush: true);
      stdout.writeln(jsonEncode({
        'result': verified.formatVersion == 4
            ? 'PRIVATE_EXTENDED_V4_VERIFIED' : 'PRIVATE_RICH_V3_VERIFIED',
        'format_version': verified.formatVersion,
        'archive_sha256': verified.archiveSha256,
        'source_fingerprint': verified.sourceFingerprint,
        'scenes': verified.blueprint.scenes.length,
        'requires_network': false,
        'can_distribute_publicly': false,
      }));
    } else if (args.length == 2 && args[0] == 'verify-world') {
      final verified = engine.inspectPrivateWorld(
          await File(args[1]).readAsBytes());
      stdout.writeln(jsonEncode({
        'result': 'PRIVATE_RICH_V3_VERIFIED',
        'archive_sha256': verified.archiveSha256,
        'source_fingerprint': verified.sourceFingerprint,
        'scenes': verified.blueprint.scenes.length,
        'requires_network': verified.requiresNetwork,
        'can_distribute_publicly': verified.canDistributePublicly,
      }));
    } else {
      stderr.writeln('Команды:');
      stderr.writeln('  dart run bin/author_book.dart inspect-source source.fb2');
      stderr.writeln('  dart run bin/author_book.dart scan-source source.fb2 [--checkpoint private/scan.json]');
      stderr.writeln('  dart run bin/author_book.dart review-plan book.fb2 events.json model_reply.json plan_review.json');
      stderr.writeln('  dart run bin/author_book.dart build-reviewed source.fb2 review.json game.bworld');
      stderr.writeln('  dart run bin/author_book.dart build-extended source.fb2 reviewed_v4.json game.bworld');
      stderr.writeln('  dart run bin/author_book.dart build-draft source.fb2 reviewed_checkpoints.json game.bworld');
      stderr.writeln('  dart run bin/author_book.dart verify-world game.bworld');
      exitCode = 64;
    }
  } on FormatException catch (error) {
    stderr.writeln('Ошибка проверки: ' + error.message);
    exitCode = 2;
  } on StateError catch (error) {
    stderr.writeln('Анализ прерван: ' + error.message);
    exitCode = 3;
  } on FileSystemException catch (error) {
    stderr.writeln('Ошибка файла: ' + error.message);
    exitCode = 74;
  }
}
