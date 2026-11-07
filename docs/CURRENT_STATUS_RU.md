# AI Story RPG — текущий статус 8 ноября 2026

Рабочая ветка `feature/p0-bookwide-gameplay-readiness-20261107`; PR #133 OPEN / DRAFT, main не изменён. Внешний E6d, tools/rpg_author и pinned contracts не согласовывались.

## Код принят на точном HEAD

**`1ac3932006aae56c9f61c8d3b25d4dc55422049f` — [CI #982](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183243) COMPLETED / SUCCESS.** [M0 #1067](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183165) SUCCESS на том же SHA.

| Проверка | Результат |
| --- | --- |
| Python reference | SUCCESS |
| Dart engine/scenario | SUCCESS |
| M1.7, схемы, независимые импортёры, SQLite, standalone | SUCCESS |
| Flutter static analysis и весь Flutter-прогон | SUCCESS |
| Windows portable release | SUCCESS |
| Android debug APK | SUCCESS |
| Публикация GitHub Release | SKIPPED |

[APK в ZIP Actions](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183243/artifacts/13592257912): 88 408 019 байт, archive SHA256 `688431f3a20f1de85e16ebf16bb90ea96c1f8409a58aa603c85fefd9d2b3dfc8`. [Windows portable](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183243/artifacts/13591998992): 15 130 636 байт, archive SHA256 `3bcc6026225049ccc5c661d83761e269416e9793ca0e6acd90547e2949a6ac22`. Это контрольные суммы скачиваемых Actions ZIP, не отдельного файла APK. Артефакты не просрочены на момент проверки.

Код приложения и route-аудит добавлены в `11bbf8a4`; `1ac39320` меняет только четыре maintenance-файла. Последующие `[skip ci]` коммиты передачи/квитанции не меняют проверенный код. Прежняя авторская редакция принята на `71824a0c` / CI #979: её телефонные регрессии уже исправлены и не являются открытым блокером.

[External RPG author #271](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418183141) FAILURE остаётся отдельно. Это не основание скрывать результат или ослаблять E6d-контракт.

## Очистка завершена

Основной [run #4](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42417159944) и завершающий [run #5](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42418176864) SUCCESS, errors=[]. Удалены **1 140 запусков, 509 артефактов, 50 релизов, 52 тега**. Размер удалённых файлов по API — **17 516 072 781 байт (~17,52 ГБ)**, включая 8 233 890 845 байт Actions-артефактов и 9 282 181 936 байт release assets. Биллинг/квота после удаления отдельно не проверены.

Сохранены релизы и test-build теги 921/856/824; отдельно убраны исторические orphan tags 258/260 после проверки сохранения их коммитов в main. После очистки наблюдалось 93 runs. Рабочие сборки, актуальные PR/checks, принятые baseline и нестандартные отчёты защищены. Ветки, исходники, коммиты и main не удалялись/не переписывались. Нет расписания автоматического удаления; завершённый maintenance не запускать повторно вслепую.

Полные deletion lists — в двух audit-артефактах с retention 7 дней. Постоянные результаты, источники и SHA: [JSON-квитанция](REPOSITORY_CLEANUP_RECEIPT_2026-11-08.json), [отчёт очистки](REPOSITORY_CLEANUP_RU_2026-11-08.md).

## Что добавлено в движок

`StoryInventoryRouteAudit` — часть существующего автономного story_core. Он вычисляет гарантированное, зависящее от ветви и недостижимое владение предметами в запрошенных сценах через реальные переходы игры и общую эквивалентность состояний. Учитывает расходование и отказ от получения. Неполный обход и превышение лимита блокируют результат. Связан с blueprintHash, не выдаёт текущий сейв за общий маршрут и не раскрывает NPC-секреты. Восемь новых pure-Dart тестов прошли в общей приёмке.

**Облачная интеграция ещё не сделана.** Следующий связанный пакет: точный принятый вариант → route-инвентарь в явно показываемом контексте → новое согласие → защита перед каждым запросом/повтором и сохранением → общий E2E. Модель не получает права менять runtime и не должна считать предложенную выдачу уже состоявшейся.

Полная книга, CANON/ALTER_FATE, живой GLM, две разные реальные приватные RU FB2 и физические устройства остаются незавершёнными. #118 и Draft PR не закрываются по синтетическим тестам.

[Передача новому чату](../START_NEW_CHAT_RU.md) · [Маршрутный инвентарь и дальнейшая интеграция](P0_ROUTE_INVENTORY_EVIDENCE_RU.md) · [Сохранение авторской работы](P0_DURABLE_AUTHOR_REVISION_RU.md)
