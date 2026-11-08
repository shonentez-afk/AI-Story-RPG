import 'dart:convert';
import 'dart:typed_data';

import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  const flow = BookToRpgWorkflow();

  test('exact edition, scope and offline resume do not grant RPG canon',
      () async {
    final fb2 = bytes('<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Сказки</book-title>'
        '</title-info></description><body>'
        '<section><p>Алиса открыла дверь.</p></section>'
        '<section><p>Борис увидел Алису.</p></section>'
        '</body></FictionBook>');
    final whole = flow.openSource('tales.fb2', fb2);
    final one = flow.openSource('tales.fb2', fb2, selectedChapter: 1);
    expect(whole.index.chapterCount, 2);
    expect(one.index.chapterCount, 1);
    expect(one.sourceFingerprint, isNot(whole.sourceFingerprint));
    OfflineScanCheckpoint? cp;
    final state = await flow.prepare(one, onCheckpoint: (value) => cp = value);
    expect(cp, isNotNull);
    expect(state.hasPlayableWorld, isFalse);
    expect(state.isLiteraryCanon, isFalse);
    expect(state.status['requires_cloud'], isFalse);
    expect(state.readiness.canStartPlayableBook, isFalse);
    final repeated = await flow.prepare(one, resume: cp);
    expect(repeated.status, state.status);
    await expectLater(flow.prepare(whole, resume: cp), throwsFormatException);
  });

  test('readiness is source-scoped and editorial review cannot bypass compile',
      () async {
    final source = flow.openSource('novel.txt',
        bytes('Алиса открыла дверь. Борис ждал. Занавес закрыт.'));
    final state = await flow.prepare(source);
    final readiness = flow.assessEditorial(state);
    expect(readiness.gates.any((g) => g.id == 'source' &&
        g.status == PreparationGateStatus.complete), isTrue);
    expect(readiness.gates.any((g) => g.id == 'compiler' &&
        g.status == PreparationGateStatus.blocked), isTrue);
    await expectLater(flow.buildReviewedDraft(snapshot: state,
        review: <String, dynamic>{
          'source_fingerprint': 'f' * 64,
        }), throwsFormatException);
    await expectLater(flow.buildReviewedDraft(snapshot: state,
        review: <String, dynamic>{
          'source_fingerprint': source.sourceFingerprint,
        }), throwsFormatException);
  });
}
