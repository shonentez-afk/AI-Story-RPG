import 'dart:isolate';

import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'world_library_gateway.dart';

enum PrivatePlayability { notReady, privatePlayable }

/// This status describes only a *verified installed short private adaptation*.
/// It does not measure coverage of a novel, prove publication rights, or
/// activate AI. A source index or an editable draft can never pass this gate.
class PrivateGameReadiness {
  const PrivateGameReadiness({
    required this.status,
    required this.explanation,
    this.world,
  });

  final PrivatePlayability status;
  final String explanation;
  final WorldLibraryItem? world;

  bool get canStartPrivateGame =>
      status == PrivatePlayability.privatePlayable && world != null;
  bool get canSharePublicly => false;
  bool get hasAiAuthoring => false;
}

/// Offline, read-only and fail-closed: inspect actual stored ZIP/SQLite bytes,
/// not just the presence of a library row. No campaigns or saves are changed.
class PrivateGameReadinessVerifier {
  const PrivateGameReadinessVerifier._();

  static const maxCandidatePackages = 32;
  static final RegExp _fingerprint = RegExp(r'^[a-f0-9]{64}$');

  static Future<PrivateGameReadiness> assess(
      BookSourceIndex index, WorldLibraryGateway gateway) async {
    if (!_fingerprint.hasMatch(index.sourceFingerprint)) {
      throw const FormatException('Некорректный отпечаток исходной книги');
    }
    if (index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16) {
      return const PrivateGameReadiness(
        status: PrivatePlayability.notReady,
        explanation: 'Не весь исходный текст проиндексирован.',
      );
    }

    // This prefix is created by PrivateClassicScenarioTranslator, not inferred
    // from a book title. Full SHA matching is still required below.
    final prefix = 'book_' + index.sourceFingerprint.substring(0, 12) + '_';
    final matching = (await gateway.worlds())
        .where((world) => world.bookworldId.startsWith(prefix)).toList();
    if (matching.length > maxCandidatePackages) {
      return const PrivateGameReadiness(
        status: PrivatePlayability.notReady,
        explanation: 'Найдено слишком много вариантов этой книги. '
            'Выберите нужный мир в библиотеке и проверьте его вручную.',
      );
    }

    for (final entry in matching) {
      try {
        final bytes = await gateway.exportWorld(entry.archiveHash);
        // SQLite/ZIP verification must not freeze the preparation UI.
        final identity = await Isolate.run(() {
          final inspected = const PrivateBookworldImporter().inspect(bytes);
          return <String>[
            inspected.sourceFingerprint,
            inspected.bookworldId,
            inspected.archiveSha256,
          ];
        });
        if (identity[0] == index.sourceFingerprint &&
            identity[1] == entry.bookworldId &&
            identity[2] == entry.archiveHash) {
          return PrivateGameReadiness(
            status: PrivatePlayability.privatePlayable,
            explanation: 'Проверена установленная короткая личная RPG '
                'по этой редакции книги. Это не автоматическая адаптация '
                'всего произведения и не разрешение на публикацию.',
            world: entry,
          );
        }
      } catch (_) {
        // Missing, corrupt or incompatible archives cannot unlock play.
        // Another independently installed candidate may still be valid.
      }
    }
    return const PrivateGameReadiness(
      status: PrivatePlayability.notReady,
      explanation: 'Проверенной личной RPG для этой книги пока нет. '
          'Подтвердите исходные события и соберите сценарий в редакторе.',
    );
  }
}
