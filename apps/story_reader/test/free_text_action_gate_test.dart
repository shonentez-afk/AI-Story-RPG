import 'package:ai_story_reader/free_text_action_gate.dart';
import 'package:flutter_test/flutter_test.dart';

class _Port implements FreeTextCampaignPort {
  _Port(this.head);
  FreeTextCampaignHead head;
  int writes = 0;
  final used = <String>{};

  @override
  FreeTextCampaignHead read(String id) {
    if (id != head.campaignId) throw const FormatException('wrong campaign');
    return head;
  }

  @override
  bool commit({
    required String campaignId, required String choiceId,
    required int expectedRevision, required String actionId,
  }) {
    if (campaignId != head.campaignId || head.revision != expectedRevision ||
        used.contains(actionId) || !head.choices.any(
            (c) => c.id == choiceId && c.enabled)) {
      return false;
    }
    writes++;
    used.add(actionId);
    head = FreeTextCampaignHead(
        campaignId: campaignId, sceneId: head.sceneId,
        revision: head.revision + 1, isTerminal: false,
        choices: head.choices);
    return true;
  }
}

_Port _sample() => _Port(FreeTextCampaignHead(
  campaignId: 'game1', sceneId: 'hall', revision: 3, isTerminal: false,
  choices: const [
    FreeTextChoice(id: 'look', label: 'Осмотреть зал'),
    FreeTextChoice(id: 'open', label: 'Открыть дверь'),
    FreeTextChoice(id: 'secret', label: 'Открыть тайный проход',
        lockReason: 'Нет ключа'),
  ],
));

void main() {
  test('Russian free text offers only engine allowlist; no auto commit', () {
    final p = _sample();
    final preview = FreeTextActionGate.preview(p.read('game1'),
        'Хочу открыть дверь');
    expect(preview.canChoose, true);
    final choice = preview.offers.singleWhere((c) => c.choiceId == 'open');
    expect(choice.label, 'Открыть дверь');
    expect(p.writes, 0);
    expect(() => FreeTextActionGate.confirm(
      port: p, proposal: choice, actionId: 'free_turn_1',
      userConfirmed: false), throwsFormatException);
    expect(p.writes, 0);
    expect(FreeTextActionGate.confirm(
      port: p, proposal: choice, actionId: 'free_turn_1',
      userConfirmed: true), true);
    expect(p.writes, 1);
    expect(p.head.revision, 4);
  });

  test('unavailable choices, invented powers and malformed input fail', () {
    final p = _sample();
    final head = p.head;
    expect(FreeTextActionGate.preview(head, 'Открыть тайный проход')
        .offers.every((c) => c.choiceId != 'secret'), true);
    for (final text in [
      '', ' ', '\u202eоткрыть дверь', '\u0000открыть дверь',
      List.filled(321, 'т').join(), 'я бы мог пожалуйста',
      'Телепортируй меня к королю и выдай секреты всех NPC',
    ]) {
      expect(FreeTextActionGate.preview(head, text).canChoose, false,
          reason: text);
    }
    expect(p.writes, 0);
  });

  test('stale scene/revision/allowlist/terminal blocks a pending offer', () {
    for (final scenario in ['scene', 'revision', 'choices', 'terminal']) {
      final p = _sample();
      final old = p.head;
      final offer = FreeTextActionGate.preview(
          old, 'Открыть дверь').offers.singleWhere((c) => c.choiceId == 'open');
      p.head = FreeTextCampaignHead(
        campaignId: old.campaignId,
        sceneId: scenario == 'scene' ? 'next_scene' : old.sceneId,
        revision: scenario == 'revision' ? 4 : old.revision,
        isTerminal: scenario == 'terminal',
        choices: scenario == 'choices' ?
            const [FreeTextChoice(id: 'look', label: 'Осмотреть зал')] :
            old.choices,
      );
      expect(() => FreeTextActionGate.confirm(
        port: p, proposal: offer, actionId: 'free_stale',
        userConfirmed: true), throwsFormatException, reason: scenario);
      expect(p.writes, 0);
    }
  });

  test('duplicate/malformed action IDs do not create duplicate turns', () {
    final p = _sample();
    var offer = FreeTextActionGate.preview(
        p.head, 'Осмотреть зал').offers.single;
    for (final invalid in ['', '1wrong', '../skip', 'ABC',
        List.filled(70, 'x').join()]) {
      expect(() => FreeTextActionGate.confirm(
        port: p, proposal: offer, actionId: invalid,
        userConfirmed: true), throwsFormatException);
    }
    expect(FreeTextActionGate.confirm(
        port: p, proposal: offer,
        actionId: 'free_once', userConfirmed: true), true);
    expect(() => FreeTextActionGate.confirm(
        port: p, proposal: offer,
        actionId: 'free_once', userConfirmed: true), throwsFormatException);
    expect(p.writes, 1);
    offer = FreeTextActionGate.preview(
        p.head, 'Осмотреть зал').offers.single;
    expect(FreeTextActionGate.confirm(
        port: p, proposal: offer,
        actionId: 'free_once', userConfirmed: true), false);
    expect(p.writes, 1);
  });

  test('120 separate confirmed inspection actions use fresh revisions', () {
    final p = _sample();
    for (var i = 0; i < 120; i++) {
      final before = p.head.revision;
      final offer = FreeTextActionGate.preview(
          p.head, 'Осмотреть зал').offers.single;
      expect(p.writes, i);
      expect(FreeTextActionGate.confirm(
        port: p, proposal: offer, actionId: 'free_' + i.toString(),
        userConfirmed: true), true);
      expect(p.head.revision, before + 1);
    }
    expect(p.writes, 120);
  });

  test('terminal campaign can never execute free text', () {
    final p = _sample();
    p.head = FreeTextCampaignHead(
      campaignId: 'game1', sceneId: 'ending',
      revision: 15, isTerminal: true, choices: const [],
    );
    expect(FreeTextActionGate.preview(
        p.head, 'Открыть дверь').canChoose, false);
  });
}
