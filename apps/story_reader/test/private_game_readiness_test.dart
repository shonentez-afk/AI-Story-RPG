import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/private_game_readiness.dart';
import 'package:ai_story_reader/private_game_readiness_panel.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReadOnlyGateway extends DeviceWorldLibraryGateway {
  _ReadOnlyGateway(this.entries, {this.archive});
  final List<WorldLibraryItem> entries;
  final Uint8List? archive;
  int exportCalls = 0;
  @override
  Future<List<WorldLibraryItem>> worlds() async => entries;
  @override
  Future<Uint8List> exportWorld(String worldHash) async {
    exportCalls++;
    if (archive == null) throw StateError('Missing archive');
    return archive!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Частная история', author: 'Автор',
      chapters: ['Дверь была закрыта. Мария открыла дверь.']));

  test('no stored world does not imply playable story', () async {
    final gateway = _ReadOnlyGateway([]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.status, PrivatePlayability.notReady);
    expect(result.canStartPrivateGame, false);
    expect(result.canSharePublicly, false);
    expect(result.hasAiAuthoring, false);
    expect(gateway.exportCalls, 0);
  });

  test('different book world is skipped without ZIP inspection', () async {
    final gateway = _ReadOnlyGateway([
      const WorldLibraryItem(
        archiveHash: 'unrelated', bookworldId: 'original_demo',
        title: 'Оригинальное демо',
      ),
    ]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 0);
  });

  test('corrupt matching ZIP fails closed with no play button', () async {
    final gateway = _ReadOnlyGateway([
      WorldLibraryItem(
        archiveHash: 'broken',
        bookworldId: 'book_${index.sourceFingerprint.substring(0, 12)}_bad',
        title: 'Повреждённая адаптация',
      ),
    ], archive: Uint8List.fromList([1, 2, 3]));
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 1);
  });

  test('unbounded matching variants fail closed without scanning archives',
      () async {
    final gateway = _ReadOnlyGateway([
      for (var i = 0;
          i < PrivateGameReadinessVerifier.maxCandidatePackages + 1;
          i++)
        WorldLibraryItem(
          archiveHash: 'invalid_$i',
          bookworldId:
              'book_${index.sourceFingerprint.substring(0, 12)}_$i',
          title: 'Вариант $i',
        ),
    ]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 0);
  });

  testWidgets('readiness panel never invents installed game', (tester) async {
    final gateway = _ReadOnlyGateway([]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        PrivateGameReadinessPanel(index: index, gateway: gateway))));
    await tester.pump();
    expect(find.textContaining('Готовность книги к RPG'), findsOneWidget);
    expect(find.byKey(const Key('prepare-open-verified-private-rpg')),
        findsNothing);
    await tester.tap(find.byKey(const Key('prepare-recheck-game')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверенной личной RPG'), findsOneWidget);
    expect(find.byKey(const Key('prepare-open-verified-private-rpg')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
