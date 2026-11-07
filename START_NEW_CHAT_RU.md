# AI Story RPG — продолжение единого пакета

8 ноября 2026. Репозиторий `shonentez-afk/AI-Story-RPG`; ветка `feature/p0-bookwide-gameplay-readiness-20261107`, существующий [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) OPEN / DRAFT. Продолжать крупными связанными пакетами. Не создавать микро-PR, второй движок, вторую библиотеку и не сливать main. E6d, tools/rpg_author и pinned contracts отложены по решению пользователя. Игра автономна: story_core / rich-v3 / SQLite, без обязательного ИИ при прохождении.

## Сначала сверить текущий HEAD и CI

Последняя ПОЛНОСТЬЮ принятая база до этого нового кода: `1ac3932006aae56c9f61c8d3b25d4dc55422049f`, [CI #982](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183243) SUCCESS, [M0 #1067](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183165) SUCCESS. Python/Dart/M1.7/Flutter и Windows/Android прошли. Publish-release SKIPPED; сборки в Actions Artifacts. [Подробная предыдущая передача](https://github.com/shonentez-afk/AI-Story-RPG/blob/04df03b5041181ae81534b0831512cb31fc3d4c1/START_NEW_CHAT_RU.md).

## Новый связанный пакет — CI ещё требуется

Отчёт: [P0_ROUTE_AWARE_NPC_WRITING_RU.md](docs/P0_ROUTE_AWARE_NPC_WRITING_RU.md). В прежнем редакторе `_generate()` подключён маршрутный инвентарь к подготовке диалогов. `NpcInventoryWritingContext` берёт exact accepted `_archiveForNpc()`, строго импортирует и проверяет source/hero/scenes/безопасные выходы, вычисляет реальные пути в data-only worker и связывает immutable результат с архивом/blueprint/книгой/планом/ролью/встречами.

`NpcWritingRequest.prepare` включает только показанный типизированный контекст в реальные JSON bytes и approvalDigest: always_present / branch_dependent / never_present на первой и ответной сцене. Область — базовые пути ДО наложения NPC-ветвей. Владение игрока не является знанием NPC, вероятности и текущий сейв не утверждаются. При лимите увеличивается явно показываемое число запросов, данные не отбрасываются молча.

`ZaiNpcCampaignWriting.generate/_send` требуют guard для inventory request и перепроверяют авторскую редакцию перед каждой попыткой, после ответа и внутри writing lock перед записью. Собственные сохранённые пакеты продолжают работу, чужая правка героя/эффектов/реплик, отмена и выключение облака останавливают отправку. Save дополнительно проверяет snapshotDigest без изменения файловой схемы. Готовые/ручные реплики не затираются и не пересылаются.

В прежнее окно согласия вынесен `NpcWritingConsentDialog`, показывающий точные bytes и объяснение инвентаря. Никаких сохранённых разрешений. Тест `npc_inventory_writing_flow_test.dart` добавляет десять проверок включая fake transport, 429/resume, реальные compiled варианты, весь offline мир, SQLite replay и телефонный диалог. **Тесты подготовлены, но новый CI пока не объявлен успешным.** Проверить фактический итог на новом SHA и обновить документы.

## Не повторять завершённое

Сохранённая авторская редакция герой/предметы/NPC и прежний телефонный UI уже приняты на 71824a0c / CI #979. `StoryInventoryRouteAudit` ядра принят в CI #982; его восемь Dart-тестов уже работают. Очистка завершена: 1 140 runs, 509 artifacts, 50 releases, 52 tags удалены; остались test-build-921/856/824. [Квитанция](docs/REPOSITORY_CLEANUP_RECEIPT_2026-11-08.json), [отчёт](docs/REPOSITORY_CLEANUP_RU_2026-11-08.md). НЕ запускать cleanup заново без новой необходимости.

## Границы и дальнейший приоритет

Строгая структура ответа ИИ не доказывает литературный смысл его слов. Живой GLM, два разных реальных приватных RU FB2, CANON/ALTER_FATE и физический Windows/Android QA остаются открытыми. Не закрывать #118 или весь PR по synthetic PASS. Текущий код не меняет wire-формат, runtime, main или внешний E6d; внешний workflow может оставаться красным, его не скрывать.

После общей приёмки — содержательная привязка мотивов/последствий NPC к проверенным событиям книги в том же полном авторском потоке, а не отдельный PR на поле. [Текущий статус](docs/CURRENT_STATUS_RU.md).
