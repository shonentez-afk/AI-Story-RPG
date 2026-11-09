# E6e — единый завершающий процесс внешнего автора

**Область:** только `tools/rpg_author`, `tests/rpg_author`. Ветка `feature/external-rpg-author-e6e-parity-20261107` создана от принятого `main` после PR #131. Нативные Dart/Flutter, BookWorld и общие workflows не редактировались.

## Почему не склеивать команды вслепую

Компиляция v3, строгий source index и совпадение sidecar являются структурным фактом. Они **не** доказывают литературный смысл, полноту вопросов NPC, готовность Android/Windows или согласие автора на фикцию. В E6e последовательность проверок явно закрывает этот риск: никакие предупреждения качества и неполные проверочные документы не могут быть приняты за финал.

## Команда

```sh
python3 -m tools.rpg_author finalize \
  --project /private/project \
  --enrichment /private/enrichment.json \
  --review /private/review.json \
  --output /private/game.bworld \
  --dialogues /private/dialogues.json \
  --question-inventory /private/question_inventory.json
```

Если интерактивных вопросов нет, **вместо двух флагов диалогов** указать `--no-interactive-questions`. Это **заявление автора**, а не программное доказательство отсутствия вопросов. Его нельзя использовать для сокрытия вопросов, присутствующих в книге/сценарии.

`question_inventory.json` — независимый полный список существующих вопросов, подготовленный при литературном анализе исходной книги, например:

```json
{"format":"ai_story_question_inventory_v1","source_fingerprint":"<SHA-256 книги>","question_ids":["ask_guard","ask_about_key"]}
```

`dialogues.json` остаётся существующим строго проверяемым `ai_story_dialogue_topics_v1`. Множество `question_id` обязано **точно** совпадать с перечисленными `question_ids`, а каждый такой choice обязан существовать в blueprint. Проверка независимости составления инвентаря от списка тем **не автоматическая**: при недобросовестном двойном пропуске нет криптографического доказательства полноты.

## Порядок проверок

1. `check_contract` — ни одного несогласованного хеша, затем `load_project` и `validate_story` (в том числе проверенные цитаты).
2. `review_coverage` — обязательный независимый отчёт: точные source/story/enrichment SHA, шесть направлений, все сцены, цитаты и обе концовки, отсутствие нерешённых замечаний. Проверяется **полнота самоотчёта**, а не художественная истина.
3. `audit_project` без предупреждений; если есть вопросы, точный inventory, `dialogue_blueprint_audit` без предупреждений.
4. Только после этого `build_rich` создаёт `game.bworld` и `game.attribution.json` **в приватной папке**, затем `verify_rich_bundle`, повторный gameplay audit с самого архива и archive-level dialogue audit при наличии вопросов.
5. Всегда создаёт `game.finalization.json` (или путь `--report`) с точными входными SHA, archive SHA при сборке, статусами стадий, причиной отказа. Ничего существующего не перезаписывает. При ошибках после записи архива статус остаётся `rejected` — такой архив НЕ выдавать как готовый.

`finalize` возвращает 0 при пройденных доступных структурных проверках, 3 при отражённом в отчёте отказе, 2 при ошибке аргументов или путей до создания отчёта. Успех имеет статус `structurally_complete_literary_report_checked_device_untested`; `user_ready=false`, `literary_truth_attested=false`, `device_playtest_completed=false` сохраняются: для настоящего USER_READY нужен отдельно подтверждённый литературный критик и Windows/Android E2E.

## Совместимость с main

Принятый [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131) предоставляет дополнительный opt-in `npc_knowledge` и правила на подписанные реплики в тех же 4 ZIP-членах rich-v3. Наша рабочая ветка наследует его `compatibility.json`, `npc_compatibility_probe.py` и Python/Dart исходники от конкретного принятого `main`, а также содержит E6d исправления `dialogue_quality.py` и тестов. Новый `finalize` не объявляет автоматическую NPC-grants генерацию готовой: текущий внешний rich builder остаётся player-only, пока нет нового source-reviewed user-consent контракта.

[Draft PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132) с `npc_social` — следующий, отдельный parity gate только **после** принятия соответствующей версии. Не отключать `contract_drift` и не обновлять пользовательский pinned skill без успешных author-tests и dart-parity на точном E6e HEAD.

## За рамками E6e

Snapshot пока не добавляет новые `dialogues.json`, `question_inventory.json`, `game.finalization.json` автоматически — сохранять вместе с проектом отдельными приватными файлами; в открытый GitHub не помещать книги/цитаты/ключи. Ни `finalize`, ни CI синтетической книги не заменяют E2E настоящего полного FB2 на Android и Windows. Старые E5 кампании у пользователя отсутствуют, миграции не делать.
