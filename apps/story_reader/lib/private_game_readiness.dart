import 'package:bookworld_format/bookworld_format.dart';

import 'book_source_index.dart';
import 'world_library_gateway.dart';

enum PrivatePlayability { notReady, privatePlayable }

/// Stronger than a guessed percentage: this is about a real, installed
/// private package, independently reopened and bound to this exact source.
/// Does not claim the whole novel is represented or authorize publication.
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

/// Read-only, fail-closed, offline inspection. Does not create a campaign,
/// change a book, save a token or send text anywhere.
class PrivateGameReadinessVerifier {
  const PrivateGameReadinessVerifier._();

  static Future<PrivateGameReadiness> assess(
      BookSourceIndex index, WorldLibraryGateway gateway) async {
    if (index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16) {
      return const PrivateGameReadiness(
        status: PrivatePlayability.notReady,
        explanation: 'Не весь текст исходной книги проиндексирован.',
      );
    }

    if (!RegExp(r'^[a-f0-9]{64}
    // Short-circuit unrelated worlds to avoid loading and verifying every
    // stored archive on a large shared library. Private compilation uses
    // book_<source fingerprint prefix>_<draft hash prefix>.
    final prefix = 'book_${index.sourceFingerprint.substring(0, 12)}_';
    var checked = 0;
    for (final entry in worlds) {
      if (!entry.bookworldId.startsWith(prefix)) continue;
      if (++checked > 32) {
        return const PrivateGameReadiness(
          status: PrivatePlayability.notReady,
          explanation: 'Слишком много вариантов этой книги: '
              'проверьте нужный игровой пакет вручную.',
        );
      }
      try {
        final bytes = await gateway.exportWorld(entry.archiveHash);
        final verified = const PrivateBookworldImporter().inspect(bytes);
        if (verified.sourceFingerprint == index.sourceFingerprint &&
            verified.bookworldId == entry.bookworldId &&
            verified.archiveSha256 == entry.archiveHash) {
          return PrivateGameReadiness(
            status: PrivatePlayability.privatePlayable,
            explanation: 'Проверена короткая личная адаптация. '
                'Результат можно играть офлайн, но он не охватывает '
                'автоматически все события книги и не подлежит публикации.',
            world: entry,
          );
        }
      } on FormatException {
        // A corrupt or mismatched package must never be advertised as playable.
      } on StateError {
        // A package may have been deleted since the catalog was enumerated.
      }
    }
    return const PrivateGameReadiness(
      status: PrivatePlayability.notReady,
      explanation: 'Пока нет проверенного игрового пакета по этой книге. '
          'Подготовьте короткую личную адаптацию в редакторе.',
    );
  }
}
).hasMatch(index.sourceFingerprint)) {
      throw const FormatException('Некорректный отпечаток книги');
    }
    final worlds = await gateway.worlds();
    // Short-circuit unrelated worlds to avoid loading and verifying every
    // stored archive on a large shared library. Private compilation uses
    // book_<source fingerprint prefix>_<draft hash prefix>.
    final prefix = 'book_${index.sourceFingerprint.substring(0, 12)}_';
    var checked = 0;
    for (final entry in worlds) {
      if (!entry.bookworldId.startsWith(prefix)) continue;
      if (++checked > 32) {
        return const PrivateGameReadiness(
          status: PrivatePlayability.notReady,
          explanation: 'Слишком много вариантов этой книги: '
              'проверьте нужный игровой пакет вручную.',
        );
      }
      try {
        final bytes = await gateway.exportWorld(entry.archiveHash);
        final verified = const PrivateBookworldImporter().inspect(bytes);
        if (verified.sourceFingerprint == index.sourceFingerprint &&
            verified.bookworldId == entry.bookworldId &&
            verified.archiveSha256 == entry.archiveHash) {
          return PrivateGameReadiness(
            status: PrivatePlayability.privatePlayable,
            explanation: 'Проверена короткая личная адаптация. '
                'Результат можно играть офлайн, но он не охватывает '
                'автоматически все события книги и не подлежит публикации.',
            world: entry,
          );
        }
      } on FormatException {
        // A corrupt or mismatched package must never be advertised as playable.
      } on StateError {
        // A package may have been deleted since the catalog was enumerated.
      }
    }
    return const PrivateGameReadiness(
      status: PrivatePlayability.notReady,
      explanation: 'Пока нет проверенного игрового пакета по этой книге. '
          'Подготовьте короткую личную адаптацию в редакторе.',
    );
  }
}
