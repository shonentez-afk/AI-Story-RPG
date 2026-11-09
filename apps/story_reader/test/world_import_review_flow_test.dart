import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/world_import_review_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_api/rpg_api.dart';

class _IntakeGateway extends Fake implements WorldLibraryGateway {
  int installedCount = 0;
  @override
  Future<WorldLibraryItem> install(Uint8List archive) async {
    installedCount++;
    final inspected = const LocalRpgWorldIntakeApi().inspect(archive);
    return WorldLibraryItem(
      archiveHash: inspected.archiveHash,
      bookworldId: inspected.bookworldId,
      title: inspected.title,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = File(
      '../../artifacts/bookworld/rich_v3/River_Rich_Hero_v3.bworld');

  Future<void> launch(WidgetTester tester, _IntakeGateway gateway,
      {Future<String?> Function()? pickReport}) async {
    final bytes = Uint8List.fromList(fixture.readAsBytesSync());
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) =>
      Scaffold(body: ElevatedButton(
        onPressed: () async {
          await WorldImportReviewFlow.confirmAndInstall(
            context: ctx, archive: bytes, gateway: gateway,
            pickReadiness: pickReport,
            inspector: (raw, report) async =>
                const LocalRpgWorldIntakeApi()
                    .inspect(raw, readinessJson: report),
          );
        },
        child: const Text('Open world import'),
      )))));
    await tester.tap(find.text('Open world import'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel does not install externally generated private world',
      (tester) async {
    final gateway = _IntakeGateway();
    await launch(tester, gateway);
    expect(find.byKey(const Key('world-intake-title')), findsOneWidget);
    expect(find.textContaining('канон'), findsWidgets);
    expect(gateway.installedCount, 0);
    await tester.tap(find.byKey(const Key('world-intake-cancel')));
    await tester.pumpAndSettle();
    expect(gateway.installedCount, 0);
  });

  testWidgets('explicit approval installs the exact native-verified world',
      (tester) async {
    final gateway = _IntakeGateway();
    await launch(tester, gateway);
    expect(gateway.installedCount, 0);
    await tester.tap(find.byKey(const Key('world-intake-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.installedCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich v3 remains importable but cannot claim a v4 author receipt',
      (tester) async {
    final gateway = _IntakeGateway();
    await launch(tester, gateway,
        pickReport: () async => '{"format":"fake"}');
    // The synthetic Flutter fixture is rich v3. The v4-only reporting
    // contract is deliberately NOT offered for legacy worlds.
    final attach = tester.widget<OutlinedButton>(
        find.byKey(const Key('world-intake-attach-report')));
    expect(attach.onPressed, isNull);
    expect(find.byKey(const Key('world-intake-report-error')), findsNothing);
    expect(find.textContaining('не приложен'), findsWidgets);
    expect(gateway.installedCount, 0);
    await tester.tap(find.byKey(const Key('world-intake-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.installedCount, 1);
    expect(tester.takeException(), isNull);
  });
}
