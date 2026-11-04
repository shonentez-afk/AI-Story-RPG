import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements AiApiKeyVault {
  @override
  Future<String?> read() async => 'SYNTHETIC-KEY';
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<void> write(String _) async {}
  @override
  Future<void> delete() async {}
}

class _Http implements AiHttpTransport {
  final bodies = <String>[];
  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    bodies.add(body);
    return const AiHttpResponse(200,
      '{"choices":[{"finish_reason":"stop",'
      '"message":{"content":"{\\"candidates\\":[]}"}}]}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('window shows its original heading and paragraphs in consent; '
      'cancel sends zero; consent uploads only reviewed chapter text',
      (tester) async {
    SharedPreferences.setMockInitialValues({'saved_game': 'intact'});
    final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Свинопас',
      author: 'ДАННЫЕ АВТОРА',
      chapters: ['Вступление.', 'Другая глава.'],
      structuredChapters: [
        BookChapter(id: 'one', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'СВИНОПАС'),
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Жил-был бедный принц.'),
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Королевство у него было маленькое-премаленькое.'),
        ]),
        BookChapter(id: 'two', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'ВТОРАЯ ГЛАВА'),
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Вторая глава начинается здесь.'),
        ]),
      ],
    ));
    final p = AiCloudPreferences();
    await p.setEnabled(true);
    final network = _Http();
    final service = ZaiSemanticPreviewService(
      preferences: p,
      vault: _Vault(),
      transport: network,
    );
    await tester.pumpWidget(MaterialApp(
      home: ZaiSemanticPreviewPage(
      reviewRepository: MemorySourceAnalysisCheckpointRepository(),index: index, service: service),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Окно 1 из 2'), findsOneWidget);
    final sourceText = find.byKey(const Key('zai-chunk-text'));
    await tester.scrollUntilVisible(sourceText, 120,
        scrollable: find.byType(Scrollable).first, maxScrolls: 35);
    expect(sourceText, findsOneWidget);

    final send = find.byKey(const Key('zai-send-single-chunk'));
    await tester.scrollUntilVisible(send, 140,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Передать это смысловое окно в Z.ai?'),
        findsOneWidget);
    expect(find.text('Свинопас'), findsOneWidget);
    final excerpt = find.byKey(const Key('zai-consent-exact-excerpt'));
    expect(excerpt, findsOneWidget);
    final exactText = tester.widget<SelectableText>(excerpt).data!;
    expect(exactText, contains('СВИНОПАС'));
    expect(exactText, contains('Жил-был бедный принц.'));
    expect(exactText, isNot(contains('ВТОРАЯ ГЛАВА')));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(network.bodies, isEmpty);

    await tester.tap(send);
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('zai-consent-exact-checkbox'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-consent-confirm')));
    await tester.pumpAndSettle();
    expect(network.bodies.length, 1);
    final body = jsonDecode(network.bodies.single) as Map<String, dynamic>;
    final data = jsonDecode(
      (body['messages'] as List<dynamic>)[1]['content'] as String,
    ) as Map<String, dynamic>;
    expect(data['book_title'], 'Свинопас');
    expect(data.containsKey('untrusted_excerpt'), isFalse);
    final pieces = data['source_chunks'] as List<dynamic>;
    expect(pieces.length, 3);
    expect(pieces[0]['kind'], 'heading');
    expect(pieces[1]['kind'], 'paragraph');
    expect(pieces[2]['kind'], 'paragraph');
    expect(network.bodies.single, isNot(contains('ДАННЫЕ АВТОРА')));
    expect(network.bodies.single, isNot(contains('ВТОРАЯ ГЛАВА')));
    expect((await SharedPreferences.getInstance()).getString('saved_game'),
        'intact');
    expect(tester.takeException(), isNull);
  });
}
