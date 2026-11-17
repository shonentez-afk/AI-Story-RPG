import 'dart:convert';
import 'dart:typed_data';

import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

const _first = 'Мария открыла ворота';
const _second = 'Иван вошёл в город';

Map<String, dynamic> _model(String a, String b) => {
  'applicable': true,
  'setup_event_id': a, 'outcome_event_id': b,
  'kind': 'agreement',
  'dilemma': 'Следует ли помочь Ивану пройти через ворота?',
  'accept_intent': 'Принять предложение и помочь пройти в город.',
  'refuse_intent': 'Отказаться от помощи и искать другой путь.',
  'followup_goal': 'Помочь Ивану пройти к городским воротам.',
  'finish_original_intent': 'Открыть ворота и закончить помощь.',
  'original_ending': 'Герой помогает Ивану и возвращается домой.',
  'alternative_search_goal': 'Отыскать обходную дорогу за воротами.',
  'search_intent': 'Осмотреть лесную тропинку около ворот.',
  'alternative_discovery': 'За деревьями появляется старая дорога.',
  'use_discovery_intent': 'Использовать найденный обходной путь.',
  'alternative_ending': 'Герой решает идти дальше по обходной дороге.',
};

void main() {
  const author = BookAuthoringEngine();

  SourceLockedBook source() =>
      author.parseAndIndex('example.txt', _bytes('$_first. $_second.'));

  Map<String, dynamic> envelope(SourceLockedBook book) {
    final index = book.index;
    final base = Map<String, dynamic>.from(
        SourceLockedEventOutline.emptyDraft(index));
    final part = index.chunks.single;
    base['events'] = [
      {
        'id': 'event_open', 'chunk_id': part.id,
        'chapter_index': part.chapterIndex,
        'block_index': part.blockIndex,
        'start_utf16': part.startUtf16, 'quote': _first,
        'label': 'Мария открывает ворота',
      },
      {
        'id': 'event_enter', 'chunk_id': part.id,
        'chapter_index': part.chapterIndex,
        'block_index': part.blockIndex,
        'start_utf16': part.startUtf16 + '$_first. '.length,
        'quote': _second, 'label': 'Иван входит в город',
      },
    ];
    return base;
  }

  test('source-locked story proposal is independently checked, not canon',
      () {
    final book = source();
    final outline = SourceLockedEventOutline.fromJson(
        book.index, envelope(book));
    final roundtrip = SourceLockedEventOutline.fromJson(
        book.index, Map<String, dynamic>.from(outline.toJson(book.index)));
    expect(roundtrip.events.length, 2);
    expect(outline.analysisComplete, true);
    expect(outline.literaryMeaningVerified, false);
    expect(outline.worldReady, false);
    final narrative = NarrativeBookModel.fromExisting(
        index: book.index, outline: outline);
    final result = StoryProposalValidator.validate(
      book: narrative,
      allowedEvents: narrative.events,
      proposedJson: _model('event_open', 'event_enter'),
    );
    expect(result.foundCandidate, true);
    final review = StoryPlanQualityGate.assess(
        book: narrative, preview: result);
    expect(review.passedFormalPreflight, true);
    expect(review.plan.situations.length, greaterThanOrEqualTo(5));
    expect(review.readyToPlay, false);
    expect(review.meaningConfirmed, false);
  });

  test('a valid quote NEVER legitimizes forged interpretation or changed source',
      () {
    final book = source();
    final original = envelope(book);
    final tampered = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    (tampered['events'] as List)[1]['quote'] = 'Иван открыл тайную дверь';
    expect(
      () => SourceLockedEventOutline.fromJson(book.index, tampered),
      throwsFormatException,
    );
    final removed = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    (removed['scanned_chunks'] as List).clear();
    expect(
      () => SourceLockedEventOutline.fromJson(book.index, removed),
      throwsFormatException,
    );
    final flipped = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    (flipped['events'] as List).insert(0, (flipped['events'] as List).removeLast());
    expect(
      () => SourceLockedEventOutline.fromJson(book.index, flipped),
      throwsFormatException,
    );
    final foreign = author.parseAndIndex('new.txt', _bytes('Чужой текст'));
    expect(
      () => SourceLockedEventOutline.fromJson(foreign.index, original),
      throwsFormatException,
    );
  });

  test('model cannot select hidden or unapproved event ID', () {
    final book = source();
    final outline = SourceLockedEventOutline.fromJson(
        book.index, envelope(book));
    final narrative = NarrativeBookModel.fromExisting(
        index: book.index, outline: outline);
    expect(() => StoryProposalValidator.validate(
      book: narrative, allowedEvents: narrative.events,
      proposedJson: _model('event_open', 'event_hidden'),
    ), throwsFormatException);
    final extra = _model('event_open', 'event_enter')..['literary_canon']=true;
    expect(() => StoryProposalValidator.validate(
      book: narrative, allowedEvents: narrative.events,
      proposedJson: extra,
    ), throwsFormatException);
    final noFit = StoryProposalValidator.validate(
      book: narrative, allowedEvents: narrative.events,
      proposedJson: const {'applicable': false},
    );
    expect(noFit.foundCandidate, false);
    expect(noFit.isPlayableRpg, false);
  });

  test('bad unicode boundaries or impersonated source are rejected', () {
    final book = author.parseAndIndex(
        'emoji.txt', _bytes('😀 Мария встретила Ивана.'));
    final base = SourceLockedEventOutline.emptyDraft(book.index);
    final sourceChunk = book.index.chunks.single;
    base['events'] = [
      {
        'id': 'event_bad', 'chunk_id': sourceChunk.id,
        'chapter_index': sourceChunk.chapterIndex,
        'block_index': sourceChunk.blockIndex,
        'start_utf16': 1, 'quote': '😀 Ма',
        'label': 'Битый символ'
      }
    ];
    expect(() => SourceLockedEventOutline.fromJson(
      book.index, Map<String, dynamic>.from(base)),
      throwsFormatException);
  });
}
