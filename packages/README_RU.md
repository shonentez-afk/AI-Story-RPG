# Повторно используемые Dart-пакеты игрового движка

Не отдельный опубликованный проект. Приложение «Живая книга» — один клиент. Архитектура допускает будущее выделение собственного open-source репозитория без переписывания правил.

- `story_core`: проверенная логика мира, события, правила и постоянные ID NPC; никакого Flutter, SQLite или ИИ.
- `story_runtime_adapter`: единая точка работы со сменяемым `story_engine`; публичные `state`, `sceneId`, `sceneText`, `choices`, `events`, `choose`, `checkpoint`.
- `bookworld_format`: проверенный переносимый `.bworld` (v1, v2, v3), не произвольный код.
- `campaign_manager`: транзакционные SQLite-кампании и переносимые `.bwsave`.

## Независимый пример

CI предварительно создаёт `artifacts/bookworld/manor_m17_original_demo.bworld` стандартным компилятором. Затем:

```sh
cd packages/campaign_manager
dart pub get
dart run example/standalone_rpg.dart ../../artifacts/bookworld/manor_m17_original_demo.bworld
```

Пример выполнит проверку мира, игровые действия, изменения знаний и предметов, экспорт/импорт сохранения и воспроизведение после закрытия БД. Flutter и ИИ не используются.

Документация и ограничения: `docs/ENGINE_STANDALONE_OPEN_SOURCE_ARCHITECTURE_RU_2026-11-06.md`. Все пакеты пока `publish_to: none`; внешний репозиторий создаётся только после готовности продукта и согласованной API-стабилизации.
