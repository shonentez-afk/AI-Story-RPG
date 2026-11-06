import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/local_dialogue_portraits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Hk0AAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a portrait stays on the device and belongs only to its campaign/name',
      () async {
    final folder = await Directory.systemTemp.createTemp('rpg_portrait_');
    try {
      final store = LocalDialoguePortraitStore(root: folder);
      final png = Uint8List.fromList(base64Decode(_onePixelPng));
      await store.save(
          campaignId: 'campaign_01', speaker: 'Лена', png: png);
      expect(await store.read(
          campaignId: 'campaign_01', speaker: 'Лена'),
          orderedEquals(png));
      expect(await store.read(
          campaignId: 'campaign_01', speaker: 'Страж'), isNull);
      expect(await store.read(
          campaignId: 'another_campaign', speaker: 'Лена'), isNull);

      // Case changes in a visible name do not redirect to another character.
      expect(await store.read(
          campaignId: 'campaign_01', speaker: ' лена '),
          orderedEquals(png));
      await store.clear(campaignId: 'campaign_01', speaker: 'Лена');
      expect(await store.read(
          campaignId: 'campaign_01', speaker: 'Лена'), isNull);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('wrong bytes and oversized/dangerous image dimensions fail closed',
      () async {
    final folder = await Directory.systemTemp.createTemp('rpg_portrait_');
    try {
      final store = LocalDialoguePortraitStore(root: folder);
      final original = Uint8List.fromList(base64Decode(_onePixelPng));
      expect(() => LocalDialoguePortraitStore.validatePng(
          Uint8List.fromList([0, 1, 2, 3])), throwsFormatException);
      expect(() => LocalDialoguePortraitStore.validatePng(
          Uint8List(2 * 1024 * 1024 + 1)), throwsFormatException);
      final maliciousWidth = Uint8List.fromList(original);
      maliciousWidth[16] = 0;
      maliciousWidth[17] = 0;
      maliciousWidth[18] = 16;
      maliciousWidth[19] = 0; // 4096px exceeds limit.
      expect(() => LocalDialoguePortraitStore.validatePng(maliciousWidth),
          throwsFormatException);

      await store.save(
          campaignId: 'test', speaker: 'Страж', png: original);
      final dir = Directory(folder.path + Platform.pathSeparator +
          'ai_story_private_portraits');
      final image = dir.listSync().whereType<File>()
          .singleWhere((f) => f.path.endsWith('.png'));
      await image.writeAsBytes(maliciousWidth, flush: true);
      expect(await store.read(campaignId: 'test', speaker: 'Страж'),
          isNull);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('an invalid replacement leaves a previously selected portrait intact',
      () async {
    final folder = await Directory.systemTemp.createTemp('rpg_portrait_');
    try {
      final store = LocalDialoguePortraitStore(root: folder);
      final original = Uint8List.fromList(base64Decode(_onePixelPng));
      await store.save(
          campaignId: 'test', speaker: 'Страж', png: original);
      await expectLater(
        store.save(campaignId: 'test', speaker: 'Страж',
            png: Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(await store.read(campaignId: 'test', speaker: 'Страж'),
          orderedEquals(original));
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
