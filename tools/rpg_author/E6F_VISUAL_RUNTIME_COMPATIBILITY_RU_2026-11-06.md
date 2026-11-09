# E6f+ — проверка совместимости AI Story RPG с процедурными пиксельными сценами и лёгкой анимацией

Дата: 2026-11-06. Статус: **архитектурный аудит; реализации и E2E ещё нет**.
Проверенный основной `main`: `a19f7ea5851a60a1ab174d2b0f7939c89cbe9708` (PR #122).
Основание: поручение сохранить текущий движок и обеспечить будущую воспроизводимость текстовых, статичных пиксельных и слегка анимированных сцен, создаваемых **кодом**, без готовых/ИИ-сгенерированных картинок.

## Итог

Никакой новый gameplay-runtime не нужен. Нужен независимый, строго ограниченный **presentation runtime**. `story_engine` продолжает выбирать переходы, `story_core` остаётся единственным авторитетом по эффектам и событиям, `story_runtime_adapter` проверяет согласованность, `campaign_manager` сохраняет подтверждённые события. Визуальная подсистема читает состояние и **не вызывает `choose` сама**.

Основное приложение — read-only для текущей ветки внешнего генератора. Документ не разрешает изменять `apps/`, `packages/`, `tools/bookworld/`, `main` или общий CI.

## Проверка существующей реализации

| Файл/класс | Что подтверждено | Чего для визуального исполнения не хватает |
|---|---|---|
| `packages/story_core/lib/src/engine.dart`, `StoryWorld`, `WorldEvent` | `sceneId`, `choiceId`, `nextSceneId`, `actionId`, `before/afterStateHash`; детерминированный replay без часов | Ничего менять ради анимации не требуется |
| `packages/story_core/lib/src/world_state.dart` | Неизменяемое состояние: сцена, ревизия, время, флаги, предметы, знания | Нет графических параметров — это намеренно правильно |
| `packages/story_runtime_adapter/lib/story_runtime_adapter.dart`, `StoryEngineCoordinator` | `story_engine` и `story_core` синхронизируются до принятия перехода | Не передавать художнику прямой доступ к runtime |
| `packages/campaign_manager/lib/campaign_manager.dart` | Атомарные SQLite event/head, replay при загрузке, `.bwsave` | Никакого нового обязательного поля для анимаций в игровых сохранениях |
| `apps/story_reader/lib/world_library_gateway.dart`, `WorldGameView` | `sceneId`, `revision`, `tick`, `inventory`, `flags`, `knownFacts`, `choices`, `journal` | Нет `worldHash/blueprintHash` в DTO и нет точного `lastCommittedChoiceId/WorldEvent.hash` на UI |
| `apps/story_reader/lib/world_play_page.dart` | Действительный выбор через `gateway.choose`, экран обновляется только после commit | Нужен необязательный визуальный слой, 3 режима и post-commit cue |
| `apps/story_reader/lib/scene_dialogue_stage.dart` | Текстовый parser даёт последовательность реплик/авторов и device-local позицию по campaign/scene/revision | Нет устойчивого `turnId`, стабильного `characterId`, callback при смене реплики; parser включается только при >=2 репликах от >=2 авторов |
| `apps/story_reader/lib/book_model.dart` | Уже объявлены `GameMediaRole`, `SpoilerPolicy`, `SceneMediaBinding` | Это пока image-oriented предложение, не контракты procedural recipe |
| `apps/story_reader/lib/draft_scene_graph_overview.dart` | Есть структурная проверка графа черновика и ссылок; `draft_scene_graph_panel.dart` показывает список и переходы | Не полноценный визуальный редактор, не рендер игрового мира |
| `apps/story_reader/lib/narrative_book_model.dart` | Есть source-locked события, claim, character mention group, chapter/chronology uncertainty | `mention_group_id` не означает уже подтверждённый `world_actor_id`; визуализацию нельзя строить на необоснованном совпадении имён |
| `tools/bookworld/private_rich_bookworld.py`, Dart importer | v3 строго 4 ZIP элемента и точные формы JSON | Нельзя молча вложить `scene_visuals.json` или произвольный source/model код |

## Предлагаемый интерфейс (ТОЛЬКО проектный, не действующий)

```text
source-anchored book graph
  -> independently reviewed story blueprint
  -> validated procedural scene recipe sidecar
  -> VisualRecipeValidator (source/world/scenes/actors/choices/turn IDs)
  -> VisualSceneController(snapshot + transition + dialogue beat + UI preferences)
  -> PixelPrimitiveRenderer (Flutter CustomPainter/Canvas)
  -> optional future Flame host for more complex timelines
```

**Чистые данные, а не исполняемые куски программ.** Генератор выдаёт `procedural_visuals_v1` с ограниченными `archetype`, `palette`, `seed`, `layer`, `pose`, `action`, `cue`, `duration_ms`; renderer знает конечный набор допустимых опкодов. Не разрешать Python/Dart/JS во входном рецепте, процедурные скрипты/шейдеры или произвольные выражения.

Минимальный будущий DTO:
- `VerifiedVisualBundle(world_archive_sha256, blueprint_sha256, source_fingerprint, story_sha256, renderer_version, recipe_hash)`;
- `SceneRecipe(scene_id, seed, backdrop, layers, actorInstances, props, cues)`;
- `ActorVisual(character_id, archetype, appearance_seed, appearance_properties, anchor, initial_pose)`;
- `VisualCue(trigger, target_id, action, duration_ms, revision_scope)`;
- `VisualFrame(scene_id, revision, object_poses, prop_visibility)`.

Точные типы и версии утвердить и проверить Python/Dart независимо перед реализацией.

## Три режима одного игрового процесса

`text`: весь текущий Flutter UI, нет анимационных циклов.
`pixels_static`: воспроизведение детерминированного базового кадра из того же recipe; никакого tick loop.
`pixels_animated`: тот же базовый кадр + лёгкие code-only движения (`idle,blink,talk,turn,appear,move,give,react,water,rain`).
Мод переключается без `story_core.choose`, не изменяет revision, world hash, save или журнал; при отсутствии renderer/recipe fallback -> text. Учитывать системную настройку reduced motion.

## Доставка событий и правильная последовательность

1. После `gateway.load`: валидировать sidecar по точному `world_archive_sha256` и `blueprint_sha256`; реконструировать композицию только из текущего `WorldGameView`. **Не проигрывать повторно старые choice animations**.
2. При смене реплики: отдельный UI-only callback `onVisibleBeat(beatKey, speakerId?)` от `DialogueStage`; `beatKey` проверяется против того же текста сцены/его sha. Пока parser не имеет устойчивых `turn_id`/ID персонажа, не считать имя надёжной identity. Одноголосые сцены должны продолжать работать без animation cue.
3. При клике: `WorldPlayPage` сначала вызывает текущий `gateway.choose` с `expectedRevision`. **Только при `result.applied=true`, `duplicate=false`, и увеличении ревизии** визуальный контроллер получает подтверждённый `VisualTransition`. При denial/stale/duplicate нельзя создавать новый эффект.
4. Transition cue относится к точному `from_scene_id + choice_id + to_scene_id + committed_revision`. В первой версии показывать entry/reaction в новой сцене. Для более сложной последовательности прежней сцены потребуется отдельный read-only before/after view и очень короткий cancelable presentation bridge.
5. При быстром повторном выборе/новой загрузке/переключении режима/закрытии приложения: отменить устаревшие анимации, не применять их к другой ревизии. Никаких `StoryWorld.apply` внутри renderer.
6. Возобновление: игровой state + deterministic recipe -> корректный устойчивый кадр, не повтор «получения» предмета. Анимация эфемерна; её exact ms/позиция не обязательны для игрового save. Для возобновления страницы диалога использовать существующий `DialoguePositionStore`, не создавать дублирующий игровой state.

`WorldGameView` сейчас выдаёт факты только для `player`. Показывать NPC-спойлеры/знания запрещено; если в дальнейшем нужны знания NPC, получать только отдельно подтверждённую и авторизованную проекцию. Рецепт, составленный по книге, не может открывать скрытые игровые факты через визуальные элементы.

## Где разместить изменения при отдельном разрешении на основной код

- В `packages/` (новый отдельный чистый пакет `procedural_scene_core` или аналог): типизированная schema, validator, state-to-frame, cue scheduling, deterministic geometry, test. **Без зависимостей от Flutter, SQLite, story_engine**.
- В `apps/story_reader/lib/` — `visual_scene_widget.dart`, `procedural_pixel_painter.dart`, `visual_scene_controller.dart`, адаптер `WorldGameView` и три режима. `WorldPlayPage` остаётся точкой монтажа поверх/рядом с диалогами.
- `WorldLibraryGateway`: добавить read-only `archiveHash`/идентификатор правил и структурированный результат успешного перехода; избегать дублирования state в UI. При необходимости `DialogueStage` — только UI callback с `turnKey` на проверенный текст.
- `tools/rpg_author/`: генератор визуальных recipe на основании проверенных персонажей/событий и точных source цитат; протокол validator и отдельный отчёт `visual_coverage`/невоспроизводимые события.
- `tools/bookworld` / `packages/bookworld_format`: **не трогать v3**. Сначала optional приватный sidecar, привязанный к exact world archive hash; переносимость и embedded format только отдельной согласованной версией с независимыми проверками.

## Renderer: технический выбор

Сначала Flutter `CustomPainter` + `Canvas`/repaint `Listenable` для ограниченного набора 2D фигур и 5-10 простых анимаций. `Flame GameWidget` нужен только если реальные тесты докажут потребность в component tree/effects/camera. Его `GameWidget` можно встраивать в существующий Flutter UI; `CameraComponent.withFixedResolution` обеспечивает логическую область и не управляет `story_core`. Не использовать `SpriteAnimationComponent` с загружаемыми PNG для кода-only проекта. Стабильные логические координаты, целочисленная пиксельная сетка, отсутствие сглаживания. Статические слои кэшировать в памяти, группировать примитивы, не рисовать тысячи одиночных rectangles каждый кадр. Не обещать побитово идентичные GPU-пиксели разных ОС; сравнивать детерминированные команды/состояния и визуальные golden с допустимым порогом.

## Проверки перед приёмкой

1. Baseline: действующий `.bworld v3` и `.bwsave` работают без побочных изменений, все старые tests/storycore и Flutter widget tests зелёные.
2. `text` не создаёт render loop; `pixels_static` без animations; `pixels_animated` короткие timed cues без freeze в диалогах.
3. Одна кодовая сцена «пруд, принцесса, лягушонок, мяч» строится **без готовой графики**, работает офлайн на Windows и Android; при двух загрузках consistent actor appearance и base visual state.
4. Старое сохранение без sidecar -> текст. Новый sidecar другой книги/сценария/версии/seed/повреждённый -> reject sidecar, игра продолжает работать.
5. Denied/stale/duplicate choice -> никакой новой transition animation; committed выбор -> одна анимация, верный `choiceId`; закрытие посередине -> восстановление корректного final frame.
6. Результат изменения предмета берётся из world state (а не из закончившегося жеста). Не показывать скрытых героев/места/предметы раньше разрешённого состояния.
7. Быстрые переходы, `DialogueStage` resume, ветвление кампании, поворот экрана/resize, отсутствие фокуса, reduced motion, Android ограничения памяти/CPU/battery.
8. Python validator и Dart validator отвергают unknown `action`, слишком большие `duration_ms`, excessive actors/objects/layers, неправильные ID, вызовы произвольного кода.
9. Реальные Windows/Android E2E и сравнение фактического FPS/памяти выполнить; **нельзя** считать их пройденными из одного audit документа.

## Не делать сейчас

Не переписывать `story_engine` и `story_core`; не менять формат `.bwsave`; не смешивать анимацию с транзакционным движком; не выдавать код генератора за готовый renderer. Не задерживать E6e завершение/QA литературной игры ради процедурных сцен. Сначала проверить одну реальную процедуру end-to-end без картинок и оценить читаемость; после этого масштабировать библиотеки форм и движений.

## Связанные материалы

- `tools/rpg_author/PROCEDURAL_PIXEL_SCENES_RU.md` — исходное решение о code-only сценах.
- Flame: https://docs.flame-engine.org/latest/flame/game_widget.html
- Flame Camera: https://docs.flame-engine.org/latest/flame/camera.html
- Flutter CustomPainter: https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
