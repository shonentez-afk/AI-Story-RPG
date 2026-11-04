import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/quick_rpg_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index() {
  const xml = '<FictionBook><description><title-info>'
      '<book-title>Книга для проверки</book-title>'
      '</title-info></description><body><section>'
      '<p>Герой открыл книгу и отправился в путь по незнакомой дороге.</p>'
      '<p>У старой реки герой нашёл маленький мост и увидел большой город.</p>'
      '<p>Путешественник вошёл в замок и рассказал о своей необычной находке.</p>'
      '<p>После долгого разговора все участники вернулись к старому дому.</p>'
      '</section></body></FictionBook>';
  return BookSourceIndexer.index(BookImporter.parse(
      'short.fb2', Uint8List.fromList(utf8.encode(xml))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('small-screen wizard offers two modes and refuses implicit '
      'approval', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: QuickRpgPage(
          index: _index(),
          gateway: const DeviceWorldLibraryGateway(background: false),
        ),
      ),
    ));
    final follow = find.byKey(const Key('quick-rpg-follow-book'));
    expect(follow, findsOneWidget);
    expect(find.byKey(const Key('quick-rpg-change-fate')), findsOneWidget);
    await tester.tap(follow);
    await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    final play = find.byKey(const Key('quick-rpg-create-and-play'));
    await tester.scrollUntilVisible(play, 180, scrollable: scroll);
    expect(find.byKey(const Key('quick-rpg-review-confirm')), findsOneWidget);
    expect(find.byKey(const Key('quick-rpg-private-confirm')), findsOneWidget);
    expect(tester.widget<FilledButton>(play).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unusably short book reports an explanation instead of '
      'starting a fake world', (tester) async {
    final index = BookSourceIndexer.index(BookImporter.parse(
        'tiny.txt', Uint8List.fromList(utf8.encode(
            'Это очень короткий текст без отдельного продолжения.'))));
    await tester.pumpWidget(MaterialApp(
      home: QuickRpgPage(
        index: index,
        gateway: const DeviceWorldLibraryGateway(background: false),
      ),
    ));
    expect(find.byKey(const Key('quick-rpg-error')), findsOneWidget);
    expect(find.byKey(const Key('quick-rpg-create-and-play')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
