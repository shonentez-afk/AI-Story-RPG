import 'quick_rpg_builder.dart';
import 'reviewed_hero_role.dart';

/// What the user actually asked the authoring pipeline to create.
enum RpgCreationRoute { shortOffline, reviewedBookwide }
enum RpgCreationPlot { sourceExcerptRoute, alterFate, canon, freeWorld }
enum RpgCreationInteraction { fixedChoices, aiFreeform }
enum RpgCreationHero { freePlayer, reviewedCharacterIdentity }

/// Versioned, portable *intent*, not a declaration that a game already
/// exists. A source character is a verified player identity/flag, NOT full
/// NPC-memory transfer or runtime BOOK_CHARACTER mode support.
final class RpgCreationIntent {
  const RpgCreationIntent({
    required this.route, required this.plot,
    this.interaction = RpgCreationInteraction.fixedChoices,
    this.hero = RpgCreationHero.freePlayer,
  });

  const RpgCreationIntent.quickFollow()
      : route = RpgCreationRoute.shortOffline,
        plot = RpgCreationPlot.sourceExcerptRoute,
        interaction = RpgCreationInteraction.fixedChoices,
        hero = RpgCreationHero.freePlayer;
  const RpgCreationIntent.quickAlterFate()
      : route = RpgCreationRoute.shortOffline,
        plot = RpgCreationPlot.alterFate,
        interaction = RpgCreationInteraction.fixedChoices,
        hero = RpgCreationHero.freePlayer;
  const RpgCreationIntent.reviewedAlterFate({
    this.hero = RpgCreationHero.freePlayer,
  }) : route = RpgCreationRoute.reviewedBookwide,
       plot = RpgCreationPlot.alterFate,
       interaction = RpgCreationInteraction.fixedChoices;

  final RpgCreationRoute route;
  final RpgCreationPlot plot;
  final RpgCreationInteraction interaction;
  final RpgCreationHero hero;

  static const format = 'ai_story_rpg_creation_intent_v1';
  Map<String, Object?> toJson() => {
    'format': format,
    'route': route.name, 'plot': plot.name,
    'interaction': interaction.name, 'hero': hero.name,
  };

  factory RpgCreationIntent.fromJson(Map<String, dynamic> row) {
    if (row.length != 5 ||
        row.keys.toSet().difference({
          'format', 'route', 'plot', 'interaction', 'hero'
        }).isNotEmpty || row['format'] != format) {
      throw const FormatException('Некорректная версия настроек RPG.');
    }
    try {
      if (row.values.any((v) => v is! String)) {
        throw const FormatException('Некорректные настройки RPG.');
      }
      return RpgCreationIntent(
        route: RpgCreationRoute.values.byName(row['route'] as String),
        plot: RpgCreationPlot.values.byName(row['plot'] as String),
        interaction: RpgCreationInteraction.values
            .byName(row['interaction'] as String),
        hero: RpgCreationHero.values.byName(row['hero'] as String),
      );
    } on ArgumentError {
      throw const FormatException('Неизвестный игровой режим RPG.');
    }
  }

  QuickRpgMode get quickMode {
    if (route != RpgCreationRoute.shortOffline ||
        interaction != RpgCreationInteraction.fixedChoices ||
        hero != RpgCreationHero.freePlayer) {
      throw const FormatException('Это не режим короткой офлайн-игры.');
    }
    return switch (plot) {
      RpgCreationPlot.sourceExcerptRoute => QuickRpgMode.followBook,
      RpgCreationPlot.alterFate => QuickRpgMode.changeFate,
      _ => throw const FormatException(
          'Литературный CANON и свободный мир ещё недоступны.'),
    };
  }
}

/// Capability snapshot shared by Flutter, CLI and future HTTP clients.
final class RpgCreationDecision {
  const RpgCreationDecision(this.supported, this.explanation, {
    required this.canPlayWithoutNetwork,
    required this.isFullLiteraryCanon,
    required this.isDynamicAiMaster,
    required this.requiresFurtherReview,
  });
  final bool supported;
  final String explanation;
  final bool canPlayWithoutNetwork, isFullLiteraryCanon;
  final bool isDynamicAiMaster, requiresFurtherReview;

  void requireSupported() {
    if (!supported) throw FormatException(explanation);
  }
}

/// Executable modes only: never silently convert CANON, FREE_WORLD or
/// AI_FREEFORM into a short fictional branching demo. Source quotes alone
/// do NOT verify in-world causality, a book character's secret knowledge,
/// or fidelity of new prose to the original book.
abstract final class RpgCreationPolicy {
  static RpgCreationDecision inspect(RpgCreationIntent intent, {
    String? sourceFingerprint,
    ReviewedHeroRole? reviewedHero,
  }) {
    RpgCreationDecision decision(bool ok, String reason) =>
        RpgCreationDecision(ok, reason,
          canPlayWithoutNetwork: ok,
          isFullLiteraryCanon: false,
          isDynamicAiMaster: false,
          requiresFurtherReview: true);
    if (intent.plot == RpgCreationPlot.canon) {
      return decision(false, 'CANON недоступен: события, хронология, '
          'мотивы и причинность всей книги ещё не доказаны.');
    }
    if (intent.plot == RpgCreationPlot.freeWorld) {
      return decision(false, 'Самостоятельная генерация нового мира '
          'пока не поддерживается проверенным компилятором.');
    }
    if (intent.interaction != RpgCreationInteraction.fixedChoices) {
      return decision(false, 'Свободный ИИ-мастер не реализован: '
          'возможен только выбор уже проверенного игрового действия.');
    }
    if (intent.route == RpgCreationRoute.shortOffline) {
      if (intent.hero != RpgCreationHero.freePlayer) {
        return decision(false, 'Короткая игра не переносит проверенные '
            'карточки героев. Выберите полную редакторскую подготовку.');
      }
      return decision(true, intent.plot == RpgCreationPlot.sourceExcerptRoute
          ? 'Короткая игра по выбранным цитатам в порядке книги. '
              'Раннее завершение возможно; это не CANON.'
          : 'Короткая игра по цитатам с вымышленными развилками. '
              'Это не полная адаптация книги.');
    }
    if (intent.plot != RpgCreationPlot.alterFate) {
      return decision(false, 'Поактовый компилятор поддерживает '
          'только проверенную частную ALTER_FATE-адаптацию.');
    }
    if (intent.hero == RpgCreationHero.reviewedCharacterIdentity) {
      if (reviewedHero == null || sourceFingerprint == null ||
          reviewedHero.sourceFingerprint != sourceFingerprint ||
          reviewedHero.confirmedMentions.isEmpty) {
        return decision(false, 'Нужна подтверждённая карточка героя '
            'с постоянным character_id из той же редакции книги.');
      }
    } else if (reviewedHero != null) {
      return decision(false, 'Нельзя незаметно заменить свободного '
          'игрока персонажем книги.');
    }
    return decision(true, 'Поактовая частная ALTER_FATE-адаптация '
        'с редакторской приёмкой. Реальный литературный CANON не заявлен.');
  }
}
