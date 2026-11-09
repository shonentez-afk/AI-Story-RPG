import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_rpg_start_page.dart';
import 'package:ai_story_reader/world_campaigns_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:bookworld_format/bookworld_format.dart'
    show RichPrivateBookworldImporter, ReviewedCanonCausalBookworldWriter;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_api/rpg_api.dart'
    show LocalRpgLiteralCanonApi, LocalRpgWorldIntakeApi;
import 'package:story_authoring/story_authoring.dart'
    show BookSourceIndexer, BookSourceSelection;
import 'package:story_core/story_core.dart' show canonicalJson;

const _book = ImportedBook(
  title: 'Сказание о мосте', author: 'Тестовый автор',
  chapters: [
    'Анна встретила героя у старого моста. '
        'Она выслушала его и решила остаться.',
    'На следующее утро Анна отправилась к реке. '
        'Там история получила свой исход.',
  ],
);
const _other = ImportedBook(
  title: 'Другая редакция', author: 'Тестовый автор',
  chapters: [
    'Анна встретила героя у нового моста. '
        'Она выслушала его и решила остаться.',
    'На следующее утро Анна отправилась к реке. '
        'Там история получила свой исход.',
  ],
);

class _ChosenWorldPicker extends FilePicker {
  _ChosenWorldPicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle, String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false, int compressionQuality = 0,
    bool allowMultiple = false, bool withData = false,
    bool withReadStream = false, bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
        PlatformFile(name: 'reviewed-causal.bworld',
            size: bytes.length, bytes: bytes),
      ]);
}

class _ConfirmedGateway implements WorldLibraryGateway {
  int installations = 0;
  Uint8List? installedArchive;
  @override
  Future<WorldLibraryItem> install(Uint8List archive) async {
    installations++;
    installedArchive = Uint8List.fromList(archive);
    final proof = const LocalRpgWorldIntakeApi().inspect(archive);
    return WorldLibraryItem(
      archiveHash: proof.archiveHash,
      bookworldId: proof.bookworldId, title: proof.title,
    );
  }

  @override
  Future<List<WorldCampaignItem>> campaigns({String? worldHash}) async =>
      const [];

  @override
  Future<Uint8List> exportWorld(String worldHash) async {
    final bytes = installedArchive;
    if (bytes == null ||
        const LocalRpgWorldIntakeApi().inspect(bytes).archiveHash != worldHash) {
      throw const FormatException('Неизвестный игровой мир');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

({Uint8List literal, Uint8List causal, String fingerprint}) _worlds() {
  final scope = BookSourceSelection.defaultChapter(_book);
  final selected = scope == null
      ? _book : BookSourceSelection.selectChapter(_book, scope);
  final indexed = BookSourceIndexer.index(selected);
  const api = LocalRpgLiteralCanonApi();
  final reviewed = api.prepareIndex(indexed);
  final literal = api.compileIndex(indexed,
      approvedDigest: reviewed.approvalDigest, userConfirmed: true);
  final original = const RichPrivateBookworldImporter().inspect(literal);
  final ids = original.blueprint.scenes.keys.toList();
  assert(ids.length >= 2);
  const actor = 'npc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final review = canonicalJson({
    'format': ReviewedCanonCausalBookworldWriter.graphReviewFormat,
    'review_scope': 'human_reviewed_private_story_causality',
    'source_fingerprint': original.sourceFingerprint,
    'base_archive_sha256': original.archiveSha256,
    'user_confirmed': true,
    'semantic_canon_automatically_verified': false,
    'witnesses': [{
      'scene_id': ids.first, 'actor_id': actor,
      'display_name': 'Анна', 'mode': 'present',
      'source_quote_sha256':
          original.sceneOrigins[ids.first]!.sourceQuoteSha256,
    }],
    'invariants': [{
      'scene_id': ids[1], 'actor_id': actor,
      'forbidden_memory_id': 'gm_anna_warning',
      'minimum_trust': null, 'maximum_trust': null,
      'source_quote_sha256':
          original.sceneOrigins[ids[1]]!.sourceQuoteSha256,
    }],
    'event_graph': [
      for (var i = 0; i < ids.length; i++) {
        'scene_id': ids[i],
        'source_quote_sha256':
            original.sceneOrigins[ids[i]]!.sourceQuoteSha256,
        'depends_on': i == 0 ? <String>[] : [ids[i - 1]],
        'preconditions': <Object>[], 'effects': <Object>[],
      },
    ],
  });
  final causal = api.compileReviewedCausality(
    verifiedBaseArchive: literal,
    sourceIndex: Map<String, dynamic>.from(indexed.toJson()),
    reviewJson: review,
    approvedDigest: ReviewedCanonCausalBookworldWriter.digest(review),
    userConfirmed: true,
  );
  return (literal: literal, causal: causal,
      fingerprint: indexed.sourceFingerprint);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openStart(WidgetTester tester,
      _ConfirmedGateway gateway, ImportedBook book) async {
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: book, gateway: gateway,
      indexer: (selected) async => BookSourceIndexer.index(selected),
    )));
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('rpg-start-import-reviewed-causal'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  void picker(Uint8List payload) {
    FilePicker? previous;
    try { previous = FilePicker.platform; } catch (_) {}
    FilePicker.platform = _ChosenWorldPicker(payload);
    addTearDown(() {
      if (previous != null) FilePicker.platform = previous;
    });
  }

  testWidgets('literal CANON cannot masquerade as reviewed causal v5',
      (tester) async {
    final worlds = _worlds();
    picker(worlds.literal);
    final gateway = _ConfirmedGateway();
    await openStart(tester, gateway, _book);
    expect(find.textContaining('не проверенный полный причинный CANON'),
        findsWidgets);
    expect(gateway.installations, 0);
    expect(find.byType(WorldCampaignsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewed v5 for a different exact edition is blocked',
      (tester) async {
    final worlds = _worlds();
    picker(worlds.causal);
    final gateway = _ConfirmedGateway();
    await openStart(tester, gateway, _other);
    expect(find.textContaining('другой редакции или главы'),
        findsWidgets);
    expect(gateway.installations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact causal-reviewed v5 must be approved and opens '
      'one shared library campaign screen', (tester) async {
    final worlds = _worlds();
    picker(worlds.causal);
    final gateway = _ConfirmedGateway();
    await openStart(tester, gateway, _book);
    expect(find.byKey(const Key('world-intake-verified-causality')),
        findsOneWidget);
    expect(find.byKey(const Key('world-intake-reviewed-hero')),
        findsOneWidget);
    expect(gateway.installations, 0);
    await tester.tap(find.byKey(const Key('world-intake-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.installations, 1);
    expect(find.byType(WorldCampaignsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('world-start')), findsOneWidget);
    expect(find.textContaining('Полная книжная RPG'), findsOneWidget);
    expect(find.textContaining('Герой:'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
