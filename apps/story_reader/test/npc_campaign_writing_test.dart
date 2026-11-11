import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/npc_campaign_writing_session.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/whole_book_npc_campaign.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_npc_campaign_writing.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  _Fixture(this.source, this.roles, this.catalog);
  final WholeBookNpcSourcePlan source;
  final List<ReviewedHeroRole> roles;
  final NpcWritingCatalog catalog;
  List<String> get ids => catalog.candidates.keys.toList();
  List<NpcWritingEdit> get empty => [
    for (var i = 0; i < ids.length; i++) NpcWritingEdit(id: ids[i]),
  ];
}

Future<_Fixture> _fixture() async {
  const names = ['Артем', 'Мария', 'Борис'];
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Три NPC — подготовка диалогов и перезапуск', author: 'Синтетический тест',
    chapters: [for (final name in names)
      List.filled(7, 'Начало пути. ').join() +
          '$name встретил путника у ворот и показал дорогу. ' +
          List.filled(12, 'Путник продолжил путешествие. ').join()],
  ));
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analyzer = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final rows = [for (var i = 0; i < 4; i++) SemanticCandidate.propose(source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16 + i * 10,
        endUtf16: chunk.startUtf16 + 150 + i * 10,
        label: 'Проверяемое событие', uncertainty: 'Смысл не подтверждён.')];
      return ZaiSemanticPreviewResult(batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: source.sourceFingerprint,
        chunkIds: [for (final c in window.chunks) c.id], candidates: rows),
        totalSuggestions: rows.length, rejectedCount: 0, rejectedNonRussian: 0);
    },
  );
  final review = await analyzer.analyze(index: index,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true, maxWindowsPerRun: 64);
  final book = NarrativeBookModel.fromExisting(index: index,
      outline: ZaiWholeBookEventOutline.build(review));
  final map = BookwideActPlanner.build(index: index, book: book);
  final proposals = [for (var i = 0; i < 3; i++) StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: book.events.where((e) => e.source.chapterIndex == i).first.id,
    outcomeEventId: book.events.where((e) => e.source.chapterIndex == i).last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Принять предложение или продолжить путь самому',
    acceptIntent: 'Принять предложение', refuseIntent: 'Отказаться',
    followupGoal: 'Выполнить выбранное условие', finishOriginalIntent: 'Исполнить обещание',
    originalEnding: 'Завершить исходный путь', alternativeSearchGoal: 'Найти другой путь',
    searchIntent: 'Исследовать дорогу', alternativeDiscovery: 'Найдена другая дорога',
    useDiscoveryIntent: 'Выбрать найденный путь', alternativeEnding: 'Завершить иной путь')];
  final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map, actProposals: proposals);
  final source = WholeBookNpcSourcePlan.fromBook(
      index: index, book: book, bookMap: map, draft: draft);
  var graph = SourceEvidenceGraph.empty(index);
  final mentions = <SourceEvidence>[];
  for (var i = 0; i < 3; i++) {
    final event = book.events.firstWhere((e) => e.source.chapterIndex == i &&
        source.extraEventIds.contains(e.id));
    final offset = event.source.quote.indexOf(names[i]);
    expect(offset, greaterThanOrEqualTo(0));
    mentions.add(SourceEvidence.propose(index, chunkId: event.source.chunkId,
      kind: EvidenceKind.character, startUtf16: event.source.startUtf16 + offset,
      endUtf16: event.source.startUtf16 + offset + names[i].length));
  }
  graph = graph.addAll(index, mentions);
  for (final m in mentions) { graph = graph.review(index, m.id, EvidenceStatus.confirmed); }
  final relations = SourceRelationReviewSession.create(index, graph);
  final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
  final editorial = SemanticEditorialReviewSession.create(index, catalog);
  final dossiers = SourceCharacterDossierIndex.build(index, graph, relations, catalog, editorial);
  var notebook = NpcEditorialNotebook.empty(index);
  for (final name in names) { notebook = notebook.putProfile(NpcEditorialNotebook.freshProfile(
      dossiers.dossiers.singleWhere((d) => d.labels.contains(name)))); }
  final roles = ReviewedHeroRole.fromReviewedSources(index: index,
      dossiers: dossiers, graph: graph, catalog: catalog, editorial: editorial, notebook: notebook);
  final candidates = BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: roles);
  expect(candidates.length, 3);
  return _Fixture(source, roles, NpcWritingCatalog(source: source, candidates: candidates));
}

class _Preferences extends AiCloudPreferences {
  bool enabled = true;
  @override Future<bool> isEnabled() async => enabled;
}
class _Vault implements AiApiKeyVault {
  String? key = 'unit-test-not-a-real-secret';
  @override Future<String?> read() async => key;
  @override Future<void> write(String value) async { key = value; }
  @override Future<void> delete() async { key = null; }
  @override Future<bool> hasKey() async => key != null;
}
class _Transport implements AiHttpTransport {
  _Transport(this.respond);
  final Future<AiHttpResponse> Function(Map<String, dynamic>, int) respond;
  final bodies = <String>[];
  @override Future<AiHttpResponse> send({required Uri uri,
      required Map<String, String> headers, required String body}) async {
    expect(uri, ZaiModel.endpoint);
    bodies.add(body);
    final root = jsonDecode(body) as Map;
    return respond(jsonDecode((root['messages'] as List).last['content'] as String)
        as Map<String, dynamic>, bodies.length);
  }
}
AiHttpResponse _answer(Map<String, dynamic> batch, {bool refuse = false, bool forged = false}) =>
    AiHttpResponse(200, jsonEncode({'choices': [{'finish_reason': 'stop', 'message': {
      'content': jsonEncode({
        'batch_id': batch['batch_id'],
        'proposals': [if (!refuse) for (final row in batch['conversations'] as List) {
          'candidate_id': row['candidate_id'],
          'actor_id': forged ? 'npc_invented' : row['actor_id'],
          'player_line': 'Расскажи о нашей встрече у ворот.',
          'npc_line': 'Я помню встречу и показанную дорогу.',
          'uncertainty': 'Игровой разговор требует проверки автором.',
        }],
        'skipped': [if (refuse) for (final row in batch['conversations'] as List) {
          'candidate_id': row['candidate_id'], 'reason': 'Недостаточно контекста для разговора.',
        }],
      }),
    }}]}));
ZaiNpcCampaignWriting _writer(_Transport transport, {_Preferences? preferences, _Vault? vault}) =>
    ZaiNpcCampaignWriting(preferences: preferences ?? _Preferences(), vault: vault ?? _Vault(),
      transport: transport, retryWait: (_) async {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUpAll(() async { fixture = await _fixture(); });

  test('manual partial dialogue persists privately across restart without '
      'keys, source quotes, cloud consent or installation approval', () async {
    final dir = await Directory.systemTemp.createTemp('npc_author_drafts_');
    try {
      final repository = FileSourceAnalysisCheckpointRepository(rootDirectory: () async => dir);
      final store = NpcWritingStore(repository: repository);
      final saved = await store.save(fixture.catalog, expectedRevision: 0, edits: [
        NpcWritingEdit(id: fixture.ids.first, playerLine: 'Незавершённый вопрос автора'),
      ]);
      final reopened = await NpcWritingStore(repository: repository).load(fixture.catalog);
      expect(reopened.revision, saved.revision);
      expect(reopened.edits.values.single.playerLine, 'Незавершённый вопрос автора');
      expect(reopened.cloudConsent, false); expect(reopened.canInstallDirectly, false);
      final raw = await repository.read(fixture.catalog.storageKey);
      expect(raw, isNot(contains('unit-test-not-a-real-secret')));
      expect(raw, isNot(contains(fixture.catalog.candidates.values.first.firstEvent.source.quote)));
      final changedCatalog = NpcWritingCatalog(source: fixture.source,
          candidates: fixture.catalog.candidates.values.skip(1).toList());
      await expectLater(store.load(changedCatalog), throwsFormatException);
      expect(await repository.read(fixture.catalog.storageKey), raw);
    } finally { await dir.delete(recursive: true); }
  });

  test('failed writes and competing editor revisions preserve the last complete draft', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcWritingStore(repository: repo);
    final old = await store.save(fixture.catalog, edits: fixture.empty, expectedRevision: 0);
    final bytes = await repo.read(fixture.catalog.storageKey);
    repo.failNextWrite = true;
    await expectLater(store.save(fixture.catalog, edits: const [], expectedRevision: old.revision),
        throwsA(isA<FileSystemException>()));
    expect(await repo.read(fixture.catalog.storageKey), bytes);
    final changed = await store.save(fixture.catalog, edits: fixture.empty.take(1), expectedRevision: old.revision);
    await expectLater(store.save(fixture.catalog, edits: fixture.empty, expectedRevision: old.revision), throwsFormatException);
    expect((await store.load(fixture.catalog)).revision, changed.revision);
    final forged = jsonDecode((await repo.read(fixture.catalog.storageKey))!) as Map<String, dynamic>;
    (forged['payload'] as Map)['approved_for_install'] = true;
    forged['sha256'] = npcWritingHash(forged['payload']);
    await repo.write(fixture.catalog.storageKey, jsonEncode(forged));
    await expectLater(store.load(fixture.catalog), throwsFormatException);
    expect(() => store.reset(fixture.catalog, confirmed: false), throwsFormatException);
  });

  test('missing exact consent, disabled cloud, missing key and forged actor never write a draft', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcWritingStore(repository: repo);
    final state = await store.save(fixture.catalog, edits: fixture.empty, expectedRevision: 0);
    final request = NpcWritingRequest.prepare(fixture.catalog, state);
    final transport = _Transport((batch, _) async => _answer(batch, forged: true));
    final prefs = _Preferences()..enabled = false;
    final vault = _Vault();
    final writer = _writer(transport, preferences: prefs, vault: vault);
    Future<NpcWritingSession> run({bool consent = true, String? digest}) => writer.generate(
      catalog: fixture.catalog, store: store, request: request,
      approvedDigest: digest ?? request.approvalDigest, explicitCloudConsent: consent);
    await expectLater(run(consent: false), throwsA(isA<AiSetupException>()));
    await expectLater(run(digest: 'stale'), throwsA(isA<AiSetupException>()));
    await expectLater(run(), throwsA(isA<AiSetupException>()));
    prefs.enabled = true; vault.key = null;
    await expectLater(run(), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty);
    vault.key = 'unit-test-not-a-real-secret';
    await expectLater(run(), throwsA(isA<AiSetupException>()));
    expect(transport.bodies.length, 1);
    expect((await store.load(fixture.catalog)).revision, state.revision);
  });

  test('partial AI batch survives failure, resumes only pending requests, '
      'then human review builds the SAME autonomous multi-NPC game', () async {
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = NpcWritingStore(repository: repo);
    final first = await store.save(fixture.catalog, edits: fixture.empty, expectedRevision: 0);
    final request = NpcWritingRequest.prepare(fixture.catalog, first, perRequest: 1);
    final failing = _Transport((batch, count) async => count == 1
        ? _answer(batch) : const AiHttpResponse(429, '{}', retryAfter: '0'));
    await expectLater(_writer(failing).generate(catalog: fixture.catalog,
      store: store, request: request, approvedDigest: request.approvalDigest,
      explicitCloudConsent: true), throwsA(isA<AiSetupException>()));
    expect(failing.bodies.length, 4);
    expect(failing.bodies.skip(1).toSet().length, 1);
    final restored = await NpcWritingStore(repository: repo).load(fixture.catalog);
    expect(restored.edits.values.where((e) => e.complete).length, 1);
    final next = NpcWritingRequest.prepare(fixture.catalog, restored, perRequest: 1);
    expect(next.requestCount, 2);
    final ok = _Transport((batch, _) async => _answer(batch));
    final completed = await _writer(ok).generate(catalog: fixture.catalog, store: store,
      request: next, approvedDigest: next.approvalDigest, explicitCloudConsent: true);
    expect(ok.bodies.length, 2);
    expect(completed.edits.values.every((e) => e.complete && e.origin == 'ai_draft'), true);
    expect(completed.canInstallDirectly, false);
    expect(() => NpcWritingRequest.prepare(fixture.catalog, completed), throwsFormatException);
    final base = await fixture.source.compileBase(
      approvedPlanDigest: fixture.source.planDigest,
      allShownQuotesReviewed: true, privateFictionConfirmed: true);
    final approval = BookwideNpcCampaignAuthoring.review(source: fixture.source,
      verifiedBaseArchive: base.archive, currentReviewedRoles: fixture.roles,
      selectedDrafts: completed.edits.values.map((e) => e.toDraft()).toList());
    final built = await BookwideNpcCampaignAuthoring.compile(source: fixture.source,
      approval: approval, freshReviewedRoles: fixture.roles,
      approvedDigest: approval.approvalDigest, explicitlyConfirmedPrivateFiction: true);
    final verified = const RichPrivateBookworldImporter().inspect(built.archive);
    expect(verified.blueprint.actors.length, 4);
    expect(built.requiresNetworkToPlay, false);
    final dir = await Directory.systemTemp.createTemp('npc_ai_to_sqlite_');
    try {
      final db = BookworldCampaignStore.openPrivateDirectory(dir.path);
      try { expect(db.createCampaign(db.installBookworld(built.archive).archiveHash), isNotEmpty); }
      finally { db.close(); }
    } finally { await dir.delete(recursive: true); }
  });

  test('cancel after a committed batch preserves it and sends no later source windows', () async {
    final store = NpcWritingStore(repository: MemorySourceAnalysisCheckpointRepository());
    final state = await store.save(fixture.catalog, edits: fixture.empty, expectedRevision: 0);
    final request = NpcWritingRequest.prepare(fixture.catalog, state, perRequest: 1);
    final transport = _Transport((batch, _) async => _answer(batch));
    final token = ZaiPreviewCancellation();
    await expectLater(_writer(transport).generate(catalog: fixture.catalog,
      store: store, request: request, approvedDigest: request.approvalDigest,
      explicitCloudConsent: true, cancellation: token,
      onSaved: (_) async => token.cancel()), throwsA(isA<AiSetupException>()));
    expect(transport.bodies.length, 1);
    expect((await store.load(fixture.catalog)).edits.values.where((e) => e.complete).length, 1);
  });

  test('model refusal is durable and manual text is never overwritten or silently resent', () async {
    final store = NpcWritingStore(repository: MemorySourceAnalysisCheckpointRepository());
    final selected = [
      NpcWritingEdit(id: fixture.ids[0], playerLine: 'Ручная реплика автора'),
      ...fixture.empty.skip(1),
    ];
    final state = await store.save(fixture.catalog, edits: selected, expectedRevision: 0);
    final request = NpcWritingRequest.prepare(fixture.catalog, state);
    expect(request.candidateCount, 2);
    final transport = _Transport((batch, _) async => _answer(batch, refuse: true));
    final saved = await _writer(transport).generate(catalog: fixture.catalog, store: store,
      request: request, approvedDigest: request.approvalDigest, explicitCloudConsent: true);
    expect(saved.edits[fixture.ids[0]]!.playerLine, 'Ручная реплика автора');
    expect(saved.edits.values.where((e) => e.noSuggestion).length, 2);
    expect(() => NpcWritingRequest.prepare(fixture.catalog, saved), throwsFormatException);
  });

  test('concurrent paid batches are rejected; an intervening manual save wins over late AI', () async {
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = NpcWritingStore(repository: repository);
    final state = await store.save(fixture.catalog, edits: fixture.empty, expectedRevision: 0);
    final request = NpcWritingRequest.prepare(fixture.catalog, state);
    final started = Completer<void>(), response = Completer<AiHttpResponse>();
    Map<String, dynamic>? transmitted;
    final transport = _Transport((batch, _) {
      transmitted = batch; started.complete(); return response.future;
    });
    final pending = _writer(transport).generate(catalog: fixture.catalog, store: store,
      request: request, approvedDigest: request.approvalDigest, explicitCloudConsent: true);
    // The author-revision guard now rejects this conflict BEFORE store.save.
    // Assert the public error and its cause, not a broad exception matcher.
    final failed = expectLater(pending, throwsA(isA<AiSetupException>().having(
        (error) => error.toString(), 'stale-draft reason',
        contains('В другом окне изменён черновик'))));
    await started.future;
    await expectLater(_writer(transport).generate(catalog: fixture.catalog, store: store,
      request: request, approvedDigest: request.approvalDigest, explicitCloudConsent: true),
      throwsA(isA<AiSetupException>()));
    final manual = await store.save(fixture.catalog, edits: [
      NpcWritingEdit(id: fixture.ids.first, playerLine: 'Более новая ручная правка'),
      ...fixture.empty.skip(1),
    ], expectedRevision: state.revision);
    final manualBytes = await repository.read(fixture.catalog.storageKey);
    response.complete(_answer(transmitted!));
    await failed;
    expect(transport.bodies.length, 1);
    final preserved = await store.load(fixture.catalog);
    expect(preserved.edits[fixture.ids.first]!.playerLine, 'Более новая ручная правка');
    expect(preserved.revision, manual.revision);
    expect(preserved.snapshotDigest, manual.snapshotDigest);
    expect(await repository.read(fixture.catalog.storageKey), manualBytes);
  });
}
