# AI Story RPG — второй самостоятельный клиент публичного API

`apps/rpg_cli` — реальная консольная программа, **не второй игровой движок**.
Она импортирует только `rpg_api` и `campaign_manager` (последний нужен для
выделения и закрытия клиентской SQLite). Движок, NPC, журнал, условия, предметы
и решения исполняются исключительно внутри `LocalRpgGameApi`.
Flutter и интернет не нужны.

В папке `apps/rpg_cli` выполните `dart pub get`, затем:

```sh
dart run bin/rpg_cli.dart prepare --book /private/book.fb2
dart run bin/rpg_cli.dart prepare-literal-canon-v5 --book /private/book.fb2
dart run bin/rpg_cli.dart compile-literal-canon-v5 --book /private/book.fb2 --approved-digest SHA256_FROM_PREVIEW --user-confirmed true --output /private/book-literal.bworld
dart run bin/rpg_cli.dart compile-reviewed-causal-v5 --book /private/book.fb2 --base-world /private/book-literal.bworld --review /private/causal_review.json --approved-digest SHA256_REVIEW --user-confirmed true --output /private/book-causal.bworld
dart run bin/rpg_cli.dart prepare --book /private/tales.fb2 --chapter 1
dart run bin/rpg_cli.dart install --store /private/cli-db --world /private/game.bworld
dart run bin/rpg_cli.dart worlds --store /private/cli-db
dart run bin/rpg_cli.dart start --store /private/cli-db --world-hash SHA256
dart run bin/rpg_cli.dart view --store /private/cli-db --campaign ID
dart run bin/rpg_cli.dart choose --store /private/cli-db --campaign ID --choice CHOICE_ID --action UNIQUE_ID --revision N
dart run bin/rpg_cli.dart export-save --store /private/cli-db --campaign ID --output /private/game.bwsave
dart run bin/rpg_cli.dart import-save --store /private/cli-db --world-hash SHA256 --input /private/game.bwsave
```

Команды возвращают JSON; каждый ход защищён проверкой последней ревизии,
каждый запуск открывает и закрывает приватную SQLite. Экспорт не перезаписывает
существующие сохранения. Имена NPC и варианты действий берутся только из
проверенной проекции текущей сцены, не из будущего сюжета.

`prepare` производит локальный scan точной редакции книги, но **не**
считает найденные упоминания каноном и возвращает
`is_playable_rpg=false`. Консольный запуск пока не сохраняет checkpoint
долгого offline-scan; соответствующий headless интерфейс существует в API.
Не публиковать приватные книги, файлы сохранений и реальные сцены в CI.

В CI собранная настоящим Python-компилятором synthetic rich-v3 фикстура
проходит новый тест: выбор → NPC/предмет → отдельные подключения SQLite →
экспорт/импорт `.bwsave` → идентичный replay. Дополнительно FB2/отдельная
сказка и отрицательные входные данные. Это архитектурная, а не литературная
приёмка. PR #133 остаётся Draft.
