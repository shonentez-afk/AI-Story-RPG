import 'dart:convert';
import 'dart:typed_data';

import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

class _CitedEvent implements BookEventProposal {
  const _CitedEvent({
    required this.id, required this.chapterIndex, required this.blockIndex,
    required this.chunkId, required this.startUtf16, required this.quote,
    required this.label,
  });
  @override final String id;
  @override final int chapterIndex;
  @override final int blockIndex;
  @override final String chunkId;
  @override final int startUtf16;
  @override final String quote;
  @override final String label;
}

class _SourceOutline implements BookEventOutline {
  const _SourceOutline({
    required this.sourceFingerprint, required this.events,
    required this.totalChapters, required this.chaptersWithEventProposals,
    required this.analysisComplete,
  });
  @override final String sourceFingerprint;
  @override final List<BookEventProposal> events;
  @override final int totalChapters;
  @override final int chaptersWithEventProposals;
  @override final bool analysisComplete;
}

Uint8List _source(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  const author = BookAuthoringEngine();

  test('source-cited story plan validates without Flutter, Z.ai or runtime',
      () {
    const first = 'Мария открыла ворота';
    const second = 'Иван вошёл в город';
    const text = '$first. $second.';
    final source = author.parseAndIndex('story.txt', _source(text));
    final chunk = source.index.chunks.single;
    final book = NarrativeBookModel.fromExisting(
      index: source.index,
      outline: _SourceOutline(
        sourceFingerprint: source.index.sourceFingerprint,
        totalChapters: source.index.chapterCount,
        chaptersWithEventProposals: 1,
        analysisComplete: true,
        events: [
          _CitedEvent(
            id: 'event_open', chapterIndex: chunk.chapterIndex,
            blockIndex: chunk.blockIndex, chunkId: chunk.id,
            startUtf16: chunk.startUtf16 + text.indexOf(first),
            quote: first, label: first,
          ),
          _CitedEvent(
            id: 'event_enter', chapterIndex: chunk.chapterIndex,
            blockIndex: chunk.blockIndex, chunkId: chunk.id,
            startUtf16: chunk.startUtf16 + text.indexOf(second),
            quote: second, label: second,
          ),
        ],
      ),
    );
    final candidate = StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: 'event_open', outcomeEventId: 'event_enter',
      kind: StoryDilemmaKind.agreement,
      dilemma: 'Попросить ли Ивана помочь открыть ворота?',
      acceptIntent: 'Согласиться помочь Ивану открыть ворота.',
      refuseIntent: 'Отказаться от помощи и искать другой путь.',
      followupGoal: 'Открыть ворота вместе с Иваном.',
      finishOriginalIntent: 'Подтвердить помощь и войти во двор.',
      originalEnding: 'Герой получает помощь и проходит через ворота.',
      alternativeSearchGoal: 'Исследовать окрестности в поисках обхода.',
      searchIntent: 'Осмотреть старую тропинку вокруг ворот.',
      alternativeDiscovery: 'На тропе находится проход между деревьями.',
      useDiscoveryIntent: 'Использовать найденную тропинку для обхода.',
      alternativeEnding: 'Герой обходит ворота и уходит своей дорогой.',
    );

    final plan = StoryPlanDilemmaGenerator.propose(book, candidate);
    expect(plan.validate(book).isStructurallySound, true);
    expect(plan.situations.length, greaterThan(3));
    final quality = StoryPlanQualityGate.assess(
      book: book,
      preview: ZaiStoryDilemmaPreview(
        proposal: candidate, plan: plan, sampledEventCount: 2),
    );
    expect(quality.plan.sourceFingerprint, source.index.sourceFingerprint);
    expect(quality.sourceEventCount, 2);
    expect(quality.readyToPlay, false);
    expect(quality.meaningConfirmed, false);
    expect(quality.canPublish, false);
    final unchanged = StoryPlan.decode(plan.encode());
    expect(unchanged.encode(), plan.encode());
    expect(quality.toReadinessJson()['status'], 'DRAFT_ONLY');
  });
}
