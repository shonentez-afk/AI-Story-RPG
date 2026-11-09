> **Актуализация 9 ноября 2026:** этот файл — исторический аудит, отдельные старые лимиты и дефекты после него могли измениться. Приоритет у [полного плана независимого движка и multi-client API](RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md), где зафиксированы E6k+ / 0.3.0a12, факты v4 (203 сцены), CI #1082, недостающие CANON/BOOK_CHARACTER/AI_FREEFORM и адаптер другого типа клиента. Не повторять устаревшую стадию E6g.

# AI Story RPG — полный архитектурный аудит автономности RPG

Дата: 8 ноября 2026. Реализация в **единственном Draft PR #133**, основная ветка и параллельный E6d не меняются.

## Ответ на главный вопрос

**Игровая RPG-логика теперь находится в чистых Dart-пакетах**, а не в
Flutter-приложении. Это не один гигантский файл, а один исполняющий движок
(`story_core` + `story_runtime_adapter` + `campaign_manager` +
`rpg_gameplay`) и один независимый сценарный конвейер (`story_authoring` +
`bookworld_format`). Клиент может подключить эти пакеты без Flutter,
Android UI, Windows UI, Z.ai и приватных книг пользователя. Командный
пример запускает готовый `.bworld`, выполняет RPG-ходы и восстанавливает
SQLite и `.bwsave` без приложения.

Это **не** означает, что уже реализована полностью автоматическая
каноническая RPG по любой книге или динамический AI-GM. Авторство
произвольных сюжетов и CANON/ALTER_FATE требуют отдельной приёмки.

## Полная карта движка

| Пакет | Единственная ответственная реализация |
|---|---|
| `story_core` | Детерминированные переходы, знания, условия, предметы, постоянные ID и причинность |
| `story_runtime_adapter` | Связь с `story_engine` без второго источника правил |
| `bookworld_format` | Проверяемый `.bworld`, rich scene/NPC dialogue, социальные и предметные контракты |
| `campaign_manager` | Настоящие SQLite-кампании, идемпотентные решения, перезапуск, переносимый `.bwsave` |
| `rpg_gameplay` | Всё пользовательское RPG-состояние и операции: герой, сцена, выборы, блокировки, журнал, память/отношения NPC, имена и видимость, владельцы предметов, идентификаторы говорящих, свободный ввод и проверка старой ревизии |
| `story_authoring` | Импорт и индексирование FB2/TXT; выбор отдельной сказки; события, персонажи, акты, альтернативы, причинные последствия; NPC-персонажи, диалоги, предметы/знания; проверка источника, вариантов сюжета, достижимости; одобренная компиляция `.bworld` |

### Что именно вынесено из приложения

- `WorldGameView` и модели действий, NPC и журнала, ранее жившие в
  `apps/story_reader/lib/world_library_gateway.dart` (сотни строк).
  Публичный API и построение verified-состояния сейчас в
  `packages/rpg_gameplay/lib/rpg_gameplay.dart`. Flutter gateway оставлен
  только для пути SQLite, открывания хранилища и выполнения isolate.
- `FreeTextActionGate` и `FreeTextWorldGatewayPort`: предложение
  разрешённого хода, подтверждение игрока, проверка ревизии и атомарное
  исполнение находятся в `rpg_gameplay`, без модели или сети.
- `QuickRpgBuilder`, full-book сценарные/предметные проверки,
  `GameplayCandidateReachabilityAuditor`,
  `ReviewedGameplayCompiler`, `NpcCampaignConsequences`,
  `NpcInventoryWritingContext`, `SourceLockedDialogueSpeakerAudit`,
  `NpcWritingCatalog`, `NpcWritingSession`,
  `NpcWritingDraftRules`, `NpcWritingRequest` и выбор героя
  перенесены в `story_authoring`.
- `ZaiCrossWindowEvidenceGraph`, `ZaiEditorialConsistencyNotebook`,
  `ZaiSourceSceneBoard`, `ZaiCausalChoiceNotebook`,
  `ZaiM2cSourceBridge`, `ZaiPrivateCompilationDraft`, независимая
  `ZaiPrivateBookworldCompilation.compile` и ручная
  `ZaiManualSourceAlignment` — теперь **проверяемые локальные Dart-модели
  и компиляторы**, а не зависимые от Flutter функции.
- Старые `GameProgress`, `GameSaveRecord`,
  `PilotSaveCodec`, `SceneDialogueScript` вынесены в `rpg_gameplay`
  только для прежних прохождений и диалогового UI.
  `ai_story_pilot_bwsave_v1` **не заменяет** современный `.bwsave` v2.
- Все старые импорты Flutter сохранены как совместимые `export`
  или узкие платформенные адаптеры; **второй экземпляр правил не создан**.

### Что осознанно осталось в клиенте

`DeviceWorldLibraryGateway` выбирает путь к приватной SQLite и запускает
isolate; `FileSourceAnalysisCheckpointRepository` хранит checkpoint на
устройстве и реализует headless `SourceAnalysisCheckpointRepository`;
`NpcWritingStore` и `NpcCampaignHeroStore` выполняют только файловые
чтения, транзакционную сериализацию и защиту от конфликтов редакций.
`ZaiPrivateBookworldCompilation.installConfirmed` лишь запрашивает
явное подтверждение установки и вызывает игровой шлюз.

`ai_connection.dart`, `zai_semantic_preview.dart` и связанные
`Zai*Service` остаются опциональными адаптерами HTTP/ключа/согласия;
`scene_dialogue_stage.dart`, `world_play_page.dart`,
`local_dialogue_portraits.dart` и `world_backup_actions.dart` —
только Flutter-представление, локальные PNG, выбор файла и UI. Подписанные
переходы и смысловое утверждение книги не должны выводиться из этих файлов.

`private_game_readiness.dart` — локальная проверка наличия уже
установленного мира по исходному fingerprint для отображения CTA. Она не
играет ход, не генерирует канон, не меняет состояние RPG; защищённая
проверка `.bworld` выполняется прежним импортером.

## Самостоятельный запуск и испытания

```sh
cd packages/rpg_gameplay
dart pub get
dart analyze
dart test --reporter expanded
dart run example/standalone_gameplay.dart ../../artifacts/bookworld/book_private_rich_items_python.bworld
```

Сам тестовый BookWorld предварительно собирается штатным инструментом в
M1.7 CI. Пример обязан пройти: запрет закрытого выбора, разрешённый ход,
социальное событие NPC, выдачу и передачу карты, журнал, stale-revision,
закрытие/открытие SQLite и перенос `.bwsave`.

`packages/story_authoring/test/headless_*.dart` независимо проверяют
аналитику источников, редакторские факты, сцены, причинность NPC и ручную
привязку цитат **без Flutter и без Z.ai**. Модели AI-предложений проходят
тот же source-review gate и не получают права исполнять команды.

`tools/ci_check_engine_boundaries.py` — обязательный архитектурный gate
для **шести** Dart-пакетов: не допускает импортов из Flutter/app,
запрещённых зависимостей и циклической платформенной связи.

## Статус приёмки на текущем коде

Кодовый HEAD для этого этапа: `480c0e448a818e624809936a7c7485683c5a4adc`.

[AI Story RPG CI #42497799413](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42497799413)
— exact-head проверка кода **ещё выполняется на момент написания**.
Python reference/Dart/M1.7/Flutter/Windows/Android отмечать SUCCESS
**только после подтверждения соответствующих jobs и артефактов**.
Предыдущие прогоны выявили только ошибки новых assertion в headless
SQLite-тесте; тест скорректирован без изменения игровых правил.

**До полного релиза открыто:** две разные реальные русские FB2 должны
пройти не только source-index/анализ/Resume, но и подтверждённые
литературные акты/роль/NPC/прохождение, полный CANON/ALTER_FATE,
разрешённое свободное AI-взаимодействие, согласованный live Z.ai,
физический UX Windows/Android, backup/restore и accessibility.
Issue #118 оставить открытым, PR #133 Draft. E6d отдельный проектный
контракт, не менять без согласования.

## Архитектурная ревизия 9 ноября 2026 (PR #133)

Семь независимых Dart-пакетов составляют 2 headless подсистемы:
1. Исполнение `story_core` / `story_runtime_adapter` /
   `bookworld_format` / `campaign_manager` / `rpg_gameplay`.
2. Книжное авторство `story_authoring`, доступ к обоим через
   `rpg_api`. Сетевые сервисы остаются адаптерами, не ядром.

Отдельный `apps/rpg_cli` — доказательный второй клиент через API.
Модульные и sqlite/replay/save CLI тесты прошли M1.7 в
[CI #42513354448](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42513354448)
на exact code SHA `bce9becab8a88d57a01cc4a46c968aca1f1238f7`.
Flutter остаётся первым клиентом с файлами, GUI, Android/Windows,
показом реплик, consent и необязательным HTTP adapter.

**Точная оценка автономности:** исполнение завершено в рамках Dart VM
без Flutter и ИИ; автономный сценарный анализ и проверенная сборка
существуют, но полный самообслуживаемый "любая длинная книга → CANON RPG"
остаётся неготовым. Web не готов из-за `dart:io`/SQLite;
AI-freeform не создаёт произвольные действия мира.
