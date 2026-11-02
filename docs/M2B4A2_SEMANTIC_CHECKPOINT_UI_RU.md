# M2b4a2 — приватный checkpoint и UI для локального semantic provider

Дата: 2026-11-02. Основная кодовая база M2b4a1 принята: PR #18 merged,
squash SHA `13e9c0ebf4ab6e2cfbbcf306ad221b78cbcc7266`.
Проверено по PR exact head `05a399c241670cda5d05e2bdda0d60cbe163812f`:
`41427964306` 6/6 PASS + M0 `41427964385` PASS.
Это подтверждает только M2b4a1, а не данный подэтап.

## Что добавлено (код, до CI M2b4a2 не принят)

- `apps/story_reader/lib/source_semantic_review.dart` — immutable session с состоянием очереди и решением редактора, точными chunk ID / текстовыми SHA, provider ID/version, source fingerprint. Шах файла — только обнаружение порчи, а не электронная подпись.
- `SemanticReviewSession.processNext` принимает не больше 8 chunks за порцию и по-прежнему вызывает fail-closed gate M2b4a1. Предложения остаются `INFERRED` и не устанавливают канон.
- `SemanticReviewSession.decode` сверяет fingerprint, каждый task, все цитаты/диапазоны SHA/UTF-16, edition/provider/version, решения, формат, checksum. Ошибки не перезаписывают старый checkpoint.
- Приватная папка `ai_story_semantic_review_m2b4a_v1` в `SourceCheckpointScope.semanticProposals`; предыдущие M2b1 mentions, M2b3b narrative и M2b3c relations находятся в отдельных каталогах. Сохранение идёт temp+flush+rename, как и для старых checkpoint.
- `book_isolate_workers.dart` — только top-level compute entrypoints для обработки, сериализации и восстановления semantic session; нет захвата Flutter State/BuildContext.
- `source_semantic_review_panel.dart` — не новый главный экран, а раскрываемая панель внутри единой `Подготовки книги`, скрытые по умолчанию цитаты, явная порционная/полная обработка с остановкой между порциями, ручные метки «Оставить для проверки»/«Отклонить», пагинация по 12, отдельный подтверждаемый сброс.
- Реальное выполнение по умолчанию — только `OfflineRuleProvider` (regexp имён/мест). Нет установленной локальной модели, облака, отправки текста или неявного скачивания.
- `gameplayCoverage=0`; `canPublishBookworld=false`; `BookWorld`, `CampaignStore`, SQLite, книги, история/ридер и три прежних checkpoint не изменены.

## Новые регрессии

- `test/source_semantic_review_test.dart`: roundtrip+resume, forged checksum+quote,
provider version/edition mismatch, негативный ответ модели и проверка физической
изоляции папок.
- `test/source_semantic_review_panel_test.dart`: закрыто до открытия,
скрытые цитаты, видимый источник, сохранение ручного решения, повторное открытие,
write-failure без ложного прогресса, отказ от сброса и явный reset.
- Старые тесты M2b4a1, M2b3, M1 / UI должны продолжить проходить.

## Границы приёмки

**CODE / CI PENDING на ветке `feature/m2b4a-semantic-checkpoints-ui-20261102`.**
До зелёных Flutter analyze+test, Dart, Python+world, Windows+Android не merge.
Физический Windows/Android device E2E, long-book stress 20MiB/30k,
power-loss, screen readers и облачные локальные модели НЕ проверены.
Не выдавать `M2b4a2` за AI-powered RPG.

Дальше: M2b4b — источник действительно семантических предложений с оригинальной
точной цитатой и проверкой противоречий, а затем M2c validated
`IntermediateStoryBlueprint` и отдельный гейт компиляции.


## ПРИНЯТО: M2b4a2 — 2026-11-02, полный CI и Release

- PR #19 https://github.com/shonentez-afk/AI-Story-RPG/pull/19 **MERGED**, кодовый squash `5c8eeb63a8aff47649107fe35a6cbfb6df729c14`; проверенный PR head `d163bf68b49436e62b381316fa9cc96377f780f9`.
- PR Actions `41430335297` **6/6 PASS**: Python, Dart, BookWorld, Flutter analyze, **176/176 Flutter tests**, Android debug APK, Windows portable. M0 `41430335058` PASS.
- Push(main) Actions `41431317114` **7/7 PASS**, включая публикацию GitHub Release; дополнительный M0 `41431317020` PASS.
- Проверенный выпуск: https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-266, опубликован 2026-11-02T10:52:37Z, target exact code SHA `5c8eeb63a8aff47649107fe35a6cbfb6df729c14`. Три актива имеют состояние `uploaded`:
  - Windows portable ZIP 13 264 516 bytes, SHA256 `6ddf5318eb95e915eb9e44db264f45b107a1345f14dac702a88106d7d6a234c8` (распаковывать полную папку exe+DLL+data).
  - Android debug APK 167 253 204 bytes, SHA256 `3e2de1b4a217b7a4d3d15ae21877bb5f2754bceca000e55d55d05d2c0af49b66`.
  - `SHA256SUMS.txt` присутствует.
- В интерфейсе: Библиотека → книга → «Подготовить к RPG» → «Семантические предложения · M2b4a» → «Открыть локальный анализ». Старая библиотека/настройки/книги/читательские позиции и M2b1/M2b3b/M2b3c и SQLite игровые сохранения не мигрировали и не удалялись.
- Это **локальный regexp-provider**, а не полноценный AI Book Compiler. Нет живой модели, облачных запросов, `IntermediateStoryBlueprint` или playable BookWorld из пользовательской книги; `gameplayCoverage=0`, `canPublishBookworld=false`. Ручной Windows/Android E2E на физическом устройстве, долгие книги 20 MiB/30k, экранный диктор, power-loss остаются **SKIP**.
- Следующая разработка: M2b4b источник проверяемых смысловых фактов/событий и отдельная интеграция модели с приватностью/правами, затем M2c causal blueprint/validator.
