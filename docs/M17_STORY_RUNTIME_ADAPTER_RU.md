# M1.7.2 — координатор story_engine ↔ story_core

**Базовый HEAD:** `2d779839c26f91146bdad63f1b3afaf7b87b97a2` (M1.7.1). GitHub Actions `41336338177` подтверждён как **SUCCESS**: Python/Dart, новые тесты ядра, 71 Flutter widget tests, Windows portable и Android debug APK.

## Цель и граница

Выполнить требования ADR-001 и FR-ENG-05/06: сохранить `story_engine:0.1.0-alpha.1` выбранным **сценарным навигатором**, а `story_core` — единственным владельцем фактов, предметов, характеристик, знания NPC и журнала подтверждённых ходов.

**Текущая пользовательская RPG M1.6 не переключена на координатор.** Это намеренно: старые сохраняемые `GameProgress`, `rulesVersion=0/1`, `CampaignStore`, `SaveStore` и экспортируемые `.bwsave` зависят от прежнего пилотного сценария и несовместимы с `manor_m17_original_demo`. Их перенос без полноценной миграции недопустим.

## Реализовано

- Новый чистый Dart-пакет `packages/story_runtime_adapter`, `StoryRuntimeAdapter` + `StoryEngineCoordinator` + `RuntimeChoice`. Только `story_engine` (основной runtime) и `story_core` (авторитетное состояние), без Flutter/LLM/Python/сервера.
- **Чтение контрактов:** оригинальный JSON blueprint M1.7.1 компилируется в `StoryProject` с теми же scene/choice IDs; `StoryValidator.validate` проверяет проект до запуска; terminal scene использует `StoryTerminalTransition` при Continue. Никакие rules/knowledge не переносятся во внутреннее состояние story_engine.
- **Кандидаты без побочных эффектов:** `StoryWorld.fork` создаёт изолированную копию immutable state и журнала. `StoryEngine.restore` создаёт независимый сценарный runtime из текущего snapshot. Сначала core проверяет условия, эффекты, expectedRevision и идемпотентность; затем scenario engine применяет выбор в своей копии. Сверяется `nextSceneId`. Только после обеих проверок меняются ссылки активного координатора на проверенные копии, без `await` между ними.
- **UI-готовый список:** `choices` содержит реальные scene/choice IDs, подписи и `lockReason` из core. Кнопки нельзя считать доступными на основании одного story_engine.
- **Повтор/отказ:** одинаковый action_id не добавляет второй ход; повтор с другим выбором под тем же ID — ошибка; отказ проверки или ошибки перехода не затрагивают live world/navigation.
- **Проверяемое восстановление:** `checkpoint()` выдаёт versioned `ai_story_bridge_checkpoint_v1` **только в памяти**: book_id, blueprint_sha256, revision, state_sha256, head_event_sha256, событийный журнал. `restore()` строго проверяет поля и лимит событий (не более 2000), весь core event log/все SHA, ожидаемый head; после этого воспроизводит каждый переход на настоящем story_engine и сверяет hash/scene ID. Не использует непрозрачный engine snapshot как авторитетный мир.
- CI job `story-core` дополнен проверкой нового пакета (`dart pub get`, `dart analyze`, `dart test`). Android и Windows **уже зависят** от успешности этого job. Старые 71 Flutter-тест и прежние проверки M0 остаются обязательными.

## Автоматические сценарии

`packages/story_runtime_adapter/test/story_engine_coordinator_test.dart`:
1. Инициализация выбранного runtime, сверка четырёх доступных действий, блокировка двери без ключа.
2. **35 подтверждённых ходов** через настоящий `story_engine` с побайтно одинаковыми hash/scene относительно независимого `StoryWorld`; промежуточный checkpoint после 23 ходов, восстановление и продолжение до финала, roundtrip.
3. Недоступные действия и несуществующие выборы не меняют движок, предметы и журнал.
4. Повтор action_id идемпотентен; переиспользование для другой команды и устаревшая revision отклоняются.
5. Два эффекта, второй из которых проваливается, не применяют первый и не сдвигают навигацию.
6. Два прохождения независимы.
7. Checkpoint связан с точной редакцией blueprint.
8. Усечённый/изменённый журнал, неверный head hash или schema version отвергаются.
9. Пустое прохождение корректно восстанавливается.

Дополнительно: новый `StoryWorld.fork` и причина блокировки тестируются в `packages/story_core/test/story_world_test.dart`.

## Чего M1.7.2 ещё НЕ делает

- **Не меняет установленные приложения** в части пользовательских экранов/пилотных сохранений и не добавляет в библиотеку второй импорт/каталог.
- **Не является SQLite/Drift-транзакцией.** Атомарность гарантируется только для синхронного перехода в памяти одного isolate, без crash-recovery и без единой записи UI+DB. Сохранение/восстановление checkpoint пока не связано с дисковым `CampaignStore`.
- **Не является portable engine-neutral `.bwsave`** и не поддерживает старые M1.6 сейвы; формат `ai_story_bridge_checkpoint_v1` предназначен только для испытаний нового runtime.
- **Не импортирует настоящую книгу**: `.bworld` ZIP/SQLite, права/хеши source refs/coverage, компилятор и реальный reader→RPG anchor — последующие стадии.
- Не реализует NPC planner/поведение, отношения/причинность, свободный ввод/AI/HYBRID и мастер выбора героя/режима.

## Проверка и следующие шаги

Для **нового SHA** после публикации обязателен GitHub Actions PASS: Python reference, Dart M0, story_core (теперь оба Dart-пакета + Python schema), Flutter 71+ widget tests, Android APK и Windows portable. Записывать фактические SHA и статусы. Предыдущий успешный CI не доказывает работоспособность нового координатора.

После подтверждения этапа: M1.7.3 — полное versioned `.bworld` со строгой проверкой ZIP/SQLite/rights/checksums и подготовленными сценами; затем M1.7.4 — SQLite/Drift, безопасная миграция M1.6, durable replay/сохранения, UI интеграция и Android↔Windows QA.

## Итоговый QA M1.7.2 — PASS (2026-11-02)

- **Проверенный исходный SHA:** `8fef11521c9f702414a6364c04b2350d30713b0d`.
- **GitHub Actions #142:** [`41337108811`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41337108811) — `completed/success`.
- **Python reference:** PASS; **Dart M0 story_engine/ink_dart и 1000-scene stress:** PASS.
- **`story_core` анализ и тесты:** PASS, **10/10**.
- **`story_runtime_adapter` анализ и тесты:** PASS, **9/9** (включая 35 ходов через `story_engine`, checkpoint после 23 ходов, replay, повреждение/несовместимость, отказ/идемпотентность).
- **JSON Schema Draft 2020-12 и adversarial fixtures:** PASS, **6/6**.
- **Flutter analyze:** PASS; **Flutter widget tests:** **71/71 PASS**.
- **Windows portable release bundle:** PASS, artifact `AI-Story-RPG-Windows-portable`.
- **Android debug APK:** PASS, artifact `AI-Story-RPG-Android-debug`; GitHub prerelease [`android-build-142`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-142), `AI-Story-RPG-M1-debug.apk` и `SHA256SUMS.txt`.
- **SKIP:** физический Android/Windows E2E тест нового адаптера (нет подключения адаптера к старому GUI), SQLite crash recovery, импорт `.bworld` и migration M1.6 пользовательских сейвов; эти функции не объявлены готовыми.

**Вердикт:** M1.7.2 — реализован и принят **по автоматическим проверкам**. К следующему этапу M1.7.3 можно переходить без переделки текущего UX; до UI интеграции и миграций сохранять разделение `ai_story_m1_intro` и `manor_m17_original_demo`.
