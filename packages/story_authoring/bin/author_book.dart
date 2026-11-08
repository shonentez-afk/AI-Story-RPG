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
    } else if (args.length == 4 && args[0] == 'build-reviewed') {
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
      );
      final verified = engine.inspectPrivateWorld(archive);
      // Never touch the output before all source+runtime validation passes.
      await File(args[3]).writeAsBytes(archive, flush: true);
      stdout.writeln(jsonEncode({
        'result': 'PRIVATE_RICH_V3_VERIFIED',
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
      stderr.writeln('  dart run bin/author_book.dart build-reviewed source.fb2 review.json game.bworld');
      stderr.writeln('  dart run bin/author_book.dart verify-world game.bworld');
      exitCode = 64;
    }
  } on FormatException catch (error) {
    stderr.writeln('Ошибка проверки: ' + error.message);
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Ошибка файла: ' + error.message);
    exitCode = 74;
  }
}
