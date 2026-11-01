/// M1.6 pilot game state. Recorded by stable choice IDs, not by UI labels.
class GameProgress {
  const GameProgress({this.courage = 0, this.insight = 0, this.items = const []});
  final int courage;
  final int insight;
  final List<String> items;

  static const itemNames = <String, String>{
    'letter': 'Старое письмо',
    'key': 'Латунный ключ',
    'map': 'План особняка',
  };

  GameProgress apply(String choiceId) {
    var nextCourage = courage;
    var nextInsight = insight;
    final nextItems = [...items];
    void collect(String id) {
      if (!nextItems.contains(id)) nextItems.add(id);
    }
    switch (choiceId) {
      case 'enter':
        nextCourage++;
      case 'inspect_letter':
        nextInsight++;
        collect('letter');
      case 'search_drawer':
        nextInsight++;
        collect('key');
      case 'take_map':
        nextInsight++;
        collect('map');
      case 'unlock_cellar':
        nextCourage++;
      case 'open_secret':
        nextInsight++;
      case 'face_shadow':
        nextCourage++;
    }
    return GameProgress(
      courage: nextCourage, insight: nextInsight, items: nextItems);
  }

  Map<String, dynamic> toJson() => {
    'courage': courage, 'insight': insight, 'items': items,
  };

  factory GameProgress.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (json['courage'] is! int || json['insight'] is! int ||
        rawItems is! List || rawItems.any((value) => value is! String)) {
      throw const FormatException('Invalid RPG progress');
    }
    return GameProgress(
      courage: (json['courage'] as int).clamp(0, 1000000),
      insight: (json['insight'] as int).clamp(0, 1000000),
      items: rawItems.cast<String>().where(itemNames.containsKey).toSet().toList(),
    );
  }
}
