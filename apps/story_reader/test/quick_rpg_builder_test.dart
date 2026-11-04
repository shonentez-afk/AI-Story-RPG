import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:campaign_manager/campaign_manager.dart';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/quick_rpg_builder.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter_test/flutter_test.dart';

const example = '<FictionBook><description><title-info><book-title>Тест</book-title>'
  '</title-info></description><body><section>'
  '<p>Один герой начал путешествие из старого дома, который стоял на самом краю деревни.</p>'
  '<p>Вторая часть книги описывала прогулку героя вдоль тёмного леса и небольшой реки.</p>'
  '<p>Следующая сцена рассказывала о добром знакомстве с новым путешественником на дороге.</p>'
  '<p>Последний эпизод повествовал о завершении путешествия и возвращении домой.</p>'
  '</section></body></FictionBook>';

BookSourceIndex sample() => BookSourceIndexer.index(
    BookImporter.parse('sample.fb2',
      Uint8List.fromList(utf8.encode(example))));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generated world performs real SQLite choices and survives restart',
      () async {
    final plan = QuickRpgBuilder.propose(sample(),
        mode: QuickRpgMode.changeFate);
    final built = await QuickRpgBuilder.compile(
      plan: plan, allQuotesReviewedByUser: true,
      privateUseConfirmed: true,
    );
    final temp = await Directory.systemTemp.createTemp('quick-rpg-sqlite-');
    late String campaign;
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        final installed = store.installBookworld(built.archive);
        campaign = store.createCampaign(installed.archiveHash);
        var moves = 0;
        while (true) {
          final current = store.loadCampaign(campaign);
          if (current.coordinator.isTerminal) break;
          final next = current.coordinator.choices.singleWhere(
              (choice) => choice.label == 'Следовать книге');
          expect(store.commitChoice(campaign,
              actionId: 'quick_continue_${moves + 1}',
              choiceId: next.id,
              expectedRevision: current.metadata.revision).applied, true);
          moves++;
          expect(moves, lessThan(30));
        }
        expect(moves, plan.sourceScenes - 1);
        expect(store.loadCampaign(campaign).coordinator.events, hasLength(moves));
        final alternateId = store.createCampaign(installed.archiveHash);
        final alternate = store.loadCampaign(alternateId);
        final branch = alternate.coordinator.choices.singleWhere(
            (choice) => choice.label == 'Изменить судьбу');
        expect(store.commitChoice(alternateId,
            actionId: 'quick_change_fate',
            choiceId: branch.id,
            expectedRevision: alternate.metadata.revision).applied, true);
        expect(store.loadCampaign(alternateId).coordinator.isTerminal, true);
        expect(store.loadCampaign(campaign).metadata.revision, moves);
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        expect(store.loadCampaign(campaign).coordinator.isTerminal, true);
        expect(store.installedWorlds(), hasLength(1));
        expect(store.campaigns(), hasLength(2));
      } finally {
        store.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('real Gutenberg Frog Prince makes a private excerpt-based route',
      () async {
    final path = Platform.environment['AI_RPG_FROG_PRINCE_FB2_PATH'];
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final book = BookImporter.parse('frog_prince_public.fb2',
        Uint8List.fromList(bytes));
    final index = BookSourceIndexer.index(book);
    final plan = QuickRpgBuilder.propose(index);
    expect(plan.sourceScenes, inInclusiveRange(2, 8));
    expect(plan.anchors.last.chapterIndex, lessThan(index.chapterCount));
    final result = await QuickRpgBuilder.compile(
      plan: plan,
      allQuotesReviewedByUser: true,
      privateUseConfirmed: true,
    );
    final inspected = const PrivateBookworldImporter().inspect(result.archive);
    expect(inspected.blueprint.scenes.length, greaterThanOrEqualTo(3));
    expect(inspected.sourceFingerprint, index.sourceFingerprint);
    expect(inspected.canDistributePublicly, false);
  });

  test('quick plan keeps exact quotes and needs consent', () async {
    final index = sample();
    final plan = QuickRpgBuilder.propose(index);
    expect(plan.anchors.length, greaterThanOrEqualTo(2));
    expect(plan.isCompleteRpgFromBook, false);
    for (final anchor in plan.anchors) {
      final chunk = index.chunks.singleWhere((c) => c.id == anchor.chunkId);
      expect(chunk.text.substring(
        anchor.startUtf16 - chunk.startUtf16,
        anchor.endUtf16 - chunk.startUtf16), anchor.quote);
    }
    await expectLater(QuickRpgBuilder.compile(
      plan: plan, allQuotesReviewedByUser: false,
      privateUseConfirmed: true), throwsFormatException);
    final built = await QuickRpgBuilder.compile(
      plan: plan, allQuotesReviewedByUser: true,
      privateUseConfirmed: true);
    final parsed = const PrivateBookworldImporter().inspect(built.archive);
    expect(parsed.bookworldId, built.bookworldId);
    expect(parsed.canDistributePublicly, false);
    expect(parsed.requiresNetwork, false);
    expect(parsed.blueprint.scenes.length, greaterThanOrEqualTo(3));
  });
}
