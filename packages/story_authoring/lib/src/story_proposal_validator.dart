import 'dart:convert';

import 'narrative_book_model.dart';
import 'story_dilemma_preview.dart';
import 'story_plan_dilemma_generator.dart';

/// One pure-Dart, provider-neutral boundary for proposed plot branches.
/// Use it for Z.ai, a local model, imported JSON or a manual editor.
/// The reply can NEVER attest CANON, install a .bworld or change SQLite.
class StoryProposalValidator {
  const StoryProposalValidator._();

  static const _fields = {
    'applicable', 'setup_event_id', 'outcome_event_id',
    'kind', 'dilemma', 'accept_intent', 'refuse_intent',
    'followup_goal', 'finish_original_intent', 'original_ending',
    'alternative_search_goal', 'search_intent',
    'alternative_discovery', 'use_discovery_intent', 'alternative_ending',
  };

  static ZaiStoryDilemmaPreview validate({
    required NarrativeBookModel book,
    required List<NarrativeEvent> allowedEvents,
    required Map<String, dynamic> proposedJson,
  }) {
    if (allowedEvents.length < 2 || allowedEvents.length > 8 ||
        !book.analysisComplete ||
        book.events.length < 2) {
      throw const FormatException('Нет двух проверяемых цитат для модели');
    }
    var last = -1;
    final known = {for (final e in book.events) e.id: e};
    final granted = <String>{};
    for (final item in allowedEvents) {
      final original = known[item.id];
      if (original == null ||
          original.source.quote != item.source.quote ||
          original.source.chunkId != item.source.chunkId ||
          original.source.startUtf16 != item.source.startUtf16 ||
          item.narrativePosition <= last ||
          !granted.add(item.id)) {
        throw const FormatException(
            'Цитаты не совпадают с конкретной редакцией книги');
      }
      last = item.narrativePosition;
    }
    if (proposedJson['applicable'] == false &&
        proposedJson.length == 1) {
      return ZaiStoryDilemmaPreview(
        proposal: null, plan: null, sampledEventCount: allowedEvents.length,
      );
    }
    if (proposedJson.length != _fields.length ||
        !proposedJson.keys.toSet().containsAll(_fields) ||
        proposedJson['applicable'] != true) {
      throw const FormatException('Нарушен контракт ответа модели');
    }
    if (!granted.contains(proposedJson['setup_event_id']) ||
        !granted.contains(proposedJson['outcome_event_id'])) {
      throw const FormatException('Событие вне разрешённых цитат');
    }
    final sourceData = <String, dynamic>{
      'format': StoryDilemmaProposal.format,
      'status': 'UNREVIEWED_PROPOSAL',
      'source_fingerprint': book.sourceFingerprint,
      for (final field in _fields)
        if (field != 'applicable') field: proposedJson[field],
    };
    final proposal = StoryDilemmaProposal.decode(jsonEncode(sourceData));
    final plan = StoryPlanDilemmaGenerator.propose(book, proposal);
    return ZaiStoryDilemmaPreview(
      proposal: proposal, plan: plan,
      sampledEventCount: allowedEvents.length,
    );
  }
}
