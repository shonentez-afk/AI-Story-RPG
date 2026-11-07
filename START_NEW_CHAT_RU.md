# AI Story RPG — продолжение единого пакета

8 ноября 2026. Репозиторий `shonentez-afk/AI-Story-RPG`; ветка `feature/p0-bookwide-gameplay-readiness-20261107`, существующий [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) OPEN / DRAFT, не объединён. Продолжать крупными связанными пакетами. Не создавать микро-PR, второй движок, вторую библиотеку и не сливать main. E6d, tools/rpg_author и pinned contracts отложены по решению пользователя. Игра автономна: story_core / rich-v3 / SQLite, без обязательного ИИ при прохождении.

## Точная текущая точка

Новый код: **`17303eb647914e87a9a10b830ecf5b9a797bb970`**. [CI #983](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42421184650), [M0 #1068](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42421184639). На последней проверке Python, Dart, весь M1.7/форматы/SQLite/standalone и Flutter static analysis SUCCESS; M0 SUCCESS. **Полный Flutter-прогон ещё выполнялся; результаты новых десяти тестов, Windows и Android пока не объявлены успешными.** Следующий шаг — проверить именно этот run и при ошибке читать его соответствующий job log, а не заново создавать пакет. Flutter job ID 128549743756. Docs-only `[skip ci]` HEAD поверх 17303eb6 не является новым проверенным кодом.

Внешний [External RPG author #272](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42421184662) FAILURE; отложенный E6d не менялся. Не называть все workflows зелёными.

Последняя полностью принятая база до новой интеграции: `1ac3932006aae56c9f61c8d3b25d4dc55422049f`, [CI #982](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183243) SUCCESS, M0 #1067 SUCCESS, Windows/Android SUCCESS. Publish-release SKIPPED; сборки в Actions Artifacts. [Подробная предыдущая передача](https://github.com/shonentez-afk/AI-Story-RPG/blob/04df03b5041181ae81534b0831512cb31fc3d4c1/START_NEW_CHAT_RU.md).

## Что реализовано одним пакетом

[Отчёт](docs/P0_ROUTE_AWARE_NPC_WRITING_RU.md). В прежнем редакторе `_generate()` теперь подключён маршрутный инвентарь. `NpcInventoryWritingContext` берёт exact accepted `_archiveForNpc()`, строго импортирует и проверяет source/hero/scenes/безопасные выходы, вычисляет реальные пути в data-only worker и связывает immutable результат с архивом/blueprint/книгой/планом/ролью/встречами.

`NpcWritingRequest.prepare` включает типизированный контекст в реально отправляемые и показываемые данные и approvalDigest: always_present / branch_dependent / never_present на первой и ответной сцене. Область — базовые пути ДО наложения NPC-ветвей. Владение игрока не является знанием NPC, вероятности и текущий сейв не утверждаются. При лимите увеличивается явно показываемое число запросов, данные не отбрасываются.

`ZaiNpcCampaignWriting.generate/_send` требуют guard для inventory request, сверяют авторскую редакцию перед каждой попыткой, после ответа и внутри writing-lock перед записью. Собственные сохранённые пакеты продолжают работу; чужая правка героя/эффектов/реплик, отмена и выключение облака останавливают новые запросы. Save дополнительно проверяет snapshotDigest без изменения файловой схемы. Готовые/ручные реплики не затираются и не пересылаются.

В прежнее окно согласия вынесен `NpcWritingConsentDialog`, показывающий полные данные и объяснение инвентаря. Разрешение не восстанавливается. `npc_inventory_writing_flow_test.dart` содержит десять новых test/testWidgets: реальные compiled варианты и ключ/расходование, fake API exact data, 429/resume, чужие правки/отзыв карточки, отмена/failed-write, запрет модельных эффектов, повреждение/область, общий offline мир/SQLite replay и телефонный диалог. Наличие тестов пока не заменяет фактический PASS CI.

## Не повторять завершённое

Сохранённая авторская редакция герой/предметы/NPC и прежний телефонный UI приняты на 71824a0c / CI #979. `StoryInventoryRouteAudit` ядра с восемью Dart-тестами принят в #982. Старый текст «инвентарь ещё не подключён к payload» обновлён: интеграция существует в 17303eb6, её приёмка проверяется отдельно.

Очистка завершена: 1 140 runs, 509 artifacts, 50 releases, 52 tags удалены; остались test-build-921/856/824. [Квитанция](docs/REPOSITORY_CLEANUP_RECEIPT_2026-11-08.json), [отчёт](docs/REPOSITORY_CLEANUP_RU_2026-11-08.md). НЕ запускать cleanup заново без новой необходимости.

## Границы и дальнейшая работа

Строгий JSON и правильный отчёт инвентаря не доказывают литературную правдивость реплики: смысл и мотивы принимает автор. Область отчёта до NPC-overlay явно указана; гарантии атомарной межпроцессной транзакции нескольких файлов нет. Уже отправленный запрос не отзывается. Готовые реплики после смены предметов сохраняются для новой проверки, не перегенерируются молча.

Живой GLM, два разных реальных приватных RU FB2, CANON/ALTER_FATE и физический Windows/Android QA остаются открытыми. #118 и весь PR не закрывать по синтетическим тестам. Следующий содержательный пакет после общей приёмки — мотивы/последствия NPC, привязанные к подтверждённым событиям книги в полном авторском потоке. [Текущий статус](docs/CURRENT_STATUS_RU.md).
