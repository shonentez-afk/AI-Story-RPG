import 'dart:convert';
import 'package:crypto/crypto.dart';

/// M2f4a: deterministic, offline interpretation of a player's text.
/// A match is only an untrusted *suggestion*, never permission to alter canon.
class FreeTextChoice {
  const FreeTextChoice({required this.id, required this.label, this.lockReason});
  final String id;
  final String label;
  final String? lockReason;
  bool get enabled => lockReason == null;
}

class FreeTextCampaignHead {
  FreeTextCampaignHead({
    required this.campaignId,
    required this.sceneId,
    required this.revision,
    required this.isTerminal,
    required List<FreeTextChoice> choices,
  }) : choices = List.unmodifiable(choices);

  final String campaignId;
  final String sceneId;
  final int revision;
  final bool isTerminal;
  final List<FreeTextChoice> choices;

  /// Local consistency fingerprint; never an authorization token.
  String get fingerprint => sha256.convert(utf8.encode(jsonEncode({
        'campaign': campaignId, 'scene': sceneId,
        'revision': revision, 'terminal': isTerminal,
        'choices': [
          for (final c in choices)
            {'id': c.id, 'label': c.label, 'lock': c.lockReason},
        ],
      }))).toString();
}

/// Cannot be constructed outside this library: only authoritative available
/// story_core choices can become proposals.
class FreeTextProposal {
  FreeTextProposal._({
    required this.campaignId, required this.sceneId,
    required this.expectedRevision, required this.fingerprint,
    required this.choiceId, required this.label, required this.score,
  });
  final String campaignId;
  final String sceneId;
  final int expectedRevision;
  final String fingerprint;
  final String choiceId;
  final String label;
  final double score;
}

class FreeTextPreview {
  FreeTextPreview({required this.error, required List<FreeTextProposal> offers})
      : offers = List.unmodifiable(offers);
  final String? error;
  final List<FreeTextProposal> offers;
  bool get canChoose => error == null && offers.isNotEmpty;
}

/// This low-level port is used by deterministic game-engine QA. Production
/// WorldPlayPage uses its existing asynchronous WorldLibraryGateway instead.
abstract class FreeTextCampaignPort {
  FreeTextCampaignHead read(String campaignId);
  bool commit({
    required String campaignId, required String choiceId,
    required int expectedRevision, required String actionId,
  });
}

class FreeTextActionGate {
  const FreeTextActionGate._();
  static const maxTextRunes = 320;
  static const maxSuggestions = 5;
  static final RegExp _unsafe = RegExp(
      r'[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]');
  static final RegExp _notWord = RegExp(r'[^a-z0-9а-я]+', unicode: true);
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static const _filler = <String>{
    'я', 'мне', 'хочу', 'пожалуйста', 'давай', 'попробую', 'попробовать',
    'можно', 'бы', 'могу', 'хотел', 'хотела', 'сейчас', 'потом', 'еще',
    'и', 'или', 'а', 'на', 'в', 'во', 'к', 'ко', 'с', 'со', 'это', 'эту',
    'этот', 'the', 'i', 'want', 'please', 'to', 'a', 'an', 'can',
  };
  static String _normalize(String raw) => raw.toLowerCase()
      .replaceAll('ё', 'е').replaceAll(_notWord, ' ').trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static Set<String> _words(String value) => _normalize(value).split(' ')
      .where((t) => t.isNotEmpty && !_filler.contains(t)).toSet();

  static bool _valid(FreeTextCampaignHead h) =>
      h.campaignId.trim().isNotEmpty && h.sceneId.trim().isNotEmpty &&
      h.revision >= 0 &&
      h.choices.map((c) => c.id).toSet().length == h.choices.length;

  /// Never executes a choice or sends text to a server.
  static FreeTextPreview preview(FreeTextCampaignHead head, String text) {
    if (!_valid(head)) {
      return FreeTextPreview(error: 'Некорректное состояние игры.',
          offers: const []);
    }
    if (text.trim().isEmpty || text.runes.length > maxTextRunes ||
        _unsafe.hasMatch(text)) {
      return FreeTextPreview(error:
          'Введите действие до 320 символов без управляющих знаков.',
          offers: const []);
    }
    if (head.isTerminal) {
      return FreeTextPreview(error: 'История завершена.',
          offers: const []);
    }
    final normalized = _normalize(text);
    final tokens = _words(text);
    if (normalized.isEmpty || tokens.isEmpty) {
      return FreeTextPreview(error: 'Не удалось выделить действие.',
          offers: const []);
    }
    final offers = <FreeTextProposal>[];
    for (final c in head.choices) {
      if (!c.enabled || c.label.trim().isEmpty) continue;
      final words = _words(c.label);
      final overlap = words.intersection(tokens).length;
      final exact = normalized == _normalize(c.label);
      if (!exact && overlap == 0) continue;
      offers.add(FreeTextProposal._(
        campaignId: head.campaignId, sceneId: head.sceneId,
        expectedRevision: head.revision, fingerprint: head.fingerprint,
        choiceId: c.id, label: c.label,
        score: exact ? 1.0 : overlap / (words.isEmpty ? 1 : words.length),
      ));
    }
    offers.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.choiceId.compareTo(b.choiceId);
    });
    return FreeTextPreview(
      error: offers.isEmpty
          ? 'Такой ход не разрешён текущим сценарием. '
            'Выберите доступное действие или переформулируйте запрос.'
          : null,
      offers: offers.take(maxSuggestions).toList(),
    );
  }


  /// Accept an untrusted AI choice ID ONLY when it is a real, currently
  /// enabled choice. The model never manufactures proposals or executes turns.
  /// Confirmation still re-reads the active SQLite campaign and revision.
  static FreeTextPreview previewAiChoice(
      FreeTextCampaignHead head, String playerText, String choiceId) {
    if (!_valid(head)) {
      return FreeTextPreview(
          error: 'Некорректное состояние игры.', offers: const []);
    }
    if (head.isTerminal) {
      return FreeTextPreview(error: 'История завершена.', offers: const []);
    }
    if (playerText.trim().isEmpty ||
        playerText.runes.length > maxTextRunes ||
        _unsafe.hasMatch(playerText) ||
        _words(playerText).isEmpty) {
      return FreeTextPreview(
          error: 'Некорректный текст игрового действия.', offers: const []);
    }
    final choices = head.choices.where((c) =>
        c.id == choiceId && c.enabled && c.label.trim().isNotEmpty).toList();
    if (choices.length != 1) {
      return FreeTextPreview(
          error: 'ИИ не нашёл допустимого хода в текущем сценарии. '
              'Выберите действие вручную.', offers: const []);
    }
    final choice = choices.single;
    return FreeTextPreview(error: null, offers: [
      FreeTextProposal._(
        campaignId: head.campaignId,
        sceneId: head.sceneId,
        expectedRevision: head.revision,
        fingerprint: head.fingerprint,
        choiceId: choice.id,
        label: choice.label,
        score: 0.0,
      ),
    ]);
  }

  /// Must be checked AGAIN immediately before a real SQLite transaction.
  /// No user text, AI proposal, translated label or parser result is used
  /// as an executable story_core choice ID.
  static void validate({
    required FreeTextCampaignHead current,
    required FreeTextProposal proposal,
    required String actionId,
    required bool userConfirmed,
  }) {
    if (!userConfirmed) {
      throw const FormatException('Игрок не подтвердил действие.');
    }
    if (!_id.hasMatch(actionId)) {
      throw const FormatException('Неверный идентификатор хода.');
    }
    if (!_valid(current) || current.isTerminal ||
        current.campaignId != proposal.campaignId ||
        current.sceneId != proposal.sceneId ||
        current.revision != proposal.expectedRevision ||
        current.fingerprint != proposal.fingerprint ||
        current.choices.where((c) => c.id == proposal.choiceId &&
            c.label == proposal.label && c.enabled).length != 1) {
      throw const FormatException(
          'Игра изменилась или действие больше недоступно. '
          'Обновите предложения перед ходом.');
    }
  }

  /// Synchronous store adapter for engine unit tests. The actual Flutter
  /// screen calls WorldLibraryGateway.choose on an isolate-backed store.
  static bool confirm({
    required FreeTextCampaignPort port,
    required FreeTextProposal proposal,
    required String actionId,
    required bool userConfirmed,
  }) {
    validate(current: port.read(proposal.campaignId),
        proposal: proposal, actionId: actionId,
        userConfirmed: userConfirmed);
    return port.commit(
      campaignId: proposal.campaignId, choiceId: proposal.choiceId,
      expectedRevision: proposal.expectedRevision, actionId: actionId,
    );
  }
}
