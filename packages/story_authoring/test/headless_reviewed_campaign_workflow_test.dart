
import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_campaign_prose_writer.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

class _Event implements BookEventProposal {
  const _Event(this.id, this.chapterIndex, this.blockIndex,
      this.chunkId, this.startUtf16, this.quote);
  @override final String id;
  @override final int chapterIndex, blockIndex, startUtf16;
  @override final String chunkId, quote;
  @override String get label => quote;
}

class _Outline implements BookEventOutline {
  const _Outline(this.sourceFingerprint, this.events);
  @override final String sourceFingerprint;
  @override final List<BookEventProposal> events;
  @override int get totalChapters => 2;
  @override int get chaptersWithEventProposals => 2;
  @override bool get analysisComplete => true;
}

String _narration(String id) => 'Ветер донёс с дороги запах дождя, '
    'и герой медленно оглядел ворота. Впереди оставался выбор, '
    'но ни один разговор ещё не состоялся и чужое обещание '
    'не считалось исполненным. Дополнительное описание сцены $id.';

StoryDilemmaProposal _proposal(String source, String setup, String outcome) =>
    StoryDilemmaProposal(
      sourceFingerprint: source,
      setupEventId: setup,
      outcomeEventId: outcome,
      kind: StoryDilemmaKind.agreement,
      dilemma: 'Попросить помощи у ворот или пройти самому?',
      acceptIntent: 'Согласиться помочь и открыть ворота.',
      refuseIntent: 'Отказаться от помощи и искать свой путь.',
      followupGoal: 'Проверить обещанное и добраться до ворот.',
      finishOriginalIntent: 'Сдержать обещание и продолжить дорогу.',
      originalEnding: 'Герой выполняет обещание и идёт дальше.',
      alternativeSearchGoal: 'Обнаружить другой способ попасть в город.',
      searchIntent: 'Осмотреть тропу за стеной.',
      alternativeDiscovery: 'Найдена тропинка между деревьями.',
      useDiscoveryIntent: 'Воспользоваться тропой вместо ворот.',
      alternativeEnding: 'Герой идёт тропой и сохраняет самостоятельность.',
    );

WholeBookNpcSourcePlan _reviewedPlan() {
  const chapters = [
    'Мария открыла ворота. Иван подошёл к дому.',
    'Иван закрыл ворота. Мария вышла к реке.',
  ];
  final source = const BookAuthoringEngine().indexImported(ImportedBook(
    title: 'Два проверяемых акта', author: 'Тестовый автор',
    chapters: chapters,
  ));
  final records = <BookEventProposal>[];
  final ids = <String>[];
  for (var i = 0; i < chapters.length; i++) {
    final chunk = source.index.chunks.singleWhere((x) => x.chapterIndex == i);
    final sentences = [
      chapters[i].split('. ')[0],
      chapters[i].split('. ')[1].replaceAll('.', ''),
    ];
    for (var j = 0; j < sentences.length; j++) {
      final id = 'event_' + i.toString() + '_' + j.toString();
      ids.add(id);
      records.add(_Event(
        id, chunk.chapterIndex, chunk.blockIndex, chunk.id,
        chunk.startUtf16 + chapters[i].indexOf(sentences[j]),
        sentences[j],
      ));
    }
  }
  final book = NarrativeBookModel.fromExisting(
    index: source.index,
    outline: _Outline(source.index.sourceFingerprint, records),
  );
  final map = BookwideActPlanner.build(index: source.index, book: book);
  final draft = BookwideStoryPlanComposer.compose(
    index: source.index, book: book, bookMap: map,
    actProposals: [
      _proposal(source.index.sourceFingerprint, ids[0], ids[1]),
      _proposal(source.index.sourceFingerprint, ids[2], ids[3]),
    ],
  );
  return WholeBookNpcSourcePlan.fromBook(
    index: source.index, book: book, bookMap: map, draft: draft,
  );
}

void main() {
  const flow = ReviewedCampaignWorkflow();

  test('one headless plan composer is shared by preview and final compiler', () {
    final source = _reviewedPlan();
    final preview = MultiActTrialPlanComposer.compose(
      index: source.index, book: source.book,
      bookMap: source.bookMap, draft: source.draft,
      reviewedInteractiveEventIds: source.extraEventIds,
      fictionalTrialAcknowledged: true,
      expanded: source.expanded,
    );
    expect(preview.npcArc, isNull);
    expect(preview.plan.encode(expanded: source.expanded),
        source.plan.encode(expanded: source.expanded));
    // A selected NPC must not hide its original introduction opportunity
    // in the unmodified preview, nor create a synthetic speaker.
    final beforeNpc = MultiActTrialPlanComposer.compose(
      index: source.index, book: source.book,
      bookMap: source.bookMap, draft: source.draft,
      reviewedInteractiveEventIds: source.extraEventIds,
      reviewedNpcEncounter: true, includeNpc: false,
      fictionalTrialAcknowledged: true,
      expanded: source.expanded,
    );
    expect(beforeNpc.npcArc, isNull);
    expect(beforeNpc.plan.encode(expanded: source.expanded),
        preview.plan.encode(expanded: source.expanded));
    expect(() => MultiActTrialPlanComposer.compose(
      index: source.index, book: source.book,
      bookMap: source.bookMap, draft: source.draft,
      reviewedInteractiveEventIds: source.extraEventIds,
      reviewedNpcEncounter: true, includeNpc: true,
      fictionalTrialAcknowledged: true,
    ), throwsFormatException);
  });

  test('two acts compile and complete with no AI, no items or NPCs', () async {
    final source = _reviewedPlan();
    await expectLater(flow.compileBase(
      source: source, reviewedRoles: const [],
      approvedPlanDigest: source.planDigest,
      approvedHeroDigest: source.heroReviewDigest,
      allShownQuotesReviewed: false, privateFictionConfirmed: true,
    ), throwsFormatException);
    final base = await flow.compileBase(
      source: source, reviewedRoles: const [],
      approvedPlanDigest: source.planDigest,
      approvedHeroDigest: source.heroReviewDigest,
      allShownQuotesReviewed: true, privateFictionConfirmed: true,
    );
    expect(base.stage, ReviewedCampaignStage.base);
    expect(base.isLiteraryCanon, false);
    await expectLater(flow.skipNpc(
      gameplay: base, reviewedRoles: const [],
      explicitlyConfirmedNoNpcDialogues: true,
    ), throwsFormatException);
    await expectLater(flow.skipEffects(
      base: base, reviewedRoles: const [],
      explicitlyConfirmedNoEffects: false,
    ), throwsFormatException);
    final gameplay = await flow.skipEffects(
      base: base, reviewedRoles: const [],
      explicitlyConfirmedNoEffects: true,
    );
    final dialogue = await flow.skipNpc(
      gameplay: gameplay, reviewedRoles: const [],
      explicitlyConfirmedNoNpcDialogues: true,
    );
    await expectLater(flow.completeWithoutNarration(
      dialogue: dialogue, reviewedRoles: const [],
      explicitlyAcceptedExistingSceneText: false,
    ), throwsFormatException);
    final done = await flow.completeWithoutNarration(
      dialogue: dialogue, reviewedRoles: const [],
      explicitlyAcceptedExistingSceneText: true,
    );
    final verified = const RichPrivateBookworldImporter().inspect(done.archive);
    expect(done.stage, ReviewedCampaignStage.complete);
    expect(done.canPlayOffline, true);
    expect(done.isPubliclyDistributable, false);
    expect(verified.requiresNetwork, false);
    expect(verified.blueprint.scenes, isNotEmpty);
    expect(done.status['literary_canon_verified'], false);
  });

  test('same standalone plan supports approved full-scene prose with CAS', () async {
    final source = _reviewedPlan();
    final base = await flow.compileBase(
      source: source, reviewedRoles: const [],
      approvedPlanDigest: source.planDigest,
      approvedHeroDigest: source.heroReviewDigest,
      allShownQuotesReviewed: true, privateFictionConfirmed: true,
    );
    final gameplay = await flow.skipEffects(
      base: base, reviewedRoles: const [],
      explicitlyConfirmedNoEffects: true,
    );
    final dialogue = await flow.skipNpc(
      gameplay: gameplay, reviewedRoles: const [],
      explicitlyConfirmedNoNpcDialogues: true,
    );
    final manifest = await flow.prepareNarration(
      dialogue: dialogue, reviewedRoles: const [],
      verifyCurrent: () async {},
    );
    final raw = CampaignProseCheckpointCodec.encode(
      manifest: manifest,
      revision: 1,
      entries: [
        for (final id in manifest.sceneIds)
          CampaignProseEntry(sceneId: id, text: _narration(id),
            uncertainty: 'Требуется проверка смысла по исходной книге.'),
      ],
    );
    final session = CampaignProseCheckpointCodec.decode(manifest, raw);
    final review = CampaignProseFinalizer.review(manifest, session);
    final digest = ReviewedCampaignProseWriter.digest(review);
    await expectLater(flow.completeWithNarration(
      dialogue: dialogue, reviewedRoles: const [],
      manifest: manifest, session: session,
      readLatest: () async => CampaignProseSession.restored(
        2, 'changed', session.entries),
      approvedDigest: digest,
      fullTextReviewed: true, privateFictionConfirmed: true,
    ), throwsFormatException);
    final done = await flow.completeWithNarration(
      dialogue: dialogue, reviewedRoles: const [],
      manifest: manifest, session: session,
      readLatest: () async => session,
      approvedDigest: digest,
      fullTextReviewed: true, privateFictionConfirmed: true,
    );
    final original = const RichPrivateBookworldImporter().inspect(dialogue.archive);
    final finished = const RichPrivateBookworldImporter().inspect(done.archive);
    expect(done.hasNewNarration, true);
    expect(done.canPlayOffline, true);
    expect(finished.blueprint.scenes.length,
        original.blueprint.scenes.length);
    for (final entry in original.blueprint.scenes.entries) {
      final scene = finished.blueprint.scenes[entry.key]!;
      expect(scene.text, startsWith(_narration(entry.key)));
      expect(scene.choices.map((e) => e.id).toList(),
          entry.value.choices.map((e) => e.id).toList());
    }
  });
}
